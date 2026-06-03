# Lab 01: Advanced GCP Monitoring Operations

## Lab goals

In this lab you will build a production-style monitoring stack.
You will create uptime checks for different protocols.
You will create notification channels for humans and automation.
You will create alerting policies with multiple conditions.
You will define a service and SLO in Cloud Monitoring.
You will publish a custom dashboard.
You will connect Cloud Monitoring to Grafana.

## Target outcomes

By the end of the lab you should be able to:

- validate black-box service availability
- route alerts to email, PagerDuty, and Pub/Sub
- create policy JSON for reliable alerting
- create service monitoring objects for SLO tracking
- build dashboards as code
- understand Grafana authentication patterns for GCP

## Reference architecture

```text
External users
    |
    v
HTTPS endpoint / TCP port / SSL cert
    |
    +--> Cloud Monitoring uptime checks
    +--> Alerting policy
    +--> Notification channels
            ├── Email
            ├── PagerDuty
            └── Pub/Sub topic
    |
    +--> Cloud Monitoring dashboards
    +--> Service + SLO objects
    +--> Grafana datasource
```

## Prerequisites

- a GCP project with billing enabled
- `gcloud` authenticated with rights to Monitoring, Pub/Sub, and IAM
- a reachable HTTP endpoint for testing
- optionally a reachable TCP service for port checks
- optionally a public TLS endpoint for SSL validation
- `curl` installed locally
- `jq` installed locally if you want to parse API responses cleanly

## Suggested APIs

Enable the following APIs before starting:

- Monitoring API
- Cloud Pub/Sub API
- Cloud Resource Manager API

```bash
export PROJECT_ID="YOUR_PROJECT_ID"
gcloud config set project "$PROJECT_ID"

gcloud services enable \
  monitoring.googleapis.com \
  pubsub.googleapis.com \
  cloudresourcemanager.googleapis.com
```

## Lab variables

Set these variables once and reuse them throughout the lab.

```bash
export PROJECT_ID="YOUR_PROJECT_ID"
export REGION="us-central1"
export ALERT_EMAIL="sre-oncall@example.com"
export PAGERDUTY_KEY="REPLACE_WITH_INTEGRATION_KEY"
export PUBSUB_TOPIC="monitoring-alert-events"
export HTTP_HOST="app.example.com"
export HTTP_PATH="/healthz"
export TCP_HOST="db.example.internal"
export TCP_PORT="5432"
export SSL_HOST="app.example.com"
```

## Step 1: verify access and project context

```bash
gcloud auth list
gcloud config get-value project
gcloud projects describe "$PROJECT_ID" --format='value(projectNumber,name)'
```

Confirm you are targeting the correct project.
Monitoring objects often look correct in one project while your workloads run in another.
That is a common source of false assumptions during incidents.

## Step 2: inspect current monitoring resources

```bash
gcloud monitoring uptime list-configs --project="$PROJECT_ID"
gcloud monitoring dashboards list --project="$PROJECT_ID"
gcloud beta monitoring channels list --project="$PROJECT_ID"
```

If the project is new, the lists may be empty.
If the project already exists, review whether naming is consistent.
A good naming standard reduces confusion in incident response.

## Step 3: create a Pub/Sub topic for machine-consumable alerts

```bash
gcloud pubsub topics create "$PUBSUB_TOPIC"

gcloud pubsub subscriptions create monitoring-alert-events-sub \
  --topic="$PUBSUB_TOPIC"
```

A Pub/Sub notification path is useful for:

- custom alert fan-out
- ChatOps automations
- incident ticket creation
- metrics or alert archival

## Step 4: create an HTTP uptime check

HTTP uptime checks validate application reachability from outside your stack.
They are a black-box signal.
For production systems, black-box signals often map closest to user pain.

```bash
gcloud monitoring uptime create prod-http-check \
  --project="$PROJECT_ID" \
  --resource-type=uptime-url \
  --resource-labels="host=${HTTP_HOST},project_id=${PROJECT_ID}" \
  --path="$HTTP_PATH" \
  --protocol=https \
  --port=443 \
  --validate-ssl \
  --period=60s \
  --timeout=10s \
  --matcher-content='ok' \
  --matcher-type=contains-string \
  --regions=usa,eur
```

Notes:

- `matcher-content` makes the check more meaningful than a raw status code only.
- `period=60s` is a common starting point.
- multiple regions reduce the chance of a single vantage point causing noise.

## Step 5: create a TCP uptime check

TCP checks are useful for:

- database listener reachability
- internal services exposed by TCP
- port-level confirmation during incident isolation

```bash
gcloud monitoring uptime create prod-tcp-check \
  --project="$PROJECT_ID" \
  --resource-type=uptime-url \
  --resource-labels="host=${TCP_HOST},project_id=${PROJECT_ID}" \
  --protocol=tcp \
  --port="$TCP_PORT" \
  --period=60s \
  --timeout=10s \
  --regions=usa
```

A TCP success does not prove the application is healthy.
It proves that the port is reachable and accepting connections.
That distinction matters when triaging partial outages.

## Step 6: create an SSL certificate check

SSL checks are low-cost and high-value.
They prevent certificate expiry incidents from becoming customer-visible outages.

```bash
gcloud monitoring uptime create prod-ssl-check \
  --project="$PROJECT_ID" \
  --resource-type=uptime-url \
  --resource-labels="host=${SSL_HOST},project_id=${PROJECT_ID}" \
  --protocol=https \
  --port=443 \
  --path=/ \
  --validate-ssl \
  --period=300s \
  --timeout=10s \
  --regions=usa
```

## Step 7: verify uptime checks

```bash
gcloud monitoring uptime list-configs \
  --project="$PROJECT_ID" \
  --format='table(name,displayName,period,timeout,monitoredResource.type)'
```

Look for all three checks.
If one is missing, re-run the command and review the host, project, and protocol fields.

## Step 8: create an email notification channel

Email is useful as a fallback.
It should not be the only path for urgent production paging.

```bash
gcloud beta monitoring channels create \
  --project="$PROJECT_ID" \
  --display-name='Primary SRE Email' \
  --description='Email fallback for production alerting' \
  --type=email \
  --channel-labels="email_address=${ALERT_EMAIL}"
```

## Step 9: create a PagerDuty notification channel

PagerDuty is the preferred human paging path in many teams.
You can create it from inline flags or a JSON/YAML definition.
Using JSON is easier when labels become more complex.

```bash
cat > pagerduty-channel.json <<'EOF'
type: pagerduty
displayName: Primary PagerDuty
description: PagerDuty integration for production paging
enabled: true
labels:
  service_key: REPLACE_WITH_INTEGRATION_KEY
userLabels:
  team: sre
  environment: prod
EOF

sed -i '' "s/REPLACE_WITH_INTEGRATION_KEY/${PAGERDUTY_KEY}/" pagerduty-channel.json

gcloud beta monitoring channels create \
  --project="$PROJECT_ID" \
  --channel-content-from-file=pagerduty-channel.json
```

If your local `sed -i` behaves differently outside macOS, adjust accordingly.
If you want a safer cross-shell flow, edit the file manually before running the create command.

## Step 10: create a Pub/Sub notification channel

```bash
cat > pubsub-channel.json <<EOF
type: pubsub
displayName: Monitoring PubSub Channel
description: Send monitoring alerts to Pub/Sub for automation
enabled: true
labels:
  topic: projects/${PROJECT_ID}/topics/${PUBSUB_TOPIC}
userLabels:
  destination: automation
  environment: prod
EOF

gcloud beta monitoring channels create \
  --project="$PROJECT_ID" \
  --channel-content-from-file=pubsub-channel.json
```

## Step 11: list notification channels and capture IDs

```bash
gcloud beta monitoring channels list \
  --project="$PROJECT_ID" \
  --format='table(name,displayName,type,enabled)'
```

Save the three channel IDs.
You will need them for alert policy creation.
A common pattern is to export them as variables.

```bash
export EMAIL_CHANNEL_ID="projects/${PROJECT_ID}/notificationChannels/EMAIL_ID"
export PD_CHANNEL_ID="projects/${PROJECT_ID}/notificationChannels/PD_ID"
export PUBSUB_CHANNEL_ID="projects/${PROJECT_ID}/notificationChannels/PUBSUB_ID"
```

## Step 12: create a multi-condition alert policy definition

This example uses two conditions.
The first watches uptime check failures.
The second watches GKE container restart counts.
The combiner is `OR` so either symptom can page.
For production use, tune the filters to your own workload labels.

```json
{
  "displayName": "Production service availability policy",
  "documentation": {
    "content": "Investigate endpoint availability, GKE pod health, and recent deployments.",
    "mimeType": "text/markdown"
  },
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "HTTP uptime check failing",
      "conditionThreshold": {
        "filter": "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\"",
        "comparison": "COMPARISON_LT",
        "thresholdValue": 1,
        "duration": "180s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_NEXT_OLDER"
          }
        ],
        "trigger": {
          "count": 1
        }
      }
    },
    {
      "displayName": "Container restart spike",
      "conditionThreshold": {
        "filter": "resource.type=\"k8s_container\" AND metric.type=\"kubernetes.io/container/restart_count\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 3,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_DELTA"
          }
        ],
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "enabled": true,
  "notificationChannels": [
    "EMAIL_CHANNEL_PLACEHOLDER",
    "PD_CHANNEL_PLACEHOLDER",
    "PUBSUB_CHANNEL_PLACEHOLDER"
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  }
}
```

## Step 13: create the policy JSON file locally

```bash
cat > alert-policy.json <<'EOF'
{
  "displayName": "Production service availability policy",
  "documentation": {
    "content": "Investigate endpoint availability, GKE pod health, and recent deployments.",
    "mimeType": "text/markdown"
  },
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "HTTP uptime check failing",
      "conditionThreshold": {
        "filter": "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\"",
        "comparison": "COMPARISON_LT",
        "thresholdValue": 1,
        "duration": "180s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_NEXT_OLDER"
          }
        ],
        "trigger": {
          "count": 1
        }
      }
    },
    {
      "displayName": "Container restart spike",
      "conditionThreshold": {
        "filter": "resource.type=\"k8s_container\" AND metric.type=\"kubernetes.io/container/restart_count\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 3,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_DELTA"
          }
        ],
        "trigger": {
          "count": 1
        }
      }
    }
  ],
  "enabled": true,
  "notificationChannels": [
    "EMAIL_CHANNEL_PLACEHOLDER",
    "PD_CHANNEL_PLACEHOLDER",
    "PUBSUB_CHANNEL_PLACEHOLDER"
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  }
}
EOF

python3 - <<'PY'
from pathlib import Path
path = Path('alert-policy.json')
text = path.read_text()
replacements = {
    'EMAIL_CHANNEL_PLACEHOLDER': 'projects/YOUR_PROJECT_ID/notificationChannels/EMAIL_ID',
    'PD_CHANNEL_PLACEHOLDER': 'projects/YOUR_PROJECT_ID/notificationChannels/PD_ID',
    'PUBSUB_CHANNEL_PLACEHOLDER': 'projects/YOUR_PROJECT_ID/notificationChannels/PUBSUB_ID',
}
for old, new in replacements.items():
    text = text.replace(old, new)
path.write_text(text)
PY
```

Replace the placeholder values with your real channel IDs before creating the policy.

## Step 14: create the alert policy with the Monitoring API

In many environments teams manage policies declaratively with Terraform or the API.
That is often cleaner than manual console editing.

```bash
ACCESS_TOKEN=$(gcloud auth print-access-token)

curl -X POST \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/alertPolicies" \
  --data @alert-policy.json
```

## Step 15: verify the alert policy

```bash
curl -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://monitoring.googleapis.com/v3/projects/${PROJECT_ID}/alertPolicies" | jq '.alertPolicies[] | {name, displayName, enabled}'
```

Check that the policy appears and that the condition logic matches your intent.
Wrong filters are a common cause of silent alerts.

## Step 16: create a monitored service object for SLOs

SLOs attach to a service definition in Cloud Monitoring.
You can define a service that represents your production endpoint.

```json
{
  "displayName": "payments-api-service",
  "basicService": {
    "serviceType": "APP_ENGINE"
  }
}
```

The exact service model varies by environment.
If you already have a service created by another tool, reuse it instead of creating a duplicate.
For a lab, the important point is understanding the API flow.

## Step 17: create a service for SLO tracking

```bash
cat > service-definition.json <<'EOF'
{
  "displayName": "payments-api-service",
  "telemetry": {
    "resourceName": "projects/YOUR_PROJECT_ID"
  }
}
EOF

python3 - <<'PY'
from pathlib import Path
path = Path('service-definition.json')
path.write_text(path.read_text().replace('YOUR_PROJECT_ID', '${PROJECT_ID}'))
PY
```

If your team already defines services through Terraform or a service catalog, follow that pattern.
The lab focuses on SLO workflow rather than one single service-definition style.

## Step 18: create an availability SLO definition

An availability SLO example for uptime checks can be modeled around a rolling window objective.

```json
{
  "displayName": "payments-api-availability-99-9",
  "goal": 0.999,
  "rollingPeriod": "2592000s",
  "basicSli": {
    "availability": {}
  }
}
```

For production systems, define the SLI based on real request behavior where possible.
Uptime checks are useful, but a load-balancer or service-metric based request SLI is often better.

## Step 19: create the SLO by API

```bash
cat > slo-definition.json <<'EOF'
{
  "displayName": "payments-api-availability-99-9",
  "goal": 0.999,
  "rollingPeriod": "2592000s",
  "basicSli": {
    "availability": {}
  }
}
EOF
```

Then create the SLO after you know the service name:

```bash
export MONITORED_SERVICE="projects/${PROJECT_ID}/services/SERVICE_ID"

curl -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "Content-Type: application/json" \
  "https://monitoring.googleapis.com/v3/${MONITORED_SERVICE}/serviceLevelObjectives" \
  --data @slo-definition.json
```

## Step 20: create an SLO burn-rate alert concept

A mature SRE setup uses burn-rate policies.
For example:

- fast burn over 1 hour for urgent pages
- slow burn over 6 or 24 hours for ticketing and trend response

Even if you do not build the full burn-rate policy in this lab, document the design.
That step separates basic monitoring from SRE monitoring.

## Step 21: create a custom dashboard as code

```yaml
displayName: Production Operations Overview
gridLayout:
  columns: 2
  widgets:
    - title: Uptime Check Status
      scorecard:
        timeSeriesQuery:
          timeSeriesFilter:
            filter: metric.type="monitoring.googleapis.com/uptime_check/check_passed"
            aggregation:
              alignmentPeriod: 60s
              perSeriesAligner: ALIGN_MEAN
    - title: Container Restarts
      xyChart:
        dataSets:
          - plotType: LINE
            timeSeriesQuery:
              timeSeriesFilter:
                filter: resource.type="k8s_container" AND metric.type="kubernetes.io/container/restart_count"
                aggregation:
                  alignmentPeriod: 60s
                  perSeriesAligner: ALIGN_DELTA
    - title: HTTPS Request Rate
      xyChart:
        dataSets:
          - plotType: LINE
            timeSeriesQuery:
              timeSeriesFilter:
                filter: metric.type="loadbalancing.googleapis.com/https/request_count"
                aggregation:
                  alignmentPeriod: 60s
                  perSeriesAligner: ALIGN_RATE
    - title: Recent Error Count
      scorecard:
        timeSeriesQuery:
          timeSeriesFilter:
            filter: metric.type="logging.googleapis.com/user/auth_failures"
            aggregation:
              alignmentPeriod: 300s
              perSeriesAligner: ALIGN_SUM
```

## Step 22: create the dashboard

```bash
cat > monitoring-dashboard.yaml <<'EOF'
displayName: Production Operations Overview
gridLayout:
  columns: 2
  widgets:
    - title: Uptime Check Status
      scorecard:
        timeSeriesQuery:
          timeSeriesFilter:
            filter: metric.type="monitoring.googleapis.com/uptime_check/check_passed"
            aggregation:
              alignmentPeriod: 60s
              perSeriesAligner: ALIGN_MEAN
    - title: Container Restarts
      xyChart:
        dataSets:
          - plotType: LINE
            timeSeriesQuery:
              timeSeriesFilter:
                filter: resource.type="k8s_container" AND metric.type="kubernetes.io/container/restart_count"
                aggregation:
                  alignmentPeriod: 60s
                  perSeriesAligner: ALIGN_DELTA
    - title: HTTPS Request Rate
      xyChart:
        dataSets:
          - plotType: LINE
            timeSeriesQuery:
              timeSeriesFilter:
                filter: metric.type="loadbalancing.googleapis.com/https/request_count"
                aggregation:
                  alignmentPeriod: 60s
                  perSeriesAligner: ALIGN_RATE
EOF

gcloud monitoring dashboards create \
  --project="$PROJECT_ID" \
  --config-from-file=monitoring-dashboard.yaml
```

## Step 23: review the dashboard list

```bash
gcloud monitoring dashboards list \
  --project="$PROJECT_ID" \
  --format='table(name,displayName)'
```

Dashboards are more useful when they are scoped to an operational question.
Avoid giant all-in-one dashboards with no owner.

## Step 24: connect Cloud Monitoring to Grafana

Grafana supports Cloud Monitoring through a native datasource.
The cleanest authentication models are:

| Grafana location | Preferred auth pattern |
|---|---|
| Grafana on GCE | attached service account |
| Grafana on GKE | Workload Identity |
| Grafana off GCP | service account with narrowly scoped key, rotated and monitored |

Recommended IAM for read-only Grafana:

- `roles/monitoring.viewer`
- `roles/logging.viewer` if log panels are needed
- optional additional resource viewer roles for metadata discovery

## Step 25: Grafana datasource checklist

In Grafana:

- add a Google Cloud Monitoring datasource
- point it at the correct project or metrics scope
- use the least-privilege identity
- verify that metrics for GKE and uptime checks are visible
- confirm time-series label filters work as expected

If Grafana runs on GKE, use Workload Identity rather than a mounted JSON key.
That keeps the integration aligned with modern GCP identity practices.

## Step 26: validate end-to-end alert delivery

A monitoring stack is not complete until delivery is tested.
Perform at least one controlled test:

- temporarily point an uptime check at a bad path
- or lower an alert threshold in a test project
- or publish a known failing synthetic condition

Then verify:

- the incident opens
- email arrives
- PagerDuty triggers
- Pub/Sub receives the event

## Step 27: inspect Pub/Sub messages from alerting

```bash
gcloud pubsub subscriptions pull monitoring-alert-events-sub \
  --auto-ack \
  --limit=5
```

If no messages arrive:

- confirm the policy actually fired
- confirm the channel type is Pub/Sub
- confirm the topic path is correct
- confirm the alert policy includes the Pub/Sub channel ID

## Step 28: operational review questions

Ask yourself:

- does the uptime check represent real user experience
- are the alert conditions actionable
- is there a noise budget for alerting
- are machine notifications separate from human notifications
- is Grafana read-only and keyless where possible
- does the dashboard answer triage questions quickly

## Verification checklist

- [ ] HTTP uptime check created and visible
- [ ] TCP uptime check created and visible
- [ ] SSL/TLS validation check created and visible
- [ ] email notification channel works
- [ ] PagerDuty notification channel works
- [ ] Pub/Sub notification channel works
- [ ] multi-condition alert policy created
- [ ] service and SLO objects planned or created
- [ ] dashboard created from YAML
- [ ] Grafana datasource connected using least privilege

## Cleanup

If you built the lab in a disposable project, delete the resources after testing.

```bash
gcloud monitoring uptime list-configs --project="$PROJECT_ID"
gcloud beta monitoring channels list --project="$PROJECT_ID"
gcloud monitoring dashboards list --project="$PROJECT_ID"
gcloud pubsub topics delete "$PUBSUB_TOPIC"
```

Delete notification channels and alert policies only after confirming no other workloads depend on them.
In production, use change control rather than ad hoc cleanup.
