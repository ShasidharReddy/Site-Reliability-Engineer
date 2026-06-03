# Incident Management — Troubleshooting

## How to Use This Guide

Use this document when the incident process itself starts failing: pages do not route, the war room falls apart, ownership is unclear, or the postmortem stalls. The patterns below focus on operational friction, not only technical root causes.

```text
alert problem -> verify scope -> stabilize the response process -> continue technical diagnosis -> capture evidence -> recover -> learn
```

| Quick principle | Why it matters |
|---|---|
| Stabilize coordination first | A chaotic team usually makes the outage longer. |
| Prefer reversible actions | Process failures often hide technical uncertainty. |
| Record facts in real time | Memory becomes unreliable after the first 20 minutes. |
| Escalate deliberately | Silent waiting is usually worse than asking for help early. |

## Common Incident Response Problems

### On-call engineer does not acknowledge in time

**Symptoms**

- PagerDuty alert remains unacknowledged beyond the response target.
- No message appears in the incident channel and no one has taken IC ownership.
- Customer impact may already be increasing while ownership is ambiguous.

**Immediate steps**

1. Check whether the alert actually triggered an incident in PagerDuty.
2. Follow the documented escalation policy instead of waiting for a late response.
3. Assign a temporary IC from available responders while escalation continues.

**Diagnosis commands**

```bash
export INCIDENT_ID='replace-me'
curl -s -H "Authorization: Token token=$PD_API_TOKEN"   "https://api.pagerduty.com/incidents/$INCIDENT_ID/log_entries" | jq '.log_entries[] | {created_at,summary}'
```

**Verification**: You should see escalation actions, notification attempts, and eventually an acknowledge event from a responder or escalation target.

**Facilitation note**: If no one responds after the final escalation target, follow the duty-manager or engineering-manager backup path and document the response gap for review.

### Runbook is outdated or wrong

**Symptoms**

- Commands reference deprecated deployments, dashboards, or ticket systems.
- The documented mitigation does not match the current architecture.
- Responders lose trust and start improvising without a shared plan.

**Immediate steps**

1. Declare that the runbook is unreliable and switch to an emergency bypass procedure.
2. Capture exactly which step failed so the document can be fixed later.
3. Nominate one person to keep working notes while another continues technical diagnosis.

**Diagnosis commands**

```bash
kubectl get deploy,svc,ing -n incident-lab
rg -n 'rollout undo|grafana|ServiceNow' 04-incident-management/templates 04-incident-management/labs
```

**Verification**: You should be able to produce an ad hoc working note with corrected commands and share it in the incident channel within a few minutes.

**Facilitation note**: Never silently keep following a wrong runbook. Mark the bad section explicitly so others do not repeat the mistake during the same incident.

### IC and TL are both the same person

**Symptoms**

- One responder is trying to debug, coordinate, and communicate simultaneously.
- Status updates slip because deep technical work consumes all attention.
- Decision quality drops because the responder is context-switching constantly.

**Immediate steps**

1. Switch to solo-incident mode and reduce optional tasks.
2. Use a timer for updates every 15 minutes even if the update is still investigating.
3. Prefer low-risk mitigations over complex diagnostics until backup arrives.

**Diagnosis commands**

```bash
while true; do
  date -u '+%H:%M UTC incident update timer'
  sleep 900
done
```

**Verification**: Even if you are alone, there should be a written update cadence and a visible list of next steps rather than only terminal activity.

**Facilitation note**: Document solo mode in the postmortem because staffing assumptions are part of incident readiness.

### PagerDuty alerts firing but no one gets paged

**Symptoms**

- Prometheus or Alertmanager shows firing alerts but PagerDuty incident count stays zero.
- Slack notifications might still work, creating false confidence.
- The failure may be in routing, deduplication, or integration credentials.

**Immediate steps**

1. Check Alertmanager receivers and recent notification failures.
2. Verify the PagerDuty routing key and integration type.
3. Send a controlled test event before changing production routing.

**Diagnosis commands**

```bash
kubectl logs -n monitoring deploy/alertmanager --since=30m | grep -i 'pagerduty\|notify'
curl -s http://127.0.0.1:9093/api/v2/status | jq
curl -X POST https://events.pagerduty.com/v2/enqueue   -H 'Content-Type: application/json'   -d '{"routing_key":"'"$PD_ROUTING_KEY"'","event_action":"trigger","payload":{"summary":"training notification test","source":"incident-lab","severity":"warning"}}'
```

**Verification**: A good test creates exactly one new PagerDuty event and a visible Alertmanager receiver log entry.

**Facilitation note**: If the integration is broken and customer impact is active, switch to backup paging or phone escalation immediately instead of waiting for tooling repair.

### StatusPage update is wrong or late

**Symptoms**

- Customers are reporting impact, but the status page still says operational.
- An update overstates resolution before metrics recover.
- Support teams are now giving inconsistent messages.

**Immediate steps**

1. Correct the status page with the current best-known impact statement.
2. Add a timestamp and note that the incident is ongoing if uncertainty remains.
3. Tell support and account teams that the previous message is superseded.

**Diagnosis commands**

```bash
curl -X PATCH https://api.statuspage.io/v1/pages/$STATUSPAGE_PAGE/incidents/$STATUSPAGE_INCIDENT   -H "Authorization: OAuth $STATUSPAGE_TOKEN"   -H 'Content-Type: application/json'   -d '{"incident":{"body":"We are correcting a previous update. Checkout remains degraded and investigation continues.","status":"investigating"}}'
```

**Verification**: The public incident page should reflect the corrected status and the support team should acknowledge the new wording.

**Facilitation note**: Write correction messages in plain language and avoid defensive phrasing.

### War room bridge link does not work

**Symptoms**

- Responders cannot join the primary bridge or meeting room.
- People split across multiple chat threads and private calls.
- Key decisions are being made without a single shared record.

**Immediate steps**

1. Switch to a predefined backup communication channel.
2. Post one canonical channel and bridge link everywhere possible.
3. Nominate one scribe to consolidate scattered notes.

**Diagnosis commands**

```bash
curl -X POST "$SLACK_WEBHOOK"   -H 'Content-type: application/json'   -d '{"text":"Primary bridge unavailable. Backup channel: #inc-sev2-backup. Fallback voice bridge: +1-555-0100 PIN 4242."}'
```

**Verification**: All responders should converge on a single backup channel within a few minutes, and the incident timeline should continue there.

**Facilitation note**: A broken bridge is itself an operational incident; fix the root cause later but keep the customer-impact response moving now.

### Cannot reproduce the issue safely

**Symptoms**

- The issue appears only under production load, real customer data, or a specific dependency state.
- Re-running the behavior risks worsening the incident.
- Engineers disagree on whether the problem is even real.

**Immediate steps**

1. Prefer production-safe observation over invasive experimentation.
2. Capture logs, metrics, traces, and config diffs for the exact impact window.
3. Use narrow-scope feature flags or a single canary replica for validation if necessary.

**Diagnosis commands**

```bash
kubectl get events -n incident-lab --sort-by='.lastTimestamp' | tail -30
kubectl logs deployment/checkout-api -n incident-lab --since=20m --tail=200
kubectl rollout history deployment/checkout-api -n incident-lab
```

**Verification**: You should be able to gather enough evidence to choose a mitigation even if you cannot deterministically reproduce the issue on demand.

**Facilitation note**: During severe incidents, cannot reproduce should never block rollback of a clearly correlated risky change.

### Database team says not our problem

**Symptoms**

- Application and database teams each point to the other domain.
- No one owns the cross-team coordination gap.
- Mitigation is delayed because data and app evidence are reviewed separately.

**Immediate steps**

1. Frame the incident around user impact and shared system behavior, not team boundaries.
2. Ask for one concrete data point from each team within a time box.
3. Escalate to the duty manager or IC if the conversation stalls.

**Diagnosis commands**

```bash
echo 'Request from IC: within 5 minutes please provide DB CPU, lock waits, and connection count for incident window 19:10-19:30 UTC.'
echo 'Request from IC: within 5 minutes please provide checkout error rate, dependency timeout count, and recent deployment diff for the same window.'
```

**Verification**: Both teams should contribute evidence tied to the same timeframe, making it easier to identify whether the failure is upstream, downstream, or shared.

**Facilitation note**: Use the escalation matrix if a dependency owner refuses to engage during active customer impact.

### Incident drags on for more than 2 hours

**Symptoms**

- Responder fatigue increases and the same hypotheses are repeated.
- Decision quality drops and updates become vague.
- Stakeholder trust declines because the response looks directionless.

**Immediate steps**

1. Refresh the IC role and rotate critical responders.
2. Summarize what is known, unknown, tried, and explicitly rejected.
3. Revisit whether the team needs a different mitigation strategy instead of deeper diagnosis.

**Diagnosis commands**

```bash
echo 'IC refresh handoff:'
echo '- Known: checkout latency fell from 4.6s to 2.1s after scaling, but DB pool remains >90% utilized.'
echo '- Unknown: whether queueing is caused by query mix or background jobs.'
echo '- Tried: scaled payment-service, reduced marketing banner traffic, restarted one stuck worker.'
echo '- Next: pause non-critical jobs and compare queue depth over 10 minutes.'
```

**Verification**: A fresh IC should be able to take over within five minutes using the handoff summary and the existing timeline.

**Facilitation note**: If you have no new evidence after multiple cycles, schedule an external review or senior escalation.

### Postmortem gets stuck in blame

**Symptoms**

- Review comments focus on who made a change rather than why the system allowed the failure to escape.
- People become defensive and factual detail quality drops.
- Action items devolve into generic requests to be more careful.

**Immediate steps**

1. Reset the conversation by restating the customer impact and learning goal.
2. Rewrite any judgmental phrasing into system- or process-focused language.
3. Require every action item to change a condition, tool, or process rather than a personality trait.

**Diagnosis commands**

```bash
rg -n 'should have|careless|failed to|mistake by' "$HOME"/postmortem-lab/*.md
```

**Verification**: The final postmortem should read as an explanation of conditions and decisions, not a performance review.

**Facilitation note**: If blame persists, bring in a neutral facilitator for the review meeting.

## Backup Communication and Escalation Paths

### Escalation Path Reference

```text
alert fires
   |
   v
primary on-call -> secondary on-call -> incident commander -> duty manager -> executive sponsor
        |                 |                    |
        +------> Slack ----+------> bridge ----+
```

| Failure mode | Primary backup | Notes |
|---|---|---|
| PagerDuty routing broken | Phone tree or manual Slack paging | Use if alerts are firing but no incident is created. |
| Primary bridge down | Backup chat channel plus PSTN bridge | Announce one canonical fallback link. |
| Status page unavailable | Support macro plus account-team email | Keep wording consistent and timestamped. |
| IC unavailable | Acting IC from responders already present | Record the handoff time in the timeline. |

### Backup Communication Commands

```bash
curl -X POST "$SLACK_WEBHOOK" \
  -H 'Content-type: application/json' \
  -d '{"text":"[incident-backup] Pager path degraded. Acting IC=@alice. Backup bridge: +1-555-0100 PIN 4242. Next update in 15 minutes."}'
```

Expected output is typically HTTP `200` from Slack or your internal webhook proxy. If the webhook path is unavailable, switch to the next documented backup channel and note the failure in the incident timeline.

### Solo Incident Management Procedure

When IC and TL are the same person, shrink the process deliberately instead of pretending you still have a full incident team.

| Time slice | Solo responder action |
|---|---|
| Minute 0-2 | Confirm impact, assign severity, open one communication channel. |
| Minute 2-5 | Check recent changes, pod health, logs, and dependency status. |
| Minute 5-10 | Choose the safest likely mitigation and announce it before making the change. |
| Every 15 min | Post a short update: impact, current hypothesis, next action, next update time. |

```bash
printf '%s\n' \
  'SEV2 declared for checkout degradation' \
  'Impact: payment path intermittently failing' \
  'Current action: checking recent deployment and dependency health' \
  'Next update: 15 minutes' > incident-update.txt
cat incident-update.txt
```

### Refresh IC Procedure After 2 Hours

Use this handoff checklist if the incident is still active after a long response window.

1. Summarize impact in one sentence.
2. List the last three actions taken and whether they changed metrics.
3. State the best current hypothesis and the strongest competing hypothesis.
4. Confirm the next decision point and who owns it.
5. Record the handoff time in chat and in the timeline.

```bash
date -u '+%Y-%m-%d %H:%M UTC handoff started'
echo 'Known: p95 improved after scaling, but DB pool still >90% used.'
echo 'Unknown: whether queueing is driven by heavy queries or background jobs.'
echo 'Next owner: @new-ic to decide on pausing non-critical jobs after 10-minute observation window.'
```

### Cross-Team Escalation Script

Use a neutral, user-impact-based script when one team is resisting ownership.

```bash
echo 'IC request: customer checkout is degraded. Please provide one data point from your domain for 19:10-19:30 UTC that best explains the current impact.'
echo 'App team: error rate, dependency timeout count, deployment diff.'
echo 'DB team: connection count, lock waits, slow query sample.'
```

The goal is not to force agreement immediately. The goal is to get comparable evidence onto one timeline so the incident can move forward.

## Diagnosis Commands

### Kubernetes and Workload State

```bash
kubectl get events -n incident-lab --sort-by='.lastTimestamp' | tail -30
kubectl describe pod -n incident-lab $(kubectl get pod -n incident-lab -l app=checkout-api -o jsonpath='{.items[0].metadata.name}')
kubectl logs deployment/checkout-api -n incident-lab --tail=100
kubectl logs deployment/payment-service -n incident-lab --tail=100
```

### Prometheus and Alertmanager History

```bash
curl -sG http://127.0.0.1:9090/api/v1/query_range   --data-urlencode 'query=sum(rate(http_requests_total{job="checkout-api",status=~"5.."}[5m]))'   --data-urlencode 'start=2025-04-12T14:00:00Z'   --data-urlencode 'end=2025-04-12T15:00:00Z'   --data-urlencode 'step=60'

curl -s http://127.0.0.1:9093/api/v2/alerts | jq '.[] | {alertname: .labels.alertname, status: .status.state, startsAt}'
```

### PagerDuty Incident Log

```bash
export INCIDENT_ID='replace-me'
curl -s -H "Authorization: Token token=$PD_API_TOKEN"   "https://api.pagerduty.com/incidents/$INCIDENT_ID" | jq '{incident_number,status,title,urgency,assignments}'
curl -s -H "Authorization: Token token=$PD_API_TOKEN"   "https://api.pagerduty.com/incidents/$INCIDENT_ID/log_entries" | jq '.log_entries[] | {created_at,summary}'
```

### ServiceNow Record Lookup

```bash
export SNOW_INC='INC0012345'
curl -s -u "$SNOW_USER:$SNOW_PASS"   "https://example.service-now.com/api/now/table/incident?sysparm_query=number=$SNOW_INC" | jq '.result[] | {number,state,assignment_group,short_description}'
```

## PagerDuty Troubleshooting

### Alert fires but no PagerDuty incident created

- Confirm the Alertmanager receiver uses the expected routing key and service integration.
- Check Alertmanager logs for HTTP 4xx or 5xx responses from PagerDuty.
- Send a controlled sample event with a unique summary to prove the path end-to-end.

```bash
kubectl logs -n monitoring deploy/alertmanager --since=15m | grep -i 'pagerduty\|error'
curl -X POST https://events.pagerduty.com/v2/enqueue   -H 'Content-Type: application/json'   -d '{"routing_key":"'"$PD_ROUTING_KEY"'","event_action":"trigger","payload":{"summary":"pd path test","source":"incident-lab","severity":"warning"}}'
```

### Wrong person paged

- Inspect the escalation policy attached to the service and confirm current schedule overrides.
- Check whether event routing rules changed the target service unexpectedly.
- Verify maintenance windows are not suppressing the intended primary responder.

```bash
curl -s -H "Authorization: Token token=$PD_API_TOKEN"   "https://api.pagerduty.com/services?query=checkout" | jq '.services[] | {name,id,escalation_policy}'
```

### Duplicate incidents

- Confirm that the dedup key is stable across retries of the same alert.
- Check whether multiple integrations are sending the same event with different fingerprints.
- Verify that resolved events are using the same dedup key as the trigger event.

```bash
curl -X POST https://events.pagerduty.com/v2/enqueue   -H 'Content-Type: application/json'   -d '{"routing_key":"'"$PD_ROUTING_KEY"'","event_action":"trigger","dedup_key":"checkout-api-high-error-rate","payload":{"summary":"duplicate test","source":"incident-lab","severity":"critical"}}'
```

## Postmortem Quality Issues

### Action items never get done

- Move action items into the team’s normal ticketing workflow instead of leaving them only in markdown.
- Require one weekly review of open postmortem actions until they close or are explicitly deprioritized.
- Track time to close action item as a reliability follow-through metric.

```bash
cat <<'EOF' > postmortem-actions.csv
incident_id,action_item,owner,due_date,status
INC-2025-0412,Add dependency retry canary,@commerce-platform,2025-05-02,open
INC-2025-0413,Create traffic surge runbook,@sre-duty-manager,2025-04-28,open
EOF
```

### Team resists blameless culture

- Open the review by stating the goal: understand conditions and decisions, not assign moral judgment.
- Ban vague behavioral action items such as be more careful unless paired with a concrete system change.
- Ask what made this reasonable at the time to surface context rather than hindsight bias.

## Key Takeaways

- Many incidents are prolonged by response-process failures rather than by the original technical bug alone.
- Keep backup channels and backup escalation paths ready before you need them.
- Evidence, ownership, and cadence are the three process controls that stabilize a messy incident.
- Blameless postmortems still require accountability, but the accountability is for changing systems and processes.
