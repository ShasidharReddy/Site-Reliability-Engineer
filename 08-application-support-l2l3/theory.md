# Application Support L2/L3 Theory

## 1. Support Tiers

| Tier | Role | SLA |
|------|------|-----|
| L1 | Help Desk — known issues, runbooks | 30 min |
| L2 | App Support — config, deployments | 4h |
| L3 | SRE/Engineering — root cause, code fixes | 24h |
| L4 | Vendor | Varies |

SRE backup = L2/L3 boundary. Activate when: resource-constrained L2, active SEV needing SRE tools, escalation with insufficient progress.

## 2. Triage Methodology

### 5 Questions Before Any Action
1. What is the user-reported symptom?
2. When did it start? (any recent change?)
3. How many users affected?
4. Is there a workaround?
5. Is this a known issue?

## 3. Application Debugging Patterns

### Pod Not Responding
```bash
kubectl get pods -n <namespace> | grep <service>
kubectl describe pod <pod> -n <namespace> | grep -A5 Conditions
kubectl get events -n <namespace> --sort-by=lastTimestamp | tail -20
kubectl logs <pod> -n <namespace> --tail=100
kubectl logs <pod> -n <namespace> --previous --tail=100
kubectl get endpoints <service> -n <namespace>
kubectl run debug --image=busybox --rm -it -- wget -qO- http://<service>:<port>/health
```

### High Response Times
```bash
kubectl top pods -n <namespace> --sort-by=memory
kubectl logs <pod> | grep -i "pool\|timeout\|queue"
```

### Memory Leak
```bash
# Track growth in Grafana
container_memory_working_set_bytes{namespace="prod", pod=~"myapp-.*"}

# Check OOM history
kubectl describe pod <pod> | grep -A5 "Last State"

# Go pprof heap
kubectl exec <pod> -- curl http://localhost:6060/debug/pprof/heap > heap.pprof
go tool pprof heap.pprof
```

## 4. ServiceNow Usage

### Incident Lifecycle
New → In Progress → Resolved → Closed

### Critical Fields
- **Short description**: [service] symptom (searchable)
- **Business service**: CMDB entry (enables trend analysis)
- **Work notes**: running investigation (not visible to requester)
- **Resolution notes**: exact fix steps (future runbook source)

### Work Note Template
```
[HH:MM] Beginning investigation.
- Symptom confirmed: [what fails]
- Grafana: error rate [X]% from [HH:MM]
- Recent deploys: [yes/no, details]
- Hypothesis: [root cause guess]
- Next step: [action] ETA 15 min
```

## 5. Escalation Criteria

Escalate L2 → L3/SRE when:
- Not resolved in 60 min despite runbook
- Root cause unclear, 10+ users affected
- Code/infra level change required
- Data integrity concern
- Access limitations

Always include:
1. Exact symptom (user-reported)
2. What you checked (specific)
3. What you tried
4. Your hypothesis
5. Relevant logs/Grafana links

Bad: "API is slow, can you look?"
Good: "API /v2/orders P95=8s since 14:30. No recent deploy. DB connections normal. Logs show thread pool exhausted every minute. Need review of ThreadPoolTaskExecutor config."

## 6. Runbook Structure

```markdown
# Runbook: [Service] [Symptom]
## Alert/Trigger
## Symptoms
## Scope
## Triage Steps
1. Check [thing] at [location]
2. Run [command] and look for [output]
## Fixes
### Fix A: [Name]
Expected outcome: [what you should see]
## Escalation
Escalate to: @team if [conditions]
```

## 7. Communication During SEV

Status update template:
```
[14:45] Update — [Service] issue
Status: INVESTIGATING / MITIGATED / RESOLVED
Impact: ~500 users, /checkout failing
Progress: Rolled back deploy from 14:15. Error rate dropping.
ETA: Full recovery in ~5min.
Next update: 15:00 if not resolved
```
