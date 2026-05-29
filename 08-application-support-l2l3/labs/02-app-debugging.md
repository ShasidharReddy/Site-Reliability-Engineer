# Lab 02: Application Debugging Runbook

## Scenario
Microservice returning 500 errors intermittently.

## Phase 1: Observe
```bash
# Error rate by pod
rate(http_requests_total{status_code=~"5.."}[5m]) by (pod)

# Memory growth
container_memory_working_set_bytes{namespace="default"}
```

## Phase 2: Isolate
```bash
# Which pod is bad?
kubectl logs <specific-bad-pod> -n default | grep ERROR | tail -20

# Compare good vs bad pod
kubectl logs <good-pod> | tail -20
kubectl logs <bad-pod> | tail -20
```

## Phase 3: Deep Dive
```bash
kubectl exec -it <bad-pod> -- bash
ps aux
netstat -an | grep ESTABLISHED | wc -l
cat /proc/meminfo | grep -i available
df -h
```

## Phase 4: Collect Evidence
```bash
kubectl logs <bad-pod> --previous > /tmp/pod-logs-previous.txt
kubectl describe pod <bad-pod> > /tmp/pod-describe.txt
```

## Phase 5: Mitigate
```bash
# Restart bad pod
kubectl delete pod <bad-pod> -n default

# Rollback deployment
kubectl rollout undo deployment/my-service -n default

# Scale up
kubectl scale deployment/my-service --replicas=5 -n default
```

## Verification
- [ ] Root cause identified
- [ ] Mitigation applied and verified
- [ ] ServiceNow updated
- [ ] Runbook created/updated
