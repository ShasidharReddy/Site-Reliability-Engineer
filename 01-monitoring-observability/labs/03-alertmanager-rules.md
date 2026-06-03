# Lab 03 — Prometheus Rules and Alertmanager Routing

## Overview

This lab covers the full alerting path:

- writing **recording rules**
- writing **alerting rules**
- implementing **multi-window multi-burn-rate SLO alerts**
- configuring **Alertmanager routing**
- adding **silence** and **inhibit** rules
- validating everything with **promtool** and **amtool**

By the end, you should be able to move from “query works” to “alert reliably reaches the right human”.

---

## Prerequisites

- Lab 01 completed
- Prometheus and Alertmanager running in `monitoring`
- `promtool` installed locally
- `amtool` installed locally
- optional Slack and PagerDuty credentials available for end-to-end testing

### Tool Checks

```bash
promtool --version
amtool --version
kubectl get pods -n monitoring
kubectl get prometheus,alertmanager -n monitoring
```

---

## Alerting Design Principles

Before writing rules, follow these guidelines:

- alerts should be actionable
- use labels for routing, not long descriptions
- use annotations for human context
- aggregate noisy dimensions away where possible
- reserve paging for user-impacting or urgent failures
- add runbook links to every meaningful alert

A mature alert usually includes these labels:

- `severity`
- `team`
- `service`
- `cluster`
- `namespace`
- `slo` when relevant

---

## Step 1 — Write Recording Rules First

Recording rules make dashboards and alert queries cheaper and more consistent.

Create `sre-rules.yaml` while following this lab:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: sre-recording-rules
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: service.recording.rules
      interval: 30s
      rules:
        - record: job:http_requests:rate5m
          expr: sum(rate(http_requests_total[5m])) by (job, namespace, service)

        - record: job:http_errors:rate5m
          expr: sum(rate(http_requests_total{status_code=~"5.."}[5m])) by (job, namespace, service)

        - record: job:http_error_ratio:rate5m
          expr: job:http_errors:rate5m / job:http_requests:rate5m

        - record: job:http_latency_p95:5m
          expr: |
            histogram_quantile(
              0.95,
              sum(rate(http_request_duration_seconds_bucket[5m])) by (job, namespace, service, le)
            )

        - record: job:slo_errors_per_request:ratio_rate5m
          expr: |
            sum(rate(http_requests_total{status_code=~"5.."}[5m])) by (job, namespace, service)
            /
            sum(rate(http_requests_total[5m])) by (job, namespace, service)

        - record: job:slo_errors_per_request:ratio_rate30m
          expr: |
            sum(rate(http_requests_total{status_code=~"5.."}[30m])) by (job, namespace, service)
            /
            sum(rate(http_requests_total[30m])) by (job, namespace, service)

        - record: job:slo_errors_per_request:ratio_rate1h
          expr: |
            sum(rate(http_requests_total{status_code=~"5.."}[1h])) by (job, namespace, service)
            /
            sum(rate(http_requests_total[1h])) by (job, namespace, service)

        - record: job:slo_errors_per_request:ratio_rate6h
          expr: |
            sum(rate(http_requests_total{status_code=~"5.."}[6h])) by (job, namespace, service)
            /
            sum(rate(http_requests_total[6h])) by (job, namespace, service)

        - record: job:slo_errors_per_request:ratio_rate3d
          expr: |
            sum(rate(http_requests_total{status_code=~"5.."}[3d])) by (job, namespace, service)
            /
            sum(rate(http_requests_total[3d])) by (job, namespace, service)
```

Apply it:

```bash
kubectl apply -f sre-rules.yaml
```

Validate it:

```bash
kubectl get prometheusrule -n monitoring sre-recording-rules -o yaml
curl -s http://localhost:9090/api/v1/rules | jq '.data.groups[] | select(.name=="service.recording.rules")'
```

---

## Step 2 — Add Alerting Rules

Now create alerting rules that consume the recording rules.

Append or create a second `PrometheusRule` manifest:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: sre-alert-rules
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: sre.alerts
      interval: 30s
      rules:
        - alert: PrometheusTargetDown
          expr: up == 0
          for: 5m
          labels:
            severity: critical
            team: platform
          annotations:
            summary: "Prometheus target {{ $labels.job }} on {{ $labels.instance }} is down"
            description: "The scrape target has been unreachable for 5 minutes. Check service discovery, endpoints, TLS, and network policy."
            runbook_url: "https://runbooks.example.com/prometheus-target-down"

        - alert: NodeMemoryHigh
          expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 85
          for: 10m
          labels:
            severity: warning
            team: platform
          annotations:
            summary: "Node {{ $labels.instance }} memory usage is high"
            description: "Memory usage is above 85% for 10 minutes on {{ $labels.instance }}"
            runbook_url: "https://runbooks.example.com/node-memory-high"

        - alert: ServiceHighErrorRate
          expr: job:http_error_ratio:rate5m > 0.02
          for: 10m
          labels:
            severity: warning
            team: app
          annotations:
            summary: "High 5xx ratio for {{ $labels.service }}"
            description: "The 5 minute error ratio for {{ $labels.service }} is above 2%."
            runbook_url: "https://runbooks.example.com/service-high-error-rate"

        - alert: ServiceLatencyP95High
          expr: job:http_latency_p95:5m > 0.75
          for: 10m
          labels:
            severity: warning
            team: app
          annotations:
            summary: "P95 latency high for {{ $labels.service }}"
            description: "The 95th percentile latency has exceeded 750ms for 10 minutes."
            runbook_url: "https://runbooks.example.com/service-latency-p95-high"
```

Apply it:

```bash
kubectl apply -f sre-alert-rules.yaml
```

---

## Step 3 — Implement Multi-Window Multi-Burn-Rate SLO Alerts

This is the recommended way to alert on SLO consumption without paging on every tiny spike.

### Example SLO

Assume:

- service availability target = **99.9%**
- allowed error budget = **0.1%** = `0.001`

### Why Burn Rate Matters

Burn rate describes how fast you are consuming the error budget.

Examples:

- burn rate `1` = consuming budget exactly at allowed pace
- burn rate `14.4` = consuming budget 14.4 times faster than allowed

### Page-Level SLO Alerts

Create another rule group:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: sre-slo-alerts
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: sre.slo.alerts
      interval: 30s
      rules:
        - alert: SLOErrorBudgetBurnFast
          expr: |
            (
              job:slo_errors_per_request:ratio_rate1h > (14.4 * 0.001)
            )
            and
            (
              job:slo_errors_per_request:ratio_rate5m > (14.4 * 0.001)
            )
          for: 2m
          labels:
            severity: critical
            team: app
            slo: availability
          annotations:
            summary: "Fast error budget burn for {{ $labels.service }}"
            description: "The service is burning the 99.9% availability budget extremely fast over both 5m and 1h windows."
            runbook_url: "https://runbooks.example.com/slo-fast-burn"

        - alert: SLOErrorBudgetBurnMedium
          expr: |
            (
              job:slo_errors_per_request:ratio_rate6h > (6 * 0.001)
            )
            and
            (
              job:slo_errors_per_request:ratio_rate30m > (6 * 0.001)
            )
          for: 15m
          labels:
            severity: warning
            team: app
            slo: availability
          annotations:
            summary: "Medium error budget burn for {{ $labels.service }}"
            description: "The service is consuming the availability error budget too quickly over 30m and 6h windows."
            runbook_url: "https://runbooks.example.com/slo-medium-burn"

        - alert: SLOErrorBudgetBurnSlow
          expr: job:slo_errors_per_request:ratio_rate3d > (1 * 0.001)
          for: 1h
          labels:
            severity: info
            team: app
            slo: availability
          annotations:
            summary: "Slow error budget burn for {{ $labels.service }}"
            description: "The service is slowly draining the availability error budget over a 3 day window."
            runbook_url: "https://runbooks.example.com/slo-slow-burn"
```

### Why These Windows Work

- short + long windows reduce noise
- short window catches current impact
- long window confirms sustained damage
- fast alerts are page-worthy
- slow alerts are better for tickets and planning

---

## Step 4 — Validate with `promtool`

Validate syntax before applying manifests.

```bash
promtool check rules sre-rules.yaml
promtool check rules sre-alert-rules.yaml
```

Validate a full Alertmanager config file later with:

```bash
promtool check config alertmanager-config.yaml
```

### Why `promtool` Matters

It catches:

- YAML formatting issues
- invalid PromQL expressions
- broken rule groups
- some template mistakes before rollout

---

## Step 5 — Configure Alertmanager Routing

Create `alertmanager-config.yaml` with multiple receivers.

```yaml
global:
  resolve_timeout: 5m
  slack_api_url_file: /etc/alertmanager/secrets/alertmanager-secrets/SLACK_WEBHOOK_URL

templates:
  - /etc/alertmanager/templates/*.tmpl

route:
  receiver: slack-default
  group_by: [alertname, cluster, service, namespace]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    - matchers:
        - severity="critical"
      receiver: pagerduty-critical
      continue: true

    - matchers:
        - severity="critical"
      receiver: slack-critical

    - matchers:
        - team="platform"
      receiver: slack-platform

    - matchers:
        - severity="info"
      receiver: email-digest
      group_wait: 10m
      group_interval: 30m
      repeat_interval: 24h

receivers:
  - name: slack-default
    slack_configs:
      - channel: '#alerts-general'
        send_resolved: true
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'

  - name: slack-critical
    slack_configs:
      - channel: '#alerts-critical'
        send_resolved: true
        color: danger
        title: 'CRITICAL: {{ .GroupLabels.alertname }}'
        text: |
          {{ range .Alerts }}
          Service: {{ .Labels.service }}
          Summary: {{ .Annotations.summary }}
          Runbook: {{ .Annotations.runbook_url }}
          {{ end }}

  - name: slack-platform
    slack_configs:
      - channel: '#platform-alerts'
        send_resolved: true
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

  - name: pagerduty-critical
    pagerduty_configs:
      - routing_key_file: /etc/alertmanager/secrets/alertmanager-secrets/PAGERDUTY_INTEGRATION_KEY
        send_resolved: true
        severity: critical
        description: '{{ .GroupLabels.alertname }} for {{ .CommonLabels.service }}'
        details:
          cluster: '{{ .CommonLabels.cluster }}'
          namespace: '{{ .CommonLabels.namespace }}'
          runbook: '{{ (index .Alerts 0).Annotations.runbook_url }}'

  - name: email-digest
    email_configs:
      - to: sre-team@example.com
        send_resolved: true
        headers:
          Subject: '[SRE] {{ .Status | toUpper }} {{ .GroupLabels.alertname }}'

inhibit_rules:
  - source_matchers:
      - alertname="PrometheusTargetDown"
    target_matchers:
      - alertname=~"ServiceHighErrorRate|ServiceLatencyP95High"
    equal: [cluster, namespace, service]

  - source_matchers:
      - severity="critical"
    target_matchers:
      - severity="warning"
    equal: [alertname, cluster, namespace, service]
```

### Apply Through the Kubernetes Secret Path

If using `kube-prometheus-stack`, Alertmanager config is commonly mounted from a secret or values file.
One pattern is:

```bash
kubectl create secret generic alertmanager-kube-prometheus-stack-alertmanager \
  --namespace monitoring \
  --from-file=alertmanager.yaml=alertmanager-config.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
```

Restart if required by your deployment mode:

```bash
kubectl rollout restart statefulset -n monitoring alertmanager-kube-prometheus-stack-alertmanager
```

---

## Step 6 — Add Silence and Inhibit Rules

### Manual Silence via UI

- open Alertmanager UI
- find a firing alert
- create a silence for `service=checkout` or `namespace=payments`
- add clear owner and expiration

### Silence via `amtool`

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
```

In another shell:

```bash
amtool --alertmanager.url=http://127.0.0.1:9093 silence add \
  alertname=ServiceHighErrorRate \
  service=checkout \
  --duration=2h \
  --author='sre-lab' \
  --comment='Silence during controlled load test'
```

List silences:

```bash
amtool --alertmanager.url=http://127.0.0.1:9093 silence query
```

Expire or delete when done.

### Inhibition Example

If `PrometheusTargetDown` is firing for a service, you generally do not want separate symptom alerts for that same service continuing to notify.

That is why inhibition should model parent-child relationships.

---

## Step 7 — Trigger and Trace Test Alerts

### Force a Target Down Alert

Scale a demo deployment to zero or change the service selector so Prometheus cannot scrape it.

Example:

```bash
kubectl scale deployment -n observability-demo demo-metrics-app --replicas=0
```

Watch the alert:

```bash
curl -s http://localhost:9090/api/v1/alerts | jq '.data.alerts[] | {name: .labels.alertname, state: .state, severity: .labels.severity}'
```

Restore service afterward:

```bash
kubectl scale deployment -n observability-demo demo-metrics-app --replicas=2
```

### Trigger a Synthetic Alert in Alertmanager

If you want to test routing quickly, send a fabricated alert directly:

```bash
amtool --alertmanager.url=http://127.0.0.1:9093 alert add \
  alertname=ManualCriticalTest \
  severity=critical \
  service=checkout \
  team=app \
  cluster=sre-lab \
  namespace=payments
```

Then confirm whether:

- Slack received the message
- PagerDuty created an incident
- Alertmanager grouped the alert correctly

---

## Step 8 — Test PagerDuty and Slack Receivers

### Slack Validation

- confirm alert arrived in the expected channel
- verify title, summary, and runbook text render correctly
- confirm resolved notification also appears if enabled

### PagerDuty Validation

- use a test integration or maintenance window
- confirm incident title includes service or alert name
- verify deduplication key behavior if using repeated alerts
- verify resolved state closes the incident if configured

### Receiver Checklist

- [ ] secret exists and is mounted
- [ ] Alertmanager config references the correct file path
- [ ] route matchers align with alert labels
- [ ] contact point works outside Alertmanager if tested manually

---

## Step 9 — Test with `amtool`

Useful commands:

```bash
amtool --alertmanager.url=http://127.0.0.1:9093 config show
amtool --alertmanager.url=http://127.0.0.1:9093 alert query
amtool --alertmanager.url=http://127.0.0.1:9093 silence query
amtool --alertmanager.url=http://127.0.0.1:9093 cluster show
```

What to validate:

- config loaded as expected
- routes are present
- silences are active
- HA peers appear healthy if multiple replicas are running

---

## Validation Checklist

### Rules

- [ ] recording rules load without errors
- [ ] alerting rules load without errors
- [ ] burn-rate rules evaluate successfully
- [ ] Prometheus UI shows expected groups and alerts

### Alertmanager

- [ ] routing tree sends warnings and critical alerts differently
- [ ] inhibition suppresses lower-priority symptoms
- [ ] silences mute matching alerts temporarily
- [ ] `amtool` can query config and active alerts

### Notification Path

- [ ] critical alerts can reach PagerDuty
- [ ] Slack messages contain summary and runbook info
- [ ] resolved notifications behave as expected

---

## Common Errors

### Error: Rule file applies but no alert ever fires

Possible causes:

- label names in the query do not exist
- service has too little traffic for the window used
- `for:` duration is too long for the test
- recording rules were never loaded

Diagnosis:

```bash
curl -s http://localhost:9090/api/v1/rules | jq
curl -sG http://localhost:9090/api/v1/query --data-urlencode 'query=job:http_error_ratio:rate5m' | jq
```

### Error: Alert fires but Alertmanager does not route it correctly

Possible causes:

- route matchers expect labels not present in the alert
- wrong secret mounted
- syntax error in Alertmanager config
- alert hits default receiver because matcher never matches

Diagnosis:

```bash
amtool --alertmanager.url=http://127.0.0.1:9093 config show
amtool --alertmanager.url=http://127.0.0.1:9093 alert query
kubectl logs -n monitoring statefulset/alertmanager-kube-prometheus-stack-alertmanager -c alertmanager
```

### Error: PagerDuty never receives the alert

Possible causes:

- bad integration key
- network egress restriction
- route does not continue into the PagerDuty receiver
- notification template or secret path is broken

Diagnosis:

- inspect Alertmanager logs
- verify secret contents and mount path
- send a manual test event to PagerDuty outside Alertmanager

### Error: Inhibition suppresses too much

Possible causes:

- `equal` fields too broad
- parent alert labels are missing or overly generic

Fix:

- make inhibition relationships explicit
- limit shared labels to true scope boundaries

---

## Final Result

You have completed this lab successfully when you can explain, with evidence:

- which rules calculate the SLI
- which rules page and which only notify chat
- which Alertmanager route receives which alert
- which inhibition rule suppresses symptom noise
- how to validate the configuration with `promtool` and `amtool`

That is the foundation of production alerting.