# Lab 01 — Defining SLIs, Writing SLOs, and Building Burn-Rate Alerts

## Lab goal

In this lab you will move from a vague reliability goal to a documented, measurable, and alertable SLO setup.
You will work with three service types:

- an HTTP API,
- a scheduled batch job,
- and a data pipeline.

By the end of the lab you will have:

- identified good user-centric SLIs,
- documented SLOs in YAML,
- implemented availability and latency SLIs in PromQL,
- created multi-window burn-rate recording and alert rules,
- designed Grafana panels for day-to-day SLO operations,
- and validated that the signals behave as expected.

---

## Learning objectives

After completing this lab, you should be able to:

1. distinguish between infrastructure metrics and user-facing SLIs,
2. define different SLI shapes for synchronous and asynchronous services,
3. write SLO YAML documentation that others can review and maintain,
4. implement PromQL for availability and latency ratio SLIs,
5. configure burn-rate alerts for 1h, 6h, 24h, and 72h decision windows,
6. validate that dashboard and alert output matches real service behavior.

---

## Scenario

Your team operates three production workloads:

| Service | Type | What users care about |
|---|---|---|
| `orders-api` | HTTP API | Requests succeed quickly |
| `invoice-batch` | Scheduled batch job | Nightly invoice generation finishes before 06:00 |
| `warehouse-pipeline` | Data pipeline | Analytics tables remain fresh within 30 minutes |

Your job is to define usable SLIs and SLOs for all three.
Only the HTTP API will use latency and availability PromQL in this lab, but the documentation must cover all services.

---

## Prerequisites

- Prometheus is running and scraping your application metrics.
- Grafana is connected to Prometheus.
- Your metrics follow stable naming conventions.
- The API exposes request counters and request duration histograms.
- The batch job exports run result and duration metrics.
- The data pipeline exports last-success timestamps or freshness lag metrics.

Recommended metrics for this lab:

- `http_requests_total`
- `http_request_duration_seconds_bucket`
- `http_request_duration_seconds_count`
- `batch_job_runs_total`
- `batch_job_deadline_met_total`
- `pipeline_records_processed_total`
- `dataset_last_success_timestamp_seconds`

---

## Step 1 — Define candidate SLIs for each service type

### 1.1 HTTP API SLIs

For an HTTP API, start with the user journey.
Ask:

- Did the request succeed?
- Did it complete quickly enough?
- Did it return a correct response?

A practical first version looks like this:

| SLI | Definition | Why it matters |
|---|---|---|
| Availability | fraction of eligible requests that do not return 5xx or timeout | users care whether the API works |
| Latency | fraction of eligible requests completed under 300 ms | users care whether it is responsive |
| Quality | fraction of responses passing contract validation | HTTP 200 alone may not be enough |

### 1.2 Batch job SLIs

A batch job should not inherit web-service SLIs blindly.
Users usually care about whether a scheduled run completes and whether it completes before a deadline.

Use these candidates:

| SLI | Definition | Why it matters |
|---|---|---|
| Completion success | fraction of scheduled runs that complete successfully | failed runs break downstream workflows |
| Deadline compliance | fraction of scheduled runs that finish before target time | late success can still be user-visible failure |
| Data quality | fraction of output files or rows passing validation | bad output may be worse than no output |

### 1.3 Data pipeline SLIs

A pipeline often needs freshness and quality more than request latency.

Use these candidates:

| SLI | Definition | Why it matters |
|---|---|---|
| Freshness | fraction of datasets updated within 30 minutes | stale dashboards mislead decisions |
| Processing success | fraction of pipeline runs that complete without terminal error | broken runs halt delivery |
| Throughput compliance | fraction of intervals meeting target processing rate | backlog growth can break freshness later |

### 1.4 Good-event definitions

Write down what counts as a good event for each workload.
This prevents numerator drift later.

| Service | Good event |
|---|---|
| `orders-api` | request returns non-5xx within 300 ms on user-facing routes |
| `invoice-batch` | scheduled run completes successfully before 06:00 |
| `warehouse-pipeline` | dataset is refreshed and freshness lag stays under 30 minutes |

### 1.5 Exclusions

Document exclusions early.
Examples:

- health checks,
- internal admin routes,
- synthetic load tests labeled `test="true"`,
- development namespaces,
- manually triggered backfill runs when they should not count against the regular job SLO.

---

## Step 2 — Write SLO documentation in YAML

Create a single document that can be reviewed by engineering, SRE, and product stakeholders.

```yaml
service_catalog:
  - service: orders-api
    type: http-api
    owners:
      team: commerce
      sre: reliability-platform
    slos:
      - name: availability
        objective: 99.9
        window: 30d
        user_journey: "Customer places or checks an order through the public API"
        source: prometheus
        sli:
          kind: ratio
          numerator: 'sum(increase(http_requests_total{service="orders-api",route!~"/healthz|/metrics",status!~"5.."}[{{ .window }}]))'
          denominator: 'sum(increase(http_requests_total{service="orders-api",route!~"/healthz|/metrics"}[{{ .window }}]))'
        exclusions:
          - synthetic traffic labeled test="true"
      - name: latency
        objective: 99.0
        window: 7d
        threshold: 0.3s
        sli:
          kind: threshold-ratio
          numerator: 'sum(increase(http_request_duration_seconds_bucket{service="orders-api",route!~"/healthz|/metrics",le="0.3"}[{{ .window }}]))'
          denominator: 'sum(increase(http_request_duration_seconds_count{service="orders-api",route!~"/healthz|/metrics"}[{{ .window }}]))'

  - service: invoice-batch
    type: batch-job
    owners:
      team: finance-platform
      sre: reliability-platform
    slos:
      - name: completion-success
        objective: 99.5
        window: 30d
        user_journey: "Nightly invoice run completes successfully"
        sli:
          kind: ratio
          numerator: 'sum(increase(batch_job_runs_total{job="invoice-batch",result="success"}[{{ .window }}]))'
          denominator: 'sum(increase(batch_job_runs_total{job="invoice-batch"}[{{ .window }}]))'
      - name: deadline-compliance
        objective: 99.0
        window: 30d
        deadline: "06:00 UTC"
        sli:
          kind: ratio
          numerator: 'sum(increase(batch_job_deadline_met_total{job="invoice-batch"}[{{ .window }}]))'
          denominator: 'sum(increase(batch_job_runs_total{job="invoice-batch",scheduled="true"}[{{ .window }}]))'

  - service: warehouse-pipeline
    type: data-pipeline
    owners:
      team: data-platform
      sre: reliability-platform
    slos:
      - name: freshness
        objective: 99.5
        window: 7d
        threshold: 30m
        user_journey: "Analytics consumers receive warehouse tables updated within 30 minutes"
        sli:
          kind: ratio
          numerator: 'avg_over_time((time() - dataset_last_success_timestamp_seconds{domain="warehouse"} <= bool 1800)[{{ .window }}:5m])'
          denominator: 'vector(1)'
      - name: throughput
        objective: 99.0
        window: 7d
        sli:
          kind: ratio
          numerator: 'avg_over_time((sum(rate(pipeline_records_processed_total{pipeline="warehouse"}[5m])) >= bool 2000)[{{ .window }}:5m])'
          denominator: 'vector(1)'
```

### 2.1 Review checklist for the YAML

Before moving on, verify:

- each SLO maps to a real user journey,
- each denominator is explicit,
- thresholds are not implied or hidden,
- windows are documented,
- exclusions are listed,
- owners are clear.

---

## Step 3 — Implement the HTTP API availability SLI in PromQL

In this section you will convert the availability definition into PromQL.

### 3.1 Decide what counts as success

For this lab, a successful `orders-api` request is:

- on a user-facing route,
- not a health or metrics route,
- not synthetic test traffic,
- not an HTTP 5xx,
- and not a request that times out at the edge.

### 3.2 Base query for a short operational window

Use a five-minute rate for dashboards and quick validation.

```promql
sum(rate(http_requests_total{
  service="orders-api",
  route!~"/healthz|/metrics",
  test!="true",
  status!~"5.."
}[5m]))
/
sum(rate(http_requests_total{
  service="orders-api",
  route!~"/healthz|/metrics",
  test!="true"
}[5m]))
```

### 3.3 Long-window availability query for SLO reporting

Use `increase()` when you want exact window math for reporting.

```promql
sum(increase(http_requests_total{
  service="orders-api",
  route!~"/healthz|/metrics",
  test!="true",
  status!~"5.."
}[30d]))
/
sum(increase(http_requests_total{
  service="orders-api",
  route!~"/healthz|/metrics",
  test!="true"
}[30d]))
```

### 3.4 Add edge timeout visibility if available

If edge metrics record request outcome directly, prefer them for availability.
This catches failures that never make it into app metrics.

```promql
sum(rate(ingress_requests_total{
  ingress="orders",
  route!~"/healthz|/metrics",
  outcome="success"
}[5m]))
/
sum(rate(ingress_requests_total{
  ingress="orders",
  route!~"/healthz|/metrics"
}[5m]))
```

### 3.5 Validation questions

- Does the query drop when you inject 5xx responses?
- Does the denominator remain stable when traffic is normal?
- Are health checks excluded?
- Does the query behave correctly when traffic is very low?

---

## Step 4 — Implement the HTTP API latency SLI in PromQL

Latency SLOs are easier to operate when expressed as a threshold ratio.
In this lab, the target is 99% of eligible requests under 300 ms over 7 days.

### 4.1 Use histogram buckets

The histogram must have a bucket at or above the threshold.
For a 300 ms target, the `le="0.3"` bucket must exist.

### 4.2 Short-window latency ratio query

```promql
sum(rate(http_request_duration_seconds_bucket{
  service="orders-api",
  route!~"/healthz|/metrics",
  le="0.3"
}[5m]))
/
sum(rate(http_request_duration_seconds_count{
  service="orders-api",
  route!~"/healthz|/metrics"
}[5m]))
```

### 4.3 Long-window latency SLI for SLO reporting

```promql
sum(increase(http_request_duration_seconds_bucket{
  service="orders-api",
  route!~"/healthz|/metrics",
  le="0.3"
}[7d]))
/
sum(increase(http_request_duration_seconds_count{
  service="orders-api",
  route!~"/healthz|/metrics"
}[7d]))
```

### 4.4 Diagnostic percentile query

Use percentile queries for debugging, not as your only SLO query.

```promql
histogram_quantile(
  0.99,
  sum by (le) (
    rate(http_request_duration_seconds_bucket{service="orders-api",route!~"/healthz|/metrics"}[5m])
  )
)
```

### 4.5 Common latency mistakes

- using averages,
- forgetting to exclude health checks,
- choosing a threshold with no matching histogram bucket,
- mixing server-side latency with end-user latency without explanation.

---

## Step 5 — Create recording rules for burn-rate calculations

This lab uses a 99.9% availability SLO.
That means the error-budget fraction is `0.001`.

Create the rule file:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: orders-api-slo-rules
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: orders-api.slo.recording
      interval: 30s
      rules:
        - record: service:error_ratio:rate5m
          expr: |
            sum(rate(http_requests_total{service="orders-api",route!~"/healthz|/metrics",status=~"5.."}[5m])) by (service)
            /
            sum(rate(http_requests_total{service="orders-api",route!~"/healthz|/metrics"}[5m])) by (service)
        - record: service:error_ratio:rate1h
          expr: |
            sum(rate(http_requests_total{service="orders-api",route!~"/healthz|/metrics",status=~"5.."}[1h])) by (service)
            /
            sum(rate(http_requests_total{service="orders-api",route!~"/healthz|/metrics"}[1h])) by (service)
        - record: service:error_ratio:rate6h
          expr: |
            sum(rate(http_requests_total{service="orders-api",route!~"/healthz|/metrics",status=~"5.."}[6h])) by (service)
            /
            sum(rate(http_requests_total{service="orders-api",route!~"/healthz|/metrics"}[6h])) by (service)
        - record: service:error_ratio:rate24h
          expr: |
            sum(rate(http_requests_total{service="orders-api",route!~"/healthz|/metrics",status=~"5.."}[24h])) by (service)
            /
            sum(rate(http_requests_total{service="orders-api",route!~"/healthz|/metrics"}[24h])) by (service)
        - record: service:error_ratio:rate72h
          expr: |
            sum(rate(http_requests_total{service="orders-api",route!~"/healthz|/metrics",status=~"5.."}[72h])) by (service)
            /
            sum(rate(http_requests_total{service="orders-api",route!~"/healthz|/metrics"}[72h])) by (service)
        - record: service:burn_rate:rate1h
          expr: service:error_ratio:rate1h / 0.001
        - record: service:burn_rate:rate6h
          expr: service:error_ratio:rate6h / 0.001
        - record: service:burn_rate:rate24h
          expr: service:error_ratio:rate24h / 0.001
        - record: service:burn_rate:rate72h
          expr: service:error_ratio:rate72h / 0.001
```

Apply the rule:

```bash
kubectl apply -f orders-api-slo-rules.yaml
```

---

## Step 6 — Add multi-window burn-rate alert rules

This lab asks for 1h, 6h, 24h, and 72h windows.
Use those windows as the main decision horizons.
A practical rule set is below.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: orders-api-slo-alerts
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: orders-api.slo.alerts
      rules:
        - alert: OrdersAPIBudgetBurnFast
          expr: |
            service:burn_rate:rate1h{service="orders-api"} > 14.4
          for: 5m
          labels:
            severity: critical
            slo: availability
          annotations:
            summary: "orders-api is burning error budget rapidly"
            description: "1h burn rate is above 14.4x; investigate active user impact now"

        - alert: OrdersAPIBudgetBurnHigh
          expr: |
            service:burn_rate:rate6h{service="orders-api"} > 6
          for: 15m
          labels:
            severity: warning
            slo: availability
          annotations:
            summary: "orders-api error budget burn is elevated"
            description: "6h burn rate is above 6x; recent changes and dependencies should be reviewed"

        - alert: OrdersAPIBudgetBurnDay
          expr: |
            service:burn_rate:rate24h{service="orders-api"} > 3
          for: 30m
          labels:
            severity: warning
            slo: availability
          annotations:
            summary: "orders-api is degrading over the last day"
            description: "24h burn rate is above 3x; budget will be consumed quickly if trend continues"

        - alert: OrdersAPIBudgetBurnTrend
          expr: |
            service:burn_rate:rate72h{service="orders-api"} > 1
          for: 1h
          labels:
            severity: info
            slo: availability
          annotations:
            summary: "orders-api shows sustained 72h burn"
            description: "72h burn is above normal budget consumption; review recurring causes and debt"
```

### 6.1 Why multiple windows matter

- `1h` catches acute outages.
- `6h` catches half-day degradation.
- `24h` shows meaningful daily reliability drift.
- `72h` highlights chronic budget erosion.

### 6.2 Optional stricter version

If you want classic fast and slow confirmation logic, pair a short operational window with each long window.
Example: `5m + 1h`, `30m + 6h`, `2h + 24h`, and `6h + 72h`.

---

## Step 7 — Build Grafana SLO dashboard panels

Create one dashboard called `orders-api-slo`.
Use the following panels.

### Panel 1 — Current availability SLI

Type: Stat

```promql
sum(rate(http_requests_total{service="orders-api",route!~"/healthz|/metrics",status!~"5.."}[5m]))
/
sum(rate(http_requests_total{service="orders-api",route!~"/healthz|/metrics"}[5m]))
```

Suggested thresholds:

- red: `< 0.999`
- yellow: `< 0.9995`
- green: `>= 0.9995`

### Panel 2 — Current latency SLI

Type: Stat

```promql
sum(rate(http_request_duration_seconds_bucket{service="orders-api",route!~"/healthz|/metrics",le="0.3"}[5m]))
/
sum(rate(http_request_duration_seconds_count{service="orders-api",route!~"/healthz|/metrics"}[5m]))
```

### Panel 3 — Error budget remaining

Type: Gauge

```promql
(
  1 - (
    sum(increase(http_requests_total{service="orders-api",route!~"/healthz|/metrics",status=~"5.."}[30d]))
    /
    sum(increase(http_requests_total{service="orders-api",route!~"/healthz|/metrics"}[30d]))
  ) / 0.001
) * 100
```

Thresholds:

- red: `< 10`
- yellow: `< 25`
- green: `>= 25`

### Panel 4 — Burn rate by window

Type: Time series

```promql
service:burn_rate:rate1h{service="orders-api"}
service:burn_rate:rate6h{service="orders-api"}
service:burn_rate:rate24h{service="orders-api"}
service:burn_rate:rate72h{service="orders-api"}
```

Add reference lines at `1`, `3`, `6`, and `14.4`.

### Panel 5 — Request volume context

Type: Time series

```promql
sum(rate(http_requests_total{service="orders-api",route!~"/healthz|/metrics"}[5m]))
```

This panel explains why ratios may look noisy during very low traffic periods.

### Panel 6 — p99 latency diagnostic panel

Type: Time series

```promql
histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket{service="orders-api",route!~"/healthz|/metrics"}[5m])))
```

---

## Step 8 — Validate and test the implementation

### 8.1 Validate rules are loaded

```bash
kubectl get prometheusrules -n monitoring
kubectl describe prometheusrule orders-api-slo-rules -n monitoring
kubectl describe prometheusrule orders-api-slo-alerts -n monitoring
```

### 8.2 Validate PromQL manually

Query these expressions directly in Prometheus UI:

- availability short window,
- latency short window,
- `service:error_ratio:rate1h`,
- `service:burn_rate:rate24h`.

Check that values are sensible.

### 8.3 Generate healthy traffic

Use a small k6 run to confirm normal conditions.

```javascript
import http from 'k6/http';
import { sleep } from 'k6';

export const options = {
  vus: 20,
  duration: '5m'
};

export default function () {
  http.get('https://orders.example.com/api/orders');
  sleep(1);
}
```

### 8.4 Generate availability failures

Introduce a temporary 5xx path in a staging environment or use a fault-injection rule.
Observe:

- availability SLI drops,
- error ratio rises,
- burn rate rises,
- budget remaining begins to fall.

### 8.5 Generate latency degradation

Add a test delay of 400 ms to a portion of requests.
Observe:

- latency SLI drops,
- p99 rises,
- availability may remain healthy,
- dashboard distinguishes latency from outright failure.

### 8.6 Compare metrics with reality

Ask a teammate to make real requests or use synthetic probes.
Verify that dashboard state matches observed user behavior.
If users report slowness while SLI looks green, re-check route filters, threshold, and measurement point.

---

## Step 9 — Completion checklist

- [ ] Three service types have documented SLI candidates.
- [ ] YAML SLO document exists and is reviewable.
- [ ] Availability SLI query works for `orders-api`.
- [ ] Latency SLI query works for `orders-api`.
- [ ] Recording rules exist for 1h, 6h, 24h, and 72h windows.
- [ ] Burn-rate alerts are present and understandable.
- [ ] Grafana dashboard shows SLI, budget, and burn-rate views.
- [ ] Validation was performed with both healthy and degraded traffic.

---

## Stretch exercises

1. Add a quality SLI for JSON schema validity.
2. Add a separate internal SLO for admin routes.
3. Create dashboard variables for `service` and `environment`.
4. Extend the same pattern to the batch job and pipeline with freshness-specific alerts.
5. Compare rolling-window versus calendar-window reporting for the same service.
