# L2 Triage Checklist

## Initial Response (0-5 min)
- [ ] Acknowledge ServiceNow ticket
- [ ] Understand symptom (not assumption)
- [ ] Check for known issue in SNOW history
- [ ] Check status pages (cloud provider, external deps)
- [ ] Determine scope: 1 user? 1 region? All users?
- [ ] Set ticket priority

## Investigation (5-30 min)
- [ ] Grafana: error/latency spike?
- [ ] Recent deployments?
- [ ] Application logs (Loki / Cloud Logging)
- [ ] K8s events (kubectl get events --sort-by=lastTimestamp)
- [ ] Resource utilization (kubectl top pods/nodes)
- [ ] External dependencies

## Mitigation
- [ ] Apply mitigation (rollback / restart / scale)
- [ ] Verify error rate returns to normal
- [ ] Update ServiceNow work notes

## Escalation Triggers
- [ ] No root cause after 30 min
- [ ] Need infra access beyond kubectl
- [ ] Data integrity concern
- [ ] Code fix required

## Resolution
- [ ] Confirm with user
- [ ] Write resolution notes
- [ ] Create action items
- [ ] Update runbook
- [ ] Close ticket
