# Lab 02: Runbook Creation

## Overview
Build runbooks from real incidents to reduce future MTTR.

## Template
```markdown
# Runbook: [Service] — [Alert Name]

## Trigger
Alert: [Prometheus rule name]
Threshold: [condition]

## Impact
- Users affected: [estimate]
- Behavior: [what users see]

## Initial Triage (< 5 min)
1. Check Grafana dashboard: [URL]
2. Verify scope: rate(http_errors[5m]) by (pod)
3. Check for recent deploy: kubectl rollout history deploy/<service>

## Diagnosis

### Is it a deployment issue?
- Recent rollout: kubectl rollout history deploy/<service>
- If yes and error correlates with deploy time: rollback
  kubectl rollout undo deploy/<service>

### Is it a resource issue?
- kubectl top pods -n <namespace>
- If OOMKilled (exit 137): scale up or increase memory limit

### Is it a dependency issue?
- kubectl exec <pod> -- nc -zv <dep-host> <dep-port>
- If connection refused: investigate dependency

## Escalation
Escalate to: @platform-team
When: Runbook steps do not resolve in 30 min

## References
- Service owner: [team]
- Grafana: [URL]
- Architecture diagram: [URL]
```

## Practice: Write a Runbook for High Error Rate

Fill in the template above for:
- Service: payment-api
- Alert: ErrorRateHigh (>5% for 5m)
- Common causes: DB slow queries, thread pool exhausted, external payment gateway degraded

## Verification
- [ ] Runbook has clear trigger conditions
- [ ] Triage steps are specific (commands, not concepts)
- [ ] Every branch has a concrete action
- [ ] Escalation condition and target defined
- [ ] Added to alert annotation runbook_url
