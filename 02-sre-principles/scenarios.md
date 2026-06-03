# SRE Principles — Real-World Scenarios

## How to use these scenarios

Treat each scenario as a tabletop exercise or a hands-on lab.
For each one:

- read the background,
- clarify the reliability goal,
- run the sample commands,
- decide what to change,
- compare your answer with the expected outcome,
- and capture at least one lesson that should become team policy.

## Shared decision flow

```text
New reliability problem
        |
        v
Identify user impact and service boundary
        |
        v
Choose the SLI that best matches user experience
        |
        v
Set target and error budget policy
        |
        v
Create alerting, dashboarding, and response path
        |
        v
Review outcome with product and engineering
```

## Scenario 1: New Service Has No SLOs and launches in 2 weeks

### Background

The payments team built `payment-api`.
It handles card authorizations and payment status checks.
The service is planned for production launch in two weeks.
There are traces and logs, but no SLIs, no SLOs, and no error budget policy.
Leadership wants "production-ready monitoring" before launch.

### Problem statement

Define practical SLIs.
Set realistic SLOs.
Build a dashboard for launch review.
Add burn-rate alerts that page only on meaningful user risk.

### Step 1 — Define service boundaries and user journeys

Start by identifying what the user actually experiences.
For `payment-api`, the main user journey is a successful authorization request that completes quickly.
Health endpoints and internal admin calls should not dominate the denominator.

```text
Mobile app / checkout page
          |
          v
     payment-api
          |
          +--> fraud-check
          +--> card processor
          +--> ledger writer
```

### Step 2 — Choose SLIs

Use one availability SLI and one latency SLI.

| SLI | Good event | Eligible event |
|---|---|---|
| Availability | response is not 5xx and not timeout | all external `/authorize` and `/payments/*` requests |
| Latency | request finishes in under 400 ms | same denominator as availability |

### Step 3 — Create recording rules

```promql
sum(rate(http_requests_total{job="payment-api",route=~"/authorize|/payments/.+",status!~"5.."}[30d]))
/
sum(rate(http_requests_total{job="payment-api",route=~"/authorize|/payments/.+"}[30d]))
```

```promql
sum(rate(http_request_duration_seconds_bucket{job="payment-api",route=~"/authorize|/payments/.+",le="0.4"}[30d]))
/
sum(rate(http_request_duration_seconds_count{job="payment-api",route=~"/authorize|/payments/.+"}[30d]))
```

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: payment-api-slo
  namespace: monitoring
spec:
  groups:
  - name: payment-api.slo
    rules:
    - record: sli:payment_api_availability:ratio30d
      expr: |
        sum(rate(http_requests_total{job="payment-api",route=~"/authorize|/payments/.+",status!~"5.."}[30d]))
        /
        sum(rate(http_requests_total{job="payment-api",route=~"/authorize|/payments/.+"}[30d]))
    - record: sli:payment_api_latency:ratio30d
      expr: |
        sum(rate(http_request_duration_seconds_bucket{job="payment-api",route=~"/authorize|/payments/.+",le="0.4"}[30d]))
        /
        sum(rate(http_request_duration_seconds_count{job="payment-api",route=~"/authorize|/payments/.+"}[30d]))
```

### Step 4 — Set the initial SLOs

Use a target that is ambitious but believable for a new service.
A practical starting point is:

- availability SLO: 99.9%,
- latency SLO: 99.0% under 400 ms.

That gives the team 43.2 minutes of monthly availability error budget.
It also makes performance visible without pretending the service is already at ultra-premium reliability.

### Step 5 — Add burn-rate alerts

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: payment-api-burnrate
  namespace: monitoring
spec:
  groups:
  - name: payment-api.alerts
    rules:
    - alert: PaymentApiHighBurnRate
      expr: |
        (
          (1 - (sum(rate(http_requests_total{job="payment-api",status!~"5.."}[5m])) / sum(rate(http_requests_total{job="payment-api"}[5m])))) / (1 - 0.999) > 14.4
        )
        and
        (
          (1 - (sum(rate(http_requests_total{job="payment-api",status!~"5.."}[1h])) / sum(rate(http_requests_total{job="payment-api"}[1h])))) / (1 - 0.999) > 14.4
        )
      for: 2m
      labels:
        severity: page
    - alert: PaymentApiSlowBurnRate
      expr: |
        (
          (1 - (sum(rate(http_requests_total{job="payment-api",status!~"5.."}[30m])) / sum(rate(http_requests_total{job="payment-api"}[30m])))) / (1 - 0.999) > 6
        )
        and
        (
          (1 - (sum(rate(http_requests_total{job="payment-api",status!~"5.."}[6h])) / sum(rate(http_requests_total{job="payment-api"}[6h])))) / (1 - 0.999) > 6
        )
      for: 15m
      labels:
        severity: ticket
```

### Step 6 — Add Alertmanager routing

```yaml
route:
  receiver: default
  routes:
  - matchers:
    - alertname="PaymentApiHighBurnRate"
    receiver: pagerduty-payments
  - matchers:
    - alertname="PaymentApiSlowBurnRate"
    receiver: slack-payments
receivers:
- name: pagerduty-payments
  pagerduty_configs:
  - routing_key: REDACTED
- name: slack-payments
  slack_configs:
  - channel: '#payments-sre'
```

### Step 7 — Build a launch dashboard

```json
{
  "title": "payment-api launch dashboard",
  "panels": [
    {
      "title": "30d availability",
      "type": "stat",
      "targets": [{"expr": "sli:payment_api_availability:ratio30d"}]
    },
    {
      "title": "30d latency compliance",
      "type": "stat",
      "targets": [{"expr": "sli:payment_api_latency:ratio30d"}]
    },
    {
      "title": "5m request rate",
      "type": "timeseries",
      "targets": [{"expr": "sum(rate(http_requests_total{job='payment-api'}[5m]))"}]
    },
    {
      "title": "p95 latency",
      "type": "timeseries",
      "targets": [{"expr": "histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{job='payment-api'}[5m])))"}]
    }
  ]
}
```

### Step 8 — Apply and validate

```bash
kubectl apply -f payment-api-slo.yaml
kubectl apply -f payment-api-burnrate.yaml
kubectl -n monitoring get prometheusrule payment-api-slo payment-api-burnrate
kubectl -n monitoring get secret alertmanager-main -o jsonpath='{.data.alertmanager\.yaml}' | base64 --decode | grep -n 'PaymentApi'
```

### Expected outcomes

- the team can explain what counts as a good event,
- the launch review has concrete reliability targets,
- the dashboard shows both long-window compliance and short-window health,
- and page-worthy burn happens only for real user risk.

### Lessons learned

A service without an SLO is not launch-ready.
Dashboards are not enough unless they encode policy and response expectations.

---

## Scenario 2: Error budget is depleted 3 weeks before month end

### Background

`checkout-api` has a 99.9% availability SLO.
That gives it 43.2 minutes of downtime budget in a 30-day month.
The service has only 5 minutes left.
There are still 3 weeks left in the month.
A product release is waiting for approval.

### Problem statement

Calculate the remaining budget.
Decide what can still deploy.
Create a freeze plan.
Explain the situation to technical and non-technical stakeholders.

### Step 1 — Calculate the number manually

```bash
python3 - <<'PY'
minutes = 30 * 24 * 60
budget = minutes * 0.001
remaining = 5
spent = budget - remaining
print(f'total_budget={budget:.1f} minutes')
print(f'spent_budget={spent:.1f} minutes')
print(f'remaining_budget={remaining:.1f} minutes')
PY
```

### Step 2 — Confirm it from Prometheus

```promql
(1 - sli:checkout_api_availability:ratio30d) * 30 * 24 * 60
```

```promql
((1 - sli:checkout_api_availability:ratio30d) / (1 - 0.999)) * 100
```

### Step 3 — Decide what can deploy

Use this decision tree.

```text
Budget healthy? ---- no ----> freeze feature releases
                              |
                              +--> allow rollback, revert, hotfix for reliability
                              |
                              +--> allow observability changes with low blast radius
                              |
                              +--> require executive exception for business-critical release
```

### Step 4 — Apply the freeze

```bash
kubectl -n argocd annotate app checkout-api sre.github.com/error-budget-freeze=true --overwrite
kubectl -n argocd patch app checkout-api --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
```

```yaml
release_freeze:
  service: checkout-api
  triggered_by: exhausted_error_budget
  allowed_changes:
    - rollback
    - revert
    - reliability hotfix
  blocked_changes:
    - feature release
    - dependency refresh
    - nonessential migration
```

### Step 5 — Communicate to stakeholders

For engineering leaders:

- only 5 minutes of downtime budget remain,
- any medium incident will breach the monthly target,
- and reliability work must take priority until the error rate stabilizes.

For product or business leaders:

- the service has nearly no room left for further disruption,
- delaying nonessential changes now reduces customer and revenue risk,
- and the freeze protects the rest of the month.

### Step 6 — Prepare the exception path

```yaml
release_exception_request:
  service: checkout-api
  change: tax-compliance-fix
  risk_summary: low blast radius config change
  rollback_plan: immediate revert within 5 minutes
  approvers:
    - vp-engineering
    - product-director
```

### Expected outcomes

- the team uses the same budget math,
- nonessential releases pause,
- exceptions have explicit ownership,
- and product leaders understand the decision in business language.

### Lessons learned

An error budget without enforcement is just a chart.
Reliability policy must be understood outside the SRE team.

---

## Scenario 3: On-call is burning out with 15 pages per night

### Background

The search platform team receives 15 or more PagerDuty alerts per night.
Many pages are duplicates, fast self-healing conditions, or low-severity warnings.
The on-call engineer is exhausted and starts muting alerts.

### Problem statement

Audit alert quality.
Quantify alert toil.
Fix the top five noisiest alerts.
Reduce pages without hiding real incidents.

### Step 1 — Measure alert toil

Use a simple formula.

```text
Alert toil minutes per week = alert count × average handling minutes
```

Example:

```text
105 pages/week × 8 minutes/page = 840 minutes/week = 14 hours/week
```

### Step 2 — Find the noisiest alerts

```bash
kubectl -n monitoring logs statefulset/alertmanager-main --since=24h | egrep 'notify|firing|resolved' | tail -200
kubectl -n monitoring get prometheusrule -o yaml | grep -n 'alert:'
```

```promql
sum by (alertname) (increase(ALERTS{alertstate="firing",severity="page"}[24h]))
```

### Step 3 — Inspect one noisy alert

```yaml
- alert: SearchApiHighLatency
  expr: histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{job="search-api"}[5m]))) > 0.3
  for: 0m
  labels:
    severity: page
```

This alert pages instantly on a short latency spike.
It has no confirmation window.
It also has no companion error-rate signal.

### Step 4 — Tune the rule

```yaml
- alert: SearchApiHighLatency
  expr: histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{job="search-api"}[5m]))) > 0.5
  for: 10m
  labels:
    severity: ticket
```

### Step 5 — Deduplicate and reroute

```yaml
route:
  receiver: default
  group_by: ['alertname', 'service', 'cluster']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
  - matchers:
    - severity="page"
    receiver: pagerduty-search
  - matchers:
    - severity="ticket"
    receiver: slack-search
```

### Step 6 — Validate the alert backlog again

```promql
sum by (alertname) (increase(ALERTS{alertstate="firing",severity="page"}[7d]))
```

```bash
kubectl -n monitoring get secret alertmanager-main -o jsonpath='{.data.alertmanager\.yaml}' | base64 --decode
```

### Expected outcomes

- page volume drops sharply,
- warnings stop waking people up,
- and the team can focus on alerts with clear user impact.

### Lessons learned

Noisy alerts are a form of toil.
A `for:` duration is often the cheapest reliability improvement available.

---

## Scenario 4: Leadership wants a 99.999% SLO

### Background

The CTO read a blog post and asks whether the main customer API can move from 99.9% to 99.999% immediately.
The request is framed as a competitive necessity.
The team has not modeled the engineering cost.

### Problem statement

Show what five nines means.
Translate the target into downtime minutes and seconds.
Recommend a realistic target with technical justification.

### Step 1 — Show the math

```bash
python3 - <<'PY'
minutes = 30 * 24 * 60
for target in [99.9, 99.99, 99.999]:
    downtime = minutes * (1 - target / 100)
    print(f'{target}% -> {downtime:.2f} minutes/month')
PY
```

### Step 2 — Present the comparison table

| Target | Allowed downtime per month |
|---|---|
| 99.9% | 43.2 minutes |
| 99.99% | 4.32 minutes |
| 99.999% | 0.432 minutes = 25.92 seconds |

### Step 3 — Explain what changes operationally

```text
Higher target
    |
    +--> less tolerance for routine maintenance
    +--> tighter dependency reliability requirements
    +--> more redundancy and failover automation
    +--> more expensive testing and rollback controls
```

### Step 4 — Build a cost and benefit view

| Option | Reliability gain | Likely cost |
|---|---|---|
| move from 99.9% to 99.95% | moderate | tighter rollout, better alerting, small infra cost |
| move from 99.9% to 99.99% | high | multi-region, stronger dependency contracts, significant engineering work |
| move to 99.999% | extreme | architectural redesign, high cloud spend, strict change controls |

### Step 5 — Recommend a realistic path

A practical answer is often:

- keep the customer-facing SLO at 99.9% or 99.95% first,
- improve dependency resilience,
- measure current incident classes,
- and revisit a stricter target after several stable quarters.

### Step 6 — Support the recommendation with current data

```promql
sli:checkout_api_availability:ratio30d
```

```promql
sum(increase(ALERTS{alertname="CheckoutApiHighBurnRate",alertstate="firing"}[90d]))
```

### Expected outcomes

- leadership sees the real meaning of five nines,
- the conversation shifts from aspiration to trade-offs,
- and the team proposes a staged plan instead of an unrealistic promise.

### Lessons learned

A higher SLO is a product and cost decision, not only a technical preference.
Five nines is usually an architecture program, not a dashboard edit.

---

## Scenario 5: Service migrated to Kubernetes and the old SLO no longer fits

### Background

A monolith moved to Kubernetes and became several services:
`frontend`, `checkout-api`, `inventory-api`, `pricing-api`, and `payment-worker`.
The old SLO measured one NGINX success ratio.
Now incidents happen in only one dependency while the old SLO hides the blast radius.

### Problem statement

Redesign the SLI model for a microservice architecture.
Decide what should be measured per service and what should remain aggregate.
Handle distributed transactions without creating meaningless SLOs.

### Step 1 — Map the user journey

```text
User -> frontend -> checkout-api -> inventory-api
                           |
                           +--> pricing-api
                           +--> payment-worker
```

### Step 2 — Separate product and component SLOs

Use two layers.

| Layer | Example SLI | Owner |
|---|---|---|
| Product SLO | checkout completion success ratio | product + platform |
| Component SLO | `inventory-api` availability | service owner |

### Step 3 — Define the product SLI

```promql
sum(rate(checkout_completed_total{status="success"}[30d]))
/
sum(rate(checkout_attempt_total[30d]))
```

### Step 4 — Define service-level SLOs

```promql
sum(rate(http_requests_total{job="inventory-api",status!~"5.."}[30d]))
/
sum(rate(http_requests_total{job="inventory-api"}[30d]))
```

```promql
sum(rate(http_requests_total{job="pricing-api",status!~"5.."}[30d]))
/
sum(rate(http_requests_total{job="pricing-api"}[30d]))
```

### Step 5 — Handle distributed transactions carefully

Do not create a fake end-to-end SLO by multiplying component SLOs.
Instead:

- measure the actual user completion rate,
- keep component SLOs for diagnosis and ownership,
- and document dependency assumptions explicitly.

### Step 6 — Review dependency policy

```yaml
dependencies:
  inventory-api:
    criticality: hard dependency
    expected_slo: 99.95
  pricing-api:
    criticality: degradable
    expected_slo: 99.9
  payment-worker:
    criticality: async completion
    expected_slo: 99.5
```

### Expected outcomes

- the user journey has a true product-level SLO,
- each service still has owner-specific indicators,
- and the architecture change no longer hides failures behind a monolith-era metric.

### Lessons learned

SLO design must evolve with architecture.
Per-service metrics are useful, but user outcomes must remain the top-level truth.

---

## Scenario 6: Toil audit shows 60% of on-call time is toil

### Background

The SRE team tracked on-call work for one month.
Sixty percent of the time went to repetitive tasks:
manual pod restarts,
copying logs into tickets,
resubmitting stuck jobs,
and scaling services before scheduled campaigns.

### Problem statement

Categorize the toil.
Estimate the cost.
Prioritize automation work.
Build the business case for one sprint focused on reduction.

### Step 1 — Categorize the work

| Category | Example | Weekly minutes |
|---|---|---|
| reactive restart | restart stuck worker | 180 |
| manual scaling | raise replicas before promotion | 120 |
| repetitive communication | copy status into ticket and Slack | 90 |
| job repair | rerun failed batch with same flags | 210 |

### Step 2 — Calculate cost

```bash
python3 - <<'PY'
weekly_minutes = 180 + 120 + 90 + 210
monthly_hours = weekly_minutes * 4 / 60
print(f'weekly_minutes={weekly_minutes}')
print(f'monthly_hours={monthly_hours:.1f}')
PY
```

### Step 3 — Rank automation opportunities

```text
High frequency + low complexity + high risk reduction = top priority
```

Example priority order:

1. add liveness probe to self-heal stuck worker,
2. create HPA for scheduled traffic growth,
3. auto-post remediation output to Slack and ticket,
4. automate batch rerun validation.

### Step 4 — Show one implementation example

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 20
  periodSeconds: 10
  failureThreshold: 3
```

```bash
kubectl -n production patch deploy order-worker --type merge -p '{"spec":{"template":{"spec":{"containers":[{"name":"order-worker","livenessProbe":{"httpGet":{"path":"/healthz","port":8080},"initialDelaySeconds":20,"periodSeconds":10,"failureThreshold":3}}]}}}}'
```

### Step 5 — Build the business case

Use the numbers.
If toil consumes 40 engineer-hours per month,
a sprint spent removing half of it pays back quickly.
Also highlight secondary gains:

- less burnout,
- faster real incident response,
- more time for reliability engineering.

### Expected outcomes

- the team has evidence instead of anecdotes,
- automation priorities are ranked by cost and impact,
- and management sees toil reduction as capacity creation.

### Lessons learned

Toil is measurable.
Once measured, it competes well for roadmap time.

---

## Scenario 7: Chaos experiment goes wrong

### Background

A chaos platform randomly kills pods in `payment-processing`.
The experiment was meant to validate self-healing.
Instead it removed too many pods at once and payment success dropped sharply.
A resilience drill became a customer incident.

### Problem statement

Run a post-incident review.
Update chaos policy.
Add blast radius controls.
Improve graceful degradation and circuit breaking.

### Step 1 — Stop the experiment

```bash
kubectl delete podchaos,networkchaos -n production --all
kubectl -n production rollout status deploy/payment-processing
```

### Step 2 — Review what failed

```bash
kubectl get events -A --sort-by=.lastTimestamp | egrep 'chaos|payment-processing|Evicted|Deleted' | tail -50
kubectl -n production logs deploy/payment-processing --since=30m | tail -100
```

```promql
sum(rate(payment_authorization_total{status="success"}[5m]))
/
sum(rate(payment_authorization_total[5m]))
```

### Step 3 — Identify policy gaps

Common failures include:

- too many targets selected,
- no environment restriction,
- no automatic abort on SLI degradation,
- and no rollback owner watching live metrics.

### Step 4 — Update the policy

```yaml
chaos_policy:
  production:
    enabled: false
  staging:
    max_targets: 1
    abort_if:
      payment_success_ratio_5m: '< 0.995'
      p95_latency_ms: '> 700'
    requires:
      - experiment-owner
      - incident-commander
```

### Step 5 — Improve graceful degradation

```yaml
circuit_breaker:
  dependency: fraud-check
  timeout_ms: 150
  failure_threshold: 5
  fallback: manual-review-queue
```

### Expected outcomes

- future chaos tests are tightly scoped,
- production cannot be targeted casually,
- and the application degrades instead of collapsing when a dependency fails.

### Lessons learned

Chaos engineering is reliability work only when the blast radius is controlled.
A test without an abort path is just unmanaged risk.

---

## Scenario 8: SLO review shows 3 months of hidden violations

### Background

A customer escalation forces a review of `reporting-api` reliability.
The team discovers the SLO has been violated for three months,
but the alert never fired because the burn-rate rule used the wrong denominator.
No one noticed until a major customer complained.

### Problem statement

Reconstruct historical compliance.
Write the key facts for a postmortem.
Fix the alert.
Plan the customer remediation conversation.

### Step 1 — Rebuild historical compliance from raw metrics

```promql
sum(rate(http_requests_total{job="reporting-api",status!~"5.."}[30d]))
/
sum(rate(http_requests_total{job="reporting-api"}[30d]))
```

```promql
sum(rate(http_requests_total{job="reporting-api",status=~"5.."}[7d]))
/
sum(rate(http_requests_total{job="reporting-api"}[7d]))
```

### Step 2 — Compare the broken alert rule

```yaml
- alert: ReportingApiHighBurnRate
  expr: |
    (1 - (sum(rate(http_requests_total{job="reporting-api",status!~"5.."}[5m])) / sum(rate(http_requests_total{job="reporting-api",status!~"5.."}[5m])))) / (1 - 0.999) > 14.4
```

The denominator equals the numerator.
The expression can never show burn correctly.

### Step 3 — Replace it with the correct rule

```yaml
- alert: ReportingApiHighBurnRate
  expr: |
    (
      (1 - (sum(rate(http_requests_total{job="reporting-api",status!~"5.."}[5m])) / sum(rate(http_requests_total{job="reporting-api"}[5m])))) / (1 - 0.999) > 14.4
    )
    and
    (
      (1 - (sum(rate(http_requests_total{job="reporting-api",status!~"5.."}[1h])) / sum(rate(http_requests_total{job="reporting-api"}[1h])))) / (1 - 0.999) > 14.4
    )
  for: 2m
```

### Step 4 — Prepare postmortem facts

Include:

- how long the SLO was breached,
- why the alert failed,
- what customers experienced,
- what monitoring review was missing,
- and what guardrail now prevents recurrence.

### Step 5 — Plan the customer conversation

Use clear facts.
Do not start with PromQL details.
Say:

- we identified a reliability gap that affected your service,
- our alerting failed to escalate it correctly,
- the monitoring logic has been corrected,
- and we are tracking remediation work with executive visibility.

### Expected outcomes

- historical compliance is reconstructed from raw data,
- the alert rule is corrected,
- and customer communication is based on accountability and facts.

### Lessons learned

Bad alert math can hide long-term reliability failure.
SLO reviews must audit the query, not only the dashboard screenshot.

---

## Final review checklist

- [ ] every scenario starts from a user-centered SLI,
- [ ] the SLO target is connected to error budget math,
- [ ] alert severity matches business urgency,
- [ ] dashboards and rules use canonical calculations,
- [ ] toil is quantified before automation is prioritized,
- [ ] leadership requests are translated into reliability trade-offs,
- [ ] architecture changes trigger SLO redesign,
- [ ] and every incident ends with a prevention action.
