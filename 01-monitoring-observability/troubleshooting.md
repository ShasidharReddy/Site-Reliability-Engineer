# Monitoring & Observability — Troubleshooting Guide

This guide is meant for hands-on incident response.
Each issue follows the same flow:

- symptom
- diagnosis commands
- root cause
- fix
- prevention

Use it as a runbook,
not as a theory note.
Run the commands,
compare the output to expected behavior,
and only then change configuration.

## Quick triage checklist

Before diving into a specific issue,
collect a short baseline:

```bash
kubectl get pods -A
kubectl get svc -A
kubectl get events -A --sort-by=.lastTimestamp | tail -n 30
kubectl top nodes 2>/dev/null || true
```

If the cluster is already unhealthy,
application-level observability symptoms can be misleading.

## 1. Prometheus Issues

### 1.1 Prometheus not scraping targets

**Symptom**

Targets that should be visible under `/targets` are missing or always `DOWN`.
Dashboards show holes,
and alerts based on those series never evaluate.

**Diagnosis commands**

```bash
kubectl get servicemonitors,podmonitors -A
kubectl get endpoints -A | grep -i my-app
kubectl -n monitoring port-forward svc/prometheus-operated 9090:9090
curl -s http://127.0.0.1:9090/api/v1/targets | jq '.data.activeTargets[] | {scrapeUrl: .scrapeUrl, health: .health}'
```

**Root cause explanation**

Common causes are the wrong metrics port,
a missing `ServiceMonitor`,
a selector mismatch,
network policy blocking access,
or an application not actually serving `/metrics`.

**Fix**

```bash
kubectl describe servicemonitor -A | sed -n '/my-app/,+30p'
kubectl patch svc my-app -n app --type merge -p '{"spec":{"ports":[{"name":"metrics","port":9090,"targetPort":9090}]}}'
kubectl rollout restart deploy/my-app -n app
```

**Prevention**

Standardize on a named `metrics` port,
validate `ServiceMonitor` label selectors in review,
and add a synthetic alert on `up == 0` for critical scrape targets.

### 1.2 High cardinality blowing up storage

**Symptom**

Prometheus memory climbs rapidly,
queries get slower,
and TSDB storage usage spikes after a deploy.

**Diagnosis commands**

```bash
kubectl -n monitoring exec -it sts/prometheus-kube-prometheus-prometheus -- promtool tsdb analyze /prometheus | head -n 50
curl -s http://127.0.0.1:9090/api/v1/status/tsdb | jq '.data.labelValueCountByLabelName[:10]'
curl -s 'http://127.0.0.1:9090/api/v1/query?query=topk(20,count%20by(__name__)(%7B__name__!=""%7D))' | jq .
```

**Root cause explanation**

A label with unbounded values,
such as `user_id`, `session_id`, `request_id`, or full URL paths,
creates too many unique time series.
Prometheus stores each unique label set separately.

**Fix**

```bash
kubectl edit servicemonitor my-app -n monitoring
kubectl set env deploy/my-app -n app METRICS_PATH_TEMPLATE=true
kubectl rollout restart deploy/my-app -n app
```

Remove high-cardinality labels from instrumentation,
replace raw URLs with route templates,
and aggregate at scrape time only when absolutely necessary.

**Prevention**

Review new metrics for label explosion,
run `promtool tsdb analyze` periodically,
and reject labels that can grow per request or per user.

### 1.3 Alert not firing when it should

**Symptom**

A dashboard clearly shows a breach,
but the alert stays `Inactive`.

**Diagnosis commands**

```bash
promtool check rules /path/to/rules.yaml
curl -s 'http://127.0.0.1:9090/api/v1/rules' | jq '.data.groups[] | {name: .name, interval: .interval}'
curl -s 'http://127.0.0.1:9090/api/v1/query?query=ALERTS' | jq .
curl -s 'http://127.0.0.1:9090/api/v1/query?query=<replace_with_alert_expr>' | jq .
```

**Root cause explanation**

Most often the expression is fine,
but the `for` duration is longer than the breach,
or the query window and evaluation interval never line up long enough for the alert to become `Firing`.

**Fix**

```bash
kubectl edit prometheusrule -n monitoring app-alerts
kubectl apply -f rules/app-alerts.yaml
curl -s 'http://127.0.0.1:9090/api/v1/rules' | jq '.data.groups[] | select(.name=="app-alerts")'
```

Reduce the `for` value,
verify the metric really stays above threshold,
and test the expression directly in Prometheus before redeploying the rule.

**Prevention**

Document the intended detection time,
choose `for` deliberately,
and test alert rules against realistic traffic patterns before production rollout.

### 1.4 Alert firing constantly or flapping

**Symptom**

An alert alternates between `Pending`, `Firing`, and `Resolved` every few minutes.
Operators stop trusting it.

**Diagnosis commands**

```bash
curl -s 'http://127.0.0.1:9090/api/v1/query_range?query=<alert_expr>&start=2024-01-01T00:00:00Z&end=2024-01-01T01:00:00Z&step=30s' | jq .
curl -s http://127.0.0.1:9090/api/v1/alerts | jq '.data.alerts[] | {labels: .labels, state: .state, activeAt: .activeAt}'
kubectl get prometheusrule -n monitoring -o yaml | sed -n '/for:/p'
```

**Root cause explanation**

Thresholds near normal variance,
small query windows,
and short `for` values produce flapping.
Noisy data leads to noisy alerts.

**Fix**

```bash
kubectl edit prometheusrule -n monitoring app-alerts
kubectl apply -f rules/app-alerts.yaml
```

Increase the range vector,
raise or lower the threshold appropriately,
and set a `for` duration longer than expected short-lived jitter.

**Prevention**

Base thresholds on historical percentiles,
not guesswork,
and always review the graph before approving a new alert.

### 1.5 Prometheus OOM killed

**Symptom**

The Prometheus pod restarts with `OOMKilled`,
queries fail,
and retention may become inconsistent.

**Diagnosis commands**

```bash
kubectl describe pod -n monitoring prometheus-kube-prometheus-prometheus-0 | sed -n '/Last State/,+15p'
kubectl top pod -n monitoring prometheus-kube-prometheus-prometheus-0
kubectl get sts -n monitoring prometheus-kube-prometheus-prometheus -o yaml | sed -n '/retention/,+10p'
```

**Root cause explanation**

Large retention,
high cardinality,
expensive recording rules,
or undersized memory requests cause Prometheus to exceed its container limit.

**Fix**

```bash
kubectl patch prometheus -n monitoring k8s --type merge -p '{"spec":{"retention":"7d","resources":{"requests":{"memory":"4Gi"},"limits":{"memory":"6Gi"}}}}'
kubectl rollout restart statefulset/prometheus-kube-prometheus-prometheus -n monitoring
```

Reduce retention,
remove bad labels,
and size memory based on actual series count instead of default chart values.

**Prevention**

Track `prometheus_tsdb_head_series`,
alert on rapid growth,
and capacity-plan Prometheus as a stateful service rather than a stateless add-on.

### 1.6 TSDB corruption recovery

**Symptom**

Prometheus fails to start,
logs mention block or WAL corruption,
and the pod crashloops.

**Diagnosis commands**

```bash
kubectl logs -n monitoring prometheus-kube-prometheus-prometheus-0 --previous | grep -Ei 'corrupt|WAL|block'
kubectl get pvc -n monitoring
kubectl describe pod -n monitoring prometheus-kube-prometheus-prometheus-0
```

**Root cause explanation**

Unclean shutdowns,
disk issues,
or abrupt node loss can leave WAL segments or blocks unreadable.

**Fix**

```bash
kubectl scale sts -n monitoring prometheus-kube-prometheus-prometheus --replicas=0
kubectl run -n monitoring prom-repair --rm -it --image=quay.io/prometheus/prometheus:v2.53.0 --overrides='{"spec":{"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"prometheus-kube-prometheus-prometheus-db-prometheus-kube-prometheus-prometheus-0"}}],"containers":[{"name":"prom","image":"quay.io/prometheus/prometheus:v2.53.0","command":["/bin/sh","-c","promtool tsdb repair /prometheus && sleep 1"],"volumeMounts":[{"name":"data","mountPath":"/prometheus"}]}]}}'
kubectl scale sts -n monitoring prometheus-kube-prometheus-prometheus --replicas=1
```

If repair fails,
restore from a snapshot or delete only the corrupted WAL/block after a backup.

**Prevention**

Use reliable storage,
avoid force deletion of Prometheus pods,
and snapshot TSDB data before risky maintenance.

### 1.7 Recording rule not updating

**Symptom**

A recording rule exists,
but the generated series is stale or missing.

**Diagnosis commands**

```bash
promtool check rules /path/to/rules.yaml
curl -s 'http://127.0.0.1:9090/api/v1/rules' | jq '.data.groups[] | select(.name=="recording-rules")'
curl -s 'http://127.0.0.1:9090/api/v1/query?query=my_recording_rule_name' | jq .
```

**Root cause explanation**

The group may fail validation,
an upstream series may be absent,
or the evaluation interval is longer than expected.
In some cases a syntax error in one rule blocks the whole group.

**Fix**

```bash
kubectl apply -f rules/recording-rules.yaml
kubectl logs -n monitoring sts/prometheus-kube-prometheus-prometheus | grep -i rule
```

Correct the rule file,
verify the source metrics exist,
and split large rule groups so one bad rule does not hide many others.

**Prevention**

Run `promtool check rules` in CI,
keep rule groups small,
and annotate recordings with their source metrics and owners.

## 2. Grafana Issues

### 2.1 Dashboard shows "No data"

**Symptom**

Panels render,
but the query result says `No data`.

**Diagnosis commands**

```bash
kubectl logs -n monitoring deploy/grafana | grep -Ei 'datasource|error'
curl -s -u admin:admin http://127.0.0.1:3000/api/datasources | jq '.[].name'
curl -s 'http://127.0.0.1:9090/api/v1/query?query=up' | jq .
```

**Root cause explanation**

Either the datasource cannot connect,
the query has a typo,
the panel uses the wrong datasource,
or the selected time range excludes existing data.

**Fix**

```bash
kubectl edit configmap -n monitoring grafana-datasources
kubectl rollout restart deploy/grafana -n monitoring
```

Correct the datasource URL,
validate the query in Prometheus or Loki directly,
and align the dashboard time range with when data exists.

**Prevention**

Provision datasources as code,
review panel JSON in Git,
and build a small smoke-test dashboard after upgrades.

### 2.2 Panels show wrong timezone

**Symptom**

Metrics are correct,
but timestamps do not match local incident timelines.

**Diagnosis commands**

```bash
date -u
kubectl exec -n monitoring deploy/grafana -- date
curl -s -u admin:admin http://127.0.0.1:3000/api/org/preferences | jq .
```

**Root cause explanation**

Grafana can render in browser time,
UTC,
or a configured org preference.
If dashboards assume one timezone while humans use another,
confusion follows.

**Fix**

```bash
curl -s -u admin:admin -X PUT http://127.0.0.1:3000/api/org/preferences \
  -H 'Content-Type: application/json' \
  -d '{"timezone":"utc"}'
```

Alternatively,
set dashboard timezone explicitly in dashboard settings.

**Prevention**

Pick a standard timezone for incident response,
usually UTC,
and document it in the on-call runbook.

### 2.3 Grafana spikes CPU on large time ranges

**Symptom**

Opening a dashboard for `Last 30 days` makes Grafana slow,
and panels load for a long time.

**Diagnosis commands**

```bash
kubectl top pod -n monitoring -l app.kubernetes.io/name=grafana
kubectl logs -n monitoring deploy/grafana | grep -Ei 'timeout|context deadline'
```

**Root cause explanation**

Grafana itself is often not the real bottleneck.
Unbounded queries,
expensive regex filters,
and high-cardinality groupings push heavy work to Prometheus or Loki.

**Fix**

```bash
kubectl edit configmap -n monitoring grafana-dashboard-queries
```

Reduce the time range,
add label selectors,
replace raw queries with recording rules,
and avoid `sum by (pod,instance,container,route,user)` style explosions.

**Prevention**

Design dashboards for common troubleshooting windows,
precompute heavy queries,
and test panels against large time ranges before sharing them widely.

### 2.4 Alert state stuck in Pending

**Symptom**

Grafana alerting shows `Pending` for a long time even though the condition looks true.

**Diagnosis commands**

```bash
curl -s -u admin:admin http://127.0.0.1:3000/api/ruler/grafana/api/v1/rules | jq .
curl -s -u admin:admin http://127.0.0.1:3000/api/alertmanager/grafana/api/v2/alerts | jq .
```

**Root cause explanation**

`Pending` means the condition is true,
but not yet true for long enough.
If the evaluation interval is `1m` and `for` is `5m`,
you need several consecutive evaluations.

**Fix**

```bash
kubectl edit secret -n monitoring grafana-alerting
```

Lower the `for` duration,
shorten the evaluation interval,
or accept that the alert is intentionally de-bounced.

**Prevention**

Write alert rules with a clear expected time-to-detect,
and train operators on the meaning of `Pending` versus `Firing`.

### 2.5 Provisioned dashboard changes not persisting

**Symptom**

A user edits a dashboard in the UI,
refreshes,
and the changes disappear.

**Diagnosis commands**

```bash
kubectl get configmap -n monitoring | grep dashboard
kubectl logs -n monitoring deploy/grafana | grep -Ei 'provision|dashboard'
```

**Root cause explanation**

Provisioned dashboards are source-of-truth controlled by files or ConfigMaps.
UI edits are overwritten on reload.

**Fix**

```bash
kubectl edit configmap -n monitoring grafana-dashboards
kubectl rollout restart deploy/grafana -n monitoring
```

Make changes in the provisioned JSON or YAML,
then redeploy.
Do not rely on UI edits for version-controlled dashboards.

**Prevention**

Document which folders are provisioned,
lock them if needed,
and keep dashboard definitions in Git.

### 2.6 LDAP or OAuth login broken

**Symptom**

Users cannot log in,
or they get redirected in a loop,
or group mapping fails.

**Diagnosis commands**

```bash
kubectl logs -n monitoring deploy/grafana | grep -Ei 'oauth|ldap|auth'
kubectl get secret -n monitoring grafana -o yaml | sed -n '/client_id/,+10p'
curl -k -I https://grafana.example.com/login
```

**Root cause explanation**

Common causes are a bad callback URL,
expired client secret,
wrong LDAP bind DN,
clock skew,
or mismatch between IdP groups and Grafana role mapping.

**Fix**

```bash
kubectl edit secret -n monitoring grafana
kubectl rollout restart deploy/grafana -n monitoring
```

Correct the callback URL,
refresh credentials,
and validate that TLS and DNS both match the external address users actually reach.

**Prevention**

Treat auth settings like application code,
rotate secrets safely,
and test login flows after certificate or ingress changes.

## 3. Alertmanager Issues

### 3.1 Alerts received but no notifications sent

**Symptom**

Prometheus shows active alerts,
but Slack, email, or PagerDuty never receives them.

**Diagnosis commands**

```bash
kubectl logs -n monitoring deploy/alertmanager-kube-prometheus-alertmanager | grep -Ei 'notify|error|receiver'
curl -s http://alertmanager-operated.monitoring.svc:9093/api/v2/alerts | jq .
curl -s http://alertmanager-operated.monitoring.svc:9093/api/v2/status | jq '.config.original'
```

**Root cause explanation**

The route may send alerts to the wrong receiver,
a secret may be missing,
or the receiver endpoint may reject requests.

**Fix**

```bash
kubectl edit secret -n monitoring alertmanager-kube-prometheus-alertmanager
kubectl rollout restart statefulset/alertmanager-kube-prometheus-alertmanager -n monitoring
```

Fix receiver credentials,
verify network egress,
and test the receiver URL with `curl` where possible.

**Prevention**

Use templated config validation in CI,
and keep a low-priority synthetic test alert for every receiver.

### 3.2 Duplicate alert notifications

**Symptom**

The same page arrives multiple times for the same outage.

**Diagnosis commands**

```bash
curl -s http://alertmanager-operated.monitoring.svc:9093/api/v2/status | jq '.config.original'
curl -s http://alertmanager-operated.monitoring.svc:9093/api/v2/alerts/groups | jq .
```

**Root cause explanation**

Grouping keys may be too specific,
multiple routes may match the same alert,
or `repeat_interval` may be too short.
In HA mode,
misconfigured clustering can also duplicate notifications.

**Fix**

```bash
kubectl edit secret -n monitoring alertmanager-kube-prometheus-alertmanager
```

Use broader `group_by` labels,
set `continue: false` unless intentional,
and review the route tree top to bottom.

**Prevention**

Keep routing trees simple,
document why each `continue` exists,
and test with representative alerts before rollout.

### 3.3 Silences not working

**Symptom**

An alert has an active silence,
but notifications still arrive.

**Diagnosis commands**

```bash
curl -s http://alertmanager-operated.monitoring.svc:9093/api/v2/silences | jq .
curl -s http://alertmanager-operated.monitoring.svc:9093/api/v2/alerts | jq '.[] | {labels: .labels, status: .status}'
```

**Root cause explanation**

Silence matchers must exactly match alert labels.
A silence on `service=api` will not mute an alert labeled `app=api` unless both are present.

**Fix**

```bash
curl -s -X POST http://alertmanager-operated.monitoring.svc:9093/api/v2/silences \
  -H 'Content-Type: application/json' \
  -d '{"matchers":[{"name":"alertname","value":"HighLatency","isRegex":false}],"startsAt":"2025-01-01T00:00:00Z","endsAt":"2025-01-01T02:00:00Z","createdBy":"sre","comment":"maintenance"}'
```

Create silences using exact label keys from the live alert payload,
not from memory.

**Prevention**

Standardize label sets on alerts,
and include the full label set in notification templates for easier silencing.

### 3.4 PagerDuty integration broken

**Symptom**

Critical alerts appear in Alertmanager,
but no incidents open in PagerDuty.

**Diagnosis commands**

```bash
kubectl logs -n monitoring sts/alertmanager-kube-prometheus-alertmanager | grep -Ei 'pagerduty|403|401|429'
curl -s http://alertmanager-operated.monitoring.svc:9093/api/v2/status | jq '.config.original' | grep -n pagerduty
```

**Root cause explanation**

PagerDuty failures are usually caused by a wrong integration key,
rate limiting,
or invalid templated payload content.

**Fix**

```bash
kubectl edit secret -n monitoring alertmanager-kube-prometheus-alertmanager
kubectl rollout restart statefulset/alertmanager-kube-prometheus-alertmanager -n monitoring
```

Replace the routing key,
verify the service type in PagerDuty,
and check whether the receiver is configured under `pagerduty_configs` instead of another block.

**Prevention**

Send periodic test notifications,
rotate keys safely,
and alert on Alertmanager notification failures.

### 3.5 Routing tree misconfigured

**Symptom**

Alerts arrive,
but warning alerts go to the critical channel,
or team ownership routes are wrong.

**Diagnosis commands**

```bash
curl -s http://alertmanager-operated.monitoring.svc:9093/api/v2/status | jq '.config.original'
promtool check config /path/to/alertmanager.yaml
```

**Root cause explanation**

Alertmanager routes are matched in order.
A broad parent route can capture alerts before more specific children get a chance.

**Fix**

```bash
kubectl apply -f alertmanager/alertmanager.yaml
kubectl rollout restart statefulset/alertmanager-kube-prometheus-alertmanager -n monitoring
```

Move specific routes above generic ones,
and only use `continue: true` when multiple receivers are intentional.

**Prevention**

Keep route trees shallow,
label alerts consistently,
and test routing with sample payloads before deploying.

## 4. Loki Issues

### 4.1 Logs not appearing in Grafana

**Symptom**

Applications are running,
but Grafana Explore shows no log lines.

**Diagnosis commands**

```bash
kubectl get pods -n monitoring | grep -Ei 'loki|promtail'
kubectl logs -n monitoring ds/promtail | grep -Ei 'error|tail|permission'
curl -s http://loki-gateway.monitoring.svc/loki/api/v1/labels
```

**Root cause explanation**

Promtail may not be collecting files,
labels may not match your query,
or retention may already have expired the relevant logs.

**Fix**

```bash
kubectl edit configmap -n monitoring promtail
kubectl rollout restart ds/promtail -n monitoring
```

Verify the scrape path,
ensure container log paths are mounted,
and query with a broader selector first such as `{namespace="app"}`.

**Prevention**

Use standard labels like `namespace`, `pod`, and `container`,
and keep a known-good query in the runbook.

### 4.2 LogQL query too slow

**Symptom**

Simple searches take a long time,
or Grafana times out.

**Diagnosis commands**

```bash
kubectl logs -n monitoring deploy/loki | grep -Ei 'slow|timeout|querier'
```

**Root cause explanation**

Queries that start with `|= "error"` and no stream selector force Loki to scan too much data.
Regex-heavy filters over broad time ranges make this worse.

**Fix**

```bash
# Bad
{job=~".*"} |= "timeout"

# Better
{namespace="tracing-lab", app="api-gateway"} |= "timeout"
```

Narrow the selector first,
then filter contents,
and shorten the time range.

**Prevention**

Teach users to start with labels,
not text search,
and avoid indexing unnecessary labels that increase stream count.

### 4.3 Loki disk full

**Symptom**

Ingestion fails,
compaction errors appear,
and PVC usage reaches 100%.

**Diagnosis commands**

```bash
kubectl describe pvc -n monitoring | grep -Ei 'loki|Used By'
kubectl logs -n monitoring deploy/loki | grep -Ei 'no space|compactor|retention'
```

**Root cause explanation**

Retention is too long,
compactor is not running,
or a burst of high-volume logs exceeded planned storage.

**Fix**

```bash
kubectl edit secret -n monitoring loki-config
kubectl rollout restart deploy/loki -n monitoring
```

Lower retention,
verify compactor settings,
and expand the PVC if your storage class supports resizing.

**Prevention**

Monitor volume usage,
size retention intentionally,
and keep debug logging disabled by default in production workloads.

### 4.4 Promtail not collecting logs

**Symptom**

Promtail is running,
but a node or workload produces no new log lines in Loki.

**Diagnosis commands**

```bash
kubectl logs -n monitoring ds/promtail | tail -n 50
kubectl describe ds -n monitoring promtail
kubectl exec -n monitoring ds/promtail -- ls -l /var/log/pods | head
```

**Root cause explanation**

Promtail may lack file permissions,
may have the wrong hostPath mounted,
or may miss files after a log rotation race.

**Fix**

```bash
kubectl edit ds -n monitoring promtail
kubectl rollout restart ds/promtail -n monitoring
```

Mount `/var/log/pods` and `/var/lib/docker/containers` or the container runtime equivalent,
and ensure the DaemonSet runs with the right host access.

**Prevention**

Pin tested Promtail configs,
watch for rotation-related warnings,
and validate log collection on every new node pool.

## 5. Tempo / Distributed Tracing Issues

### 5.1 No traces appearing

**Symptom**

Applications report requests,
but Grafana Explore shows no traces.

**Diagnosis commands**

```bash
kubectl logs -n tracing-lab deploy/frontend | grep -Ei 'otlp|export|error'
kubectl logs -n monitoring deploy/tempo | grep -Ei 'receiver|error|grpc'
kubectl exec -n tracing-lab deploy/frontend -- printenv | grep OTEL
```

**Root cause explanation**

The most common problems are the wrong OTLP endpoint,
a TLS mismatch,
exporter protocol mismatch,
or network policy blocking egress to Tempo.

**Fix**

```bash
kubectl set env deploy/frontend -n tracing-lab OTEL_EXPORTER_OTLP_ENDPOINT=http://tempo.monitoring.svc.cluster.local:4317
kubectl set env deploy/api-gateway -n tracing-lab OTEL_EXPORTER_OTLP_ENDPOINT=http://tempo.monitoring.svc.cluster.local:4317
kubectl set env deploy/backend -n tracing-lab OTEL_EXPORTER_OTLP_ENDPOINT=http://tempo.monitoring.svc.cluster.local:4317
```

Also ensure the SDK uses `insecure` mode if the endpoint is plain gRPC inside the cluster.

**Prevention**

Standardize OTEL environment variables,
and add startup logs that print the exporter destination.

### 5.2 Traces truncated or incomplete

**Symptom**

A trace exists,
but expected child spans are missing,
or only the first part of a request path is visible.

**Diagnosis commands**

```bash
kubectl logs -n monitoring deploy/tempo | grep -Ei 'max_bytes_per_trace|discard|limit'
kubectl logs -n tracing-lab deploy/api-gateway | grep -Ei 'span|batch|drop'
```

**Root cause explanation**

Large traces can hit SDK batch limits,
collector processor limits,
or Tempo per-trace limits.
Improper shutdown can also drop buffered spans.

**Fix**

```bash
kubectl edit secret -n monitoring tempo
kubectl rollout restart deploy/tempo -n monitoring
```

Increase trace size limits carefully,
reduce excessively chatty span creation,
and flush exporters gracefully on process shutdown.

**Prevention**

Instrument meaningful operations,
not every loop iteration,
and test shutdown paths during deployments.

### 5.3 Service graph not showing dependencies

**Symptom**

You can open traces,
but Grafana service map is empty or incomplete.

**Diagnosis commands**

```bash
kubectl logs -n monitoring deploy/tempo | grep -Ei 'metrics-generator|service graph|spanmetrics'
curl -s 'http://127.0.0.1:9090/api/v1/label/__name__/values' | jq '.data[]' | grep traces_spanmetrics || true
```

**Root cause explanation**

Tempo can store traces without producing the span metrics or service graph data Grafana expects.
Missing resource attributes such as `service.name` also break graph generation.

**Fix**

```bash
kubectl edit secret -n monitoring tempo
kubectl rollout restart deploy/tempo -n monitoring
```

Enable the metrics generator,
ensure Grafana points service map features to Prometheus,
and set `service.name` in every instrumented service.

**Prevention**

Treat `service.name` as mandatory,
and test service maps as part of tracing rollout validation.

## 6. Node Exporter / Metrics Collection Issues

### 6.1 Node exporter metrics missing

**Symptom**

Host CPU,
filesystem,
or memory graphs are empty for one or more nodes.

**Diagnosis commands**

```bash
kubectl get ds -n monitoring node-exporter -o wide
kubectl logs -n monitoring ds/node-exporter | grep -Ei 'cgroup|permission|collector'
kubectl get nodes -o wide
```

**Root cause explanation**

Node exporter can fail because of cgroup version mismatches,
missing kernel interfaces,
host networking differences,
or DaemonSet scheduling problems.

**Fix**

```bash
kubectl edit ds -n monitoring node-exporter
kubectl rollout restart ds/node-exporter -n monitoring
```

Update collector flags for the node OS,
confirm host mounts are present,
and ensure taints still allow scheduling where required.

**Prevention**

Validate node exporter on every Kubernetes version upgrade,
and keep platform-specific flags documented per cluster type.

### 6.2 kube-state-metrics stale data

**Symptom**

Deployments are scaled,
but dashboards still show old replica counts or status for too long.

**Diagnosis commands**

```bash
kubectl logs -n monitoring deploy/kube-state-metrics | grep -Ei 'watch|list|error|forbidden'
kubectl auth can-i list deployments --as system:serviceaccount:monitoring:kube-state-metrics -A
curl -s 'http://127.0.0.1:9090/api/v1/query?query=kube_deployment_status_replicas' | jq .
```

**Root cause explanation**

Stale kube-state-metrics data usually comes from RBAC failures,
watch reconnect issues,
or the exporter itself lagging behind the API server.

**Fix**

```bash
kubectl rollout restart deploy/kube-state-metrics -n monitoring
kubectl apply -f rbac/kube-state-metrics.yaml
```

Restore missing permissions,
restart the deployment,
and verify watches reconnect successfully.

**Prevention**

Keep RBAC definitions under version control,
and watch exporter error logs after cluster API upgrades.

### 6.3 cAdvisor not reporting container metrics

**Symptom**

Node metrics exist,
but per-container CPU and memory panels are blank.

**Diagnosis commands**

```bash
curl -s 'http://127.0.0.1:9090/api/v1/query?query=container_cpu_usage_seconds_total' | jq .
kubectl get --raw /api/v1/nodes/$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')/proxy/metrics/cadvisor | head
```

**Root cause explanation**

Some managed clusters restrict cAdvisor exposure,
or scrape configs omit kubelet metrics endpoints,
or authentication to kubelet metrics is broken.

**Fix**

```bash
kubectl edit servicemonitor -n monitoring kubelet
kubectl rollout restart statefulset/prometheus-kube-prometheus-prometheus -n monitoring
```

Restore kubelet scrape configuration,
verify TLS and bearer tokens,
and adapt queries if your platform exposes metrics under different names.

**Prevention**

Test kubelet and cAdvisor scrapes after cluster upgrades,
and maintain platform-specific dashboards when metric availability differs.

## Final advice

When debugging observability problems,
separate three questions:

1. is the workload healthy?
2. is the signal being produced?
3. is the signal being transported and queried correctly?

That order prevents wasted time.
A broken dashboard is sometimes just a broken app.
A missing alert is sometimes a valid `for` duration.
A missing trace is often only one bad endpoint variable away from working.
