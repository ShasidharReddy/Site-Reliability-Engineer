# Lab 04 — Loki Logging and LogQL

## Overview

This lab covers production-style Loki deployment, log shipping with Promtail, LogQL parsing and metrics, and alerting on log patterns.

By the end of this lab you should be able to:

- deploy Loki with a production-oriented configuration
- ship Kubernetes logs with Promtail pipeline stages
- write LogQL for filters, regex, JSON, and logfmt parsing
- derive metrics from logs
- create log-based alerts in Grafana or Loki Ruler
- reason about label design and ingestion failures

---

## Prerequisites

- `monitoring` namespace already exists
- Grafana is running
- Kubernetes workloads emit container stdout logs
- object storage plan decided for production retention
- optional Slack receiver configured if you want to test alerts end to end

### Quick Checks

```bash
kubectl get nodes
kubectl get pods -n monitoring
helm repo list
```

---

## Loki Architecture Refresher

```text
Promtail / Agent
      ↓
   Distributor
      ↓
    Ingester
      ↓
  Chunks + Index
      ↓
 Query Frontend / Querier
      ↓
    Grafana
```

Important ideas:

- logs are pushed, not scraped
- labels define streams
- chunks store compressed log data
- the compactor manages retention and compaction
- query cost depends heavily on label design and time range

---

## Step 1 — Create a Production-Oriented Loki Values File

Save this as `./loki-values.yaml` when running the lab.

```yaml
loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1

  schemaConfig:
    configs:
      - from: 2024-01-01
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: loki_index_
          period: 24h

  storage:
    type: filesystem
    filesystem:
      chunks_directory: /var/loki/chunks
      rules_directory: /var/loki/rules

  limits_config:
    ingestion_rate_mb: 16
    ingestion_burst_size_mb: 32
    retention_period: 30d
    max_streams_per_user: 20000
    max_label_names_per_series: 20
    reject_old_samples: true
    reject_old_samples_max_age: 168h

  compactor:
    working_directory: /var/loki/compactor
    compaction_interval: 10m
    retention_enabled: true

  ruler:
    enabled: true
    storage:
      type: local
      local:
        directory: /var/loki/rules
    rule_path: /tmp/loki/rules-temp
    alertmanager_url: http://kube-prometheus-stack-alertmanager.monitoring.svc:9093

singleBinary:
  replicas: 1
  persistence:
    enabled: true
    size: 50Gi
    storageClass: standard
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2
      memory: 4Gi

monitoring:
  dashboards:
    enabled: true
  serviceMonitor:
    enabled: true

promtail:
  enabled: true
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 512Mi
```

> In real production, replace `filesystem` with S3, GCS, or another durable object store.

---

## Step 2 — Deploy Loki and Promtail

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install loki grafana/loki \
  --namespace monitoring \
  --values ./loki-values.yaml \
  --wait \
  --timeout 15m
```

Validate:

```bash
kubectl get pods -n monitoring | grep -E 'loki|promtail'
kubectl get svc -n monitoring | grep loki
kubectl get pvc -n monitoring | grep loki
```

---

## Step 3 — Verify Promtail is Collecting Logs

Promtail normally runs as a DaemonSet so every node ships logs.

```bash
kubectl get daemonset -n monitoring
kubectl logs -n monitoring daemonset/loki-promtail --tail=50
```

Useful checks:

```bash
kubectl describe daemonset -n monitoring loki-promtail
kubectl logs -n monitoring daemonset/loki-promtail --tail=100 | grep -E 'error|warn|push'
```

Expected result:

- one Promtail pod per node
- no continuous push failures
- log positions file is being updated

---

## Step 4 — Configure Promtail Pipeline Stages

Promtail pipeline stages let you parse and enrich logs before shipping them.

Example Promtail snippet:

```yaml
promtail:
  config:
    snippets:
      pipelineStages:
        - cri: {}
        - json:
            expressions:
              level: level
              msg: message
              trace_id: trace_id
              status: status_code
              method: method
              path: path
        - labels:
            level:
            method:
        - match:
            selector: '{namespace="payments"}'
            stages:
              - regex:
                  expression: '.*status=(?P<status_code>[0-9]{3}).*duration=(?P<duration_ms>[0-9]+)ms.*'
              - metrics:
                  nginx_requests_total:
                    type: Counter
                    description: 'Generated from payment logs'
                    config:
                      match_all: true
                      action: inc
```

### Pipeline Stage Ideas

- `cri` or `docker` for container log decoding
- `json` for structured logs
- `logfmt` for key=value logs
- `regex` for legacy text parsing
- `labels` for bounded labels only
- `timestamp` for custom timestamps
- `drop` for noisy lines
- `metrics` for log-derived counters and gauges

### Label Extraction Rule

Only promote bounded fields to labels.

Good labels:

- namespace
- app
- container
- level
- method

Do **not** promote fields like:

- request_id
- user_id
- trace_id
- full URL with IDs

---

## Step 5 — Add Loki as a Grafana Datasource

If Grafana sidecar provisioning is enabled, you can provision Loki automatically.
Otherwise add it manually.

Suggested datasource settings:

- Name: `Loki`
- URL: `http://loki.monitoring.svc:3100`
- Access: `Server`
- UID: `loki-uid`

Optional derived field to link logs to traces:

```yaml
derivedFields:
  - name: TraceID
    matcherRegex: 'trace_id=(\w+)|"trace_id":"(\w+)"'
    datasourceUid: tempo-uid
    url: '$${__value.raw}'
```

---

## Step 6 — Explore Logs with Basic LogQL

Open Grafana -> Explore -> select Loki.

### Basic Stream Selector

```logql
{namespace="default", app="api"}
```

### Exact Text Filter

```logql
{namespace="default", app="api"} |= "ERROR"
```

### Negative Filter

```logql
{namespace="default", app="api"} != "healthcheck"
```

### Regex Filter

```logql
{namespace="default", app="api"} |~ "timeout|connection refused|panic"
```

### Search Only a Narrow Time Range

For faster results, reduce the range from `Last 24 hours` to `Last 15 minutes` during active investigation.

---

## Step 7 — Parse JSON and `logfmt`

### JSON Logs

```logql
{namespace="payments", app="checkout"}
| json
| level="error"
| status_code >= 500
```

Useful follow-up query:

```logql
{namespace="payments", app="checkout"}
| json
| line_format "{{.method}} {{.path}} status={{.status_code}} trace={{.trace_id}}"
```

### `logfmt` Logs

```logql
{namespace="payments", app="worker"}
| logfmt
| level="warn"
| task="reconcile"
```

### Regex Parsing for Unstructured Lines

```logql
{app="nginx"}
| regexp `status=(?P<status>[0-9]{3}) path=(?P<path>\S+) duration=(?P<duration>[0-9]+)ms`
```

---

## Step 8 — Derive Metrics from Logs

LogQL can produce time series for dashboards and alerts.

### Error Rate from Logs

```logql
sum(rate({namespace="payments", app="checkout"} |= "ERROR" [5m]))
```

### Count HTTP 5xx from JSON Logs

```logql
sum(rate({namespace="payments", app="checkout"} | json | status_code >= 500 [5m]))
```

### Log Volume by Pod

```logql
sum(count_over_time({namespace="payments"}[5m])) by (pod)
```

### Top Error Messages

```logql
topk(10, sum(count_over_time({namespace="payments", app="checkout"} |= "ERROR" [30m])) by (message))
```

### Failed Login Attempts

```logql
sum(rate({namespace="security", app="auth"} | json | event="login_failed" [15m])) by (source_ip)
```

> Be careful: grouping by `source_ip` may be useful for security analysis but can become expensive if cardinality is huge.

---

## Step 9 — Create Log-Based Metrics for SLOs

Sometimes access logs are the only reliable place to calculate success ratios.

### Example Success Ratio from Logs

```logql
1 - (
  sum(rate({namespace="payments", app="checkout"} | json | status_code >= 500 [5m]))
  /
  sum(rate({namespace="payments", app="checkout"} | json [5m]))
)
```

### Example Latency Threshold from Logs

If logs include `duration_ms`:

```logql
avg_over_time({namespace="payments", app="checkout"} | json | unwrap duration_ms [5m])
```

### When Log-Based SLIs Are Useful

- no native application metrics exist yet
- third-party appliance exposes logs only
- audit workflows require event-derived KPIs

### When Metrics Are Better

- high-volume APIs
- low-latency alerting requirements
- large-scale percentile analysis

---

## Step 10 — Alert on Log Patterns

There are two common ways:

- Loki ruler
- Grafana unified alerting using Loki as datasource

### Option A: Grafana Alerting on Loki

Example alert expression for frequent errors:

```logql
sum(rate({namespace="payments", app="checkout"} |= "ERROR" [5m])) > 10
```

Suggested alert settings:

- Evaluate every: `1m`
- For: `5m`
- Severity label: `warning`
- Notification policy: route to the app team

### Option B: Loki Ruler Example

```yaml
groups:
  - name: loki-log-alerts
    interval: 1m
    rules:
      - alert: CheckoutErrorLogSpike
        expr: sum(rate({namespace="payments", app="checkout"} |= "ERROR" [5m])) > 10
        for: 5m
        labels:
          severity: warning
          team: app
        annotations:
          summary: "Checkout error log spike"
          description: "Loki detected more than 10 error lines/sec over 5 minutes for checkout."
```

Apply rules according to your Loki chart or ruler provisioning method.

---

## Step 11 — Validation Commands

### Loki Health

```bash
kubectl get pods -n monitoring | grep loki
kubectl logs -n monitoring statefulset/loki --tail=50
kubectl port-forward -n monitoring svc/loki 3100:3100
curl -s http://127.0.0.1:3100/ready
```

### Promtail Health

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail
kubectl logs -n monitoring daemonset/loki-promtail --tail=50
```

### Query Loki HTTP API

```bash
curl -G -s http://127.0.0.1:3100/loki/api/v1/query \
  --data-urlencode 'query={namespace="default"}' | jq
```

### Query Metrics from Logs

```bash
curl -G -s http://127.0.0.1:3100/loki/api/v1/query \
  --data-urlencode 'query=sum(rate({namespace="payments", app="checkout"} |= "ERROR" [5m]))' | jq
```

---

## Common Errors

### Error: Loki receives no logs

Possible causes:

- Promtail DaemonSet not running on all nodes
- wrong path mounts for container logs
- network policy blocks push traffic
- labels or parsing stages broke the pipeline

Diagnosis:

```bash
kubectl logs -n monitoring daemonset/loki-promtail --tail=100
kubectl describe pod -n monitoring -l app.kubernetes.io/name=promtail
```

### Error: Queries are slow

Possible causes:

- too wide time range
- bad label design
- regex used before narrowing labels
- too many active streams

Fix:

- reduce time range
- filter by labels first
- remove dynamic labels from streams
- review `max_streams_per_user` and ingestion patterns

### Error: JSON parsing returns nothing

Possible causes:

- logs are not actually JSON
- field names do not match
- parser applied after an incompatible stage

Fix:

- inspect raw line first
- confirm exact field names and case
- test the query incrementally

### Error: Alert never fires

Possible causes:

- query returns logs but not a metric series
- threshold too high
- alert evaluation interval too slow
- alerting policy not connected to Loki datasource

Fix:

- test the exact LogQL expression in Explore
- convert to a numeric time series with `rate()` or `count_over_time()`
- validate contact point and notification policy

---

## Final Validation

You have completed this lab successfully when:

- [ ] Loki is healthy and queryable
- [ ] Promtail is shipping logs from each node
- [ ] basic, regex, JSON, and `logfmt` LogQL queries work
- [ ] you can derive metrics from logs
- [ ] a log-based alert can be evaluated
- [ ] you understand which fields belong in labels and which belong in the log body
