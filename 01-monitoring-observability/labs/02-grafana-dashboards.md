# Lab 02 — Building Advanced Grafana Dashboards

## Overview

This lab walks through creation of a production-style **Golden Signals** dashboard in Grafana.
You will add chained variables, multiple panel types, deploy annotations, thresholds, data links, JSON export/import, and dashboard versioning practices.

By the end of the lab you should be able to:

- build a dashboard from first principles instead of importing one blindly
- create chained variables for cluster, namespace, and pod
- select the correct panel type for each signal
- add deploy and incident annotations
- configure thresholds and drill-down links
- export, import, diff, and version dashboard JSON

---

## Prerequisites

- Lab 01 completed successfully
- Grafana reachable on port `3000`
- Prometheus reachable on port `9090`
- example application metrics available for HTTP rate, error, and latency
- optional Loki and Tempo datasources if you want logs/traces drill-downs

### Access Grafana

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

### Access Prometheus

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

### Quick Datasource Check

- open Grafana
- log in with the admin credentials from Lab 01
- verify the Prometheus datasource is healthy
- optionally verify Loki and Tempo are configured

---

## Dashboard Design Goal

We will create one dashboard that answers these questions quickly:

1. is the service receiving traffic?
2. are users seeing errors?
3. is latency rising at p95/p99?
4. are pods or nodes saturating?
5. did a deployment or incident start around the same time?
6. can I jump from metrics to logs and traces fast?

### Suggested Layout

```text
Row 1: Service overview (traffic, error %, p95, saturation summary)
Row 2: Traffic and errors over time
Row 3: Latency percentiles + heatmap
Row 4: Saturation by pod / node
Row 5: Top failing routes / pods / namespaces
```

---

## Step 1 — Create a Folder and New Dashboard

### Option A: UI

- Grafana -> Dashboards -> New -> New Folder
- Folder name: `SRE Services`
- Create a new dashboard inside that folder

### Option B: API

```bash
GRAFANA_PASS=$(kubectl get secret grafana-admin-credentials -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 --decode)

curl -s -X POST http://admin:${GRAFANA_PASS}@localhost:3000/api/folders \
  -H 'Content-Type: application/json' \
  -d '{"title":"SRE Services","uid":"sre-services"}' | jq
```

Name the dashboard:

```text
Golden Signals — Kubernetes Service
```

---

## Step 2 — Create Chained Variables

Variables make the dashboard reusable across clusters and workloads.

### Variable 1: `cluster`

- Type: Query
- Data source: Prometheus
- Query:

```promql
label_values(up, cluster)
```

Recommended settings:

- Multi-value: enabled
- Include All option: enabled
- Refresh: On dashboard load

### Variable 2: `namespace`

- Type: Query
- Query:

```promql
label_values(kube_pod_info{cluster=~"$cluster"}, namespace)
```

Recommended settings:

- Multi-value: enabled
- Include All option: enabled
- Sort: alphabetical

### Variable 3: `pod`

- Type: Query
- Query:

```promql
label_values(kube_pod_info{cluster=~"$cluster", namespace=~"$namespace"}, pod)
```

Recommended settings:

- Multi-value: enabled
- Include All option: enabled

### Optional Variable 4: `service`

```promql
label_values(http_requests_total{cluster=~"$cluster", namespace=~"$namespace"}, service)
```

### Why Chained Variables Matter

- dashboard stays reusable
- queries stay scoped
- responders can pivot quickly during incidents
- panels do not scan the entire cluster unnecessarily

---

## Step 3 — Build the Golden Signals Panels

We will use five different panel types:

- Time series
- Stat
- Table
- Heatmap
- Bar gauge

### Panel 1 — Traffic Rate (Time Series)

**Question answered:** how much traffic is the service receiving?

Query:

```promql
sum(rate(http_requests_total{cluster=~"$cluster", namespace=~"$namespace", service=~"$service"}[5m])) by (service)
```

Recommended settings:

- Panel type: Time series
- Title: `Request Rate (req/s)`
- Unit: `reqps`
- Legend: `{{service}}`
- Line width: `2`
- Fill opacity: `15`
- Min step: `30s`

### Panel 2 — Error Ratio (Stat)

**Question answered:** are users seeing request failures?

Query A:

```promql
sum(rate(http_requests_total{cluster=~"$cluster", namespace=~"$namespace", service=~"$service", status_code=~"5.."}[5m]))
```

Query B:

```promql
sum(rate(http_requests_total{cluster=~"$cluster", namespace=~"$namespace", service=~"$service"}[5m]))
```

Expression C:

```text
$A / $B * 100
```

Recommended settings:

- Panel type: Stat
- Title: `5xx Error %`
- Unit: `percent (0-100)`
- Color mode: Background
- Reduce: Last not null

Thresholds:

- green: `< 1`
- yellow: `>= 1`
- red: `>= 5`

### Panel 3 — Latency Percentiles (Time Series)

**Question answered:** how bad is request latency at different percentiles?

P50:

```promql
histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket{cluster=~"$cluster", namespace=~"$namespace", service=~"$service"}[5m])) by (le, service))
```

P95:

```promql
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{cluster=~"$cluster", namespace=~"$namespace", service=~"$service"}[5m])) by (le, service))
```

P99:

```promql
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{cluster=~"$cluster", namespace=~"$namespace", service=~"$service"}[5m])) by (le, service))
```

Recommended settings:

- Panel type: Time series
- Title: `Latency Percentiles`
- Unit: `s`
- Legend: `p50`, `p95`, `p99`
- Draw style: Lines
- Stack: off

Threshold example:

- warning line at `0.5`
- critical line at `1.0`

### Panel 4 — Latency Distribution (Heatmap)

**Question answered:** is latency shifting for the whole distribution or only at the tail?

Query:

```promql
sum(increase(http_request_duration_seconds_bucket{cluster=~"$cluster", namespace=~"$namespace", service=~"$service"}[$__interval])) by (le)
```

Recommended settings:

- Panel type: Heatmap
- Title: `Latency Distribution Heatmap`
- Format: Time series buckets
- Unit: `s`

### Panel 5 — Pod Saturation (Bar Gauge)

**Question answered:** which pods are hottest right now?

CPU query:

```promql
topk(10, sum(rate(container_cpu_usage_seconds_total{cluster=~"$cluster", namespace=~"$namespace", pod=~"$pod"}[5m])) by (pod))
```

Alternative memory query:

```promql
topk(10, sum(container_memory_working_set_bytes{cluster=~"$cluster", namespace=~"$namespace", pod=~"$pod"}) by (pod) / 1024 / 1024)
```

Recommended settings:

- Panel type: Bar gauge
- Title: `Top Pods by CPU`
- Orientation: Horizontal
- Unit: `cores`
- Sort: descending

### Panel 6 — Top Failing Routes (Table)

**Question answered:** which endpoints are contributing most to failures?

Query:

```promql
topk(
  10,
  sum(rate(http_requests_total{cluster=~"$cluster", namespace=~"$namespace", service=~"$service", status_code=~"5.."}[5m])) by (route, status_code)
)
```

Recommended settings:

- Panel type: Table
- Title: `Top Failing Routes`
- Columns: `route`, `status_code`, `Value`
- Transformations: organize fields, sort by Value descending

---

## Step 4 — Add Thresholds, Units, and Data Links

A dashboard becomes operationally useful when values are easy to interpret.

### Threshold Guidance

| Signal | Warning | Critical |
|---|---|---|
| Error ratio | 1% | 5% |
| P95 latency | 500 ms | 1 s |
| CPU per pod | 0.7 cores | 0.9 cores |
| Memory working set | 75% of limit | 90% of limit |

### Data Links

Data links allow direct pivoting from a panel to logs or traces.

#### Example link to Grafana Explore for logs

- Add a Data link to the latency panel
- URL example:

```text
/explore?left={"datasource":"Loki","queries":[{"expr":"{namespace=~\"$namespace\",app=~\"$service\"}"}],"range":{"from":"now-1h","to":"now"}}
```

#### Example link to a traces dashboard or Explore

```text
/explore?left={"datasource":"Tempo","queries":[{"query":"{ service.name = \"$service\" }"}]}
```

### Unit Guidance

Use correct units everywhere:

- requests/sec for traffic
- percent for error ratio
- seconds or milliseconds for latency
- bytes or MiB/GiB for memory
- cores or percent for CPU

---

## Step 5 — Add Deployment and Incident Annotations

Annotations tell responders what changed at the same moment the graphs changed.

### Deployment Annotation from Prometheus

If you have Kubernetes metrics available:

```promql
changes(kube_deployment_status_observed_generation{namespace=~"$namespace"}[5m]) > 0
```

Suggested annotation config:

- Name: `Deployments`
- Data source: Prometheus
- Title: `Deployment changed`
- Text: `{{deployment}} rolled out`
- Icon color: blue

### Incident Annotation

You can also create manual annotations from the Grafana UI for:

- incident start
- mitigation applied
- rollback executed
- problem resolved

### Optional Alert Annotation Source

If Grafana alerting is enabled, add alert state history as annotations so you can see when alert transitions happened.

---

## Step 6 — Add Drill-Down Usability Improvements

### Add Panel Descriptions

Every panel should explain:

- what it shows
- the PromQL used
- what “bad” looks like
- who owns the signal

### Add Repeated Links

Good links to include:

- logs for this service
- traces for this service
- deployment pipeline
- runbook
- service catalog entry

### Add Dashboard Tags

Suggested tags:

- `golden-signals`
- `sre`
- `kubernetes`
- `service-overview`

---

## Step 7 — Export and Import Dashboard JSON

### Export via UI

- Dashboard -> Share -> Export
- enable `Export for sharing externally` only when needed
- save file as `golden-signals-dashboard.json`

### Export via API

First find the dashboard UID in Grafana.
Then use:

```bash
curl -s http://admin:${GRAFANA_PASS}@localhost:3000/api/dashboards/uid/<DASHBOARD_UID> | jq '.dashboard' > golden-signals-dashboard.json
```

### Import via UI

- Grafana -> Dashboards -> Import
- upload the JSON file
- select the destination folder
- map datasources if prompted

### Import via API

```bash
jq -n --argjson dashboard "$(cat golden-signals-dashboard.json)" '{dashboard: $dashboard, overwrite: true, folderUid: "sre-services"}'
```

If you prefer a single API call, use the payload format Grafana expects:

```bash
curl -s -X POST http://admin:${GRAFANA_PASS}@localhost:3000/api/dashboards/db \
  -H 'Content-Type: application/json' \
  -d @dashboard-import-payload.json | jq
```

---

## Step 8 — Dashboard Versioning and Diffing

Treat dashboards as code.

### Recommended Workflow

1. export JSON after meaningful changes
2. normalize JSON formatting
3. commit to Git
4. review diffs in pull requests
5. provision dashboards automatically where possible

### Normalize JSON for Better Diffs

```bash
jq -S . golden-signals-dashboard.json > golden-signals-dashboard.sorted.json
```

### Git Diff Examples

```bash
git add golden-signals-dashboard.sorted.json
git diff --staged --word-diff
```

### What to Watch in Diffs

- datasource UIDs changed unexpectedly
- panel IDs renumbered without purpose
- thresholds changed
- queries widened too broadly
- annotations removed accidentally
- variable definitions broken or reordered badly

### Provisioning Advice

Long term, prefer one of these:

- Grafana provisioning files
- ConfigMaps with dashboard sidecars
- Terraform for Grafana resources
- Jsonnet/Tanka for dashboard generation

---

## Step 9 — Validation Checklist

### Dashboard Functionality

- [ ] dashboard loads without errors
- [ ] variable dropdowns populate
- [ ] changing `cluster` updates `namespace`
- [ ] changing `namespace` updates `pod`
- [ ] panels show current data, not `No data`

### Golden Signals

- [ ] traffic panel moves when load changes
- [ ] error stat responds to 5xx traffic
- [ ] p95/p99 latency graphs differ from p50 when tail latency appears
- [ ] bar gauge highlights hot pods
- [ ] table ranks failing routes correctly

### Usability

- [ ] annotations show deploys or incidents
- [ ] thresholds render visibly
- [ ] data links open the right logs or traces view
- [ ] exported JSON can be re-imported cleanly

---

## Common Errors

### Error: Dashboard shows `No data`

Possible causes:

- wrong datasource selected
- wrong label names in PromQL
- variables returning empty values
- service metrics do not exist yet

Diagnosis:

- test each query in Grafana Explore first
- verify metric names in Prometheus UI
- temporarily hardcode one namespace or service to isolate the problem

### Error: Variables do not chain correctly

Possible causes:

- child query does not reference parent variable
- `Include All` value expands unexpectedly
- labels such as `cluster` are not present on metrics

Fix:

- confirm variable queries independently
- use regex `=~` when multi-select is enabled
- ensure external labels or relabeling actually add the labels you expect

### Error: Heatmap is empty

Possible causes:

- histogram buckets do not exist
- wrong bucket metric name
- using `_sum` or `_count` instead of `_bucket`

Fix:

- verify `http_request_duration_seconds_bucket` exists in Prometheus
- use `increase()` or `rate()` grouped by `le`

### Error: Table panel is unreadable

Fixes:

- add `Organize fields`
- rename columns clearly
- sort by `Value`
- reduce decimal noise

### Error: Export/import changes break the dashboard

Possible causes:

- datasource UID mismatch
- exported JSON still contains environment-specific references
- provisioning overwrote UI changes

Fix:

- use datasource variables where possible
- normalize JSON and review diffs
- document your expected dashboard source of truth

---

## Final Result

You have completed this lab successfully when you can open one dashboard and immediately answer:

- what is the request rate?
- what is the error ratio?
- what are p50, p95, and p99 latency doing?
- which pods are hottest?
- did a deployment happen at the same time?
- can you jump from metric spike to logs and traces quickly?

That is what makes a Grafana dashboard operational instead of decorative.
