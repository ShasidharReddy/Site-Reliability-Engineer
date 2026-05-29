# Lab 03 — Writing and Testing Prometheus Alert Rules

## Overview
Write PrometheusRule resources for common SRE scenarios, configure Alertmanager routing, and test alerts.

## Prerequisites
- Lab 01 completed (kube-prometheus-stack running)

## Step 1 — Write PrometheusRules

```bash
kubectl apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: sre-alert-rules
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
  - name: kubernetes.reliability
    rules:

    # Pod has restarted more than 5 times in 15 minutes
    - alert: PodCrashLooping
      expr: increase(kube_pod_container_status_restarts_total[15m]) > 5
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Pod {{ $labels.pod }} is crash-looping"
        description: "Pod {{ $labels.namespace }}/{{ $labels.pod }} has restarted {{ $value }} times in 15m"
        runbook_url: "https://runbooks.example.com/pod-crashloop"

    # Node memory > 85%
    - alert: NodeMemoryHigh
      expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 85
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Node {{ $labels.instance }} memory > 85%"
        description: "Memory usage is {{ printf \"%.1f\" $value }}% on {{ $labels.instance }}"

    # Node memory critical > 95%
    - alert: NodeMemoryCritical
      expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 95
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "CRITICAL: Node {{ $labels.instance }} memory > 95%"

    # API error rate > 1%
    - alert: HighErrorRate
      expr: |
        sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)
        /
        sum(rate(http_requests_total[5m])) by (service) * 100 > 1
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High error rate on {{ $labels.service }}"
        description: "Error rate is {{ printf \"%.2f\" $value }}% on service {{ $labels.service }}"

    # Pod not ready
    - alert: PodNotReady
      expr: kube_pod_status_ready{condition="true"} == 0
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "Pod {{ $labels.pod }} not ready for 10 minutes"

    # Disk filling up
    - alert: DiskSpaceLow
      expr: (node_filesystem_avail_bytes{fstype!~"tmpfs|fuse.lxcfs"} / node_filesystem_size_bytes) * 100 < 20
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Disk space low on {{ $labels.instance }}: {{ $labels.mountpoint }}"

    # Target down
    - alert: PrometheusTargetDown
      expr: up == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Prometheus target {{ $labels.instance }} is DOWN"
EOF
```

## Step 2 — Configure Alertmanager Routing to Slack

```bash
# Create Slack webhook secret (replace with real webhook URL)
kubectl create secret generic alertmanager-slack \
  --from-literal=webhook_url="https://hooks.slack.com/services/YOUR/WEBHOOK/URL" \
  -n monitoring

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: alertmanager-kube-prometheus-stack
  namespace: monitoring
stringData:
  alertmanager.yaml: |
    global:
      slack_api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
      resolve_timeout: 5m

    route:
      receiver: default-slack
      group_by: ['alertname', 'namespace']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      routes:
        - match:
            severity: critical
          receiver: critical-slack
          continue: true
        - match:
            severity: warning
          receiver: warning-slack

    receivers:
      - name: default-slack
        slack_configs:
          - channel: '#alerts-default'
            send_resolved: true
            title: '{{ template "slack.default.title" . }}'
            text: '{{ template "slack.default.text" . }}'

      - name: critical-slack
        slack_configs:
          - channel: '#alerts-critical'
            send_resolved: true
            color: 'danger'
            title: '🔴 CRITICAL: {{ .GroupLabels.alertname }}'
            text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

      - name: warning-slack
        slack_configs:
          - channel: '#alerts-warning'
            send_resolved: true
            color: 'warning'
            title: '🟡 WARNING: {{ .GroupLabels.alertname }}'

    inhibit_rules:
      - source_match:
          severity: critical
        target_match:
          severity: warning
        equal: ['alertname', 'namespace']
EOF
```

## Step 3 — Trigger a Test Alert

```bash
# Force a pod into CrashLoopBackOff
kubectl run crash-test --image=busybox --restart=Always -- /bin/sh -c "exit 1"

# Watch restarts increase
watch kubectl get pod crash-test

# Check alert in Prometheus UI → Alerts tab
# Should see PodCrashLooping in FIRING state after 5m

# Clean up
kubectl delete pod crash-test
```

## Step 4 — Test AlertManager Routing

```bash
# Port-forward Alertmanager UI
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093 &
open http://localhost:9093

# Create a test silence (suppress for 1 hour)
curl -X POST http://localhost:9093/api/v2/silences \
  -H 'Content-Type: application/json' \
  -d '{
    "matchers": [{"name": "alertname", "value": "TestAlert", "isRegex": false}],
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
    "endsAt": "'$(date -u -v+1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "+1 hour" +%Y-%m-%dT%H:%M:%SZ)'",
    "createdBy": "sre-lab",
    "comment": "Test silence"
  }'
```

## Verification Checklist
- [ ] PrometheusRule created: `kubectl get prometheusrules -n monitoring`
- [ ] Alert appears in Prometheus UI → Alerts
- [ ] Alert routes to correct Alertmanager receiver
- [ ] Silence works in Alertmanager UI
