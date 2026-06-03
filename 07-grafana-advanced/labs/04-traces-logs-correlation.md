# Lab 04: Traces, Logs, and Metrics Correlation

## Lab goals

- Configure Tempo and Prometheus so latency panels can show exemplars.
- Configure Loki derived fields so logs link to Tempo traces.
- Use Grafana Explore to pivot across metrics, traces, and logs during investigation.
- Build a repeatable incident investigation workflow that starts from a golden signals dashboard.

## Signal flow

```
Prometheus metric panel --exemplar--> Tempo trace
Loki log line --derived field--> Tempo trace
Dashboard data link -----------> Explore with matching time range and labels
```

## Prerequisites

- [ ] Tempo, Loki, Prometheus, and Grafana are installed and reachable.
- [ ] Applications emit traces with a trace ID that can also appear in logs or exemplars.
- [ ] Prometheus or the instrumentation pipeline stores exemplars for latency histograms.
- [ ] The Grafana datasource UIDs for Prometheus, Loki, and Tempo are known.

## Step 1: Configure Tempo datasource with exemplars

First create or verify the Tempo datasource.


### Tempo datasource YAML

```yaml
apiVersion: 1

datasources:
  - name: Tempo
    uid: tempo-main
    type: tempo
    access: proxy
    url: http://tempo.monitoring.svc:3200
    editable: false
    jsonData:
      nodeGraph:
        enabled: true
      search:
        hide: false
```

### Prometheus exemplar linkage

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    uid: prometheus-main
    type: prometheus
    access: proxy
    url: http://prometheus-operated.monitoring.svc:9090
    jsonData:
      exemplarTraceIdDestinations:
        - name: trace_id
          datasourceUid: tempo-main
```

### Verification

- [ ] Tempo datasource test succeeds.
- [ ] Prometheus datasource references Tempo in exemplarTraceIdDestinations.
- [ ] Latency panels show exemplar dots when the selected metric has exemplars.

## Step 2: Configure Loki trace correlation fields

- Loki derived fields let Grafana extract a trace ID from log messages or structured log fields.
- Use the exact trace key emitted by your application, such as `trace_id`, `traceID`, or `otel.trace_id`.

### Loki datasource YAML

```yaml
apiVersion: 1

datasources:
  - name: Loki
    uid: loki-main
    type: loki
    access: proxy
    url: http://loki-gateway.monitoring.svc:3100
    jsonData:
      derivedFields:
        - name: TraceID
          matcherRegex: 'trace_id=(\w+)'
          url: '$${__value.raw}'
          datasourceUid: tempo-main
```

### Example log line

```json
{
  "level": "error",
  "service": "checkout",
  "message": "payment provider timeout",
  "trace_id": "4f8dfec23c91f1a9",
  "route": "/checkout"
}
```

### Verification

- [ ] A log line in Explore displays the derived TraceID field as a link.
- [ ] Clicking the link opens the corresponding trace in Tempo.
- [ ] The same trace ID is present in application logs and trace backend.

## Step 3: Link Prometheus metrics to Tempo traces

- Use latency histogram panels or Explore to surface exemplars during spikes.
- Choose metrics with user-facing value, especially request duration histograms.

### Example query

```promql
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{job="$service"}[5m])) by (le))
```

### Panel settings checklist

- [ ] Enable exemplars in the panel display options.
- [ ] Use a time range where traces still exist in Tempo retention.
- [ ] Avoid too coarse a query interval or exemplar dots may be hard to interpret.

### Example panel JSON fragment

```json
{
  "fieldConfig": {
    "defaults": {
      "custom": {
        "showPoints": "never",
        "showExemplars": true
      }
    }
  }
}
```

## Step 4: Use Grafana Explore for cross-datasource correlation

1. Open Explore with the Prometheus datasource and run a latency or error query for the selected service.
2. Zoom into the problematic time range and click an exemplar to open the specific Tempo trace.
3. Split the Explore view and open Loki in the second pane.
4. Filter Loki to the same service and time range to inspect related errors or retries.
5. Use trace span attributes such as route or HTTP status to identify the affected path.

### Explore query examples

```promql
sum(rate(http_requests_total{job="$service",status_code=~"5.."}[5m])) by (route)
```

```logql
{app="$service"} |= "ERROR" | json | trace_id!=""
```

### Verification

- [ ] Explore split view keeps the same time range across panes.
- [ ] You can pivot from a trace back to related logs.
- [ ] At least one metric spike can be traced to a concrete request path or dependency span.

## Step 5: Build a correlated incident investigation workflow

| Step | Tool | Question |
| --- | --- | --- |
| 1 | Dashboard | Which golden signal degraded and when? |
| 2 | Annotations | Did a deployment or incident event line up with the change? |
| 3 | Explore metrics | Which route, pod, or status code is abnormal? |
| 4 | Tempo traces | Which span or downstream dependency is slow or failing? |
| 5 | Loki logs | What concrete errors match the traces and time window? |

### Incident playbook checklist

- [ ] Start from a service-level dashboard, not from random logs.
- [ ] Use variables to narrow the service and pod scope before opening Explore.
- [ ] Capture the trace ID and add it to incident notes.
- [ ] Bookmark the relevant dashboard time range for post-incident review.

### Optional dashboard data link

```json
{
  "title": "Open correlated logs",
  "url": "/explore?left={\"datasource\":\"loki-main\",\"queries\":[{\"expr\":\"{app=\\\"$service\\\"}\"}],\"range\":{\"from\":\"${__from}\",\"to\":\"${__to}\"}}"
}
```

## Step 6: Build a correlation validation matrix

Use a small matrix so you can prove every hop works before an incident.

| Correlation hop | Expected operator action | Success signal |
| --- | --- | --- |
| Metric -> Trace | Click exemplar from latency panel | Tempo opens the matching trace |
| Log -> Trace | Click derived field in Loki log line | Trace waterfall shows the same request |
| Dashboard -> Explore | Use a data link from the golden signals dashboard | Explore opens with matching service and time range |
| Trace -> Logs | Pivot from a trace span attribute back to logs | Logs show the same trace ID or route |

### Validation commands

```bash
curl -s -u admin:admin http://localhost:3000/api/datasources/uid/tempo-main | jq '.name,.uid'
curl -s -u admin:admin http://localhost:3000/api/datasources/uid/loki-main | jq '.name,.uid'
curl -s -u admin:admin http://localhost:3000/api/datasources/uid/prometheus-main | jq '.jsonData.exemplarTraceIdDestinations'
```

### Verification

- [ ] Every correlation hop in the table succeeds at least once.
- [ ] The service name and time range stay aligned as you pivot.
- [ ] Operators do not need to copy trace IDs manually when the integration is healthy.

## Step 7: End-to-end verification

1. Trigger or replay a request with a known trace ID.
2. Confirm the trace exists in Tempo.
3. Confirm the same trace ID appears in Loki logs.
4. Confirm the latency histogram or time series shows an exemplar for the request.
5. Confirm operators can navigate among all three signals without manually copying IDs.
6. Save screenshots of the dashboard, Explore view, and Tempo trace for incident training material.

### Final checklist

- [ ] Tempo datasource is provisioned and healthy.
- [ ] Loki derived fields create working trace links.
- [ ] Prometheus panels show exemplars where expected.
- [ ] The investigation workflow is documented and repeatable.
- [ ] The validation matrix has at least one confirmed example per hop.

## Step 8: Troubleshooting quick map

| Symptom | Fastest check | Likely fix |
| --- | --- | --- |
| No exemplar dots | Inspect Prometheus datasource JSON | Add `exemplarTraceIdDestinations` and verify exemplar storage |
| Log line has no trace link | Review Loki `derivedFields` regex | Match the real trace field emitted by the app |
| Tempo trace opens but spans are missing | Check trace retention and query filters | Widen time range or adjust Tempo search filters |
| Explore panes are unsynchronized | Verify time sync and data link parameters | Open Explore from the dashboard with `${__from}` and `${__to}` |

### Quick commands

```bash
curl -s -u admin:admin http://localhost:3000/api/datasources/uid/tempo-main | jq
curl -s -u admin:admin http://localhost:3000/api/datasources/uid/loki-main | jq '.jsonData.derivedFields'
curl -s -u admin:admin http://localhost:3000/api/datasources/uid/prometheus-main | jq '.jsonData.exemplarTraceIdDestinations'
```

### Verification

- [ ] An operator can use the table to narrow the failing layer in under five minutes.
- [ ] The quick commands return the expected datasource settings.
- [ ] The team knows which datasource owns each correlation hop.

## Appendix: Fast reference

### Reference 1: Verification commands

- Use API calls to validate Grafana state.
- Use `kubectl logs` for sidecar and backend inspection.
- Use `jq` to validate dashboard JSON.

```bash
curl -s -u admin:admin http://localhost:3000/api/health | jq
kubectl logs -n monitoring deploy/grafana --since=5m
jq . dashboards/service-reliability.json > /dev/null
```

### Reference 2: Review checklist

- Titles are stable and descriptive.
- Thresholds and units are explicit.
- UIDs are stable across environments.

```yaml
review:
  dashboard_title: stable
  datasource_uid: prometheus-main
  alert_labels: normalized
```

### Reference 3: Hand-off notes

- Store exported JSON in Git.
- Capture screenshots for incident or change records.
- Record the final verification output.

```json
{
  "owner": "sre",
  "artifact": "dashboard-json",
  "verified": true
}
```
