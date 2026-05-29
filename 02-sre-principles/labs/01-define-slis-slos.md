# Lab 01 — Define SLIs, Write SLO Alert Rules

## Overview
Define SLIs for a sample HTTP service, implement multi-window burn rate alerts, and build an SLO dashboard in Grafana.

## Prerequisites
- Lab 01-01 completed (Prometheus running with kube-prometheus-stack)
- Sample app serving HTTP metrics

## Step 1 — Define Your SLIs

For a sample API service, define:
```yaml
# Document your SLIs (save as slo-definition.yaml)
service: api-service
slos:
  - name: availability
    description: "% of requests that return a non-5xx response"
    sli_query: |
      sum(rate(http_requests_total{status!~"5.."}[{{.window}}]))
      / sum(rate(http_requests_total[{{.window}}]))
    target: 0.999  # 99.9%
    window: 30d

  - name: latency-p99
    description: "% of requests completing under 500ms"
    sli_query: |
      sum(rate(http_request_duration_seconds_bucket{le="0.5"}[{{.window}}]))
      / sum(rate(http_request_duration_seconds_count[{{.window}}]))
    target: 0.995  # 99.5%
    window: 7d
```

## Step 2 — Create Recording Rules for SLIs
```bash
kubectl apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: slo-recording-rules
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
  - name: slo.recording
    interval: 30s
    rules:
    # Short-window error ratio (for fast-burn detection)
    - record: job:http_error_ratio:rate5m
      expr: |
        sum(rate(http_requests_total{status=~"5.."}[5m])) by (job)
        / sum(rate(http_requests_total[5m])) by (job)

    # Long-window error ratio (for slow-burn detection)
    - record: job:http_error_ratio:rate1h
      expr: |
        sum(rate(http_requests_total{status=~"5.."}[1h])) by (job)
        / sum(rate(http_requests_total[1h])) by (job)

    - record: job:http_error_ratio:rate6h
      expr: |
        sum(rate(http_requests_total{status=~"5.."}[6h])) by (job)
        / sum(rate(http_requests_total[6h])) by (job)

    - record: job:http_error_ratio:rate24h
      expr: |
        sum(rate(http_requests_total{status=~"5.."}[24h])) by (job)
        / sum(rate(http_requests_total[24h])) by (job)

  - name: slo.alerts
    rules:
    # CRITICAL: Fast burn — will exhaust 1h budget in 5 minutes (14.4x burn rate)
    - alert: SLOBurnRateCritical
      expr: |
        job:http_error_ratio:rate5m > (14.4 * 0.001)
        AND
        job:http_error_ratio:rate1h > (14.4 * 0.001)
      for: 2m
      labels:
        severity: critical
        slo: availability
      annotations:
        summary: "CRITICAL: SLO burn rate too high for {{ $labels.job }}"
        description: "Error rate {{ $value | humanizePercentage }} burning error budget at 14.4x"

    # WARNING: Slow burn — will exhaust budget in 6 hours (6x burn rate)
    - alert: SLOBurnRateHigh
      expr: |
        job:http_error_ratio:rate1h > (6 * 0.001)
        AND
        job:http_error_ratio:rate6h > (6 * 0.001)
      for: 15m
      labels:
        severity: warning
        slo: availability
      annotations:
        summary: "WARNING: SLO burn rate elevated for {{ $labels.job }}"
        description: "Error rate burning budget at 6x — investigate before budget exhausted"
EOF
```

## Step 3 — Calculate Error Budget Remaining
```promql
# Error budget remaining (%) for last 30 days
# SLO = 99.9%, so budget = 0.1%
(
  1 - (
    sum(rate(http_requests_total{status=~"5.."}[30d]))
    / sum(rate(http_requests_total[30d]))
  ) / 0.001
) * 100
```

## Step 4 — Build SLO Dashboard in Grafana

Create a new dashboard with these panels:

**Panel 1 — Current SLI (Stat)**
```promql
1 - (sum(rate(http_requests_total{status=~"5.."}[1h])) / sum(rate(http_requests_total[1h])))
```
Thresholds: < 0.999 = red, < 0.9995 = yellow, >= 0.9995 = green

**Panel 2 — Error Budget Remaining (Gauge)**
```promql
(0.001 - sum(rate(http_requests_total{status=~"5.."}[30d])) / sum(rate(http_requests_total[30d]))) / 0.001 * 100
```
Thresholds: < 25 = red, < 50 = yellow, >= 50 = green

**Panel 3 — Burn Rate (Time Series)**
```promql
# Overlay 5m and 1h burn rates
job:http_error_ratio:rate5m / 0.001
job:http_error_ratio:rate1h / 0.001
```
Reference lines at y=14.4 (critical) and y=6 (warning)

## Verification
- [ ] Recording rules appear in Prometheus Status → Rules
- [ ] Dashboard shows current SLI value
- [ ] Error budget gauge shows remaining budget
- [ ] Trigger 5xx errors and watch burn rate spike
