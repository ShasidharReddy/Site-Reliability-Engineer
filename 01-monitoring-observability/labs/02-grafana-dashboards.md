# Lab 02 — Building Production-Grade Grafana Dashboards

## Overview
Create a Kubernetes monitoring dashboard with variables, annotations, thresholds, and export it as JSON.

## Prerequisites
- Lab 01 completed (Prometheus + Grafana running)
- Port-forward Grafana: `kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &`

## Steps

### 1. Create a new dashboard
- Grafana UI → "+" → New Dashboard → Add new panel

### 2. Panel 1 — Cluster CPU Usage (Time Series)
**Query**:
```promql
100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```
**Settings**:
- Title: "Cluster CPU Usage %"
- Unit: Percent (0-100)
- Thresholds: 70 = yellow, 85 = red
- Fill opacity: 10

### 3. Panel 2 — Node Memory Usage (Stat Panel)
**Query**:
```promql
(1 - sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes)) * 100
```
**Settings**:
- Panel type: Stat
- Unit: percent (0-100)
- Thresholds: 80 = orange, 90 = red
- Color mode: Background

### 4. Panel 3 — Pod Count by Namespace (Bar Gauge)
**Query**:
```promql
count(kube_pod_info{phase="Running"}) by (namespace)
```
**Settings**:
- Panel type: Bar gauge
- Legend: {{namespace}}
- Orientation: Horizontal

### 5. Add Variables (dynamic filtering)
Dashboard Settings → Variables → New Variable:
```
Name: namespace
Type: Query
Data source: Prometheus
Query: label_values(kube_pod_info, namespace)
Multi-value: ON
Include All: ON
```

Update panel queries to use the variable:
```promql
count(kube_pod_info{namespace=~"$namespace"}) by (namespace)
```

### 6. Panel 4 — HTTP Request Rate (requires sample app)
```promql
sum(rate(http_requests_total{namespace=~"$namespace"}[5m])) by (service)
```

### 7. Add Annotations
Dashboard Settings → Annotations → New:
```
Name: Deployments
Data source: Prometheus
Query: changes(kube_deployment_status_observed_generation{namespace=~"$namespace"}[2m]) > 0
Title: Deployment changed: {{deployment}}
```

### 8. Set Panel Alerts
In a Time Series panel → Alert tab:
```
Condition: WHEN avg() OF query(A, 5m, now) IS ABOVE 85
Evaluate every: 1m For: 5m
```

### 9. Export Dashboard JSON
Dashboard → Share → Export → Export for sharing externally → Download JSON

### 10. Import Dashboard (Grafana Community)
Grafana UI → "+" → Import:
- Enter ID `315` — Kubernetes cluster monitoring by Instrumentalapp
- Enter ID `1860` — Node Exporter Full
- Enter ID `13332` — Kube State Metrics v2

## Best Practices
- ✅ Always add a `$datasource` variable for portability
- ✅ Link related dashboards via panel drill-down
- ✅ Use consistent color scheme: green=good, yellow=warn, red=critical
- ✅ Add description to every panel explaining what it measures
- ❌ Don't use pie charts for time-series data
- ❌ Don't create dashboards only you can read
