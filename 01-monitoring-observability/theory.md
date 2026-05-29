# Monitoring & Observability — Theory

## 1. The Three Pillars of Observability

Observability is the ability to understand the internal state of a system by examining its external outputs.
The three pillars are **Metrics**, **Logs**, and **Traces**.

### 1.1 Metrics
- **What**: Numeric measurements aggregated over time (counters, gauges, histograms)
- **Why**: Efficient storage, fast queries, ideal for alerting and dashboards
- **When to use**: Track trends, alert thresholds, SLO measurements
- **Tools**: Prometheus, Datadog, Cloud Monitoring, InfluxDB
- **Example**: `http_requests_total{method="GET", status="200"}` — counter of HTTP 200 GETs

### 1.2 Logs
- **What**: Timestamped, structured or unstructured event records
- **Why**: Rich context for debugging — tells you *what happened* in detail
- **When to use**: Debugging specific errors, audit trails, understanding request flow
- **Tools**: Loki, Elasticsearch (ELK), Splunk, Cloud Logging, Fluentd/Fluent Bit
- **Structured logging**: JSON logs with consistent fields enable grep and aggregation

### 1.3 Traces
- **What**: End-to-end request paths across distributed services (spans + context)
- **Why**: Find *where* latency or errors occur in a call chain
- **When to use**: Microservices, slow requests, pinpointing service bottlenecks
- **Tools**: Jaeger, Zipkin, Tempo, AWS X-Ray, Cloud Trace
- **Key concepts**: Trace ID (unique per request), Span (one service's work), Parent-child spans

### 1.4 Correlating Pillars in Grafana Explore
- Exemplars: Prometheus metrics can embed Trace IDs → click on a metric spike → jump to trace
- Loki → Tempo: log lines with trace IDs link directly to traces
- Grafana Explore: switch between metrics/logs/traces for the same time window

---

## 2. Prometheus Architecture

### 2.1 Core Components
```
┌──────────────────────────────────────────────────────────┐
│                     Prometheus Server                    │
│  ┌────────────┐  ┌──────────────┐  ┌─────────────────┐  │
│  │  Retrieval │  │     TSDB     │  │   HTTP Server   │  │
│  │  (scraper) │  │  (storage)   │  │  (query/rules)  │  │
│  └────────────┘  └──────────────┘  └─────────────────┘  │
└──────────────────────────────────────────────────────────┘
        │                                      ▲
        ▼                                      │
  ┌──────────┐    ┌──────────────┐    ┌──────────────────┐
  │ Exporters│    │  Pushgateway │    │    Alertmanager   │
  │ node,    │    │  (for batch) │    │  (route/silence)  │
  │ cadvisor,│    └──────────────┘    └──────────────────┘
  │ app, etc.│
  └──────────┘
```

### 2.2 Scrape Model
- Prometheus **pulls** metrics from targets via HTTP `/metrics` endpoint
- `scrape_interval`: how often to collect (default: 1m, common: 15s-30s)
- `scrape_timeout`: max wait per scrape (must be < scrape_interval)
- **Service Discovery**: Kubernetes SD, Consul SD, EC2 SD — auto-discovers targets

### 2.3 TSDB (Time Series Database)
- Data stored in **chunks** (2-hour blocks compressed on disk)
- **WAL** (Write-Ahead Log): crash recovery
- **Compaction**: older blocks merged/compacted automatically
- Default retention: 15 days (configurable via `--storage.tsdb.retention.time`)
- Storage format: highly compressed (Gorilla encoding for timestamps, XOR for values)

### 2.4 Exporters
| Exporter | What it Monitors |
|----------|-----------------|
| `node_exporter` | Linux host: CPU, memory, disk, network |
| `kube-state-metrics` | K8s object states: deployment replicas, pod phases |
| `cadvisor` | Container CPU/memory/network (built into kubelet) |
| `blackbox_exporter` | External probing: HTTP, DNS, TCP, ICMP |
| `postgres_exporter` | PostgreSQL metrics |
| `redis_exporter` | Redis metrics |
| `jmx_exporter` | JVM/Java application metrics |

### 2.5 Pushgateway
- For **short-lived jobs** (batch, cron) that finish before Prometheus scrapes
- Job pushes metrics → Pushgateway stores → Prometheus scrapes Pushgateway
- ⚠️ **Avoid for long-running services** — metrics persist even after job dies

### 2.6 Remote Write / Remote Read
- `remote_write`: ship metrics to long-term storage (Thanos, Cortex, Mimir, Cloud Monitoring)
- Enables multi-region aggregation and long retention
- Has a queue (capacity, max_shards) — monitor `prometheus_remote_storage_queue_*` metrics

### 2.7 Federation
- Hierarchical scraping: regional Prometheus → global Prometheus
- Global scrapes `/federate` endpoint of regional instances
- Best for dashboards spanning multiple clusters

---

## 3. PromQL Deep Dive

### 3.1 Metric Types
| Type | Description | Example |
|------|-------------|---------|
| **Counter** | Only increases (resets on restart) | `http_requests_total` |
| **Gauge** | Can go up/down | `node_memory_MemAvailable_bytes` |
| **Histogram** | Bucketed observations, includes `_sum`, `_count`, `_bucket` | `http_request_duration_seconds` |
| **Summary** | Pre-computed quantiles on client side | `go_gc_duration_seconds` |

### 3.2 Key Functions
```promql
# Rate of increase per second (for counters) — use for alerts
rate(http_requests_total[5m])

# Instant rate (last 2 samples) — more responsive but spiky
irate(http_requests_total[5m])

# Total increase over a range
increase(http_requests_total[1h])

# Percentile from histogram (p99 latency)
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))

# Alert when a metric is absent (useful for heartbeat monitoring)
absent(up{job="my-service"})

# Top 5 pods by CPU
topk(5, sum(rate(container_cpu_usage_seconds_total[5m])) by (pod))

# Memory usage as percentage
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# Error rate percentage
sum(rate(http_requests_total{status=~"5.."}[5m])) /
sum(rate(http_requests_total[5m])) * 100
```

### 3.3 Label Matchers
```promql
# Exact match
http_requests_total{job="api", status="200"}

# Regex match (all 5xx errors)
http_requests_total{status=~"5.."}

# Negative match
http_requests_total{status!="200"}

# Negative regex
http_requests_total{namespace!~"kube-.*"}
```

### 3.4 Aggregations
```promql
# Sum across all instances, group by job
sum(http_requests_total) by (job)

# Average CPU by namespace
avg(rate(container_cpu_usage_seconds_total[5m])) by (namespace)

# Max memory per node
max(node_memory_MemTotal_bytes) by (instance)

# Count pods per node
count(kube_pod_info) by (node)
```

### 3.5 Recording Rules
Pre-compute expensive queries for performance:
```yaml
groups:
  - name: slo_recording_rules
    interval: 30s
    rules:
      - record: job:http_requests_total:rate5m
        expr: sum(rate(http_requests_total[5m])) by (job)
      - record: job:http_errors_total:rate5m
        expr: sum(rate(http_requests_total{status=~"5.."}[5m])) by (job)
      - record: job:http_error_ratio:rate5m
        expr: job:http_errors_total:rate5m / job:http_requests_total:rate5m
```

---

## 4. Alertmanager

### 4.1 Architecture
```
Prometheus → [alert fires] → Alertmanager → [route] → Receiver (Slack/PagerDuty/Email)
```

### 4.2 Routing Tree
```yaml
route:
  receiver: default
  group_by: ['alertname', 'cluster', 'namespace']
  group_wait: 30s        # Wait before sending first notification (for grouping)
  group_interval: 5m     # Wait before sending updated notification for group
  repeat_interval: 4h    # Re-notify if still firing after this time
  routes:
    - match:
        severity: critical
      receiver: pagerduty
      continue: false
    - match:
        severity: warning
      receiver: slack-warnings
```

### 4.3 Key Concepts
- **Inhibition**: Suppress child alerts when a parent fires (e.g., suppress pod alerts if node is down)
- **Silences**: Mute alerts by matchers for a time window (scheduled maintenance)
- **Group_by**: Combine similar alerts into one notification (reduce noise)

```yaml
inhibit_rules:
  - source_match:
      alertname: NodeDown
    target_match:
      alertname: PodCrashLooping
    equal: ['node']
```

---

## 5. Grafana

### 5.1 Data Sources
- Prometheus (metrics), Loki (logs), Tempo (traces), Cloud Monitoring, Elasticsearch
- Each datasource has a UID used in dashboard JSON for portability

### 5.2 Panel Types
| Panel | Best For |
|-------|----------|
| Time Series | Trend over time (CPU, requests, latency) |
| Stat | Single current value with thresholds (uptime, error count) |
| Gauge | Value within a range (disk usage %) |
| Bar Gauge | Comparison across series (CPU per pod) |
| Heatmap | Distribution over time (request latency distribution) |
| Table | Multi-dimensional data with sorting/filtering |
| Logs | Log streams from Loki |
| Histogram | Value distribution snapshot |

### 5.3 Variables
```
Type: Query → runs PromQL/LogQL to get dynamic list
Example: label_values(kube_pod_info{namespace="$namespace"}, pod)

Chaining: $namespace variable → $pod variable (only shows pods in selected namespace)
Multi-value: enable "Multi-value" + "Include All" for batch selection
```

### 5.4 The Golden Signals (Google SRE)
1. **Latency** — time to serve a request (separate successful vs failed)
2. **Traffic** — how much demand is hitting the system (RPS, QPS)
3. **Errors** — rate of failed requests (explicit 5xx + implicit timeouts)
4. **Saturation** — how full the system is (CPU %, memory %, disk %)

### 5.5 USE Method (Infrastructure)
- **Utilization**: % time resource is busy (CPU %)
- **Saturation**: extra work queued (CPU run queue, memory swap)
- **Errors**: error events (disk errors, network drops)

### 5.6 RED Method (Services)
- **Rate**: requests per second
- **Errors**: error rate
- **Duration**: latency (p50/p95/p99)

---

## 6. Loki & Log Management

### 6.1 Loki Architecture
```
App → Promtail/Fluent Bit → Loki (Distributor → Ingester → Chunks in GCS/S3)
                                           ↓
                                      Query Frontend → Querier → Grafana
```

- **Promtail**: log shipper (tails files, Kubernetes pod logs)
- **Distributor**: receives log streams, validates, routes to ingesters
- **Ingester**: buffers logs in memory, writes compressed chunks to object storage
- **Compactor**: merges and deduplicates chunks
- **Index**: labels only (not log content) → low cardinality, efficient

### 6.2 LogQL
```logql
# Select logs from a pod
{namespace="production", pod=~"api-.*"}

# Filter by content
{namespace="production"} |= "ERROR"

# Parse JSON logs
{namespace="production"} | json | status_code >= 500

# Rate of error logs
rate({namespace="production"} |= "ERROR" [5m])

# Log volume by pod
sum(count_over_time({namespace="production"}[5m])) by (pod)
```

---

## 7. Distributed Tracing

### 7.1 Concepts
- **Trace**: complete request journey through the system (unique trace_id)
- **Span**: single unit of work within a trace (service call, DB query)
- **Context Propagation**: HTTP headers (W3C TraceContext: `traceparent`) carry trace_id between services
- **Sampling**: record only N% of traces (head-based vs tail-based sampling)

### 7.2 Tempo (Grafana's Trace Backend)
- Stores traces in object storage (S3/GCS/local)
- Integrates with Grafana Explore — search by trace ID or attributes
- Supports TraceQL query language

### 7.3 Instrumentation
```python
# Python (OpenTelemetry)
from opentelemetry import trace
tracer = trace.get_tracer(__name__)
with tracer.start_as_current_span("database-query") as span:
    span.set_attribute("db.query", "SELECT * FROM users")
    result = db.execute(query)
```

---

## 8. High Availability for Prometheus

### 8.1 Problem
Single Prometheus = single point of failure + limited retention

### 8.2 Thanos
```
Prometheus A ──┐
               ├── Thanos Query (global view, deduplication)
Prometheus B ──┘       │
                   Thanos Store (reads from object storage)
                   Thanos Compactor (downsample + retention)
                   Thanos Ruler (cross-cluster recording rules)
```

### 8.3 Grafana Mimir
- Drop-in Prometheus-compatible TSDB with horizontal scalability
- Handles cardinality that single Prometheus can't (billions of active series)
- Multi-tenancy built-in

---

## 9. Cardinality Management

**High cardinality** = too many unique label value combinations → OOM, slow queries

```
❌ Bad label: user_id, request_id, IP address (unbounded)
✅ Good label: method, status_code, service, namespace (bounded set)
```

**Detection**:
```promql
# Find metrics with most time series
topk(10, count({__name__=~".+"}) by (__name__))

# Check cardinality of a specific metric
count(http_requests_total) by (job)
```

**Mitigation**:
- Remove high-cardinality labels from metrics
- Use recording rules to pre-aggregate
- Implement metric relabeling in scrape config
