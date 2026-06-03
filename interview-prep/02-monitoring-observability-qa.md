# Monitoring & Observability Q&A

## Basic

**Q: [Basic] What are the four Prometheus metric types?**
Prometheus supports counters, gauges, histograms, and summaries. Counters only increase, gauges go up and down, histograms store bucketed distributions, and summaries calculate quantiles client-side. In interviews, it helps to mention that histograms aggregate well across instances while summaries generally do not.

**Q: [Basic] How does the Prometheus pull model work?**
Prometheus scrapes targets on a schedule by calling their metrics endpoint, usually `/metrics`. This makes service discovery, health tracking, and target metadata simpler because Prometheus controls collection centrally. The pull model also lets operators inspect a target directly when a scrape fails.

**Q: [Basic] What is the difference between a gauge and a counter?**
A counter is for values that only increase, such as requests served or errors seen, and it is usually queried with `rate()` or `increase()`. A gauge is for values that can rise and fall, such as memory usage, queue depth, or active sessions. Using the wrong metric type leads to bad alerts and confusing graphs.

**Q: [Basic] What is a log?**
A log is an event record produced by an application or system at a specific point in time. Logs are useful for detailed context, such as errors, request parameters, user actions, and state transitions that metrics cannot capture. Strong answers also mention that structured logs are much easier to query at scale than free-form text.

**Q: [Basic] When should you use a histogram versus a summary?**
Use a histogram when you need to aggregate latency or size distributions across many instances. Histograms expose buckets, count, and sum, which makes them compatible with `histogram_quantile()` after aggregation. Summaries are acceptable for single-process views, but they are less flexible for fleet-wide percentiles.

**Q: [Basic] What is the difference between monitoring and observability?**
Monitoring tells you whether known failure conditions are happening, usually with dashboards and alerts on defined metrics. Observability is the ability to ask new questions about system behavior using telemetry such as metrics, logs, and traces. A well-observed system makes unknown failures easier to investigate when they occur.

**Q: [Basic] Why are logs, metrics, and traces all needed?**
Metrics show trends and trigger alerts, logs provide detailed event context, and traces show how work flows across distributed services. Each signal answers a different part of the incident response question. Mature teams correlate all three so responders can pivot quickly from symptom to root cause.

## Intermediate

**Q: [Intermediate] What does the PromQL `rate()` function do?**
`rate()` calculates the per-second average increase of a counter over a time range. It smooths short-term noise and also handles counter resets that happen during process restarts. This is why request or error counters should almost never be graphed as raw values.

**Q: [Intermediate] How does `histogram_quantile()` work?**
`histogram_quantile()` estimates a percentile from histogram buckets after those buckets are aggregated by the `le` label. It is commonly used for p90, p95, or p99 latency views. The accuracy depends heavily on having sensible bucket boundaries for the traffic pattern you expect.

**Q: [Intermediate] What does the PromQL `absent()` function help with?**
`absent()` returns a result when no matching time series exist, which makes it useful for “no data” alerts. Teams often use it to detect missing exporters, failed batch jobs, or targets that disappeared from service discovery. It should be paired with a sensible `for` duration so brief restarts do not create noise.

**Q: [Intermediate] How do PromQL aggregation and label matching affect query results?**
PromQL combines time series based on labels, so missing or extra labels can completely change the result of a query. Functions like `sum by (...)`, `sum without (...)`, and vector matching operators control how dimensions are kept or dropped. Many bad alerts come from forgetting to aggregate at the right level before comparing a threshold.

**Q: [Intermediate] How does Alertmanager routing work?**
Alertmanager evaluates labels on incoming alerts and routes them through a routing tree to different receivers such as PagerDuty, Slack, or email. Teams usually group related alerts together and set intervals for first delivery, updates, and repeats. Good routing uses severity, team, service, and environment labels so the right people get paged.

**Q: [Intermediate] What is the difference between silences and inhibition in Alertmanager?**
A silence is a manual suppression rule used during maintenance, known incidents, or planned noisy work. Inhibition is an automatic rule that suppresses lower-level alerts when a higher-level parent alert is already firing. Together they reduce paging noise without deleting useful alert definitions.

**Q: [Intermediate] What are cardinality issues in monitoring?**
Cardinality is the number of unique time series created by metric names and label combinations. Unbounded labels such as `user_id`, `request_id`, or raw IP addresses can explode storage, slow queries, and even crash a Prometheus server. High-cardinality problems are usually operational design problems, not hardware problems.

**Q: [Intermediate] How do you prevent a cardinality explosion?**
Start by designing labels around bounded dimensions like service, method, endpoint template, region, or status code class. Avoid labels that create a new series per request, customer, pod restart, or UUID. Recording rules, metric reviews, and instrumentation guidelines help teams catch dangerous changes before they hit production.

**Q: [Intermediate] What is LogQL?**
LogQL is Loki’s query language, and it combines label selection with log filtering and metric-style aggregation. You can search raw log lines, parse structured data, and build rate or count queries from logs over time windows. It feels familiar to Prometheus users because the label model is intentionally similar.

**Q: [Intermediate] When would you choose Loki over a full-text log platform?**
Loki is attractive when you want lower operational cost and already use Prometheus-style labels heavily. It indexes labels rather than every word in every log line, which makes it cheaper but less flexible for arbitrary full-text analytics. If the organization needs deep full-text search and many ad hoc log analytics workflows, an ELK-style stack may still fit better.

**Q: [Intermediate] What are recording rules and why do they matter?**
Recording rules precompute expensive or commonly reused PromQL expressions and store the result as new time series. They reduce dashboard latency, standardize team-wide calculations, and lower query cost for alerts. They are especially valuable for SLO math, fleet-wide rates, and other queries used repeatedly.

## Advanced

**Q: [Advanced] How do you optimize recording rules?**
Keep recording rules focused on high-value queries that are reused often, not every possible aggregation. Evaluate them at an interval that matches the freshness requirement, and store the lowest useful cardinality rather than every label combination. It is also important to name them consistently so teams know which series are safe to build on.

**Q: [Advanced] What does multi-signal correlation mean in practice?**
Multi-signal correlation means using metrics, logs, traces, and deployment events together during investigation. For example, a latency spike on a dashboard should let you jump directly to related traces and logs for the same time range and service. Good tooling reduces the number of manual context switches responders need to make.

**Q: [Advanced] What are exemplars?**
Exemplars are references attached to metric samples that point to a related trace or event identifier. They are especially useful on latency histograms because they let you click a metric spike and open a representative trace for that time. Exemplars make metrics far more actionable during incident triage.

**Q: [Advanced] How do Thanos, Cortex, or Mimir help with Prometheus at scale?**
These systems add horizontal scalability, long-term storage, and global querying on top of Prometheus-style data. They are commonly used for high availability, multi-cluster views, and retention periods longer than a single Prometheus server can comfortably handle. In interviews, mention deduplication, object storage, and central query layers.

**Q: [Advanced] What is Prometheus remote write used for?**
Remote write streams samples from Prometheus to another storage backend for long retention or centralized analysis. It is often paired with Thanos, Mimir, VictoriaMetrics, or vendor platforms that can store more history and serve larger queries. Teams should monitor queue lag and failed sample metrics because remote write backpressure can hide data loss.

**Q: [Advanced] What are common distributed tracing sampling strategies?**
Head-based sampling makes the decision at trace start and is simple to run, but it can miss rare slow or failed paths. Tail-based sampling waits until the trace is complete so it can keep unusual or high-value traces, though it needs more infrastructure. Some teams use hybrid strategies, such as always keeping errors and only sampling a percentage of healthy traffic.

**Q: [Advanced] What is the difference between blackbox and whitebox monitoring?**
Blackbox monitoring checks the system from the outside, such as HTTP probes, DNS checks, or synthetic transactions. Whitebox monitoring looks inside the system at internal telemetry like CPU, queue depth, GC time, or RPC error rate. Strong monitoring programs use both because customer-visible health and component health do not always fail at the same time.

**Q: [Advanced] What are RED and USE, and when are they helpful?**
RED stands for Rate, Errors, and Duration, and it works well for request-driven services such as APIs. USE stands for Utilization, Saturation, and Errors, and it is better suited to infrastructure components like CPU, disks, and queues. Using both frameworks together often gives a balanced application and platform view.

**Q: [Advanced] What are common monitoring anti-patterns?**
Common anti-patterns include alerting on every infrastructure symptom, paging on raw CPU alone, and collecting metrics with unbounded labels. Other mistakes are building dashboards that show component internals but not user impact, or creating alerts with no runbooks and no clear owner. Mature teams optimize for signal quality, not for the total number of graphs.

**Q: [Advanced] What makes a good observability dashboard?**
A good dashboard starts with service health, such as traffic, errors, latency, and saturation, before drilling into deeper component details. It should make time ranges, deployments, and major dimensions like region or environment easy to compare. The best dashboards are designed for fast incident triage, not for showing every metric ever collected.
