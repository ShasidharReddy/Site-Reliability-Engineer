# Grafana Advanced Troubleshooting Guide

## How to use this guide

- Start with the symptom that most closely matches what the operator sees.
- Follow the investigation steps in order so you do not skip low-cost checks such as datasource UIDs or silences.
- Apply the smallest safe fix, then run the verification checklist before moving on.

## Quick triage table

| Problem area | First place to look | Fastest evidence |
| --- | --- | --- |
| Dashboard rendering | Panel inspect view | Rendered query and datasource UID |
| Alert routing | Notification policies and silences | Route matchers and suppression status |
| Variables | Dashboard variable queries | Dropdown query result |
| Provisioning | Sidecar and Grafana logs | Whether the JSON file reaches Grafana |
| Trace correlation | Datasource config and exemplar settings | Tempo link or derived field |

## 1. Dashboard shows "No data"

### Symptoms

- Panels display `No data` or empty legends
- Variables may still populate but panel queries return empty frames
- Direct Prometheus query in another tool may work

### Likely causes

| Cause | Why it happens |
| --- | --- |
| Wrong datasource UID | Imported dashboard points to a missing datasource |
| Variable mismatch | Selected labels produce an empty series set |
| Time range mismatch | Metric retention or panel time range excludes data |

### Investigation steps

1. Open panel -> Inspect -> Query to see the final rendered PromQL.
2. Run the rendered query directly in Explore or Prometheus.
3. Check datasource health and the dashboard time range.
4. Confirm variable values actually exist in the underlying metrics.

### Commands

```bash
curl -s -u admin:admin http://localhost:3000/api/datasources | jq '.[].uid'
# Compare with dashboard JSON datasource UIDs
grep -n "datasource" dashboards/service-reliability.json
```

### Fix example

```yaml
datasourceUid: prometheus-main
relativeTimeRange:
  from: 3600
  to: 0
```

### Fix actions

- Replace stale datasource UIDs in the dashboard JSON or rebind the datasource in the UI.
- Relax or correct variable filters so they match real labels.
- Use a broader time range to confirm the signal exists before narrowing.

### Verification

- [ ] At least one panel returns series data.
- [ ] Inspect query shows the intended datasource and label filters.
- [ ] Refreshing the dashboard no longer shows `No data`.

### Notes

- Capture screenshots or API output in the incident ticket if the issue is production-impacting.
- If the issue recurs, convert the manual fix into code through provisioning or dashboard-as-code workflows.

## 2. Alert fires but no notification received

### Symptoms

- Rule state is firing in Grafana
- No Slack, PagerDuty, or email notification arrives
- The rule may show as silenced or routed unexpectedly

### Likely causes

| Cause | Why it happens |
| --- | --- |
| Policy mismatch | Labels do not match any intended policy branch |
| Silence or mute timing | The alert is currently suppressed |
| Receiver failure | Webhook, integration key, or SMTP settings are broken |

### Investigation steps

1. Inspect the rule labels and annotations.
2. Review the active notification policy tree.
3. Check silences and mute timings.
4. Use contact point test messages and backend logs.

### Commands

```bash
curl -s -u admin:admin http://localhost:3000/api/alertmanager/grafana/api/v2/silences | jq
curl -s -u admin:admin http://localhost:3000/api/alertmanager/grafana/config/api/v1/receivers | jq
```

### Fix example

```yaml
object_matchers:
  - ["severity", "=", "critical"]
receiver: PagerDuty-Critical
```

### Fix actions

- Add or correct routing labels such as `severity`, `team`, or `service`.
- Delete or narrow the silence if it suppresses too much.
- Repair the failing receiver secret and rerun a contact point test.

### Verification

- [ ] A fresh test alert reaches the correct receiver.
- [ ] Policy preview or reasoning matches the expected route.
- [ ] Suppression state is visible and intentional.

### Notes

- Capture screenshots or API output in the incident ticket if the issue is production-impacting.
- If the issue recurs, convert the manual fix into code through provisioning or dashboard-as-code workflows.

## 3. Dashboard variables not populating

### Symptoms

- Dropdown is empty
- Variable spinner runs forever
- Panels depending on the variable also fail

### Likely causes

| Cause | Why it happens |
| --- | --- |
| Slow query | Variable query scans too much data |
| Bad metric | The metric used in `label_values` does not exist |
| Chain break | Upstream variable has no selected value |

### Investigation steps

1. Inspect the variable query in dashboard settings.
2. Test the query in Explore.
3. Check whether the datasource for variables differs from the panel datasource.
4. Confirm regex formatting for multi-value variables.

### Commands

```bash
grep -n "templating" dashboards/service-reliability.json
curl -s -u admin:admin http://localhost:3000/api/datasources | jq
```

### Fix example

```yaml
query: label_values(kube_pod_info, cluster)
refresh: 1
includeAll: false
```

### Fix actions

- Use a more reliable metric like `kube_pod_info` for environment and pod discovery.
- Simplify regex and avoid `Include All` on high-cardinality labels.
- Make the variable chain explicit so service depends on environment and pod depends on service.

### Verification

- [ ] Dropdowns populate within a few seconds.
- [ ] Changing a parent variable refreshes children correctly.
- [ ] Panel queries render with the new variable values.

### Notes

- Capture screenshots or API output in the incident ticket if the issue is production-impacting.
- If the issue recurs, convert the manual fix into code through provisioning or dashboard-as-code workflows.

## 4. Grafana slow or timing out on queries

### Symptoms

- Dashboards load slowly
- Prometheus queries hit timeout errors
- Repeated panels or tables freeze the browser

### Likely causes

| Cause | Why it happens |
| --- | --- |
| Expensive PromQL | Histogram or high-cardinality aggregations are too broad |
| Too many panels | One dashboard does the job of many |
| Variable fan-out | Repeated panels create dozens of expensive queries |

### Investigation steps

1. Check panel inspection timings.
2. Review backend logs for slow datasource calls.
3. Identify whether time range, repetition, or raw label breakdowns are the cause.
4. Compare the same query with and without recording rules.

### Commands

```bash
kubectl logs -n monitoring deploy/grafana --since=10m | grep -i query
curl -s http://prometheus-operated.monitoring.svc:9090/api/v1/status/runtimeinfo | jq
```

### Fix example

```yaml
jsonData:
  timeInterval: 30s
  cacheLevel: High
```

### Fix actions

- Use recording rules or recorded queries for expensive expressions.
- Reduce default time range and split dashboards by purpose.
- Avoid repeated panels on pod or route labels unless heavily scoped.

### Verification

- [ ] Dashboard load time drops to an acceptable level.
- [ ] Prometheus queries stop timing out.
- [ ] Operators can open the dashboard during incidents without browser lockups.

### Notes

- Capture screenshots or API output in the incident ticket if the issue is production-impacting.
- If the issue recurs, convert the manual fix into code through provisioning or dashboard-as-code workflows.

## 5. Provisioned dashboard not appearing

### Symptoms

- ConfigMap exists but dashboard is missing
- Grafana logs mention no dashboard provider changes
- UI import works manually but provisioned flow does not

### Likely causes

| Cause | Why it happens |
| --- | --- |
| Wrong sidecar label | The sidecar ignores the ConfigMap |
| Wrong folder path | Dashboard file is copied somewhere Grafana does not watch |
| Invalid JSON | Grafana rejects the dashboard model |

### Investigation steps

1. Inspect sidecar logs.
2. Verify the dashboard file exists inside the Grafana pod.
3. Confirm the provider path matches the mounted folder.
4. Validate the JSON syntax with `jq`.

### Commands

```bash
kubectl logs -n monitoring deploy/grafana -c grafana-sc-dashboard --since=10m
kubectl exec -n monitoring deploy/grafana -c grafana -- ls -R /var/lib/grafana/dashboards
jq . dashboards/service-reliability.json > /dev/null
```

### Fix example

```yaml
providers:
  - name: sre-dashboards
    options:
      path: /var/lib/grafana/dashboards
```

### Fix actions

- Correct the ConfigMap label and reapply.
- Mount or point the provider to the same folder the sidecar writes to.
- Fix invalid JSON and ensure dashboard UIDs are unique.

### Verification

- [ ] Dashboard appears in the expected folder.
- [ ] Grafana API can fetch it by UID.
- [ ] Updating the ConfigMap updates the dashboard after the refresh interval.

### Notes

- Capture screenshots or API output in the incident ticket if the issue is production-impacting.
- If the issue recurs, convert the manual fix into code through provisioning or dashboard-as-code workflows.

## 6. Trace exemplars not showing

### Symptoms

- Latency panel has no exemplar dots
- Tempo traces exist but panel cannot link to them
- Exemplars appear in Prometheus but not Grafana

### Likely causes

| Cause | Why it happens |
| --- | --- |
| No exemplar storage | Prometheus is not storing exemplars |
| Datasource mapping missing | Prometheus datasource lacks exemplarTraceIdDestinations |
| Wrong metric type | Panel uses a non-histogram metric or an aggregate that drops exemplars |

### Investigation steps

1. Confirm instrumentation emits exemplars.
2. Check Prometheus exemplar support and retention.
3. Review the Prometheus datasource JSON settings.
4. Inspect panel options for exemplar display.

### Commands

```bash
curl -s -u admin:admin http://localhost:3000/api/datasources/uid/prometheus-main | jq
grep -n "exemplar" configs/datasources.yml
```

### Fix example

```yaml
jsonData:
  exemplarTraceIdDestinations:
    - name: trace_id
      datasourceUid: tempo-main
```

### Fix actions

- Enable exemplar storage in Prometheus and instrumentation.
- Configure `exemplarTraceIdDestinations` to point to Tempo.
- Use the raw histogram bucket metric in a panel that supports exemplars.

### Verification

- [ ] Exemplar dots appear on the latency chart.
- [ ] Clicking an exemplar opens the related trace.
- [ ] The trace matches the time window of the latency spike.

### Notes

- Capture screenshots or API output in the incident ticket if the issue is production-impacting.
- If the issue recurs, convert the manual fix into code through provisioning or dashboard-as-code workflows.

## Escalation checklist

- [ ] You collected the final rendered query, datasource UID, and relevant logs.
- [ ] You checked whether a silence or mute timing explains suppression.
- [ ] You verified whether the issue is limited to one service, one dashboard, or the entire Grafana instance.
- [ ] You documented the fix and whether code changes are required to prevent recurrence.
