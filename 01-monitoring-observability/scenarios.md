# Monitoring & Observability — Real-World Scenarios

These exercises are written like short incident simulations.
Each one gives you:

- background context
- symptoms and alerts received
- investigation steps with actual commands
- the root cause
- mitigation
- a short postmortem fragment

Use them in three ways:

1. as self-study drills
2. as team tabletop exercises
3. as runbook-writing practice

## Scenario map

| Scenario | Theme | Primary skill |
|---|---|---|
| 1 | alert never fires | rule timing and evaluation |
| 2 | green dashboard but unhappy users | percentile thinking |
| 3 | alert storm | label cardinality control |
| 4 | no logs for an hour | Promtail and rotation debugging |
| 5 | SLO says fine but customers disagree | SLI design |
| 6 | trace is slow but culprit unclear | async tracing gaps |
| 7 | Grafana is slow | query optimization |
| 8 | 2am alert resolved instantly | flapping analysis |
| 9 | saw-tooth memory chart | GC interpretation |
| 10 | service missing from service map | discovery and instrumentation |

## 1. Prometheus is scraping but alert never fires

### Background context

A payment API exposes metrics correctly.
Prometheus scrapes the service every 30 seconds.
The on-call team created a `HighErrorRate` alert using a five-minute rate expression.
During a load test,
errors clearly rise above threshold,
but nobody gets paged.

### Symptoms and alerts received

- the Grafana panel for `5xx` percentage is above the threshold
- Prometheus `/targets` shows the job as `UP`
- the alert never leaves `Inactive`
- users report intermittent checkout failures

### Investigation steps

Check that the target is truly being scraped:

```bash
kubectl -n monitoring port-forward svc/prometheus-operated 9090:9090
curl -s 'http://127.0.0.1:9090/api/v1/query?query=up{job="payment-api"}' | jq .
```

Inspect the rule definition:

```bash
kubectl get prometheusrule -n monitoring payment-rules -o yaml
promtool check rules rules/payment-rules.yaml
```

Graph the exact alert expression and compare it to the configured `for` value:

```bash
curl -s 'http://127.0.0.1:9090/api/v1/query?query=(sum(rate(http_requests_total{job="payment-api",code=~"5.."}[5m]))/sum(rate(http_requests_total{job="payment-api"}[5m])))*100' | jq .
curl -s http://127.0.0.1:9090/api/v1/rules | jq '.data.groups[] | select(.name=="payment-rules")'
```

### Finding the root cause

The alert used:

```yaml
expr: (errors / total) * 100 > 5
for: 10m
```

The load test only kept the error rate above 5% for about six minutes.
Because the evaluation interval was one minute,
Prometheus never observed ten continuous minutes above the threshold.
The alert expression was correct.
The timing logic was not.

### Mitigation

Short-term mitigation:

```bash
kubectl edit prometheusrule -n monitoring payment-rules
```

Change the rule to:

```yaml
for: 3m
```

Then rerun the load test and confirm the alert reaches `Firing`.
If the intent is to catch customer-impacting bursts quickly,
three minutes is more realistic than ten.

### Postmortem fragment / lessons learned

We confused detection confidence with alert usefulness.
A long `for` protected us from flapping,
but it also blinded us to genuine outages shorter than the hold-down period.
Future rule reviews must include:

- expected evaluation interval
- expected breach duration
- why the chosen `for` matches user impact

## 2. Dashboard is green but users are complaining

### Background context

A customer-facing search service shows healthy request rate,
low average latency,
and low error percentage.
Support tickets still say the site is "freezing" for some users.

### Symptoms and alerts received

- no critical alerts fired
- average latency panel is below 150 ms
- p99 is not shown anywhere on the dashboard
- support reports a pattern only during large searches

### Investigation steps

Check the dashboard queries currently in use.
Most panels aggregate across all routes and all response sizes.

```bash
curl -s -u admin:admin http://127.0.0.1:3000/api/search?query=search-dashboard | jq .
```

Query latency percentiles directly in Prometheus:

```bash
curl -s 'http://127.0.0.1:9090/api/v1/query?query=histogram_quantile(0.50,sum by (le)(rate(http_request_duration_seconds_bucket{job="search-api"}[5m])))' | jq .
curl -s 'http://127.0.0.1:9090/api/v1/query?query=histogram_quantile(0.95,sum by (le)(rate(http_request_duration_seconds_bucket{job="search-api"}[5m])))' | jq .
curl -s 'http://127.0.0.1:9090/api/v1/query?query=histogram_quantile(0.99,sum by (le)(rate(http_request_duration_seconds_bucket{job="search-api",route="/search"}[5m])))' | jq .
```

Split by route and request class:

```bash
curl -s 'http://127.0.0.1:9090/api/v1/query?query=histogram_quantile(0.99,sum by (le,route)(rate(http_request_duration_seconds_bucket{job="search-api"}[5m])))' | jq .
```

### Finding the root cause

The dashboard only showed averages.
Fast, lightweight requests hid a small but important population of very slow heavy searches.
The `/search` route with large result sets had a p99 above 4 seconds,
but the average across all routes looked healthy.

### Mitigation

Update the dashboard to include:

- p95 and p99 latency
- route-level breakdown
- request volume by route
- error rate segmented by major user workflow

A safer PromQL example:

```promql
histogram_quantile(0.99, sum by (le, route) (rate(http_request_duration_seconds_bucket{job="search-api"}[5m])))
```

### Postmortem fragment / lessons learned

A green dashboard is only useful if it reflects user experience.
Averages are cheap to compute and easy to misunderstand.
For customer-facing paths,
percentiles and segmentation by route matter more than overall means.

## 3. We're getting 1000 alerts per minute

### Background context

A new deployment adds a `request_id` label to an application metric.
Within minutes,
Prometheus storage grows rapidly,
and Alertmanager starts receiving thousands of logically identical alerts.

### Symptoms and alerts received

- Alertmanager UI floods with similar `HighLatency` alerts
- Prometheus memory increases sharply
- Grafana queries become slow
- the paging channel becomes unusable

### Investigation steps

Inspect active alerts and compare label sets:

```bash
curl -s http://alertmanager-operated.monitoring.svc:9093/api/v2/alerts | jq '.[0:5]'
```

Check cardinality hotspots:

```bash
kubectl -n monitoring exec -it sts/prometheus-kube-prometheus-prometheus -- promtool tsdb analyze /prometheus | head -n 80
curl -s http://127.0.0.1:9090/api/v1/status/tsdb | jq '.data.labelValueCountByLabelName[:10]'
```

Inspect the metric definition in the new service deployment:

```bash
kubectl logs -n app deploy/web-api | grep -i request_id | head
kubectl get deploy -n app web-api -o yaml | sed -n '/image:/,+30p'
```

### Finding the root cause

The alert grouped on all original labels,
and the application metric included `request_id`.
Every request produced a unique time series,
which then produced effectively unique alert instances.
This was both a storage incident and an alerting incident.

### Mitigation

Immediate actions:

```bash
kubectl scale deploy -n app web-api --replicas=0
kubectl edit prometheusrule -n monitoring app-rules
```

Then remove `request_id` from instrumentation,
redeploy,
and simplify alert grouping in Alertmanager:

```yaml
group_by: [alertname, service, severity]
```

### Postmortem fragment / lessons learned

High cardinality is not just a Prometheus problem.
It cascades into query latency,
alert explosion,
and operator fatigue.
Metrics labels must represent bounded dimensions,
not per-request identity.

## 4. Loki suddenly shows no logs for the last hour

### Background context

Your workloads are still serving traffic,
but Grafana Explore stops showing new application logs.
Older logs are visible.
The break starts almost exactly at the top of the hour after a node image update.

### Symptoms and alerts received

- log panels are blank for the last hour
- metrics still show healthy request traffic
- Promtail pods are restarting on some nodes
- no immediate application errors are visible

### Investigation steps

Check Promtail status:

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail -o wide
kubectl logs -n monitoring ds/promtail --tail=100 | grep -Ei 'error|rotate|permission|positions'
```

Inspect one affected node's log mount paths:

```bash
kubectl exec -n monitoring ds/promtail -- ls -l /var/log/pods | head
kubectl exec -n monitoring ds/promtail -- cat /run/promtail/positions.yaml | head -n 30
```

Query Loki directly for recent labels:

```bash
curl -s 'http://loki-gateway.monitoring.svc/loki/api/v1/query_range?query={namespace="app"}&limit=5&start=1710000000000000000&end=1710003600000000000' | jq .
```

### Finding the root cause

The node update changed log rotation timing.
Promtail restarted during rotation,
and the positions file pointed to files that no longer existed.
The new files were not picked up immediately because the scrape config and inode tracking interacted badly during the restart window.

### Mitigation

Restart Promtail after fixing the scrape config and positions handling:

```bash
kubectl edit configmap -n monitoring promtail
kubectl rollout restart ds/promtail -n monitoring
```

On severely affected nodes,
clear only the stale positions entry if needed,
then let Promtail rescan the path.

### Postmortem fragment / lessons learned

Logs can disappear even when applications are healthy.
Log collection is its own distributed system.
Node updates,
rotation behavior,
and file tailing state must be tested together,
not independently.

## 5. Our SLO dashboard shows 99.95% but customers say the site was down

### Background context

Leadership sees a healthy monthly availability number.
Meanwhile,
customers report a 20-minute outage during checkout.
The SLO dashboard did not show a meaningful drop.

### Symptoms and alerts received

- the monthly SLO panel remains above target
- support tickets cluster around checkout failures
- synthetic checks from one region failed for 20 minutes
- error budget burn alerts did not trigger

### Investigation steps

Inspect the SLI query behind the dashboard:

```bash
curl -s 'http://127.0.0.1:9090/api/v1/query?query=sum(rate(http_requests_total{job="frontend",code!~"5.."}[30d]))/sum(rate(http_requests_total{job="frontend"}[30d]))' | jq .
```

Compare it to a checkout-only SLI:

```bash
curl -s 'http://127.0.0.1:9090/api/v1/query?query=sum(rate(http_requests_total{job="frontend",route="/checkout",code!~"5.."}[30d]))/sum(rate(http_requests_total{job="frontend",route="/checkout"}[30d]))' | jq .
```

Check synthetic monitoring results:

```bash
kubectl logs -n monitoring deploy/synthetic-checkout | tail -n 100
```

### Finding the root cause

The SLO measured overall frontend success,
not the critical user journey.
Because most traffic was to static assets and browsing routes,
a full checkout outage barely moved the aggregate success ratio.
The SLI was mathematically correct but operationally useless.

### Mitigation

Redefine the SLI around the customer-critical workflow.
For example:

```promql
sum(rate(http_requests_total{job="frontend",route="/checkout",code!~"5.."}[5m]))
/
sum(rate(http_requests_total{job="frontend",route="/checkout"}[5m]))
```

Also add synthetic checks that exercise the real path end to end.

### Postmortem fragment / lessons learned

SLOs reflect what you choose to measure.
If the SLI ignores the user journey that matters most,
a good SLO score can hide a bad customer experience.
Route-specific and workflow-specific SLIs are often more honest than platform-wide aggregates.

## 6. Trace shows an 8 second span but we can't find the slow service

### Background context

A Tempo trace for a request shows total duration around 8 seconds.
The service map looks normal,
and no single synchronous child span explains the delay.
The request path uses a message broker between the API and worker.

### Symptoms and alerts received

- the root span duration is high
- synchronous downstream spans are all fast
- user-facing latency alert fires
- queue depth metrics are elevated,
but nobody linked them to the trace initially

### Investigation steps

Open the trace and inspect span timeline.
Then check whether async boundaries are instrumented.

```bash
kubectl logs -n app deploy/api-gateway | grep -Ei 'publish|traceparent' | tail -n 20
kubectl logs -n app deploy/worker | grep -Ei 'consume|traceparent' | tail -n 20
```

Query queue metrics:

```bash
curl -s 'http://127.0.0.1:9090/api/v1/query?query=rabbitmq_queue_messages_ready{queue="checkout-jobs"}' | jq .
curl -s 'http://127.0.0.1:9090/api/v1/query?query=rate(worker_jobs_processed_total[5m])' | jq .
```

Inspect messaging instrumentation configuration:

```bash
kubectl exec -n app deploy/api-gateway -- printenv | grep OTEL
kubectl exec -n app deploy/worker -- printenv | grep OTEL
```

### Finding the root cause

Trace context was propagated across HTTP calls,
but not into the message published to the broker.
The worker created a new trace instead of continuing the original one.
The 8-second root span included waiting time on the queue,
but the worker work appeared somewhere else entirely.

### Mitigation

Inject W3C TraceContext into message headers on publish,
and extract it on consume.
Then create spans for:

- publish
- queue wait
- consume
- worker processing

Also add queue latency metrics and correlate them with traces.

### Postmortem fragment / lessons learned

Distributed tracing is only as complete as the propagation boundaries you instrument.
HTTP-only tracing gives false confidence in event-driven systems.
Whenever you use a queue,
trace the publish and consume path explicitly.

## 7. Grafana became unusable slow

### Background context

After a new dashboard launch,
Grafana CPU rises,
panels time out,
and users complain that Explore is nearly unusable.
The issue is worst on a dashboard shared in the company home page.

### Symptoms and alerts received

- Grafana latency alerts fire
- Prometheus and Loki query load increase sharply
- the slow dashboard includes regex-heavy queries
- panel refresh interval is set to 10 seconds

### Investigation steps

Check Grafana logs and pod resources:

```bash
kubectl top pod -n monitoring -l app.kubernetes.io/name=grafana
kubectl logs -n monitoring deploy/grafana | grep -Ei 'timeout|proxy|datasource'
```

Review the panel queries for missing selectors:

```bash
curl -s -u admin:admin http://127.0.0.1:3000/api/search?query=executive-overview | jq .
```

Test the suspected Prometheus query directly:

```bash
curl -s 'http://127.0.0.1:9090/api/v1/query?query=sum by (pod,container,instance,route,user)(rate(http_requests_total[1m]))' | jq .
```

### Finding the root cause

One panel grouped by too many labels and used no service selector.
It attempted to compute a near-global high-cardinality rate every 10 seconds for all users viewing the dashboard.
Grafana was not the source of the bad math,
but it amplified the bad query across many browsers.

### Mitigation

Replace the query with a recording rule or a scoped query,
for example:

```promql
sum by (service) (rate(http_requests_total{namespace="prod",service!=""}[5m]))
```

Increase the refresh interval,
remove unnecessary regex matchers,
and cache or precompute expensive panels.

### Postmortem fragment / lessons learned

Dashboard popularity changes the blast radius of a bad query.
A query that is tolerable for one engineer in Explore can become a mini denial-of-service when embedded in a shared landing page.
Performance review is part of dashboard review.

## 8. Alert fired at 2am, resolved by 2:01am — was it real?

### Background context

An alert woke the primary on-call at 02:00.
By the time they opened Grafana,
it had already resolved.
There was no obvious customer ticket.
The team must decide whether to tune or keep the alert.

### Symptoms and alerts received

- one brief `HighLatency` page
- resolution within one minute
- little evidence remains on dashboards at default ranges
- operator trust in the alert is decreasing

### Investigation steps

Expand the time window around the alert and inspect the raw series:

```bash
curl -s 'http://127.0.0.1:9090/api/v1/query_range?query=histogram_quantile(0.95,sum by (le)(rate(http_request_duration_seconds_bucket{job="api"}[5m])))&start=2025-01-01T01:45:00Z&end=2025-01-01T02:15:00Z&step=15s' | jq .
```

Inspect alert metadata:

```bash
curl -s http://127.0.0.1:9090/api/v1/alerts | jq .
curl -s http://alertmanager-operated.monitoring.svc:9093/api/v2/alerts/groups | jq .
```

Check for concurrent infrastructure blips:

```bash
kubectl get events -A --sort-by=.lastTimestamp | tail -n 50
kubectl logs -n ingress deploy/nginx-ingress-controller | grep '02:0'
```

### Finding the root cause

The alert was based on a short query window and a short `for` value.
A brief ingress retry storm pushed latency above threshold just long enough to fire.
It was a real signal,
but too brief to justify a paging interruption at that sensitivity level.

### Mitigation

Retune the rule:

- widen the range vector from `1m` to `5m`
- increase `for` from `0m` to `3m`
- add a lower-severity notification for brief spikes

Keep the raw series and incident review notes so future tuning stays evidence-based.

### Postmortem fragment / lessons learned

Not every real event deserves the same delivery path.
We should distinguish between user-impacting sustained failures and momentary turbulence.
Flapping diagnosis is about improving signal quality,
not hiding problems.

## 9. Memory usage chart shows saw-tooth pattern

### Background context

A Java service shows memory climbing steadily,
then dropping sharply,
over and over.
A new engineer reports a likely memory leak.
The service still responds normally.

### Symptoms and alerts received

- container memory graph has a saw-tooth shape
- CPU spikes align with the drops
- p99 latency occasionally bumps during the drops
- no OOM kills yet

### Investigation steps

Check container memory and restart counts:

```bash
kubectl top pod -n app -l app=checkout
kubectl get pods -n app -l app=checkout -o wide
```

Query GC-related metrics:

```bash
curl -s 'http://127.0.0.1:9090/api/v1/query?query=jvm_gc_pause_seconds_count{job="checkout"}' | jq .
curl -s 'http://127.0.0.1:9090/api/v1/query?query=jvm_memory_used_bytes{job="checkout",area="heap"}' | jq .
curl -s 'http://127.0.0.1:9090/api/v1/query?query=rate(process_cpu_seconds_total{job="checkout"}[5m])' | jq .
```

Inspect logs around long GC pauses:

```bash
kubectl logs -n app deploy/checkout | grep -Ei 'Full GC|Pause Young|Pause Full' | tail -n 50
```

### Finding the root cause

The saw-tooth pattern was expected garbage collection behavior,
not necessarily a leak.
However,
a recent configuration change reduced heap headroom,
so GC happened more often and introduced visible latency spikes.
The issue was capacity tuning,
not runaway growth.

### Mitigation

Increase memory limits modestly,
review JVM heap sizing,
and tune dashboard panels to show:

- heap used
- heap max
- GC pause count
- GC pause duration
- request latency percentiles

If the slope after each GC keeps rising to a higher baseline over days,
then revisit leak suspicion.

### Postmortem fragment / lessons learned

Pattern recognition matters.
A saw-tooth chart often means memory management is working.
The operational question is whether GC overhead is acceptable,
not whether any up-and-down memory graph is automatically a leak.

## 10. New service isn't appearing in service map

### Background context

A new recommendations service was added last week.
It serves traffic successfully,
and engineers can see some logs and metrics.
Tempo traces exist for the gateway,
but the recommendations service never appears in the service map.

### Symptoms and alerts received

- service map shows gateway and backend only
- recommendation requests are visible in application logs
- no direct alert fires for the missing node
- traces appear partially connected

### Investigation steps

Check whether the new service is instrumented and exporting spans:

```bash
kubectl logs -n app deploy/recommendations | grep -Ei 'otel|trace|export'
kubectl exec -n app deploy/recommendations -- printenv | grep OTEL
```

Verify `service.name` is set:

```bash
kubectl exec -n app deploy/recommendations -- printenv | grep OTEL_SERVICE_NAME
```

Check Prometheus for span metrics:

```bash
curl -s 'http://127.0.0.1:9090/api/v1/query?query=traces_spanmetrics_calls_total{service="recommendations"}' | jq .
```

Inspect Tempo metrics generator and Grafana datasource settings:

```bash
kubectl logs -n monitoring deploy/tempo | grep -Ei 'metrics-generator|spanmetrics|service graph'
kubectl get secret -n monitoring grafana -o yaml | grep -n tempo
```

### Finding the root cause

The service exported traces,
but it did not set `service.name` explicitly.
The SDK defaulted to an unhelpful process name,
so Grafana could not map spans into the expected service graph identity.
Additionally,
span metrics generation had not been enabled for the updated namespace.

### Mitigation

Set:

```bash
kubectl set env deploy/recommendations -n app OTEL_SERVICE_NAME=recommendations
kubectl rollout restart deploy/recommendations -n app
```

Then verify Tempo metrics generation is enabled and that Grafana uses Prometheus for service map data.
Generate new traffic and reopen the trace.

### Postmortem fragment / lessons learned

Discovery in observability is rarely automatic.
You need working instrumentation,
stable naming,
and the right backend features enabled.
A missing service map node is usually a metadata problem before it is a visualization problem.

## How to practice these scenarios

Run each scenario as a small exercise:

1. read only the background and symptoms
2. write your first three hypotheses
3. run the diagnosis commands in order
4. decide whether the issue is instrumentation,
   collection,
   storage,
   query design,
   or alert design
5. document the minimum fix and the prevention action

## Common habits across all scenarios

The best investigators do a few things consistently:

- they verify the raw signal before trusting the dashboard
- they compare one tool against another,
  for example Prometheus API versus Grafana panel output
- they inspect labels and dimensions,
  not just values
- they ask whether the current metric or trace actually represents user impact
- they finish with a prevention note,
  not just a tactical fix

If you can work through these ten scenarios calmly,
you are already thinking like an SRE rather than a dashboard viewer.
