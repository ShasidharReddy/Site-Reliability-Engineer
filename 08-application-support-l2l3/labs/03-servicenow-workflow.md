# Lab 03: ServiceNow Workflow
## Lab goals
This lab covers the operational workflow around:
- incident ticket lifecycle.
- priority setting and SLA management.
- problem record creation from repeat incidents.
- change request creation for fix deployment.
- communication templates for each priority level.

## Scenario context

`payment-api` is producing intermittent 503 errors during checkout.
You are the resolver group receiving the incident in ServiceNow.
Your job is not only technical response.
Your job is also correct record handling, communication, and follow-through.

---

## 1. Incident ticket lifecycle

### Lifecycle states

A practical lifecycle is:
1. New
2. Assigned
3. In Progress
4. On Hold
5. Resolved
6. Closed

### What each state means

| State | Meaning | Required action |
|---|---|---|
| New | ticket created but not yet owned | validate routing and priority |
| Assigned | ticket routed to resolver group | accept ownership quickly |
| In Progress | investigation or mitigation underway | keep work notes current |
| On Hold | waiting on customer, vendor, or planned window | document exact reason and owner |
| Resolved | service restored and fix documented | add resolution notes and verification |
| Closed | requester confirmed or policy timer elapsed | ensure links to problem/change are complete |

### Incident intake checklist

At assignment time verify:
- caller or monitoring source.
- affected business service.
- environment.
- start time.
- impact statement.
- workaround availability.
- related alerts or incidents.

### Example incident creation

```text
Short description: [payment-api] Intermittent 503 during checkout in production
Category: Application
Subcategory: API
Business service: Payment Platform
Configuration item: payment-api-prod
Environment: Production
Assignment group: Application Support L2
Contact type: Monitoring
```

### Example long description

```text
Monitoring and customer reports indicate intermittent 503 errors from payment-api.
Affected workflow: checkout payment submission.
Start time: 14:05 UTC.
Observed scope: approximately 20% of requests.
Workaround: retry sometimes succeeds.
Recent changes: payment-api deployment revision 44 at 13:58 UTC.
```

### Ownership rules

- the assignee owns next action, not just the ticket.
- if reassigned, confirm accepting team in chat or call.
- if multiple teams are involved, keep a single owner for coordination.
- during major incident, incident commander owns coordination while resolver teams own technical tasks.

### Work note standard

Each note should answer:
- what was observed?
- what was done?
- what was the result?
- what is next?
- when is the next update due?

### Sample work note sequence

```text
[14:12 UTC] Incident accepted by App Support L2. Initial priority set to P2 pending impact validation.
[14:16 UTC] Confirmed 503 responses from payment-api through synthetic check. Checkout impact confirmed.
[14:21 UTC] Reviewed rollout history. New revision 44 started at 13:58 UTC.
[14:24 UTC] New pods show DB TLS handshake failures. Old pods healthy.
[14:28 UTC] Proposed rollback under incident change path. Awaiting approval from incident commander.
[14:34 UTC] Rollback initiated.
[14:40 UTC] Error rate falling. Monitoring for 10-minute stability.
```

### Resolution notes standard

Resolution notes should include:
- confirmed root cause.
- exact fix or mitigation.
- validation method.
- preventive follow-up.
- whether a problem record was created.

### Example resolution note

```text
Root cause: deployment revision 44 lacked the updated DB trust bundle required after certificate rotation.
Mitigation: rolled back payment-api to revision 43.
Validation: checkout success rate returned to baseline and health checks passed for 15 minutes.
Prevention: add truststore verification to build pipeline and create problem record PRB001245.
```

---

## 2. Priority setting and SLA management

### Priority matrix

Use impact multiplied by urgency.

| Impact \ Urgency | High urgency | Medium urgency | Low urgency |
|---|---|---|---|
| High impact | P1 | P2 | P3 |
| Medium impact | P2 | P3 | P4 |
| Low impact | P3 | P4 | P4 |

### How to determine impact

High impact examples:
- checkout unavailable for many customers.
- authentication broadly failing.
- revenue or compliance event at risk.

Medium impact examples:
- one region affected.
- one important feature degraded.
- workaround exists but is painful.

Low impact examples:
- one user or a small group affected.
- issue is informational or cosmetic.
- no business-critical transaction affected.

### How to determine urgency

High urgency:
- active production outage.
- major business event underway.
- rapid impact expansion.

Medium urgency:
- production issue with workaround.
- business function degraded but not stopped.

Low urgency:
- can be planned.
- no immediate customer harm.

### Example priority decisions

| Situation | Impact | Urgency | Priority | Reason |
|---|---|---|---|---|
| checkout down for all users | high | high | P1 | critical revenue path unavailable |
| login slow only in one region | medium | medium | P3 | degraded but usable |
| nightly report failed with manual rerun available | medium | low | P4 | workaround exists |
| one executive user blocked from app access | low | high | P3 | high urgency but limited blast radius |

### SLA example table

| Priority | Acknowledge target | Work start target | Update interval | Target restore or workaround |
|---|---:|---:|---:|---:|
| P1 | 15 min | immediate | 15-30 min | 4 hours or fastest mitigation |
| P2 | 30 min | 30 min | 30-60 min | same business day |
| P3 | 4 hours | same business day | daily | 3 business days |
| P4 | 1 business day | scheduled | as agreed | 5-10 business days |

### SLA management workflow

1. validate priority immediately.
2. start the clock-aware response.
3. update before warning thresholds.
4. escalate before breach if blocked.
5. reclassify if impact changes.
6. capture actual restoration time.

### SLA breach prevention examples

- create a calendar reminder for next update.
- assign backup owner during shift change.
- use `On Hold` only with valid reason.
- notify manager when a P1 has no technical owner.
- escalate if a vendor dependency is delaying resolution.

### Example ServiceNow fields to watch

- Priority
- State
- Assignment group
- Assigned to
- SLA due
- Breach status
- Major incident flag
- Related records

---

## 3. Major incident handling inside ServiceNow

### When to mark a major incident

Mark as major incident when:
- there is broad production impact.
- executive or customer visibility is high.
- multiple resolver groups are engaged.
- the standard queue workflow is too slow.

### Major incident actions

- create or join incident bridge.
- link child incidents.
- assign incident commander.
- assign communications lead.
- update status page if required.
- increase update frequency.

### Example major incident timeline entries

```text
[14:10 UTC] Major incident process activated. Incident bridge opened.
[14:12 UTC] Incident commander assigned.
[14:13 UTC] Communications lead assigned.
[14:16 UTC] Child incidents linked from EU customer reports.
[14:20 UTC] Payment team, DB team, and SRE engaged.
```

### Bridge discipline notes

ServiceNow notes should mirror the bridge timeline.
Do not rely only on chat history.
Use UTC timestamps consistently.
Link conference, war room, or status page references if policy allows.

---

## 4. Problem record creation from repeat incidents

### When to create a problem record

Create a problem when:
- the same incident pattern repeats.
- the root cause is known but not permanently fixed.
- a workaround exists but is operationally expensive.
- several incidents point to one underlying issue.

### Example repeat pattern

Three incidents in one month:
- payment-api fails after certificate rotation.
- same truststore packaging gap each time.
- rollback works, but prevention is missing.

### Problem record fields

```text
Problem title: Repeat payment-api incidents after DB certificate rotation
Business service: Payment Platform
Known error: New deployment package may omit current DB trust bundle
Workaround: Roll back to previous image and retain last trusted bundle
Root cause summary: Build pipeline does not validate production truststore contents
```

### Problem analysis structure

- affected incidents.
- frequency and trend.
- root cause.
- contributing factors.
- known workaround.
- permanent corrective actions.
- target completion date.

### Example corrective actions

| Action | Owner | Due date | Success measure |
|---|---|---|---|
| add truststore validation test to CI | platform engineering | 2025-08-20 | build fails on missing CA |
| alert on DB cert expiry 30 days ahead | DBA team | 2025-08-15 | alert visible in monitoring |
| update release checklist | app support lead | 2025-08-12 | checklist linked in change template |

### Known error article contents

A good known error article should provide:
- symptom keywords.
- scope indicators.
- quick validation steps.
- approved workaround.
- escalation criteria.

---

## 5. Change request for fix deployment

### Why a change record matters

Incidents restore service.
Changes make the restoration auditable and safer.
If you deploy a fix, revert a config, or restart under controlled policy, record the change path used.

### Change type selection

| Change type | Use when | Example |
|---|---|---|
| Standard | pre-approved repeat step | restart one stateless pod under runbook |
| Normal | planned fix with review | deploy truststore packaging fix |
| Emergency | urgent service restoration | rollback payment-api during active outage |

### Example emergency change for rollback

```text
Change type: Emergency
Reason: Restore payment processing during active production incident INC0012456
Implementation plan:
1. Pause current rollout
2. Roll back deployment to revision 43
3. Confirm healthy endpoints
4. Monitor error rate for 15 minutes
Backout plan: Reapply revision 44 only after corrected trust bundle is validated in non-prod
Risk: Low to medium; reverting to last known good release
Validation: checkout synthetic test and application health checks
```

### Example normal change for permanent fix

```text
Change type: Normal
Summary: Deploy payment-api revision 45 with updated trust bundle and CI validation gate
Risk: Medium
Test evidence: staging rollout passed, DB TLS handshake verified, synthetic checkout passed
Implementation window: 22:00-22:30 UTC
Validation steps:
- health endpoints green
- DB TLS handshake succeeds from pod
- checkout flow succeeds end to end
- no abnormal 5xx in first 15 minutes
Backout: roll back to revision 43 if error rate exceeds threshold
```

### CAB review checklist

For normal change requiring CAB, prepare:
- business justification.
- test evidence.
- implementation plan.
- validation plan.
- rollback plan.
- customer communication plan.
- dependency approvals.

### Example validation commands for change record

```bash
kubectl rollout status deployment/payment-api -n prod-payments
kubectl get endpoints payment-api -n prod-payments
kubectl exec -n prod-payments deploy/payment-api -- \
  curl -s http://localhost:8080/actuator/health/readiness
curl -sk -o /dev/null -w '%{http_code} %{time_total}\n' https://checkout.example.com/api/payments/health
```

---

## 6. Communication templates for each priority level

### P1 communication template

```text
Subject: P1 - Payment checkout outage in production
Status: Investigating
Impact: Customers may be unable to complete checkout in production.
Start time: 14:05 UTC.
Current findings: intermittent 503 from payment-api following deployment revision 44.
Actions underway: rollback evaluation and dependency validation.
Next update: 14:30 UTC or sooner if status changes.
```

### P2 communication template

```text
Subject: P2 - Elevated payment-api errors in production
Status: Mitigating
Impact: Some checkout attempts are failing; retry may succeed.
Current findings: issue isolated to pods on latest deployment revision.
Actions underway: rollback in progress.
Next update: within 60 minutes.
```

### P3 communication template

```text
Subject: P3 - Degraded login latency in one region
Status: Investigating
Impact: Users in EU region may experience slower logins.
Workaround: retry generally succeeds.
Actions underway: latency analysis and downstream dependency checks.
Next update: end of day or sooner if priority changes.
```

### P4 communication template

```text
Subject: P4 - Reporting job delay under investigation
Status: Open
Impact: No production outage; report delivery may be delayed.
Workaround: manual report available if needed.
Planned action: investigate during next support window.
Next update: by next business day.
```

### Resolver-to-L3 escalation template

```text
Escalation target: SRE / Application Engineering
Incident: INC0012456
Priority: P1
Symptom: payment-api returns intermittent 503 from checkout path
Impact: ~20% of checkout requests failing in production
Start time: 14:05 UTC
What changed: deployment revision 44 at 13:58 UTC
Findings: new pods fail DB TLS handshake; old pods healthy
Actions taken: rollout paused, rollback prepared
Requested help: confirm root cause and approve permanent fix path
```

### Customer update closure template

```text
The checkout issue affecting some production users has been mitigated.
Service has been stable since 14:40 UTC.
Cause: issue introduced by a recent deployment; full preventive fix is being tracked.
If you continue to see errors, please retry and contact support with timestamp and order ID.
```

---

## 7. End-to-end exercise

Use the scenario context and complete the following.

### Exercise step 1

Create the incident with:
- correct business service.
- clear short description.
- accurate initial priority.
- start time and impact.

### Exercise step 2

Add at least four work notes covering:
- symptom confirmation.
- recent change correlation.
- technical finding.
- mitigation action.

### Exercise step 3

Decide whether a major incident flag is required.
Justify the choice.

### Exercise step 4

Create a problem record if the issue is a repeat pattern.
List at least three permanent corrective actions.

### Exercise step 5

Create the matching emergency or normal change record.
Include validation and rollback steps.

---

## 8. Verification checklist

- [ ] incident states were used correctly.
- [ ] priority matched impact and urgency.
- [ ] SLA clocks and update intervals were considered.
- [ ] work notes show a clear timeline.
- [ ] problem record captures repeat-pattern analysis.
- [ ] change record includes implementation, validation, and rollback.
- [ ] communication template fits the incident priority.
- [ ] closure notes explain both mitigation and prevention.
