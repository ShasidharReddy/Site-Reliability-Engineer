# Lab 02 — Error Budget Tracking, Policy Activation, and Reporting

## Lab goal

In this lab you will move from static SLO math to live error-budget operations.
You will calculate current budget state from real metrics, create recording rules, visualize the budget in Grafana, simulate a breach, and walk through the policy response.
You will also automate a weekly budget report so the process continues outside the lab.

---

## Learning objectives

After this lab you should be able to:

1. calculate budget remaining from production-like metrics,
2. distinguish error rate from burn rate,
3. persist budget calculations in recording rules,
4. build a dashboard with budget remaining, burn rate, and projection panels,
5. simulate a breach safely and observe the policy workflow,
6. automate a weekly budget summary for stakeholders.

---

## Scenario

Continue using the `orders-api` availability SLO from Lab 01.
Assume:

- SLO target = `99.9%`
- window = `30d`
- error budget fraction = `0.001`
- eligible traffic is all non-health-check user requests

Your job is to operationalize the budget so that anyone on the team can answer:

- How much budget is left?
- How quickly are we burning it?
- If current conditions continue, when will we breach?
- What actions should the team take now?

---

## Prerequisites

- Lab 01 is complete.
- Prometheus is scraping `orders-api` metrics.
- Grafana is connected to Prometheus.
- Alertmanager or equivalent paging system is available.
- You can safely inject failure in staging or a low-risk environment.

---

## Step 1 — Define the budget math explicitly

Start with formulas before writing queries.

### 1.1 Basic formulas

```text
error_budget_fraction = 1 - slo_target
error_ratio = bad_requests / total_requests
budget_used = error_ratio / error_budget_fraction
budget_remaining = 1 - budget_used
burn_rate = error_ratio / error_budget_fraction
```

### 1.2 Example interpretation

For a 99.9% SLO:

- budget fraction = `0.001`
- if current 30-day error ratio is `0.0002`, then budget used = `20%`
- if current 1h error ratio is `0.006`, then burn rate = `6x`

### 1.3 Decide what is policy-driving

Use the 30-day availability budget as the primary policy signal.
Latency can also have its own SLO, but the policy in this lab is driven by availability budget state.

---

## Step 2 — Query the current error-budget state from real metrics

### 2.1 Current 30-day error ratio

```promql
sum(increase(http_requests_total{
  service="orders-api",
  route!~"/healthz|/metrics",
  status=~"5.."
}[30d]))
/
sum(increase(http_requests_total{
  service="orders-api",
  route!~"/healthz|/metrics"
}[30d]))
```

### 2.2 Current 30-day budget remaining percentage

```promql
(
  1 - (
    sum(increase(http_requests_total{service="orders-api",route!~"/healthz|/metrics",status=~"5.."}[30d]))
    /
    sum(increase(http_requests_total{service="orders-api",route!~"/healthz|/metrics"}[30d]))
  ) / 0.001
) * 100
```

### 2.3 Current budget used percentage

```promql
(
  sum(increase(http_requests_total{service="orders-api",route!~"/healthz|/metrics",status=~"5.."}[30d]))
  /
  sum(increase(http_requests_total{service="orders-api",route!~"/healthz|/metrics"}[30d]))
) / 0.001 * 100
```

### 2.4 Current burn rate views

```promql
service:error_ratio:rate1h{service="orders-api"} / 0.001
service:error_ratio:rate6h{service="orders-api"} / 0.001
service:error_ratio:rate24h{service="orders-api"} / 0.001
service:error_ratio:rate72h{service="orders-api"} / 0.001
```

### 2.5 Manual interpretation checklist

If budget remaining is:

- above `50%`, normal posture usually applies,
- between `25%` and `50%`, the team should start weekly budget reviews,
- below `25%`, deployment scrutiny increases,
- below `10%`, risky changes should stop,
- at `0%` or less, breach policy activates.

---

## Step 3 — Create recording rules for budget tracking

Recording rules make dashboards and alerts faster and more consistent.
Create a rule file such as `orders-api-budget-rules.yaml`.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: orders-api-budget-rules
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: orders-api.budget.recording
      interval: 30s
      rules:
        - record: service:error_ratio:30d
          expr: |
            sum(increase(http_requests_total{service="orders-api",route!~"/healthz|/metrics",status=~"5.."}[30d])) by (service)
            /
            sum(increase(http_requests_total{service="orders-api",route!~"/healthz|/metrics"}[30d])) by (service)

        - record: service:error_budget_fraction
          expr: |
            0.001

        - record: service:error_budget_used_ratio:30d
          expr: |
            service:error_ratio:30d
            /
            on() group_left service:error_budget_fraction

        - record: service:error_budget_remaining_ratio:30d
          expr: |
            1 - service:error_budget_used_ratio:30d

        - record: service:error_budget_remaining_percent:30d
          expr: |
            service:error_budget_remaining_ratio:30d * 100

        - record: service:error_budget_used_percent:30d
          expr: |
            service:error_budget_used_ratio:30d * 100

        - record: service:burn_rate:1h
          expr: |
            service:error_ratio:rate1h / on() group_left service:error_budget_fraction

        - record: service:burn_rate:6h
          expr: |
            service:error_ratio:rate6h / on() group_left service:error_budget_fraction

        - record: service:burn_rate:24h
          expr: |
            service:error_ratio:rate24h / on() group_left service:error_budget_fraction

        - record: service:burn_rate:72h
          expr: |
            service:error_ratio:rate72h / on() group_left service:error_budget_fraction
```

Apply it:

```bash
kubectl apply -f orders-api-budget-rules.yaml
```

### 3.1 Why recording rules help

- dashboards load faster,
- everyone uses the same formulas,
- alert rules stay readable,
- weekly reports can reuse stable series.

---

## Step 4 — Add budget-state classification rules

It is helpful to classify the current policy posture directly in metrics or annotations.
While Prometheus is not a workflow engine, you can still create useful state expressions.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: orders-api-budget-state-rules
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: orders-api.budget.state
      interval: 30s
      rules:
        - record: service:error_budget_state:healthy
          expr: service:error_budget_remaining_percent:30d{service="orders-api"} > 50
        - record: service:error_budget_state:watch
          expr: service:error_budget_remaining_percent:30d{service="orders-api"} <= 50 and service:error_budget_remaining_percent:30d{service="orders-api"} > 25
        - record: service:error_budget_state:guarded
          expr: service:error_budget_remaining_percent:30d{service="orders-api"} <= 25 and service:error_budget_remaining_percent:30d{service="orders-api"} > 10
        - record: service:error_budget_state:critical
          expr: service:error_budget_remaining_percent:30d{service="orders-api"} <= 10 and service:error_budget_remaining_percent:30d{service="orders-api"} > 0
        - record: service:error_budget_state:breached
          expr: service:error_budget_remaining_percent:30d{service="orders-api"} <= 0
```

These booleans are useful for dashboard banners.

---

## Step 5 — Build the error-budget dashboard

Create a Grafana dashboard named `orders-api-error-budget`.
The minimum useful panels are below.

### Panel 1 — Budget remaining

Type: Gauge

```promql
service:error_budget_remaining_percent:30d{service="orders-api"}
```

Suggested thresholds:

- red: `< 10`
- orange: `< 25`
- yellow: `< 50`
- green: `>= 50`

### Panel 2 — Budget used

Type: Stat

```promql
service:error_budget_used_percent:30d{service="orders-api"}
```

This is useful for leadership updates because it answers "how much have we spent?"

### Panel 3 — Burn rate by window

Type: Time series

```promql
service:burn_rate:1h{service="orders-api"}
service:burn_rate:6h{service="orders-api"}
service:burn_rate:24h{service="orders-api"}
service:burn_rate:72h{service="orders-api"}
```

Add reference lines at `1`, `3`, `6`, and `14.4`.

### Panel 4 — Error ratio by window

Type: Time series

```promql
service:error_ratio:rate1h{service="orders-api"}
service:error_ratio:rate6h{service="orders-api"}
service:error_ratio:rate24h{service="orders-api"}
service:error_ratio:rate72h{service="orders-api"}
```

This helps when you want raw error-rate context rather than normalized burn rate.

### Panel 5 — Projection panel

The simplest projection estimates how many days remain if the 24h burn rate continues.

```promql
30 / clamp_min(service:burn_rate:24h{service="orders-api"}, 0.001)
```

Interpretation:

- `30` means healthy baseline pace,
- `10` means budget would last roughly ten more days,
- values near `1` indicate severe risk.

### Panel 6 — Volume context

Type: Time series

```promql
sum(rate(http_requests_total{service="orders-api",route!~"/healthz|/metrics"}[5m]))
```

Low volume can make ratios noisy.
Always keep a volume panel nearby.

### Panel 7 — Policy banner

Type: Stat or State timeline

Use one of the recorded state metrics from Step 4.
For example:

```promql
service:error_budget_state:breached{service="orders-api"}
```

Map values to text in Grafana:

- `1` = `BREACHED`
- `0` = hidden or no text

Repeat for healthy, watch, guarded, and critical if desired.

---

## Step 6 — Simulate an SLO breach safely

Do this in staging or a protected canary slice.
Do not run this first in broad production traffic.

### 6.1 Option A: Inject application failures

If your app supports feature flags or debug endpoints, enable a short-lived failure mode.
Example behavior:

- 10% of requests return HTTP 500,
- test runs for 15 minutes,
- only staging traffic is affected.

### 6.2 Option B: Use a fault-injection proxy

If you run a service mesh or ingress controller with fault support, inject a fixed percentage of failures.
A conceptual example:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: orders-api-fault
spec:
  hosts:
    - orders-api
  http:
    - fault:
        abort:
          httpStatus: 500
          percentage:
            value: 10
      route:
        - destination:
            host: orders-api
```

### 6.3 What to observe during the simulation

- 1h burn rate should rise first,
- 6h view will lag behind,
- budget remaining will start trending down,
- availability SLI should visibly drop,
- alerting should trigger according to thresholds.

### 6.4 Stop conditions

Abort the experiment if:

- error budget alerts fire in unexpected environments,
- blast radius expands beyond the intended target,
- downstream systems start failing unexpectedly,
- dashboards stop updating correctly.

---

## Step 7 — Walk through the error-budget policy workflow

Metrics alone do not change behavior.
Practice the human workflow.

### 7.1 Example workflow when burn rate crosses 6h threshold

1. On-call confirms user impact or staging test conditions.
2. Incident is declared if production user impact exists.
3. Recent deploys are reviewed.
4. Service owner decides whether to pause risky changes.
5. SRE or engineering lead checks current budget remaining.
6. If remaining budget is low, a reliability review is scheduled immediately.
7. Action items are recorded before the incident fully closes.

### 7.2 Example workflow when budget remaining drops below 10%

- feature launches touching the critical path are paused,
- only reliability fixes, rollback work, or low-risk patches proceed,
- the team meets daily to review burn,
- leadership receives a short update,
- recovery work is tracked visibly.

### 7.3 Example workflow when budget is breached

- change freeze on risky features,
- mandatory postmortem for the breach-driving incidents,
- reliability debt backlog reordered,
- exception process required for any urgent release,
- recovery criteria documented before normal delivery resumes.

### 7.4 Questions to ask during the walkthrough

- Did alerts fire when expected?
- Did humans know what actions to take?
- Were thresholds and actions already documented?
- Was there disagreement about whether the policy should apply?
- Do dashboards make budget state obvious to non-experts?

---

## Step 8 — Automate weekly reporting

A weekly report keeps the policy visible even during calm periods.
The report can be sent to email, Slack, or a ticketing system.

### 8.1 Example report fields

Include:

- service name,
- SLO target,
- 30-day budget remaining,
- 30-day budget used,
- current 1h, 6h, 24h, and 72h burn rates,
- top incidents this week,
- current policy posture,
- recommended actions.

### 8.2 Example shell script

```bash
#!/usr/bin/env bash
set -euo pipefail

PROM_URL="http://localhost:9090"
SERVICE="orders-api"

query() {
  local expr="$1"
  curl -sG "$PROM_URL/api/v1/query" --data-urlencode "query=$expr" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); r=d["data"]["result"]; print(r[0]["value"][1] if r else "NaN")'
}

BUDGET_REMAINING=$(query 'service:error_budget_remaining_percent:30d{service="orders-api"}')
BUDGET_USED=$(query 'service:error_budget_used_percent:30d{service="orders-api"}')
BURN_1H=$(query 'service:burn_rate:1h{service="orders-api"}')
BURN_6H=$(query 'service:burn_rate:6h{service="orders-api"}')
BURN_24H=$(query 'service:burn_rate:24h{service="orders-api"}')
BURN_72H=$(query 'service:burn_rate:72h{service="orders-api"}')

POSTURE="healthy"
python3 - <<'PY' "$BUDGET_REMAINING"
import sys
v=float(sys.argv[1])
if v <= 0:
    print("breached")
elif v < 10:
    print("critical")
elif v < 25:
    print("guarded")
elif v < 50:
    print("watch")
else:
    print("healthy")
PY
```

### 8.3 Example human-readable output format

```text
Weekly Error Budget Report — orders-api
SLO: 99.9% over 30d
Budget remaining: 82.4%
Budget used: 17.6%
Burn rates: 1h=0.4x, 6h=0.8x, 24h=0.9x, 72h=1.1x
Posture: healthy
Recommended action: continue normal delivery, review slow 72h trend in weekly reliability sync
```

### 8.4 Scheduling the report

Use one of these approaches:

- CronJob in Kubernetes,
- GitHub Actions on a weekly schedule,
- CI scheduler in your internal platform,
- Airflow or another orchestrator for data/reliability reporting.

### 8.5 Example Kubernetes CronJob wrapper

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: orders-api-budget-report
  namespace: monitoring
spec:
  schedule: "0 9 * * 1"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: reporter
              image: alpine:3.20
              command: ["/bin/sh", "-c"]
              args:
                - |
                  apk add --no-cache curl python3
                  /scripts/error-budget-report.sh
```

---

## Step 9 — Validation checklist

- [ ] 30-day error ratio query returns expected values.
- [ ] Budget remaining and used recording rules are present.
- [ ] Burn-rate recording rules show 1h, 6h, 24h, and 72h views.
- [ ] Dashboard includes remaining, used, burn, and projection panels.
- [ ] Simulated breach changes dashboard output as expected.
- [ ] Alerting behavior matches configured thresholds.
- [ ] Policy workflow is documented and practiced.
- [ ] Weekly report can run without manual query editing.

---

## Stretch exercises

1. Add a latency budget report alongside availability.
2. Add incident count annotations to the Grafana dashboard.
3. Export weekly reports to object storage or Git history for trend analysis.
4. Compare time-based budget explanation versus request-based budget operation.
5. Add a policy exception report for releases approved during low-budget periods.
