# Grafana Advanced Theory

## 1. Grafana Architecture

```
                    ┌──────────────────────────────────┐
                    │           Grafana Server          │
  Browser  ────────▶│  Frontend (React)                 │
                    │  Backend (Go)                     │
                    │    - Plugin manager               │
                    │    - Query multiplexer            │
                    │    - Auth middleware               │
                    │    - Alerting engine               │
                    └──────┬───────────────┬────────────┘
                           │               │
               ┌───────────▼───┐   ┌───────▼──────────┐
               │  Prometheus   │   │   Grafana DB      │
               │  Loki         │   │  (SQLite/Postgres)│
               │  Tempo        │   │  Dashboards,      │
               │  CloudWatch   │   │  Users, Alerts    │
               └───────────────┘   └──────────────────┘
```

## 2. Dashboard Design Principles

### Golden Signals Layout
Every service dashboard should have this structure:
```
Row 1: Overview (SLO status, error budget, key thresholds)
Row 2: Traffic (requests/sec, active connections)
Row 3: Errors (error rate %, count, by type/path)
Row 4: Latency (p50, p95, p99 heatmap)
Row 5: Saturation (CPU, memory, disk I/O, queue depth)
Row 6: Dependencies (downstream service health)
```

### Variable Design
```yaml
# Chained variables — second depends on first
variable: cluster
  query: label_values(up, cluster)
  type: query
  
variable: namespace
  query: label_values(up{cluster="$cluster"}, namespace)
  depends_on: cluster
  
variable: service  
  query: label_values(up{cluster="$cluster", namespace="$namespace"}, job)
  depends_on: [cluster, namespace]
```

### Repeat Panels
```json
{
  "repeat": "service",        // Variable to repeat for
  "repeatDirection": "h",     // h=horizontal, v=vertical
  "maxPerRow": 4,             // Panels per row
  "datasource": "$datasource" // Always variable
}
```

## 3. PromQL for Dashboards

### Request Rate with Method Breakdown
```promql
# Traffic by status code group
sum(rate(http_requests_total{job="$service", namespace="$namespace"}[5m])) by (status_code_group)

# Define group in metric labels or use regex:
sum(rate(http_requests_total{job="$service", status_code=~"2.."}[5m]))
/
sum(rate(http_requests_total{job="$service"}[5m])) * 100
```

### Latency Heatmap
```promql
# For heatmap visualization — native Grafana heatmap panel
sum(increase(http_request_duration_seconds_bucket{job="$service"}[$__rate_interval])) by (le)
```

### Recording Rules for Performance
```yaml
groups:
  - name: sre.dashboard.recording
    interval: 30s
    rules:
      - record: job:http_requests:rate5m
        expr: sum(rate(http_requests_total[5m])) by (job, namespace)
      
      - record: job:http_errors:rate5m
        expr: sum(rate(http_requests_total{status_code=~"5.."}[5m])) by (job, namespace)
      
      - record: job:http_error_rate:ratio5m
        expr: |
          job:http_errors:rate5m
          /
          job:http_requests:rate5m
      
      - record: job:http_latency_p99:5m
        expr: |
          histogram_quantile(0.99,
            sum(rate(http_request_duration_seconds_bucket[5m])) by (job, namespace, le)
          )
```

## 4. Dashboard Provisioning (Dashboard-as-Code)

### Folder Provisioning Config
```yaml
# /etc/grafana/provisioning/dashboards/main.yaml
apiVersion: 1

providers:
  - name: SRE Dashboards
    orgId: 1
    folder: SRE
    folderUid: sre-folder
    type: file
    disableDeletion: true        # Prevent manual deletion
    updateIntervalSeconds: 30    # Re-read every 30s
    allowUiUpdates: true         # Allow UI edits (saved to DB only)
    options:
      path: /var/lib/grafana/dashboards
      foldersFromFilesStructure: true  # Subdirs become subfolders
```

### Datasource Provisioning
```yaml
# /etc/grafana/provisioning/datasources/datasources.yaml
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    uid: prometheus-uid          # Stable UID — use in dashboard JSON
    isDefault: true
    jsonData:
      timeInterval: 30s
      exemplarTraceIdDestinations:
        - name: traceID
          datasourceUid: tempo-uid  # Link exemplars → Tempo
    editable: false

  - name: Loki
    type: loki
    access: proxy
    url: http://loki:3100
    uid: loki-uid
    jsonData:
      derivedFields:
        - name: TraceID
          matcherRegex: '"traceId":"(\w+)"'
          url: '$${__value.raw}'
          datasourceUid: tempo-uid   # Link log trace IDs → Tempo
    editable: false

  - name: Tempo
    type: tempo
    access: proxy
    url: http://tempo:3200
    uid: tempo-uid
    editable: false
```

### Kubernetes ConfigMap Deployment
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
  namespace: monitoring
  labels:
    grafana_datasource: "1"          # Grafana sidecar picks this up
data:
  datasources.yaml: |
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        url: http://prometheus-operated:9090
        uid: prometheus-uid
        isDefault: true
```

## 5. Grafana Unified Alerting

### Alert Rule Structure
```yaml
# alert-rules.yaml for provisioning
apiVersion: 1

groups:
  - orgId: 1
    name: SRE Alerts
    folder: SRE
    interval: 1m
    rules:
      - uid: high-error-rate
        title: High Error Rate
        condition: C
        data:
          - refId: A
            queryType: ''
            relativeTimeRange:
              from: 600    # Look back 10m
              to: 0
            datasourceUid: prometheus-uid
            model:
              expr: |
                sum(rate(http_requests_total{status_code=~"5.."}[5m])) by (job)
                /
                sum(rate(http_requests_total[5m])) by (job)
              intervalMs: 1000
              maxDataPoints: 43200
          - refId: C
            queryType: ''
            relativeTimeRange:
              from: 0
              to: 0
            datasourceUid: "__expr__"
            model:
              conditions:
                - evaluator:
                    params: [0.05]          # 5% threshold
                    type: gt
                  operator:
                    type: and
                  query:
                    params: [A]
                  reducer:
                    type: last
              type: threshold
              refId: C
        noDataState: OK
        execErrState: Error
        for: 5m                             # Must be sustained 5m
        annotations:
          summary: "High error rate on {{ $labels.job }}"
          runbook_url: "https://wiki.company.com/runbooks/high-error-rate"
        labels:
          severity: warning
          team: sre
```

### Contact Points
```yaml
contactPoints:
  - orgId: 1
    name: PagerDuty-SEV1
    receivers:
      - uid: pd-sev1
        type: pagerduty
        settings:
          integrationKey: ${PAGERDUTY_INTEGRATION_KEY}
          severity: critical
          
  - orgId: 1
    name: Slack-SRE
    receivers:
      - uid: slack-sre
        type: slack
        settings:
          url: ${SLACK_WEBHOOK_URL}
          channel: "#sre-alerts"
          title: "{{ .GroupLabels.alertname }}"
          text: "{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}"
```

## 6. Exemplars — Connecting Metrics to Traces

Exemplars are point samples in histograms that carry trace IDs, letting you jump from a latency spike to the specific trace.

### Prometheus Config to Accept Exemplars
```yaml
feature_flags:
  - exemplar-storage

storage:
  exemplars:
    max_exemplars: 100000
```

### Application Code (Go example)
```go
histogram.With(labels).Observe(duration, prometheus.Labels{
    "traceID": span.SpanContext().TraceID().String(),
})
```

### Grafana Panel — Enable Exemplars
```json
{
  "fieldConfig": {
    "defaults": {
      "custom": {
        "showExemplars": true
      }
    }
  }
}
```

## 7. Alert Routing Architecture

```
                Grafana Alerting / Alertmanager
                           │
              ┌────────────┼────────────┐
              │                         │
         severity=critical          severity=warning
              │                         │
    ┌─────────▼─────────┐      ┌────────▼────────┐
    │    PagerDuty       │      │   Slack #alerts  │
    │  (immediate page)  │      │   (no page)      │
    └────────────────────┘      └──────────────────┘
    
Inhibition Rules:
- NodeDown suppresses all PodCrash on same node
- SEV1 active suppresses all SEV2/3 on same service
```

## 8. SLO Dashboard Best Practices

```promql
# Error budget remaining (burn rate dashboards)
-- 30-day window burn rate
1 - (
  (
    sum(rate(http_requests_total{status_code=~"5..", job="$service"}[30d]))
  ) / (
    sum(rate(http_requests_total{job="$service"}[30d]))
  )
) / 0.001    # 99.9% SLO = 0.001 error budget

-- Multi-window burn rate for fast-burn detection
(
  sum(rate(http_requests_total{status_code=~"5..", job="$service"}[1h]))
  / sum(rate(http_requests_total{job="$service"}[1h]))
) > 14.4    # 14.4x = depletes 1h in 1h budget = 2% monthly budget
```

## 9. Grafana Performance Tuning

- **caching**: enable unified alerting with concurrent_render_limit
- **database**: migrate from SQLite to PostgreSQL for teams >10 users
- **rendering**: grafana-image-renderer needs Chrome — use server-side rendering pool
- **query optimization**: use recording rules, limit default time ranges, use $__rate_interval
- **dashboard count**: >500 dashboards? Use folders + RBAC, consider Grafana Cloud
