# Incident Management — Scenarios

## How to Use These Scenarios

Each scenario below is designed for tabletop drills, solo practice, or role-play interviews. Read the background, scan the symptoms, and then force yourself to answer three questions before you touch a keyboard: what is the user impact, who owns the next action, and what single fact would most change your response plan?

| Drill mode | How to use the scenarios |
|---|---|
| Solo | Read one section at a time and write your first three actions before continuing. |
| Pair | One person plays IC, the other TL; switch roles after mitigation. |
| Team | Add a communications lead and require live status updates every 10 to 15 minutes. |

```text
detect -> assess impact -> assign roles -> collect evidence -> mitigate -> verify -> communicate -> postmortem
```

## Scenario 1: Cascading Failure from Bad Deployment

### Background

A new checkout release modifies retry behavior and timeout defaults. Within minutes, the payment path saturates and the database begins queueing writes.

### Symptoms and Alerts

- CheckoutApiHighErrorRate fires at 8% and climbs.
- PaymentService429Rate warning appears first.
- DB lock wait time increases while CPU remains moderate.

### Investigation Steps

```bash
kubectl rollout history deployment/checkout-api -n incident-lab
kubectl logs deployment/checkout-api -n incident-lab --since=30m | grep -i 'retry\|timeout' | tail -20
kubectl logs deployment/payment-service -n incident-lab --since=30m | grep -i '429\|lock' | tail -20
```

### Correct Approach

1. Declare SEV2 quickly because the revenue path is degraded.
2. Compare deployment timing to error growth and prepare rollback early.
3. Rollback the new checkout release once evidence shows retry amplification.

### Postmortem Fragment

At 14:20 UTC the team rolled back checkout-api, which reduced 429s on payment-service and allowed DB lock wait time to return to baseline within 11 minutes.

### Lessons Learned

- Keep the first response anchored on user impact for scenario 1: cascading failure from bad deployment.
- Align timeline, metrics, and decisions so the postmortem explains not only what happened but why the response made sense.
- Convert scenario-specific observations into reusable runbook or alert improvements.

### Questions to Discuss

- What would you do first if the deployer insists the release is unrelated?
- How would you communicate a cascading dependency failure to non-technical stakeholders?

## Scenario 2: Database Connection Pool Exhaustion

### Background

Checkout traffic is steady, but payment-service begins timing out because all shared DB connections are in use.

### Symptoms and Alerts

- Latency increases before error rate spikes.
- Payment-service logs show pool exhausted and queue growth.
- Database CPU is only 45%, which makes the issue easy to misread.

### Investigation Steps

```bash
kubectl logs deployment/payment-service -n incident-lab --tail=50 | grep -i 'pool\|timeout'
curl -sG http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=max(db_pool_in_use{service="payment-service"})'
kubectl exec -n incident-lab deploy/db -- sh -c 'psql -U checkout -d checkout -c "select now();"'
```

### Correct Approach

1. Treat this as a dependency-capacity incident, not a CPU incident.
2. Reduce non-critical database consumers and raise customer-critical capacity first.
3. Capture pool, queue, and throughput metrics together for the postmortem.

### Postmortem Fragment

The team paused background reporting jobs, freeing 28 connections and allowing checkout success rate to recover before a deeper pool design change was scheduled.

### Lessons Learned

- Keep the first response anchored on user impact for scenario 2: database connection pool exhaustion.
- Align timeline, metrics, and decisions so the postmortem explains not only what happened but why the response made sense.
- Convert scenario-specific observations into reusable runbook or alert improvements.

### Questions to Discuss

- How do you explain why CPU was not the right leading signal?
- When is increasing the pool size a safe action versus a risky one?

## Scenario 3: Mysterious Traffic Spike (DDoS or viral event?)

### Background

Traffic doubles, then triples, then reaches 6x normal volume. Some requests look normal, some appear bot-like, and the marketing team is unsure whether a campaign drove the increase.

### Symptoms and Alerts

- Ingress request rate surges from multiple networks.
- Frontend autoscaling keeps up, but checkout latency climbs.
- CDN cache hit rate drops because product detail pages are being bypassed.

### Investigation Steps

```bash
curl -sG http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=sum(rate(nginx_ingress_controller_requests[5m]))'
kubectl logs deployment/frontend-web -n incident-lab --tail=50 | grep -i 'user-agent' | tail -20
kubectl top pod -n incident-lab -l app=checkout-api
```

### Correct Approach

1. Start by preserving customer-facing capacity regardless of whether the source is malicious or legitimate.
2. Engage CDN or edge controls while marketing confirms campaign status.
3. Avoid prematurely blocking traffic patterns that could be real customers without evidence.

### Postmortem Fragment

The incident review concluded that mixed traffic sources were involved: a real promotion plus opportunistic bot scraping that amplified origin load.

### Lessons Learned

- Keep the first response anchored on user impact for scenario 3: mysterious traffic spike (ddos or viral event?).
- Align timeline, metrics, and decisions so the postmortem explains not only what happened but why the response made sense.
- Convert scenario-specific observations into reusable runbook or alert improvements.

### Questions to Discuss

- What evidence would help separate DDoS from viral traffic?
- How do you communicate uncertainty without sounding unprepared?

## Scenario 4: SEV1 Alert at 3 AM with No Runbook

### Background

The on-call engineer is paged for a checkout outage outside normal business hours and discovers there is no runbook attached to the alert.

### Symptoms and Alerts

- PagerDuty fires a high-urgency incident.
- Alert annotations include dashboard links but no procedural guidance.
- The first responder is unfamiliar with the service internals.

### Investigation Steps

```bash
curl -s http://127.0.0.1:9093/api/v2/alerts | jq '.[] | select(.labels.alertname=="CheckoutApiHighErrorRate")'
kubectl get pods -n incident-lab
kubectl rollout history deployment/checkout-api -n incident-lab
```

### Correct Approach

1. Assign an IC immediately, even if the same person also starts as TL.
2. Use a generic first-five-minutes checklist: impact, deploys, pods, logs, dependencies.
3. Create an emergency working note that can later become the missing runbook.

### Postmortem Fragment

The postmortem highlighted missing operational documentation as a primary contributing factor and created a P1 action to attach runbooks to all high-urgency alerts.

### Lessons Learned

- Keep the first response anchored on user impact for scenario 4: sev1 alert at 3 am with no runbook.
- Align timeline, metrics, and decisions so the postmortem explains not only what happened but why the response made sense.
- Convert scenario-specific observations into reusable runbook or alert improvements.

### Questions to Discuss

- What is the minimum structure of an emergency ad hoc runbook?
- How do you keep from freezing when documentation is absent?

## Scenario 5: Conflicting Teams During Incident

### Background

The application team believes the database is slow. The database team believes the application deployed a bad query pattern. Customer impact continues while the debate grows louder.

### Symptoms and Alerts

- Different dashboards tell partial stories.
- Each team shares evidence using different time windows.
- No one is synthesizing the combined picture for the IC.

### Investigation Steps

```bash
echo 'Request app team metrics for 19:10-19:30 UTC: error rate, latency, deployment diff.'
echo 'Request DB team metrics for 19:10-19:30 UTC: CPU, lock waits, active sessions.'
```

### Correct Approach

1. Force both teams onto the same timeline and the same incident window.
2. Ask for one fact from each team that most supports or weakens their theory.
3. Escalate cross-team ownership issues early instead of allowing silent stalling.

### Postmortem Fragment

The postmortem noted that cross-team handoffs lacked a shared evidence template, which extended diagnosis by 18 minutes.

### Lessons Learned

- Keep the first response anchored on user impact for scenario 5: conflicting teams during incident.
- Align timeline, metrics, and decisions so the postmortem explains not only what happened but why the response made sense.
- Convert scenario-specific observations into reusable runbook or alert improvements.

### Questions to Discuss

- How do you keep authority balanced without letting the incident become a debate club?
- What would a useful cross-team evidence template include?

## Scenario 6: Partial Outage in One Region

### Background

Users in one cloud region see slow checkouts while other regions remain healthy. Synthetic checks from a different region continue to pass.

### Symptoms and Alerts

- Regional latency alert fires only for us-east1.
- Global dashboards dilute the impact and make the incident look small.
- Support tickets mention geography-specific failures.

### Investigation Steps

```bash
curl -sG http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=sum(rate(http_requests_total{job="checkout-api",region="us-east1",status=~"5.."}[5m]))'
kubectl get pods -n incident-lab -o wide
```

### Correct Approach

1. Do not let healthy regions hide localized user pain.
2. Scope the incident regionally and consider traffic steering if available.
3. Communicate clearly which users are affected and which are not.

### Postmortem Fragment

Traffic was temporarily shifted away from the impaired region while the team restored a failing dependency endpoint local to that region.

### Lessons Learned

- Keep the first response anchored on user impact for scenario 6: partial outage in one region.
- Align timeline, metrics, and decisions so the postmortem explains not only what happened but why the response made sense.
- Convert scenario-specific observations into reusable runbook or alert improvements.

### Questions to Discuss

- Would you call this SEV1 or SEV2 if only one region is affected but it handles 40% of traffic?
- How do you word a status update for partial regional impact?

## Scenario 7: False Positive Alert Flood

### Background

A misconfigured alert rule triggers hundreds of warnings across multiple services, masking one real customer-impacting issue in the noise.

### Symptoms and Alerts

- Alert volume spikes suddenly with low correlation to business metrics.
- Slack channels fill with automated messages.
- Responders start ignoring notifications altogether.

### Investigation Steps

```bash
curl -s http://127.0.0.1:9093/api/v2/alerts | jq 'length'
kubectl get prometheusrule -A | grep -i 'warning\|latency'
```

### Correct Approach

1. Suppress or mute the noisy alert safely while preserving evidence.
2. Protect attention for the likely real incident by creating a clean working channel.
3. Review whether alert inhibition or routing should have prevented the flood.

### Postmortem Fragment

The postmortem separated alert-quality remediation from the actual service incident to ensure both got addressed without conflating them.

### Lessons Learned

- Keep the first response anchored on user impact for scenario 7: false positive alert flood.
- Align timeline, metrics, and decisions so the postmortem explains not only what happened but why the response made sense.
- Convert scenario-specific observations into reusable runbook or alert improvements.

### Questions to Discuss

- When is it safe to silence alerts during an incident?
- How do you avoid teaching people to ignore pages permanently?

## Scenario 8: Data Loss Incident

### Background

A background cleanup job deletes recent order draft records incorrectly. Checkout still works, but some users lose carts or saved progress.

### Symptoms and Alerts

- Error rate is low, but support tickets spike with missing-cart reports.
- Audit logs show a cleanup job deleting more rows than expected.
- The incident may require legal or compliance review depending on retention obligations.

### Investigation Steps

```bash
kubectl logs deployment/order-cleaner -n incident-lab --since=1h | tail -50
kubectl exec -n incident-lab deploy/db -- sh -c 'psql -U checkout -d checkout -c "select count(*) from cart_drafts;"'
```

### Correct Approach

1. Stop the destructive process first, even before full root cause is known.
2. Preserve forensic evidence and confirm backup or recovery options.
3. Escalate to data governance or security if policy requires it.

### Postmortem Fragment

The team disabled the cleanup job, restored affected records from point-in-time recovery, and created a separate customer-remediation workstream.

### Lessons Learned

- Keep the first response anchored on user impact for scenario 8: data loss incident.
- Align timeline, metrics, and decisions so the postmortem explains not only what happened but why the response made sense.
- Convert scenario-specific observations into reusable runbook or alert improvements.

### Questions to Discuss

- How does impact communication change when data integrity is involved?
- What should happen before any data repair script is run?

## Scenario 9: Third-Party Vendor Incident

### Background

A payment gateway vendor begins timing out intermittently. Your services are healthy, but a critical dependency outside your control is not.

### Symptoms and Alerts

- Outbound requests to the vendor exceed timeout thresholds.
- Vendor status page posts are delayed and vague.
- Retry behavior in your application risks amplifying vendor instability.

### Investigation Steps

```bash
kubectl logs deployment/payment-service -n incident-lab --tail=60 | grep -i 'gateway\|timeout'
curl -I https://vendor-status.example.com
```

### Correct Approach

1. Enable protective degradation such as queueing, cached responses, or feature restriction if supported.
2. Contact the vendor through the emergency support path while reducing self-amplifying retries.
3. Keep status updates honest about dependency ownership without sounding helpless.

### Postmortem Fragment

The postmortem focused on how internal retry and timeout behavior shaped customer impact even though the initiating fault was external.

### Lessons Learned

- Keep the first response anchored on user impact for scenario 9: third-party vendor incident.
- Align timeline, metrics, and decisions so the postmortem explains not only what happened but why the response made sense.
- Convert scenario-specific observations into reusable runbook or alert improvements.

### Questions to Discuss

- What is your responsibility when the root cause is outside your company?
- How would you decide whether to fail closed or fail open?

## Scenario 10: Incident During Planned Maintenance

### Background

A storage maintenance window is in progress when an unrelated checkout latency alert fires. Responders initially assume it is expected noise from the maintenance.

### Symptoms and Alerts

- The maintenance calendar overlaps with the incident start time.
- Some symptoms look similar to the planned work but extend beyond the declared scope.
- Confirmation bias delays escalation.

### Investigation Steps

```bash
echo 'Check maintenance scope, start time, expected symptoms, and rollback plan.'
kubectl get events -n incident-lab --sort-by='.lastTimestamp' | tail -30
kubectl rollout history deployment/checkout-api -n incident-lab
```

### Correct Approach

1. Treat overlapping maintenance as a clue, not proof.
2. Verify whether the current symptoms match the approved maintenance risk statement.
3. Escalate if customer impact exceeds planned expectations or persists after the maintenance action completes.

### Postmortem Fragment

Reviewers concluded that maintenance context biased triage and delayed the team from noticing an unrelated checkout configuration regression.

### Lessons Learned

- Keep the first response anchored on user impact for scenario 10: incident during planned maintenance.
- Align timeline, metrics, and decisions so the postmortem explains not only what happened but why the response made sense.
- Convert scenario-specific observations into reusable runbook or alert improvements.

### Questions to Discuss

- How do you challenge the assumption that maintenance explains everything?
- What should every maintenance plan include to help incident responders later?
