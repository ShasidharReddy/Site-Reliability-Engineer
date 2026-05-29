# Monitoring & Observability Q&A

**Q1: What are the 4 Prometheus metric types?**
Counter: only increases (HTTP requests total, errors total). Always use rate(). Gauge: goes up/down (memory used, active connections, queue depth). Histogram: samples into configurable buckets + sum + count. Use for latency, request size. Enables histogram_quantile(). Summary: client-side pre-computed quantiles. Can't aggregate across instances. Prefer histograms.

**Q2: rate() vs irate() — when to use each?**
rate(counter[5m]): avg rate over 5m window. Smooth, good for alerts and dashboards. irate(counter[5m]): uses only last 2 samples — very responsive to spikes but noisy. Use rate() for production alerts (stable signal). Use irate() to investigate sudden short-lived spikes. Both handle counter resets. Never use rate() on a gauge.

**Q3: How does histogram_quantile() work? Gotchas?**
Interpolates the Nth percentile within the bucket containing it. histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le)). Gotchas: (1) Must aggregate by le label. (2) Only as accurate as bucket boundaries — plan them carefully. (3) Never average quantiles across instances — always re-compute from raw buckets with sum(rate(...)) by (le). (4) Sparse data gives poor accuracy.

**Q4: What is label cardinality and why does it matter?**
Cardinality = number of unique time series. High cardinality from unbounded labels (user_id, request_id, IP) causes Prometheus OOM crashes, slow queries, high storage costs. Detection: topk(10, count({__name__=~".+"}) by (__name__)). Fix: remove high-cardinality labels, use recording rules to pre-aggregate, consider Mimir for scale.

**Q5: Explain Alertmanager routing tree.**
Route tree: root has a default receiver. Child routes match on labels and override receiver/timing. group_by: combine related alerts into one notification. group_wait: 30s wait before first notification (allows grouping). group_interval: 5m between updates to same group. repeat_interval: 4h re-notify if still firing. inhibit_rules: suppress child alerts when parent fires (e.g., all pod alerts when NodeDown fires on that node).

**Q6: What is Pushgateway and when should you avoid it?**
Pushgateway: short-lived jobs push metrics instead of being scraped. Use ONLY for batch/cron jobs that finish before Prometheus polls. Avoid for: long-running services (scrape directly), multiple instances of same job (last-writer-wins semantics is confusing), metrics that should disappear when process dies (Pushgateway retains them until manual deletion).

**Q7: Loki vs Elasticsearch — when to use each?**
Loki: indexes only labels (like Prometheus), much cheaper operationally, best for K8s pod logs with Promtail, uses LogQL. Elasticsearch: indexes full log content, powerful full-text search, complex queries on log content, but expensive (CPU/memory for indexing). Choose Loki: Prometheus-based shop wanting consistency, cost-sensitive, primarily structured logs. Choose Elasticsearch: need full-text search, complex log analytics, already invested in ELK.

**Q8: How do you alert on absence of data?**
absent(up{job="my-service"}) returns 1 when no time series match. Tricky: (1) If Prometheus is down, it can't evaluate the rule. (2) Use for: 5m to avoid flapping during restarts. Better: heartbeat metric — service pushes a gauge to Pushgateway every minute, alert if absent for 3+ minutes. Also: blackbox_exporter probing an HTTP endpoint is more reliable for availability alerting.

**Q9: How do you design a good Grafana dashboard?**
Structure: Golden Signals at the top (latency, traffic, errors, saturation), then drill-down panels. Variables: namespace + service selectors. Thresholds: consistent colors (green/yellow/red). Every panel: title + description. Link to runbook on alert panels. Avoid: vanity metrics, raw counter values (use rates), pie charts for time series, more than 20 panels (use sub-dashboards). Key test: on-call at 3am should understand it in 30 seconds.

**Q10: What is Grafana provisioning? Why use it?**
Provisioning: YAML files that configure datasources/dashboards at startup. Dashboard JSON stored in Git → CI/CD → ConfigMap → mounted into Grafana pod → auto-reloaded every 30s. Benefits: version-controlled, auditable, identical across environments, no "someone deleted my dashboard," new Grafana instances get all dashboards automatically. The alternative (manual UI) is operationally fragile.

**Q11: Explain Prometheus remote_write.**
Sends metrics to long-term storage (Thanos, Mimir, VictoriaMetrics) via HTTP POST. Key parameters: max_shards (parallel senders), capacity (in-memory queue size), max_samples_per_send (batch size). Monitor: prometheus_remote_storage_queue_highest_sent_timestamp_seconds (lag) and prometheus_remote_storage_failed_samples_total. If falling behind: increase max_shards or fix backend.

**Q12: What is Thanos? When do you need it?**
Thanos adds to Prometheus: global query view across multiple clusters (with deduplication), long-term object storage (GCS/S3), HA via running 2x Prometheus replicas, downsampling old data. Use when: multiple clusters needing unified dashboards, retention beyond 15 days, multi-region setups. Alternative: Grafana Mimir (horizontally scalable, multi-tenant, drop-in Prometheus replacement).

**Q13: What is a recording rule? When should you create one?**
Recording rule pre-computes an expensive PromQL query and saves result as a new metric. Use when: a query is used in many dashboards/alerts (compute once, read many), a query is slow (high cardinality, long range), you want consistent aggregation across teams. Example: job:http_request_rate5m:rate = sum(rate(http_requests_total[5m])) by (job). Naming convention: level:metric:operation.

**Q14: How do you correlate metrics, logs, and traces in Grafana?**
Configure exemplars in Prometheus (histogram metrics embed trace IDs) → clicking a spike opens the trace in Tempo. Configure derived fields in Loki datasource (regex extracts trace IDs from log lines) → clicking links to Tempo. In Grafana Explore: view metrics, logs, traces in same pane with linked time range. Datasource config: prometheus exemplarTraceIdDestinations pointing to Tempo UID, loki derivedFields linking to Tempo.

**Q15: What is LogQL? Give 5 common queries.**
LogQL is Loki's query language, similar to PromQL.
1. Select by labels: {namespace="prod", app="api"}
2. Filter by content: {app="api"} |= "ERROR"
3. Parse JSON: {app="api"} | json | status_code >= 500
4. Rate of errors: rate({app="api"} |= "ERROR" [5m])
5. Top error messages: topk(5, sum(count_over_time({app="api"} |= "ERROR" [1h])) by (msg))
