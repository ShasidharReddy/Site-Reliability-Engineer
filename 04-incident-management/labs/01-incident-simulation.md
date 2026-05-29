# Lab 01 — Incident Simulation

## Overview
Simulate a production incident on your minikube cluster, practice the incident response process, and write up findings.

## Setup: Deploy Sample App
```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: incident-app
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: incident-app
  template:
    metadata:
      labels:
        app: incident-app
    spec:
      containers:
      - name: app
        image: nginx:alpine
        resources:
          requests: {cpu: 100m, memory: 64Mi}
          limits: {cpu: 200m, memory: 128Mi}
        readinessProbe:
          httpGet: {path: /, port: 80}
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: incident-app
spec:
  selector:
    app: incident-app
  ports:
  - port: 80
EOF
```

## Scenario 1: CrashLoopBackOff Incident

### Inject Failure
```bash
# Update deployment with a broken command
kubectl set image deployment/incident-app app=nginx:bad-tag-does-not-exist
```

### Practice Response
```bash
# 1. Detect (check alerts or pods)
kubectl get pods -w   # Watch pods go to ImagePullBackOff

# 2. Triage
kubectl describe pod $(kubectl get pods -l app=incident-app -o jsonpath='{.items[0].metadata.name}') | tail -20

# 3. Mitigate (rollback)
kubectl rollout undo deployment/incident-app
kubectl rollout status deployment/incident-app

# 4. Verify
kubectl get pods -l app=incident-app
```

## Scenario 2: Memory OOM Incident

### Inject Failure
```bash
# Deploy with memory limit that will be exceeded
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: oom-test
spec:
  containers:
  - name: memory-hog
    image: polinux/stress
    resources:
      limits:
        memory: "50Mi"
    command: ["stress"]
    args: ["--vm", "1", "--vm-bytes", "100M", "--vm-hang", "1"]
EOF

# Watch the OOMKill
kubectl get pod oom-test -w
kubectl describe pod oom-test | grep -A5 "Last State"
```

## Incident Response Drill Checklist
- [ ] Detected within 5 minutes
- [ ] SEV level declared
- [ ] Impact assessed (how many pods affected?)
- [ ] Mitigation applied within 10 minutes
- [ ] Root cause identified
- [ ] Resolution verified
- [ ] Post-incident notes written
