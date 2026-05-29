# Lab 01: Build a Golden Signals Dashboard

## Overview
Build a complete production-grade Golden Signals Grafana dashboard for an HTTP service.

## Prerequisites
- Grafana running (port 3000)
- Prometheus running (port 9090) with http_requests_total, http_request_duration_seconds metrics
- Or use the deploy-monitoring-stack.sh script from /scripts/

## Part 1: Create a Folder
1. Grafana UI → Dashboards → New Folder → name it "Production Services"
2. Or via API:
```bash
curl -s -X POST http://admin:admin@localhost:3000/api/folders \
  -H 'Content-Type: application/json' \
  -d '{"title": "Production Services", "uid": "prod-services"}'
```

## Part 2: Create Dashboard with Variables
1. Click + → Dashboard → Settings
2. Add variables:
   - Name: `namespace`, Query: `label_values(up, namespace)`, type: Query
   - Name: `service`, Query: `label_values(up{namespace="$namespace"}, job)`, depends on namespace
3. Save variable settings

## Part 3: Add Golden Signal Panels

### Panel 1 — Request Rate (Stat + Time Series)
- New panel → Time series
- Query: `sum(rate(http_requests_total{job="$service"}[5m]))`
- Title: "Request Rate (req/s)"
- Unit: "requests/sec"
- Thresholds: >1000 yellow, >5000 red

### Panel 2 — Error Rate
- New panel → Stat
- Query A (errors): `sum(rate(http_requests_total{job="$service", status_code=~"5.."}[5m]))`
- Query B (total): `sum(rate(http_requests_total{job="$service"}[5m]))`
- Expression C: `$A / $B * 100`
- Unit: percent
- Thresholds: >1 yellow, >5 red

### Panel 3 — Latency Percentiles
- New panel → Time series
- Query p50: `histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket{job="$service"}[5m])) by (le))`
- Query p95: `histogram_quantile(0.95, ...)`
- Query p99: `histogram_quantile(0.99, ...)`
- Unit: seconds (s), auto scale

### Panel 4 — CPU Saturation
- New panel → Time series
- Query: `sum(rate(container_cpu_usage_seconds_total{namespace="$namespace"}[5m])) by (pod)`
- Title: "Pod CPU Usage"

## Part 4: Layout and Polish
1. Arrange panels in Golden Signals order (traffic, errors, latency, saturation)
2. Add a Row for each section
3. Set default time range: last 1 hour
4. Save: Ctrl+S → Title: "Service Golden Signals — $service"

## Verification
- [ ] Dashboard loads without errors
- [ ] Variables filter panels correctly
- [ ] Panels show real data
- [ ] Error panel shows % correctly
- [ ] Save to folder "Production Services"
