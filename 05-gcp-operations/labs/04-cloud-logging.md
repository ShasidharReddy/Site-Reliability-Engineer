# Lab 04: Advanced Cloud Logging Operations

## Lab goals

This lab takes Cloud Logging from basic viewing to production operations.
You will build useful Log Explorer queries.
You will create log-based metrics.
You will route logs to BigQuery, Cloud Storage, and Pub/Sub.
You will analyze structured logs for troubleshooting.
You will create alerts from log patterns.
You will reduce cost with log exclusions.

## Outcomes

By the end of the lab you should be able to:

- filter logs quickly for incident triage
- reason about structured and unstructured payloads
- create counters and distribution metrics from logs
- export logs to the right destination for the right purpose
- alert on repeated failure patterns
- apply exclusions safely without blinding investigations

## Prerequisites

- a GCP project with Logging, Monitoring, Pub/Sub, Storage, and BigQuery APIs enabled
- `gcloud`, `bq`, and `jq` installed locally
- application or GKE logs already flowing into Cloud Logging
- IAM permissions to create sinks, metrics, and datasets

## Environment variables

```bash
export PROJECT_ID="YOUR_PROJECT_ID"
export DATASET="sre_logs"
export BUCKET="${PROJECT_ID}-log-archive"
export TOPIC="critical-log-events"
export METRIC_NAME="payments_5xx_count"
```

## Step 1: set the project and enable required APIs

```bash
gcloud config set project "$PROJECT_ID"

gcloud services enable \
  logging.googleapis.com \
  monitoring.googleapis.com \
  pubsub.googleapis.com \
  storage.googleapis.com \
  bigquery.googleapis.com
```

## Step 2: inspect existing log buckets and sinks

```bash
gcloud logging sinks list --project="$PROJECT_ID"
gcloud logging read 'severity>=ERROR' --project="$PROJECT_ID" --limit=5
```

This establishes what already exists.
In mature projects, avoid creating duplicate sinks or duplicate metrics with overlapping purpose.

## Step 3: practice basic Log Explorer filters

Start with simple filters.
These are the fastest way to answer whether a problem is widespread or isolated.

```text
severity>=ERROR
```

```text
resource.type="k8s_container"
severity>=WARNING
```

```text
resource.type="gce_instance"
logName="projects/YOUR_PROJECT_ID/logs/syslog"
```

## Step 4: practice workload-specific queries

Filter by cluster, namespace, and container.

```text
resource.type="k8s_container"
resource.labels.cluster_name="prod-cluster"
resource.labels.namespace_name="payments"
resource.labels.container_name="payments-api"
severity>=ERROR
```

This pattern is a core SRE skill for GKE.
You will use it constantly during incidents.

## Step 5: practice HTTP failure queries

```text
resource.type="http_load_balancer"
httpRequest.status>=500
```

```text
resource.type="http_load_balancer"
httpRequest.requestMethod="POST"
httpRequest.status=502
```

These are useful for edge failures.
They also help separate app-generated errors from infrastructure path failures.

## Step 6: practice text payload search

```text
textPayload:"connection refused"
```

```text
textPayload:"timeout" OR textPayload:"deadline exceeded"
```

Text search is quick but less reliable than structured field queries.
Prefer structured logging whenever you can influence application logging design.

## Step 7: practice structured JSON queries

```text
jsonPayload.level="error"
jsonPayload.service="payments-api"
jsonPayload.code=500
```

```text
jsonPayload.event="db_failover"
jsonPayload.region="us-central1"
```

Structured fields make filters precise.
They also make log-based metrics much easier to define.

## Step 8: practice audit log queries for access changes

```text
logName="projects/YOUR_PROJECT_ID/logs/cloudaudit.googleapis.com%2Factivity"
protoPayload.methodName="SetIamPolicy"
```

```text
logName="projects/YOUR_PROJECT_ID/logs/cloudaudit.googleapis.com%2Factivity"
protoPayload.authenticationInfo.principalEmail:"@example.com"
```

These are essential for change correlation during IAM or service outages.

## Step 9: run the queries via CLI

```bash
gcloud logging read 'resource.type="k8s_container" AND severity>=ERROR' \
  --project="$PROJECT_ID" \
  --limit=20 \
  --format='table(timestamp,resource.labels.namespace_name,resource.labels.container_name,severity)'
```

```bash
gcloud logging read 'httpRequest.status>=500' \
  --project="$PROJECT_ID" \
  --limit=20 \
  --freshness=1h \
  --format=json | jq '.[].httpRequest | {status, requestMethod, requestUrl}'
```

## Step 10: create a BigQuery dataset for long-term analysis

```bash
bq --location=US mk --dataset "${PROJECT_ID}:${DATASET}"
```

Why BigQuery matters:

- joins across long time windows
- fast ad hoc incident analysis
- trend and cost analysis
- IAM and deployment change investigations

## Step 11: create a GCS bucket for archival

```bash
gcloud storage buckets create "gs://${BUCKET}" \
  --project="$PROJECT_ID" \
  --location=us-central1 \
  --uniform-bucket-level-access
```

Cloud Storage is useful for:

- cold archives
- compliance retention
- cheaper long-term storage than hot analytics paths

## Step 12: create a Pub/Sub topic for critical events

```bash
gcloud pubsub topics create "$TOPIC"
```

Pub/Sub export is useful when logs must trigger downstream automation or incident workflows.

## Step 13: create a sink to BigQuery

```bash
gcloud logging sinks create sre-errors-bq \
  "bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/${DATASET}" \
  --project="$PROJECT_ID" \
  --log-filter='severity>=ERROR'
```

## Step 14: grant the sink service account access to BigQuery

```bash
BQ_SINK_SA=$(gcloud logging sinks describe sre-errors-bq --project="$PROJECT_ID" --format='value(writerIdentity)')

echo "$BQ_SINK_SA"
```

Then grant the role.

```bash
bq add-iam-policy-binding \
  --member="$BQ_SINK_SA" \
  --role='roles/bigquery.dataEditor' \
  "${PROJECT_ID}:${DATASET}"
```

## Step 15: create a sink to Cloud Storage

```bash
gcloud logging sinks create sre-archive-gcs \
  "storage.googleapis.com/${BUCKET}" \
  --project="$PROJECT_ID" \
  --log-filter='logName:"cloudaudit.googleapis.com" OR severity>=CRITICAL'
```

## Step 16: grant the sink service account access to Cloud Storage

```bash
GCS_SINK_SA=$(gcloud logging sinks describe sre-archive-gcs --project="$PROJECT_ID" --format='value(writerIdentity)')

gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
  --member="$GCS_SINK_SA" \
  --role='roles/storage.objectCreator'
```

## Step 17: create a sink to Pub/Sub

```bash
gcloud logging sinks create sre-critical-pubsub \
  "pubsub.googleapis.com/projects/${PROJECT_ID}/topics/${TOPIC}" \
  --project="$PROJECT_ID" \
  --log-filter='severity>=CRITICAL'
```

## Step 18: grant the sink service account access to Pub/Sub

```bash
PUBSUB_SINK_SA=$(gcloud logging sinks describe sre-critical-pubsub --project="$PROJECT_ID" --format='value(writerIdentity)')

gcloud pubsub topics add-iam-policy-binding "$TOPIC" \
  --project="$PROJECT_ID" \
  --member="$PUBSUB_SINK_SA" \
  --role='roles/pubsub.publisher'
```

## Step 19: verify sink configuration

```bash
gcloud logging sinks list \
  --project="$PROJECT_ID" \
  --format='table(name,destination,filter,writerIdentity)'
```

If a sink exists but exports nothing, the most common cause is missing writer permissions.
Always verify both the sink object and destination IAM.

## Step 20: query exported logs in BigQuery

After some logs arrive, run:

```sql
SELECT
  timestamp,
  resource.type,
  severity,
  jsonPayload.message,
  resource.labels.namespace_name,
  resource.labels.container_name
FROM `YOUR_PROJECT_ID.sre_logs._AllLogs`
WHERE timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
  AND severity = 'ERROR'
ORDER BY timestamp DESC
LIMIT 100;
```

Depending on your dataset export layout, table names may vary.
Confirm the actual tables in BigQuery after the first export lands.

## Step 21: create a simple counter log-based metric

This metric counts HTTP 5xx events from a workload.

```bash
gcloud logging metrics create "$METRIC_NAME" \
  --project="$PROJECT_ID" \
  --description='Count of payments API 5xx responses' \
  --log-filter='resource.type="k8s_container" AND resource.labels.namespace_name="payments" AND jsonPayload.code>=500'
```

## Step 22: inspect the metric

```bash
gcloud logging metrics describe "$METRIC_NAME" \
  --project="$PROJECT_ID"
```

Make sure the filter matches actual log structure.
If your application logs use `status_code` instead of `code`, update the filter.

## Step 23: create a distribution log-based metric example

Distribution metrics are useful when logs contain numeric latency values.
Use a config file for richer metric definitions.

```yaml
name: request_latency_ms
metricDescriptor:
  metricKind: DELTA
  valueType: DISTRIBUTION
  unit: ms
filter: resource.type="k8s_container" AND jsonPayload.latency_ms!=""
valueExtractor: EXTRACT(jsonPayload.latency_ms)
```

Save the file and create the metric:

```bash
cat > latency-metric.yaml <<'EOF'
name: request_latency_ms
metricDescriptor:
  metricKind: DELTA
  valueType: DISTRIBUTION
  unit: ms
filter: resource.type="k8s_container" AND jsonPayload.latency_ms!=""
valueExtractor: EXTRACT(jsonPayload.latency_ms)
EOF

gcloud logging metrics create request_latency_ms \
  --project="$PROJECT_ID" \
  --config-from-file=latency-metric.yaml
```

## Step 24: parse structured logs for troubleshooting

Structured logs help you answer more than just “did it fail”.
They let you ask:

- which tenant failed
- which dependency failed
- which trace ID was involved
- which rollout version introduced the error

Example query:

```text
resource.type="k8s_container"
jsonPayload.service="payments-api"
jsonPayload.trace_id="TRACE_ID_HERE"
```

## Step 25: correlate by deployment version

If the application logs image tag or release SHA, use it.
That is a huge accelerator during incident response.

```text
resource.type="k8s_container"
jsonPayload.release="2025.01.07-rc3"
severity>=ERROR
```

This turns “something broke after deploy” into a searchable question instead of a guess.

## Step 26: create an alert from a log-based metric

The log-based metric now behaves like a Monitoring metric.
You can alert on it in the same way as platform metrics.
A typical design is:

- create the metric from logs
- graph the metric for a few hours or days
- choose a threshold that reflects real failure
- create a Monitoring alert policy on the metric

Example metric filter for the alert condition:

```text
metric.type="logging.googleapis.com/user/payments_5xx_count"
resource.type="global"
```

## Step 27: create a focused log exclusion for noisy health checks

Exclusions reduce cost, but only when used carefully.
A common safe example is successful health check noise.

```bash
gcloud logging sinks update _Default \
  --project="$PROJECT_ID" \
  --add-exclusion=name=exclude-healthchecks,description='Exclude successful health checks',filter='resource.type="http_load_balancer" AND httpRequest.requestUrl:"/healthz" AND httpRequest.status=200'
```

Review this carefully.
Do not exclude failed health checks.
Do not exclude logs you need for security or compliance.

## Step 28: verify exclusion behavior

After some time, compare volume before and after.
Look in Log Explorer and confirm:

- success health checks are reduced
- error logs still appear
- sink exports still receive the logs you care about

## Step 29: advanced troubleshooting query patterns

High-cardinality app errors:

```text
resource.type="k8s_container"
severity>=ERROR
jsonPayload.service="payments-api"
jsonPayload.customer_id="C12345"
```

Authentication drift:

```text
logName="projects/YOUR_PROJECT_ID/logs/cloudaudit.googleapis.com%2Factivity"
protoPayload.methodName="google.iam.admin.v1.CreateServiceAccountKey"
```

Pod crash investigation:

```text
resource.type="k8s_container"
resource.labels.pod_name:"payments-api"
(textPayload:"OOMKilled" OR jsonPayload.reason="OOMKilled")
```

## Step 30: validate Pub/Sub export by subscribing

```bash
gcloud pubsub subscriptions create critical-log-events-sub \
  --topic="$TOPIC"

gcloud pubsub subscriptions pull critical-log-events-sub \
  --auto-ack \
  --limit=5
```

If no events arrive, confirm that a critical log actually matched the sink filter.
No match means no export, even when the sink is configured correctly.

## Step 31: review cost and retention strategy

Use this table to align destination to purpose.

| Destination | Best use |
|---|---|
| default bucket | near-term operational search |
| custom log bucket | separated retention or access control |
| BigQuery | analytics and investigations |
| Cloud Storage | low-cost archive and compliance |
| Pub/Sub | automation and downstream processing |

## Step 32: operational review questions

- which queries would you save as team bookmarks
- which logs should become metrics
- which sinks are truly needed and which are duplication
- which exclusions save cost without harming detection
- which structured fields should the application add next

## Verification checklist

- [ ] Log Explorer queries tested from basic to advanced
- [ ] BigQuery sink created and granted permissions
- [ ] GCS sink created and granted permissions
- [ ] Pub/Sub sink created and granted permissions
- [ ] counter log-based metric created
- [ ] distribution log-based metric example created or understood
- [ ] alert design from log pattern documented
- [ ] exclusion added only after reviewing impact
- [ ] exported logs validated at the destination

## Cleanup

If you ran this in a disposable project, remove lab-only resources after validation.

```bash
gcloud logging metrics delete "$METRIC_NAME" --project="$PROJECT_ID"
gcloud logging metrics delete request_latency_ms --project="$PROJECT_ID"
gcloud logging sinks delete sre-errors-bq --project="$PROJECT_ID"
gcloud logging sinks delete sre-archive-gcs --project="$PROJECT_ID"
gcloud logging sinks delete sre-critical-pubsub --project="$PROJECT_ID"
gcloud pubsub subscriptions delete critical-log-events-sub --project="$PROJECT_ID"
```

Do not delete production sinks or metrics without checking who depends on them.
