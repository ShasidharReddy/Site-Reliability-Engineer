# Lab 01: Probe Configuration

## Bad Probes (Common Mistakes)
```yaml
# BAD: Liveness hits external dependency
livenessProbe:
  httpGet:
    path: /health/full   # Hits DB + Redis = cascade restarts
    port: 8080

# BAD: No startup probe for slow app (JVM takes 90s)
livenessProbe:
  initialDelaySeconds: 5  # Too short -> restarts during init
```

## Correct Design
```yaml
containers:
- name: app
  startupProbe:
    httpGet:
      path: /health/live
      port: 8080
    periodSeconds: 10
    failureThreshold: 30    # 300s max startup

  livenessProbe:
    httpGet:
      path: /health/live    # Process alive only - no deps
      port: 8080
    periodSeconds: 10
    failureThreshold: 3

  readinessProbe:
    httpGet:
      path: /health/ready   # Checks dependencies
      port: 8080
    periodSeconds: 5
    failureThreshold: 2
```

## Test
```bash
kubectl apply -f probe-deployment.yaml
kubectl get pods -w

# Simulate readiness fail
kubectl exec <pod> -- touch /tmp/not-ready

# Watch endpoints
kubectl get endpoints <service> -w
kubectl describe ep <service> | grep Addresses
```

## Verification
- [ ] Startup probe allows full init
- [ ] Readiness failure removes from endpoints (no service traffic)
- [ ] Liveness failure triggers restart only
- [ ] App has separate /health/live and /health/ready
