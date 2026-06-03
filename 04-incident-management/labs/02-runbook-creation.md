# Lab 02 — Runbook Creation

## Prerequisites

- Completion of [Lab 01 — Incident Simulation](01-incident-simulation.md) or equivalent hands-on incident response practice.
- Access to the sample `checkout-api`, `payment-service`, and `db` workloads in a test namespace.
- Familiarity with Prometheus rules, Alertmanager annotations, and markdown editing.
- Ability to create local files in a scratch working directory such as `$HOME/runbook-lab`.
- Optional: access to Grafana dashboards and a change-management system for linking remediation tickets.

## Overview

This lab focuses on converting scattered tribal knowledge into production-quality runbooks. You will build a template, write scenario-specific procedures, test them against controlled failures, add a searchable registry, and wire the results into alert metadata so responders land in the right document quickly.

| Level | Learning objectives |
|---|---|
| Basic | Write a runbook with clear trigger conditions, triage commands, and verification steps. |
| Intermediate | Encode branching logic for multiple failure causes and keep actions safe under time pressure. |
| Advanced | Link runbooks to alerts, create a runbook registry, and evaluate document quality using an explicit checklist. |

## Setup and Working Directory

```bash
export NS=incident-lab
export RUNBOOK_DIR="$HOME/runbook-lab"
mkdir -p "$RUNBOOK_DIR/runbooks"
cd "$RUNBOOK_DIR"
```

### Baseline Verification

```bash
kubectl get deploy -n "$NS"
kubectl get pods -n "$NS"
kubectl get svc -n "$NS"
```
Expected output should show the same three core services used in the incident simulation lab.

```text
NAME              READY   UP-TO-DATE   AVAILABLE   AGE
checkout-api      3/3     3            3           24m
payment-service   2/2     2            2           24m
db                1/1     1            1           24m
```

## Runbook Anatomy

### Template Structure

Use a consistent order so responders do not hunt for the next step during stress.

| Section | Why it exists |
|---|---|
| Trigger | Tells the reader exactly when the runbook applies. |
| Impact | Forces quick user-centered thinking before technical curiosity takes over. |
| Triage | Provides first five minutes of safe commands. |
| Diagnosis branches | Helps responders decide between likely causes. |
| Mitigation | Lists reversible or bounded actions in priority order. |
| Escalation | Defines when the current responder should ask for help. |
| Verification | Confirms that the chosen action actually worked. |
| References | Links dashboards, owners, and prior incidents. |

### Create the Base Template

```bash
cat <<'EOF' > "$RUNBOOK_DIR/runbooks/_template.md"
# Runbook: <service> — <alert>

## Trigger
- Alert name:
- Severity:
- Applies when:

## Impact
- User symptoms:
- Estimated blast radius:
- SLO or business signal:

## Initial Triage
1. Confirm alert freshness.
2. Check recent deploys.
3. Check pod health, logs, and dependency status.

## Diagnosis Branches
### Branch A
### Branch B
### Branch C

## Mitigation
- First safe action:
- Second safe action:
- Rollback plan:

## Escalation
- Escalate after:
- Escalate to:
- Incident commander notes:

## Verification
- Metric recovered:
- Alert resolved:
- Customer impact ended:

## References
- Dashboards:
- Service owner:
- Related incidents:
EOF
```

### Verify the Template

```bash
sed -n '1,80p' "$RUNBOOK_DIR/runbooks/_template.md"
```

## Scenario 1 — High Error Rate Runbook

### Scenario Context

The `checkout-api` alert fires when 5xx responses exceed 5% for five minutes. Common causes include a bad deployment, a failing dependency, or thread-pool exhaustion during burst traffic.

### Create the Runbook

```bash
cat <<'EOF' > "$RUNBOOK_DIR/runbooks/checkout-api-high-error-rate.md"
# Runbook: checkout-api — High Error Rate

## Trigger
- Alert name: CheckoutApiHighErrorRate
- Severity: SEV2 by default, SEV1 if >25% of requests fail or cart data is at risk
- Applies when: `sum(rate(http_requests_total{job="checkout-api",status=~"5.."}[5m])) / sum(rate(http_requests_total{job="checkout-api"}[5m])) > 0.05`

## Impact
- User symptoms: checkout requests fail with 500 or timeout pages
- Estimated blast radius: partial to total revenue path failure
- SLO or business signal: checkout availability SLO burn and conversion drop

## Initial Triage
1. Confirm alert state in Prometheus or Alertmanager.
2. Check `kubectl rollout history deployment/checkout-api -n incident-lab` for recent changes.
3. Inspect pods, events, and logs.
4. Validate connectivity to `payment-service`.

## Diagnosis Branches
### Branch A — Recent deploy caused regression
- Evidence: error rate rises within five minutes of rollout; logs show startup or handler exceptions.
- Action: rollback deployment.

### Branch B — Dependency failure
- Evidence: checkout logs show connection errors to `payment-service`; dependency pods are unhealthy.
- Action: fail open if safe, or restore dependency before changing checkout.

### Branch C — Resource saturation
- Evidence: CPU throttling, queue growth, or thread pool exhaustion under load.
- Action: scale out, then evaluate whether the saturation is traffic-driven or a code regression.

## Mitigation
- First safe action: rollback the latest checkout deployment if the timeline matches.
- Second safe action: scale checkout replicas from 3 to 5 to reduce queue depth.
- Rollback plan: `kubectl rollout undo deployment/checkout-api -n incident-lab`

## Escalation
- Escalate after: 15 minutes without a stable downward trend in errors
- Escalate to: application owner, database on-call if dependency evidence appears, incident commander if not already assigned
- Incident commander notes: assign one owner to mitigation and a second to evidence capture

## Verification
- Metric recovered: 5xx ratio below 1% for 10 consecutive minutes
- Alert resolved: Alertmanager no longer shows CheckoutApiHighErrorRate as firing
- Customer impact ended: successful synthetic checkout and no fresh support tickets

## References
- Dashboards: checkout overview, ingress errors, dependency map
- Service owner: Commerce API team
- Related incidents: INC-2025-0412, INC-2025-0526
EOF
```

### Test the Runbook by Triggering High Errors

```bash
kubectl set image deployment/checkout-api   checkout-api=ghcr.io/examplecorp/sre-labs/checkout-api:broken-startup   -n "$NS"
kubectl get pods -n "$NS" -l app=checkout-api
kubectl logs deployment/checkout-api -n "$NS" --previous --tail=30
```

### Verification Steps for the Runbook

```bash
rg -n 'Trigger|Diagnosis Branches|Verification' "$RUNBOOK_DIR/runbooks/checkout-api-high-error-rate.md"
kubectl rollout undo deployment/checkout-api -n "$NS"
kubectl rollout status deployment/checkout-api -n "$NS"
```
Expected output should confirm the runbook contains the required sections and that the service recovers after rollback.

```text
3:## Trigger
17:## Diagnosis Branches
36:## Verification
deployment "checkout-api" successfully rolled out
```

### Advanced Variation

- Rewrite the mitigation section assuming checkout cannot be rolled back because a database schema migration already ran.
- Add a feature-flag disable step ahead of rollback and explain when it is safer.
- Ask a peer to execute the runbook literally and note any ambiguity they hit.

## Scenario 2 — OOM Runbook

### Scenario Context

The `payment-service` container sometimes restarts with exit code 137 during spikes or after memory-heavy code paths are introduced. Responders need to distinguish between a true memory leak, too-low limits, and a burst of legitimate load.

### Create the Runbook

```bash
cat <<'EOF' > "$RUNBOOK_DIR/runbooks/payment-service-oom.md"
# Runbook: payment-service — OOM

## Trigger
- Alert name: PaymentServiceOOMKilled
- Severity: SEV2 if all replicas restart repeatedly, SEV3 if one pod restarts but service remains healthy
- Applies when: `increase(kube_pod_container_status_restarts_total{namespace="incident-lab",container="payment-service"}[10m]) > 2`

## Impact
- User symptoms: checkout attempts slow down or fail because payment authorization becomes unavailable
- Estimated blast radius: medium to high depending on replica count
- SLO or business signal: transaction completion rate drops and p95 latency climbs

## Initial Triage
1. Confirm OOMKilled in `kubectl describe pod`.
2. Compare current usage and configured limits.
3. Check whether a deploy or config change happened in the last 30 minutes.
4. Verify whether traffic volume also increased.

## Diagnosis Branches
### Branch A — Memory limit too low
- Evidence: usage plateaus just above the configured limit and restarts stop after raising it.

### Branch B — Real leak or runaway allocation
- Evidence: usage rises steadily over pod lifetime and does not stabilize after scale-out.

### Branch C — Traffic-driven burst
- Evidence: request rate, queue depth, and memory grow together; restarts reduce after scale-out.

## Mitigation
- First safe action: scale from 2 to 3 replicas.
- Second safe action: restore prior known-good memory limits.
- Rollback plan: revert the latest deployment or config patch if a recent change introduced the issue.

## Escalation
- Escalate after: any customer-visible impact persists beyond 10 minutes
- Escalate to: commerce backend owner and platform team if node pressure contributes
- Incident commander notes: avoid increasing memory without documenting the current peak first

## Verification
- Metric recovered: no new restarts for 15 minutes and memory stays below 80% of limit
- Alert resolved: PaymentServiceOOMKilled clears in Alertmanager
- Customer impact ended: checkout success rate returns to baseline

## References
- Dashboards: container memory, pod restarts, transaction rate
- Service owner: Commerce Payments team
- Related incidents: INC-2025-0304
EOF
```

### Trigger the Condition

```bash
kubectl patch deployment payment-service -n "$NS" --type='json' -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"96Mi"},
  {"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"CHAOS_ALLOCATE_MB","value":"180"}}
]'
kubectl rollout status deployment/payment-service -n "$NS"
kubectl describe pod -n "$NS" $(kubectl get pod -n "$NS" -l app=payment-service -o jsonpath='{.items[0].metadata.name}') | sed -n '/Last State/,+12p'
```

### Verify the Runbook Handles Branching

```bash
rg -n 'Branch A|Branch B|Branch C|Escalate after' "$RUNBOOK_DIR/runbooks/payment-service-oom.md"
kubectl set resources deployment/payment-service -n "$NS"   --limits=cpu=500m,memory=256Mi   --requests=cpu=100m,memory=128Mi
kubectl rollout status deployment/payment-service -n "$NS"
```

### Expected Output Example

```text
16:### Branch A — Memory limit too low
19:### Branch B — Real leak or runaway allocation
22:### Branch C — Traffic-driven burst
31:- Escalate after: any customer-visible impact persists beyond 10 minutes
```

### Advanced Variation

- Add a decision note for when it is acceptable to raise limits temporarily even if the root cause is still unknown.
- Include one command for checking node-level memory pressure so responders do not blame the app too quickly.
- Add a do-not-do-this note describing why deleting pods blindly can increase customer impact.

## Scenario 3 — Slow Database Queries Runbook

### Scenario Context

Slow queries do not always generate 5xx errors first. Often the first visible symptom is rising latency, request queueing, or thread exhaustion in an upstream service.

### Create the Runbook

```bash
cat <<'EOF' > "$RUNBOOK_DIR/runbooks/db-slow-queries.md"
# Runbook: db — Slow Queries

## Trigger
- Alert name: DatabaseSlowQueries
- Severity: SEV2 if checkout latency breaches SLO and query backlog grows; SEV3 for isolated warning spikes
- Applies when: query duration p95 exceeds 250ms for 10 minutes or checkout dependency latency rises above 500ms

## Impact
- User symptoms: slow cart loads, delayed payment authorization, or intermittent checkout timeouts
- Estimated blast radius: any service using the shared checkout database
- SLO or business signal: latency SLO burn and queue depth increase

## Initial Triage
1. Confirm the alert on the database dashboard.
2. Check active queries and lock waits.
3. Check whether a deploy or migration changed query patterns.
4. Confirm whether database CPU, IOPS, or connection saturation aligns with the alert window.

## Diagnosis Branches
### Branch A — Missing or unused index
- Evidence: one query shape dominates top SQL duration and explain plan shows sequential scan.

### Branch B — Lock contention
- Evidence: many blocked sessions and rising transaction age.

### Branch C — Saturated infrastructure
- Evidence: storage or CPU is pinned even though query mix is unchanged.

## Mitigation
- First safe action: stop the offending batch job or feature flag that generates the heavy query.
- Second safe action: scale read replicas or application replicas only if that reduces queue pressure without increasing DB churn.
- Rollback plan: revert the deployment, migration, or feature that introduced the expensive query.

## Escalation
- Escalate after: 15 minutes if query latency remains above threshold after obvious rollout rollback
- Escalate to: database on-call, application owner, and incident commander
- Incident commander notes: treat schema and data fixes as high-risk changes during the live incident

## Verification
- Metric recovered: query p95 < 100ms for 15 minutes and checkout latency follows
- Alert resolved: DatabaseSlowQueries clears in Alertmanager
- Customer impact ended: successful checkout synthetic path and normal API latency

## References
- Dashboards: postgres overview, top queries, checkout dependency latency
- Service owner: Data Platform
- Related incidents: INC-2025-0221, INC-2025-0408
EOF
```

### Trigger the Condition

```bash
kubectl exec -n "$NS" deploy/db -- sh -c 'psql -U checkout -d checkout -c "select now();"'
kubectl set env deployment/payment-service -n "$NS" CHAOS_SLOW_QUERY_MS=750
kubectl rollout status deployment/payment-service -n "$NS"
kubectl logs deployment/payment-service -n "$NS" --tail=40 | grep -i 'query'
```

### Verify the Runbook

```bash
rg -n 'Slow Queries|Branch A|Branch B|Branch C|Verification' "$RUNBOOK_DIR/runbooks/db-slow-queries.md"
kubectl set env deployment/payment-service -n "$NS" CHAOS_SLOW_QUERY_MS-
kubectl rollout status deployment/payment-service -n "$NS"
```

### Expected Output Example

```text
1:# Runbook: db — Slow Queries
17:### Branch A — Missing or unused index
20:### Branch B — Lock contention
23:### Branch C — Saturated infrastructure
34:## Verification
```

### Advanced Variation

- Add a branch for connection pool exhaustion and explain how it differs from a truly slow query pattern.
- Write one safe-to-do action and one unsafe-during-incident action for database responders.
- Include a mini-checklist for capturing SQL evidence needed later in the postmortem.

## Build a Runbook Registry

A registry helps responders find the right document quickly and helps reviewers spot gaps or duplicates.

```bash
cat <<'EOF' > "$RUNBOOK_DIR/runbooks/README.md"
# Runbook Registry

| Service | Alert | Severity | Runbook |
|---|---|---|---|
| checkout-api | CheckoutApiHighErrorRate | SEV2 | checkout-api-high-error-rate.md |
| payment-service | PaymentServiceOOMKilled | SEV2 | payment-service-oom.md |
| db | DatabaseSlowQueries | SEV2 | db-slow-queries.md |
EOF
sed -n '1,40p' "$RUNBOOK_DIR/runbooks/README.md"
```

## Add Runbook Links to Prometheus Alert Annotations

The following `PrometheusRule` manifest shows how to embed `runbookUrl` values so responders can jump straight into the correct document from Alertmanager, Slack notifications, or pager payloads.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: checkout-runbook-alerts
  namespace: incident-lab
spec:
  groups:
  - name: checkout.runbooks
    rules:
    - alert: CheckoutApiHighErrorRate
      expr: sum(rate(http_requests_total{job="checkout-api",status=~"5.."}[5m])) / sum(rate(http_requests_total{job="checkout-api"}[5m])) > 0.05
      for: 5m
      labels:
        severity: critical
        team: commerce-api
      annotations:
        summary: checkout-api error rate is above 5%
        description: checkout-api is serving elevated 5xx responses in incident-lab.
        runbookUrl: https://wiki.example.internal/runbooks/checkout-api-high-error-rate
    - alert: PaymentServiceOOMKilled
      expr: increase(kube_pod_container_status_restarts_total{namespace="incident-lab",container="payment-service"}[10m]) > 2
      for: 0m
      labels:
        severity: warning
        team: commerce-payments
      annotations:
        summary: payment-service restarted repeatedly with exit code 137
        description: payment-service may be memory constrained or leaking under load.
        runbookUrl: https://wiki.example.internal/runbooks/payment-service-oom
    - alert: DatabaseSlowQueries
      expr: histogram_quantile(0.95,sum(rate(db_query_duration_seconds_bucket{service="payment-service"}[5m])) by (le)) > 0.25
      for: 10m
      labels:
        severity: warning
        team: data-platform
      annotations:
        summary: database query p95 exceeds 250ms
        description: checkout dependency queries are slower than expected.
        runbookUrl: https://wiki.example.internal/runbooks/db-slow-queries
```

### Apply and Validate the Rules

```bash
cat <<'EOF' > "$RUNBOOK_DIR/checkout-runbook-alerts.yaml"
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: checkout-runbook-alerts
  namespace: incident-lab
spec:
  groups:
  - name: checkout.runbooks
    rules:
    - alert: CheckoutApiHighErrorRate
      expr: sum(rate(http_requests_total{job="checkout-api",status=~"5.."}[5m])) / sum(rate(http_requests_total{job="checkout-api"}[5m])) > 0.05
      for: 5m
      labels:
        severity: critical
        team: commerce-api
      annotations:
        summary: checkout-api error rate is above 5%
        description: checkout-api is serving elevated 5xx responses in incident-lab.
        runbookUrl: https://wiki.example.internal/runbooks/checkout-api-high-error-rate
    - alert: PaymentServiceOOMKilled
      expr: increase(kube_pod_container_status_restarts_total{namespace="incident-lab",container="payment-service"}[10m]) > 2
      for: 0m
      labels:
        severity: warning
        team: commerce-payments
      annotations:
        summary: payment-service restarted repeatedly with exit code 137
        description: payment-service may be memory constrained or leaking under load.
        runbookUrl: https://wiki.example.internal/runbooks/payment-service-oom
    - alert: DatabaseSlowQueries
      expr: histogram_quantile(0.95,sum(rate(db_query_duration_seconds_bucket{service="payment-service"}[5m])) by (le)) > 0.25
      for: 10m
      labels:
        severity: warning
        team: data-platform
      annotations:
        summary: database query p95 exceeds 250ms
        description: checkout dependency queries are slower than expected.
        runbookUrl: https://wiki.example.internal/runbooks/db-slow-queries
EOF
kubectl apply -f "$RUNBOOK_DIR/checkout-runbook-alerts.yaml"
kubectl get prometheusrule -n "$NS" checkout-runbook-alerts -o yaml | grep -n 'runbookUrl'
```

### Expected Output Example

```text
18:        runbookUrl: https://wiki.example.internal/runbooks/checkout-api-high-error-rate
27:        runbookUrl: https://wiki.example.internal/runbooks/payment-service-oom
36:        runbookUrl: https://wiki.example.internal/runbooks/db-slow-queries
```

## Runbook Quality Checklist

Score each runbook from 0 to 2 for the criteria below. A production-ready runbook should score at least 12/16.

| Criterion | 0 | 1 | 2 |
|---|---|---|---|
| Trigger clarity | Alert vague or missing | Alert named but threshold unclear | Alert name, threshold, and scope clear |
| Safety | No rollback or risk note | Some mitigations listed | Safe order, rollback plan, and risky actions called out |
| Verification | No confirmation steps | Generic check dashboard note | Explicit metrics, commands, and exit criteria |
| Escalation | No owners listed | Owners listed but timing vague | Owners and escalation timing explicit |
| Branching | Single path only | Some conditional logic | Clear branches for likely causes |
| Business impact | System-only framing | Limited impact note | User symptoms and business signal clear |
| Evidence capture | No timeline notes | Some commands included | Commands plus evidence to save for postmortem |
| Maintenance | No owner or review date | Partial metadata | Owner, review date, and registry entry present |

### Quick Self-Review Commands

```bash
for file in "$RUNBOOK_DIR"/runbooks/*.md; do
  echo "=== $file ==="
  rg -n 'Trigger|Impact|Initial Triage|Diagnosis Branches|Mitigation|Escalation|Verification|References' "$file"
done
```

## Bonus Challenges

- Add a runbook for a noisy alert that should probably be deleted instead of documented.
- Convert one runbook step into a shell script and note where automation is safe and where human judgment is still required.
- Review whether your alert descriptions contain enough context to help a responder choose the right runbook without opening multiple documents.

## Teardown

```bash
kubectl delete prometheusrule checkout-runbook-alerts -n "$NS" --ignore-not-found
rm -rf "$RUNBOOK_DIR"
unset RUNBOOK_DIR NS
```

## Key Takeaways

- Good runbooks reduce decision latency by making the first five minutes obvious.
- The best runbook is not the longest one; it is the clearest one with safe branching and verification.
- If an alert has no runbook and no obvious owner, the monitoring is incomplete even if the expression is technically correct.
- Linking runbook URLs into alert annotations shortens the gap between detection and useful action.
- Quality review matters: stale or vague runbooks create false confidence during real incidents.
