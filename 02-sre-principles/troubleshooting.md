# SRE Principles — Troubleshooting Guide

## Purpose

Use this guide when SRE principles look correct on paper but break down in production.
Each issue focuses on the operational gap between theory and reality.
Every section includes:

- symptom,
- diagnosis commands,
- root cause,
- fix with commands or config,
- and prevention guidance.

## Shared triage workflow

```text
Customer impact or internal alert
            |
            v
+-----------------------------+
| Confirm the user symptom    |
| before debugging internals  |
+-------------+---------------+
              |
              v
+-----------------------------+
| Check the current SLI, SLO  |
| and alert definitions        |
+-------------+---------------+
              |
              v
+-----------------------------+
| Compare telemetry sources   |
| Prometheus, Grafana, logs   |
+-------------+---------------+
              |
              v
+-----------------------------+
| Identify measurement issue  |
| policy issue, or system bug |
+-------------+---------------+
              |
              v
+-----------------------------+
| Apply smallest safe fix     |
| then validate the SLI again |
+-----------------------------+
```

## Quick baseline command pack

```bash
kubectl config current-context
kubectl get ns
kubectl get deploy -A
kubectl get pods -A | egrep -v 'Running|Completed'
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -50
kubectl top nodes
kubectl top pods -A --sort-by=cpu | tail -20
kubectl top pods -A --sort-by=memory | tail -20
kubectl -n monitoring get prometheus
kubectl -n monitoring get alertmanager
kubectl -n monitoring get prometheusrule
```

## Quick SLO math reference

| Target | Error budget | Monthly downtime allowed |
|---|---|---|
| 99.0% | 1.0% | 7h 18m |
| 99.5% | 0.5% | 3h 39m |
| 99.9% | 0.1% | 43.2m |
| 99.95% | 0.05% | 21.6m |
| 99.99% | 0.01% | 4.32m |
| 99.999% | 0.001% | 25.92s |

## Scenario index

| Area | Problem | First check |
|---|---|---|
| SLO / budget | SLO keeps dropping even though service looks fine | audit the SLI query |
| SLO / budget | Error budget is exhausted but team still wants releases | compute remaining budget manually |
| SLO / budget | Alert fires constantly but dashboard shows good availability | inspect burn-rate alert windows |
| SLO / budget | Teams see conflicting SLO dashboards | standardize canonical numerator and denominator |
| Toil | Automation exists but work is still toil | measure manual touch points |
| Toil | Automation works in staging, fails in prod | compare runtime environment details |
| Toil | Runbook automation is halfway done | track manual steps as automation debt |
| Policy | Product ignores release freeze | enforce escalation and deployment guardrails |
| Policy | Engineers are gaming the SLO | audit exclusions and raw traffic |
| Capacity | Load test says 10k RPS, prod fails at 7k | look for coordination limits |
| Capacity | Forecast overprovisioned by 3x | review demand model and right-size requests |
| Reliability testing | Chaos test broke production | reduce blast radius before rerun |
| Reliability testing | Load test polluted production metrics | isolate synthetic traffic |

---

## 1. SLO / Error Budget Problems

### 1.1 SLO compliance keeps dropping even though the service seems fine

#### Symptom

Users are not reporting major problems.
Application logs look normal.
Yet the monthly availability SLO keeps drifting downward.
The service owner says, "the app is healthy, Prometheus must be wrong."

#### Diagnosis commands

Audit whether the SLI measures the actual service instead of a proxy.
A common failure is measuring load balancer reachability instead of application success.

```promql
sum(rate(http_requests_total{job="checkout-api",status!~"5.."}[30d]))
/
sum(rate(http_requests_total{job="checkout-api"}[30d]))
```

```promql
sum(rate(envoy_cluster_upstream_rq_total{envoy_cluster_name="checkout-api",response_code!~"5.."}[30d]))
/
sum(rate(envoy_cluster_upstream_rq_total{envoy_cluster_name="checkout-api"}[30d]))
```

```promql
sum(rate(probe_success{job="public-lb-blackbox"}[30d]))
/
sum(rate(probe_success{job="public-lb-blackbox"}[30d]))
```

```bash
kubectl -n monitoring get prometheusrule slo-rules -o yaml
kubectl -n monitoring port-forward svc/prometheus-k8s 9090:9090
curl -s 'http://127.0.0.1:9090/api/v1/rules' | grep -n 'checkout-api'
kubectl -n production get svc,ep,deploy,pod -l app=checkout-api
kubectl -n production logs deploy/checkout-api --since=30m | egrep 'ERROR|Exception' | tail -50
```

#### Root cause

The SLI denominator is based on a metric that does not represent user-visible success.
Typical mistakes include:

- using `probe_success` from a load balancer check as the availability SLI,
- excluding 499 or timeout paths that users still experience as failures,
- or counting proxy retries as separate good requests.

#### Fix

Create a canonical application-level SLI and mark the old query deprecated.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: checkout-api-sli
  namespace: monitoring
spec:
  groups:
  - name: checkout-api.sli
    rules:
    - record: sli:checkout_api_availability:ratio30d
      expr: |
        sum(rate(http_requests_total{job="checkout-api",route!="/healthz",status!~"5.."}[30d]))
        /
        sum(rate(http_requests_total{job="checkout-api",route!="/healthz"}[30d]))
```

```bash
kubectl apply -f checkout-api-sli-rule.yaml
kubectl -n monitoring rollout restart statefulset prometheus-k8s
kubectl -n monitoring get prometheusrule checkout-api-sli -o yaml
```

#### Prevention

Document the good-event definition in the service SLO spec.
Review numerator and denominator changes in code review.
Require one query review by the service owner and one by the SRE reviewer.
Keep a test dashboard that shows raw request counts beside the ratio.

---

### 1.2 Error budget exhausted and the team wants to keep deploying

#### Symptom

The monthly target is 99.9%.
The service has already spent nearly all 43.2 minutes of monthly downtime.
Product leadership still wants a release because a revenue feature is due.
The team argues that only a few minutes remain and the change is low risk.

#### Diagnosis commands

First calculate the budget manually so everyone sees the same number.

```bash
python3 - <<'PY'
slo = 99.9
minutes_in_30_day_month = 30 * 24 * 60
budget = minutes_in_30_day_month * (1 - slo / 100)
spent = 39.8
remaining = budget - spent
print(f'total_budget_minutes={budget:.1f}')
print(f'spent_minutes={spent:.1f}')
print(f'remaining_minutes={remaining:.1f}')
PY
```

```promql
(1 - sli:checkout_api_availability:ratio30d) * 30 * 24 * 60
```

```promql
((1 - sli:checkout_api_availability:ratio30d) / (1 - 0.999)) * 100
```

```bash
kubectl -n monitoring get prometheusrule checkout-api-burnrate -o yaml
gh issue create --repo your-org/checkout-api --title 'Error budget freeze for checkout-api' --body 'Budget nearly exhausted. Freeze feature deployments until recovery plan is approved.'
```

#### Root cause

There is no enforced error budget policy.
The budget exists as a dashboard number but not as a release control mechanism.
The organization treats SLO review as optional instead of a product governance input.

#### Fix

Define the freeze state and block feature deployments while allowing emergency reliability fixes.

```yaml
error_budget_policy:
  service: checkout-api
  slo_target: 99.9
  freeze_threshold_percent: 100
  allowed_changes_during_freeze:
    - rollback
    - configuration revert
    - incident remediation
    - observability fixes
  blocked_changes_during_freeze:
    - feature release
    - schema migration without rollback
    - risky dependency upgrade
```

```bash
cat <<'EOF' > /Users/shasidharreddy_mallu/Site-Reliability-Engineer/02-sre-principles/templates/error-budget-freeze-example.yaml
service: checkout-api
freeze_active: true
approved_by: sre-manager
expires_at: 2026-04-30T23:59:00Z
EOF
```

```bash
kubectl -n argocd patch app checkout-api --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
kubectl -n argocd annotate app checkout-api sre.github.com/error-budget-freeze=true --overwrite
```

#### How to communicate to product management

Lead with business risk, not SRE jargon.
Use language like:

- we have 3.4 minutes of unplanned downtime left this month,
- one medium incident could consume the rest,
- and a freeze now protects revenue for the remaining weeks.

Frame the freeze as a product control.
Do not describe it as an infrastructure preference.

#### Prevention

Add budget status to weekly product reviews.
Automate release gates in CI or CD.
Require an exception record for any deployment during freeze.
Review exception outcomes in the monthly reliability meeting.

---

### 1.3 SLO alert fires constantly but Grafana shows 99.9% availability

#### Symptom

PagerDuty alerts are firing every few hours.
The main SLO dashboard still shows compliance around 99.9% over 30 days.
On-call engineers suspect Alertmanager is noisy.
The real issue is often the burn-rate rule or routing configuration.

#### Diagnosis commands

Check whether the alert uses multi-window burn-rate math correctly.

```promql
(
  1 -
  (
    sum(rate(http_requests_total{job="checkout-api",status!~"5.."}[5m]))
    /
    sum(rate(http_requests_total{job="checkout-api"}[5m]))
  )
) / (1 - 0.999)
```

```promql
(
  1 -
  (
    sum(rate(http_requests_total{job="checkout-api",status!~"5.."}[1h]))
    /
    sum(rate(http_requests_total{job="checkout-api"}[1h]))
  )
) / (1 - 0.999)
```

```bash
kubectl -n monitoring get prometheusrule checkout-api-burnrate -o yaml
kubectl -n monitoring get secret alertmanager-main -o jsonpath='{.data.alertmanager\.yaml}' | base64 --decode
kubectl -n monitoring logs statefulset/alertmanager-main --since=15m | tail -100
curl -s 'http://127.0.0.1:9090/api/v1/alerts' | grep -n 'CheckoutApi'
```

#### Root cause

The alert is probably one of these:

- using a single short window without a matching long window,
- dividing by the wrong objective error ratio,
- or routing a warning alert as a page.

Grafana may show 30-day compliance while the alert correctly or incorrectly reacts to a short high burn period.
These views are supposed to differ.
They should not conflict due to misconfiguration.

#### Fix

Use a standard fast-burn and slow-burn pair.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: checkout-api-burnrate
  namespace: monitoring
spec:
  groups:
  - name: checkout-api.alerts
    rules:
    - alert: CheckoutApiHighBurnRate
      expr: |
        (
          (1 - (sum(rate(http_requests_total{job="checkout-api",status!~"5.."}[5m])) / sum(rate(http_requests_total{job="checkout-api"}[5m])))) / (1 - 0.999) > 14.4
        )
        and
        (
          (1 - (sum(rate(http_requests_total{job="checkout-api",status!~"5.."}[1h])) / sum(rate(http_requests_total{job="checkout-api"}[1h])))) / (1 - 0.999) > 14.4
        )
      for: 2m
      labels:
        severity: page
    - alert: CheckoutApiSlowBurnRate
      expr: |
        (
          (1 - (sum(rate(http_requests_total{job="checkout-api",status!~"5.."}[30m])) / sum(rate(http_requests_total{job="checkout-api"}[30m])))) / (1 - 0.999) > 6
        )
        and
        (
          (1 - (sum(rate(http_requests_total{job="checkout-api",status!~"5.."}[6h])) / sum(rate(http_requests_total{job="checkout-api"}[6h])))) / (1 - 0.999) > 6
        )
      for: 15m
      labels:
        severity: ticket
```

```yaml
route:
  receiver: default
  routes:
  - matchers:
    - alertname="CheckoutApiHighBurnRate"
    receiver: pagerduty
  - matchers:
    - alertname="CheckoutApiSlowBurnRate"
    receiver: slack-sre
```

#### Prevention

Keep burn-rate rules in a reusable template.
Test alerts against historical incidents before enabling paging.
Make dashboard panels show short-window burn and 30-day compliance side by side.
Route ticket-level alerts away from PagerDuty.

---

### 1.4 SLO dashboard shows conflicting numbers between teams

#### Symptom

Platform engineering claims the service is at 99.95%.
The application team claims 99.72%.
Customer success cites another dashboard.
Nobody trusts the numbers during incident review.

#### Diagnosis commands

Compare the exact numerator, denominator, and exclusions used by each team.

```bash
kubectl -n monitoring get prometheusrule -o yaml | egrep -n 'checkout-api|availability|latency'
grep -R "checkout-api" /Users/shasidharreddy_mallu/Site-Reliability-Engineer/02-sre-principles -n
```

```promql
sum(rate(http_requests_total{job="checkout-api",route!="/healthz",status!~"5.."}[30d]))
/
sum(rate(http_requests_total{job="checkout-api",route!="/healthz"}[30d]))
```

```promql
sum(rate(http_requests_total{job="checkout-api",status=~"2..|3.."}[30d]))
/
sum(rate(http_requests_total{job="checkout-api"}[30d]))
```

```promql
histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{job="checkout-api"}[5m])))
```

#### Root cause

The teams are using different methodologies.
One excludes health checks.
Another excludes 429 responses.
A third uses latency as the primary SLI and labels it availability.
Conflicting dashboards are usually a process failure before they are a tool failure.

#### Fix

Publish one canonical SLI contract.

```yaml
service: checkout-api
sli:
  availability:
    good_events: status not in 5xx and no timeout
    eligible_events: all external user requests except /healthz and /metrics
    source_metric: http_requests_total
    calculation_owner: sre-platform
  latency:
    good_events: request_duration_seconds_bucket le="0.3"
    eligible_events: same denominator as availability
    source_metric: http_request_duration_seconds_bucket
```

```bash
kubectl create configmap checkout-api-sli-contract \
  -n monitoring \
  --from-file=sli-contract.yaml=/Users/shasidharreddy_mallu/Site-Reliability-Engineer/02-sre-principles/templates/slo-definition.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
```

#### Prevention

Review SLI methodology quarterly.
Store dashboards and rules in version control.
Require every dashboard panel to reference the recording rule name.
Treat ad hoc PromQL pasted into Grafana as untrusted until reviewed.

---

## 2. Toil Reduction Problems

### 2.1 “We automated it but it is still toil”

#### Symptom

A team says they automated a task.
But on-call engineers still babysit the workflow, re-run jobs, fill in missing parameters, or clean up bad outputs.
The automation reduced keystrokes but did not remove cognitive load.

#### Diagnosis commands

Measure the manual touch points around the automation.

```bash
grep -R "manual" /Users/shasidharreddy_mallu/Site-Reliability-Engineer/02-sre-principles -n || true
kubectl -n production logs cronjob/report-repair --since=7d | tail -100
kubectl -n production get jobs --sort-by=.metadata.creationTimestamp | tail -20
```

```bash
python3 - <<'PY'
manual_minutes = 210
automated_minutes = 95
handoff_minutes = 70
total = manual_minutes + automated_minutes + handoff_minutes
print(f'automation_assist_ratio={automated_minutes/total:.2f}')
print(f'human_touch_ratio={(manual_minutes + handoff_minutes)/total:.2f}')
PY
```

#### Root cause

The script automated the middle of the task but left setup and recovery manual.
This is disguised toil.
Common examples include:

- needing a human to choose input files every run,
- needing a human to validate obvious success signals,
- or requiring a human to clean partial state after failure.

#### Fix

Perform a toil audit on the full workflow instead of the script alone.

```yaml
task: nightly-report-repair
steps:
  - step: identify failed tenant
    manual: true
  - step: run repair script
    manual: false
  - step: compare output row counts
    manual: true
  - step: notify analytics team
    manual: true
```

```bash
cat <<'EOF' > /Users/shasidharreddy_mallu/Site-Reliability-Engineer/02-sre-principles/templates/toil-audit-example.yaml
task: nightly-report-repair
current_manual_minutes: 28
weekly_frequency: 9
automation_candidates:
  - auto-discover failed tenant
  - verify output checksums automatically
  - send success notification from pipeline
EOF
```

#### Prevention

Define success as zero routine human intervention.
Track automation debt separately from feature debt.
Require every automation project to measure before and after toil minutes.

---

### 2.2 Automation script keeps failing in production but works in staging

#### Symptom

A remediation script passes in staging every time.
In production it fails with odd parsing errors, missing binaries, or permission problems.
The script owner says, "it works on my cluster."

#### Diagnosis commands

Run an environment parity checklist.

```bash
kubectl -n staging exec deploy/ops-tools -- sh -c 'uname -a; bash --version 2>/dev/null || true; sh --version 2>/dev/null || true; date --version 2>/dev/null || date'
kubectl -n production exec deploy/ops-tools -- sh -c 'uname -a; bash --version 2>/dev/null || true; sh --version 2>/dev/null || true; date --version 2>/dev/null || date'
```

```bash
kubectl -n production exec deploy/ops-tools -- sh -c 'command -v bash; command -v awk; command -v sed; command -v jq || true'
kubectl -n production exec deploy/ops-tools -- sh -c 'ls -l /bin/sh && readlink /bin/sh || true'
```

```bash
sh -n remediation.sh
bash -n remediation.sh
```

#### Root cause

Production often differs in one of these ways:

- `/bin/sh` is `dash` or BusyBox instead of Bash,
- GNU tools used in staging are BSD variants in production,
- service accounts differ,
- environment variables are not present,
- or network egress is blocked.

#### Fix

Make the script explicit and portable.

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

DATE_BIN=date
if command -v gdate >/dev/null 2>&1; then
  DATE_BIN=gdate
fi

"$DATE_BIN" -u '+%Y-%m-%dT%H:%M:%SZ'
```

```bash
kubectl -n production create configmap ops-script-config --from-env-file=prod.env --dry-run=client -o yaml | kubectl apply -f -
kubectl -n production set image deploy/ops-tools ops-tools=ghcr.io/your-org/ops-tools:1.4.2
kubectl -n production rollout status deploy/ops-tools
```

#### Prevention

Pin the runtime image.
Run the same container in staging and production.
Prefer POSIX shell if Bash features are unnecessary.
Document GNU versus BSD assumptions in the script header.

---

### 2.3 Runbook automation is halfway done and some steps remain manual

#### Symptom

The runbook says 80% automated.
In reality the operator still copies pod names, looks up ticket context, and confirms each step by hand.
The remaining manual work is enough to make the task interruptive and error-prone.

#### Diagnosis commands

List the manual steps that remain after the current automation finishes.

```bash
grep -n "manual" /Users/shasidharreddy_mallu/Site-Reliability-Engineer/02-sre-principles/**/*.md 2>/dev/null || true
kubectl -n production get pods -l app=checkout-api -o name
kubectl -n production logs deploy/checkout-api --since=10m | tail -50
```

#### Root cause

Automation work stopped when the most visible part was scripted.
The team never tracked the remaining manual steps as debt.
Half automation often survives because it looks complete in demos.

#### Fix

Create an automation debt tracker and burn it down in small increments.

```yaml
automation_debt:
  - id: ad-001
    step: select affected pod automatically
    current_manual_minutes: 3
    owner: sre
  - id: ad-002
    step: attach incident link to remediation output
    current_manual_minutes: 2
    owner: platform
  - id: ad-003
    step: validate remediation success from metrics
    current_manual_minutes: 4
    owner: app-team
```

```bash
kubectl -n production create configmap checkout-remediation-workflow \
  --from-literal=selector='app=checkout-api' \
  --from-literal=success_query='sum(rate(http_requests_total{job="checkout-api",status!~"5.."}[5m])) / sum(rate(http_requests_total{job="checkout-api"}[5m]))' \
  --dry-run=client -o yaml | kubectl apply -f -
```

#### Prevention

Track automation debt in backlog grooming.
Estimate manual minutes removed, not just story completion.
Close a runbook automation project only when the runbook can execute end to end with bounded human approval steps.

---

## 3. Error Budget Policy Conflicts

### 3.1 Product team ignores the error budget freeze

#### Symptom

The SLO is clearly violated.
The freeze policy exists in a document.
Yet feature release requests keep arriving, often with a claim that the release is urgent.
The SRE team gets treated as a blocker instead of a partner.

#### Diagnosis commands

Collect evidence before escalating.

```promql
sli:checkout_api_availability:ratio30d
```

```promql
((1 - sli:checkout_api_availability:ratio30d) / (1 - 0.999)) * 100
```

```bash
gh issue list --repo your-org/checkout-api --search 'error budget freeze' || true
gh pr list --repo your-org/checkout-api --state open
kubectl -n argocd get app checkout-api -o yaml | egrep -n 'syncPolicy|annotation|freeze'
```

#### Root cause

The escalation path is vague.
The freeze is framed as an engineering preference.
There is no executive agreement on what counts as a valid exception.

#### Fix

Document the escalation ladder and automate the guardrail.

```text
SRE on-call detects budget breach
        |
        v
service owner notified within 15 minutes
        |
        v
product manager and engineering manager review freeze status
        |
        v
VP or delegated approver required for exception
```

```yaml
release_exception:
  service: checkout-api
  budget_status: exhausted
  requested_change: tax-rounding-fix
  business_reason: legal compliance
  rollback_plan: revert deployment within 5 minutes
  approvers:
    - vp-engineering
    - product-director
```

```bash
kubectl -n argocd annotate app checkout-api sre.github.com/freeze=active --overwrite
kubectl -n argocd patch app checkout-api --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
```

#### Prevention

Review freeze exceptions monthly.
Add product managers to SLO review meetings.
Make the cost of exceptions visible in the postmortem and quarterly business review.

---

### 3.2 Engineering team is gaming the SLO metric

#### Symptom

The official SLO looks healthier after a service change.
At the same time customer complaints increase.
The app team may have excluded failure modes from the denominator or filtered bad routes after the fact.

#### Diagnosis commands

Compare raw traffic to the recorded SLI.

```promql
sum(rate(http_requests_total{job="checkout-api"}[5m]))
```

```promql
sum(rate(http_requests_total{job="checkout-api",route!="/healthz"}[5m]))
```

```promql
sum(rate(http_requests_total{job="checkout-api",status=~"499|5.."}[5m]))
```

```bash
kubectl -n monitoring get prometheusrule checkout-api-sli -o yaml
kubectl -n production logs deploy/checkout-api --since=1h | egrep 'timeout|cancel|503|504' | tail -100
kubectl -n production get ingress,svc,virtualservice -A | grep checkout-api
```

#### Root cause

The team optimized the metric instead of the service.
Typical gaming patterns include:

- excluding 429 responses even when users experience them as hard failures,
- filtering out the busiest route because it is noisy,
- or moving failures to a downstream system that is outside the current SLI.

#### Fix

Audit SLO changes like production changes.

```yaml
slo_change_review:
  requires:
    - service-owner approval
    - sre approval
    - customer-impact explanation
    - historical backtest
```

```bash
kubectl -n monitoring label prometheusrule checkout-api-sli review-status=pending --overwrite
kubectl -n monitoring annotate prometheusrule checkout-api-sli audit.sre.github.com/requested-by=app-team --overwrite
```

#### Prevention

Backtest every SLI change against 90 days of historical data.
Include customer support trends in SLO reviews.
Treat denominator changes as policy changes, not dashboard tweaks.

---

## 4. Capacity Planning Problems

### 4.1 Load test shows 10k RPS but production fails at 7k RPS

#### Symptom

Synthetic load testing says the service survives 10k requests per second.
In production the same service degrades at 7k.
Latency spikes, queue depth rises, and connection errors appear.
The load test result was real, but the production system has coordination costs the test missed.

#### Diagnosis commands

Measure external dependencies, queueing, and runtime pauses.

```promql
sum(rate(http_requests_total{job="checkout-api"}[5m]))
```

```promql
histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket{job="checkout-api"}[5m])))
```

```promql
sum(rate(db_connection_pool_wait_seconds_sum{job="checkout-api"}[5m]))
/
sum(rate(db_connection_pool_wait_seconds_count{job="checkout-api"}[5m]))
```

```promql
histogram_quantile(0.99, sum by (le) (rate(go_gc_duration_seconds_bucket{job="checkout-api"}[5m])))
```

```bash
kubectl -n production top pods -l app=checkout-api
kubectl -n production exec deploy/checkout-api -- sh -c 'ss -s; ulimit -n'
kubectl -n production logs deploy/checkout-api --since=15m | egrep 'timeout|pool exhausted|connection reset' | tail -100
```

#### Root cause

Production differs from load test in one or more ways:

- real database or cache limits,
- TLS handshake and connection reuse behavior,
- garbage collection pauses,
- cross-zone network latency,
- or shared dependency contention.

#### Fix

Tune for the real bottleneck.

```bash
kubectl -n production patch deploy checkout-api --type='json' -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/env/0","value":{"name":"DB_POOL_MAX","value":"80"}},
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"1000m"}
]'
kubectl -n production rollout status deploy/checkout-api
```

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: checkout-api
  namespace: production
spec:
  minReplicas: 8
  maxReplicas: 40
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 65
```

#### Prevention

Mirror production dependency limits in performance testing.
Include p99 latency, connection pool wait, and GC pause in test success criteria.
Always compare synthetic load shape to real traffic distribution.

---

### 4.2 Capacity forecast was wrong and the team overprovisioned by 3x

#### Symptom

The cluster runs far below reserved CPU and memory.
Finance notices cloud cost is much higher than expected.
SRE reviews show average pod CPU at 18% of request and memory at 35%.

#### Diagnosis commands

Look at requested versus used resources over time.

```promql
sum(kube_pod_container_resource_requests{resource="cpu",namespace="production"})
```

```promql
sum(rate(container_cpu_usage_seconds_total{namespace="production",container!=""}[5m]))
```

```promql
sum(kube_pod_container_resource_requests{resource="memory",namespace="production"})
```

```promql
sum(container_memory_working_set_bytes{namespace="production",container!=""})
```

```bash
kubectl -n production top pods --containers
kubectl -n production get deploy -o custom-columns=NAME:.metadata.name,CPU_REQ:.spec.template.spec.containers[*].resources.requests.cpu,MEM_REQ:.spec.template.spec.containers[*].resources.requests.memory
```

#### Root cause

The forecast relied on peak anecdotes instead of observed percentiles.
The model may have assumed all services peak together.
Requests and limits were copied from a high-risk launch period and never revisited.

#### Fix

Right-size from historical percentiles and apply safer request-to-limit ratios.

```bash
kubectl -n production patch deploy checkout-api --type='json' -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"300m"},
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"512Mi"},
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/cpu","value":"1000m"},
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"1Gi"}
]'
```

```yaml
rightsizing_policy:
  cpu_request_basis: p95_usage * 1.2
  memory_request_basis: p99_usage * 1.15
  review_interval: 30d
```

#### Prevention

Review requests and limits monthly.
Model seasonality instead of only average traffic.
Separate baseline capacity from event-driven surge capacity.
Track cost per request alongside utilization.

---

## 5. Reliability Testing Problems

### 5.1 Chaos engineering broke production instead of staging

#### Symptom

A chaos experiment terminated pods or injected latency in production.
The blast radius expanded beyond the intended service.
A resilience exercise became a customer incident.

#### Diagnosis commands

Find the experiment scope and stop it first.

```bash
kubectl get chaosengine,chaosexperiment,networkchaos,podchaos -A
kubectl get events -A --sort-by=.lastTimestamp | egrep 'chaos|delete|evict|latency' | tail -50
kubectl -n production get pods -l app=payment-api -o wide
kubectl -n production logs deploy/payment-api --since=15m | tail -100
```

```promql
sum(rate(http_requests_total{job="payment-api",status!~"5.."}[5m]))
/
sum(rate(http_requests_total{job="payment-api"}[5m]))
```

#### Root cause

The experiment lacked blast radius control.
Common misses include:

- no namespace scoping,
- no traffic guardrail,
- no abort threshold,
- or running in production before staging validation.

#### Fix

Stop the experiment and restore normal traffic immediately.

```bash
kubectl delete networkchaos,podchaos -n production --all
kubectl -n production rollout restart deploy/payment-api
kubectl -n production rollout status deploy/payment-api
```

Use pre-chaos validation and emergency stop controls next time.

```yaml
chaos_policy:
  environments:
    - staging
  production_allowed: false
  abort_conditions:
    availability_ratio_5m: '< 0.995'
    p95_latency_ms: '> 500'
  max_targets: 1
  required_approvals: 2
```

#### Prevention

Start with one replica, one namespace, and one failure mode.
Require a rollback owner before the test starts.
Monitor user SLIs during the experiment, not just chaos tool output.

---

### 5.2 Load test contaminated production metrics

#### Symptom

After a performance test, the production SLO dashboard looks worse.
Error budget burn rises even though real customers were not impacted.
Executives ask why reliability dropped during an internal benchmark.

#### Diagnosis commands

Check whether synthetic traffic is labeled and excluded.

```promql
sum(rate(http_requests_total{job="checkout-api",traffic_type="synthetic"}[5m]))
```

```promql
sum(rate(http_requests_total{job="checkout-api",traffic_type!="synthetic",status!~"5.."}[30d]))
/
sum(rate(http_requests_total{job="checkout-api",traffic_type!="synthetic"}[30d]))
```

```bash
kubectl -n loadtest get jobs,pods
kubectl -n production logs deploy/checkout-api --since=30m | grep 'traffic_type'
kubectl -n monitoring get servicemonitor -o yaml | grep -n 'relabelings' -n
```

#### Root cause

Synthetic traffic used the same path, labels, and dashboards as production traffic.
The observability stack had no way to separate test requests from customer requests.

#### Fix

Label synthetic traffic at the source and exclude it from SLO calculations.

```bash
curl -H 'X-Traffic-Type: synthetic' https://checkout.example.com/healthz
```

```yaml
metric_relabel_configs:
- source_labels: [http_header_x_traffic_type]
  target_label: traffic_type
```

```promql
sum(rate(http_requests_total{job="checkout-api",traffic_type!="synthetic",status!~"5.."}[30d]))
/
sum(rate(http_requests_total{job="checkout-api",traffic_type!="synthetic"}[30d]))
```

#### Prevention

Reserve a header or tenant for synthetic traffic.
Add a dedicated Grafana row for load tests.
State in the test plan whether synthetic traffic is included in or excluded from the SLO.

---

## Final verification checklist

- [ ] the SLI is user-centered and owned,
- [ ] error budget math is documented and reproducible,
- [ ] burn-rate alerts use paired windows,
- [ ] dashboards reference canonical recording rules,
- [ ] automation removes human work instead of moving it,
- [ ] policy exceptions are explicit and reviewable,
- [ ] capacity plans are tied to observed production limits,
- [ ] reliability tests include blast radius and traffic isolation controls.
