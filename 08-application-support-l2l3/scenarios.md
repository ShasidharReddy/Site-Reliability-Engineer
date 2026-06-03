# Scenario Workbook: Application Support L2/L3

- These scenarios are designed for tabletop drills, shift onboarding, and post-incident coaching.
- Each scenario can be run as a discussion, a written exercise, or a live lab against a training environment.

## Scenario 1: L2 ticket: app down for one user but not others

- A finance user reports the app is down. Other users log in normally.

### Facilitator prompts

1. Check whether the symptom is tied to one account, device, browser, role, or office network.
2. Review identity provider logs, group membership, and recent MFA or certificate changes.
3. Compare the affected user with a healthy peer in the same tenant.

### Command and evidence pack

```bash
kubectl logs deploy/portal-api -n prod-portal --since=30m | grep userId=fin-204
kubectl logs deploy/portal-web -n prod-portal --since=30m | tail -120
curl -sk https://portal.example.com/health
```

### Expected responder outputs

- Likely isolated token corruption or browser certificate problem.
- L2 should fix the user-specific condition and avoid unnecessary major-incident escalation.
- Document why the issue was isolated and what evidence proved the wider service was healthy.

### ServiceNow update template

```text
Impact summary:
Scope:
What changed:
Current mitigation:
Escalation owner:
Next update due:
```

### Verification prompts

1. What evidence proved the chosen owner was correct?
2. What was the safest mitigation?
3. What would trigger management or vendor escalation?
4. What prevention action belongs in the follow-up backlog?

## Scenario 2: L3 escalation: memory leak in Java app over 3 days

- Account-service pods are OOMKilled every 72 hours and L2 has already ruled out config drift.

### Facilitator prompts

1. L2 must send graphs, restart times, traffic correlation, and any heap or class histogram evidence.
2. L3 should investigate unbounded caches, retained sessions, backlog objects, and client library regressions.
3. Mitigation must protect availability while the code-level fix is prepared.

### Command and evidence pack

```bash
kubectl top pod -n prod-account -l app=account-service
kubectl exec -n prod-account <pod> -- jcmd 1 GC.heap_info
kubectl exec -n prod-account <pod> -- jmap -histo:live 1 | head -50
```

### Expected responder outputs

- Short-term controlled restart may be necessary.
- Permanent prevention includes code fix, cache bound, memory slope alerting, and runbook updates.
- The problem record should track repeat incident count and final preventive change.

### ServiceNow update template

```text
Impact summary:
Scope:
What changed:
Current mitigation:
Escalation owner:
Next update due:
```

### Verification prompts

1. What evidence proved the chosen owner was correct?
2. What was the safest mitigation?
3. What would trigger management or vendor escalation?
4. What prevention action belongs in the follow-up backlog?

## Scenario 3: Major incident: database connection pool depleted

- Checkout, order history, and invoicing all begin timing out because a shared database pool is exhausted.

### Facilitator prompts

1. Open a war room and assign incident commander, application lead, database lead, and communications owner.
2. Split investigation into blocking sessions, pool configuration, traffic spike, and recent change review.
3. Protect the highest-priority customer transactions first.

### Command and evidence pack

```bash
kubectl logs deploy/checkout-api -n prod-orders --since=20m | grep -i pool
kubectl exec -n prod-orders deploy/checkout-api -- printenv | grep DB_POOL
psql -c "SELECT state, wait_event_type, count(*) FROM pg_stat_activity GROUP BY state, wait_event_type;"
```

### Expected responder outputs

- Mitigation may include terminating blocking sessions, rolling back pool changes, or reducing batch traffic.
- Verification requires pool wait recovery, timeout recovery, and stable metrics through one traffic cycle.
- A problem record is mandatory if pool depletion has happened before.

### ServiceNow update template

```text
Impact summary:
Scope:
What changed:
Current mitigation:
Escalation owner:
Next update due:
```

### Verification prompts

1. What evidence proved the chosen owner was correct?
2. What was the safest mitigation?
3. What would trigger management or vendor escalation?
4. What prevention action belongs in the follow-up backlog?

## Scenario 4: Post-incident: how to prevent repeat escalations

- The incident is closed, but the same service has escalated to L3 three times in two months.

### Facilitator prompts

1. Review the incident timeline for missed detection, weak runbooks, and manual repeated actions.
2. Identify what L2 could safely automate or decide earlier next time.
3. Create prevention actions that change the system, not only the process.

### Command and evidence pack

```bash
gh issue list --limit 20
kubectl get configmap -n prod-payments payment-api -o yaml
kubectl get deploy -n prod-payments payment-api -o yaml
```

### Expected responder outputs

- Examples include deployment guardrails, better dashboards, clearer escalation matrices, and problem-driven backlog items.
- Measure success with lower repeat incident count and faster mitigation time.
- Close the exercise only after naming owners and due dates for each prevention item.

### ServiceNow update template

```text
Impact summary:
Scope:
What changed:
Current mitigation:
Escalation owner:
Next update due:
```

### Verification prompts

1. What evidence proved the chosen owner was correct?
2. What was the safest mitigation?
3. What would trigger management or vendor escalation?
4. What prevention action belongs in the follow-up backlog?

## Scenario comparison matrix

| Scenario | Primary owner | First escalation if blocked | Permanent prevention theme |
| --- | --- | --- | --- |
| One-user app down | L2 app support | Identity or endpoint support | Better user-specific diagnostics |
| Three-day memory leak | L3 / SRE | Application engineering | Code fix plus memory observability |
| Pool depleted major incident | L2 + L3 incident bridge | DBA / vendor if needed | Pool guardrails and lock visibility |
| Prevent repeat escalations | Problem manager / service owner | Engineering leadership | Automation, alerting, and runbook maturity |

## Facilitation checklist

1. State business impact before discussing root cause.
2. Ask responders to separate evidence from assumption.
3. Require at least one safe mitigation and one escalation trigger.
4. End each scenario with a measurable prevention action.

## Scenario scoring rubric

| Score area | 1 | 3 | 5 |
| --- | --- | --- | --- |
| Impact assessment | vague | partly quantified | quantified with business meaning |
| Evidence quality | assumptions only | some logs/metrics | clear logs, metrics, traces, timeline |
| Mitigation choice | risky or missing | workable | safest viable option with verification |
| Escalation quality | wrong owner | owner identified late | precise owner with evidence package |
| Prevention thinking | none | generic | measurable action with owner |

## Role cards for drills

### Incident commander

- Keeps responders focused on current impact and next decision.
- Approves production changes or confirms the approver.
- Owns next-update cadence.

### L2 responder

- Confirms symptom and impact.
- Runs safe diagnostics and approved mitigations.
- Prepares crisp escalation notes.

### L3 or SRE responder

- Investigates code-level, architectural, or systemic causes.
- Advises on rollback, failover, and reliability risk.
- Owns follow-up prevention work with service owner.

### Communications owner

- Converts technical progress into stakeholder language.
- Tracks next update times.
- Makes sure customer and leadership messages stay consistent.

## Debrief questions after every scenario

1. Which signal should have detected the issue first?
2. What evidence most clearly narrowed the failure domain?
3. Which mitigation reduced risk fastest?
4. Which task should move into a runbook or automation?
5. What would you change in alerting, release control, or observability?

## Example war-room timeline

```text
09:05 UTC - First user ticket created.
09:08 UTC - Monitoring confirms elevated error rate.
09:10 UTC - L2 accepts incident and confirms impact scope.
09:15 UTC - Technical bridge starts.
09:22 UTC - First safe mitigation selected.
09:30 UTC - Error rate begins dropping.
09:45 UTC - Stable recovery confirmed.
10:00 UTC - Problem and change follow-up owners assigned.
```

## Practice checklist

- [ ] Identify the user-visible symptom in one sentence.
- [ ] State impact in business terms.
- [ ] Name the narrowest likely failing component.
- [ ] Choose one safe mitigation.
- [ ] Name the first escalation target if blocked.
- [ ] Record one durable prevention action.

## Additional scenario prompts

### One-user outage extension

- Ask whether the user is behind a special VPN, proxy, or browser certificate policy.
- Ask whether the user belongs to a unique authorization group.
- Ask whether the issue follows the user account or the workstation.

### Memory leak extension

- Ask what changed in the 72-hour cycle: report batch, cache refresh, or scheduled reconciliation.
- Ask whether heap growth follows one endpoint or all traffic.
- Ask what evidence must be captured before the next restart.

### Pool depletion extension

- Ask whether batch traffic can be rate-limited to protect interactive traffic.
- Ask whether the database is waiting on locks, I/O, or connection churn.
- Ask whether a recent config change reduced pool headroom.

### Prevention extension

- Ask which repeated L2 action should become automation.
- Ask which alert fired too late or routed poorly.
- Ask what deployment guardrail could block the same failure next time.

## Scenario completion criteria

1. A responder states the impact clearly.
2. A responder states the likely owner clearly.
3. A safe mitigation is chosen.
4. An escalation trigger is named.
5. A prevention action is assigned.
6. A verification method is named.

## Final facilitator reminder

- Keep the team focused on impact first.
- Separate observation from assumption.
- Prefer one clean mitigation over many speculative changes.
- End with a measurable prevention action and owner.
Practice one escalation note and one stakeholder update for every scenario.
Use the same time zone in all timeline notes.
Verify recovery before ending the exercise.
Escalate with evidence, not guesses.
