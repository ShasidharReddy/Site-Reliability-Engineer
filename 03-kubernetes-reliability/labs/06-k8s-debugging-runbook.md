# Lab 06 — Kubernetes Debugging Runbook

## Universal Debug Flow
```
1. kubectl get pods -A | grep -v Running | grep -v Completed
2. kubectl describe pod <pod> -n <namespace>
3. kubectl logs <pod> -n <namespace> [--previous]
4. kubectl get events -n <namespace> --sort-by='.lastTimestamp'
5. kubectl top pods -n <namespace>
6. kubectl top nodes
```

## Issue: CrashLoopBackOff
```bash
# Step 1: Get last exit code and reason
kubectl describe pod $POD -n $NS | grep -A5 "Last State:"

# Step 2: Get logs from crashed container
kubectl logs $POD -n $NS --previous --tail=100

# Step 3: Check events
kubectl get events -n $NS --field-selector involvedObject.name=$POD

# Step 4: Exec into running container (if it starts briefly)
kubectl exec -it $POD -n $NS -- /bin/sh

# Common fixes:
# - Exit code 1: app bug — check logs for error message
# - Exit code 137: OOMKilled — increase memory limit
# - Exit code 139: Segfault — app crash — escalate to dev team
# - "back-off restarting failed container": check liveness probe config
```

## Issue: Pending Pods
```bash
# Check why pod is pending
kubectl describe pod $POD -n $NS | grep -A20 "Events:"

# Check node resources
kubectl describe nodes | grep -A5 "Allocated resources"
kubectl get pods -A -o wide | grep $NODE  # What's running on target node?

# Check taints
kubectl describe node $NODE | grep Taints

# Check affinity/selectors
kubectl get pod $POD -n $NS -o yaml | grep -A20 affinity
kubectl get pod $POD -n $NS -o yaml | grep -A5 nodeSelector
```

## Issue: Service Not Routing Traffic
```bash
# Step 1: Verify service endpoints
kubectl get endpoints $SVC -n $NS
# If endpoints is empty → selector doesn't match any pods

# Step 2: Verify pod labels match service selector
kubectl get pod -l app=my-app -n $NS
kubectl get svc $SVC -n $NS -o yaml | grep -A5 selector

# Step 3: Test service from within cluster
kubectl run curl-test --image=curlimages/curl -it --rm -- \
  curl -v http://$SVC.$NS.svc.cluster.local

# Step 4: Test DNS resolution
kubectl run dns-test --image=busybox -it --rm -- \
  nslookup $SVC.$NS.svc.cluster.local

# Step 5: Check kube-proxy / iptables
# On a node:
iptables-save | grep $SVC
```

## Issue: Node Not Ready
```bash
# Check node conditions
kubectl describe node $NODE | grep -A20 Conditions

# SSH to node (if accessible)
ssh $NODE
systemctl status kubelet
journalctl -u kubelet -n 100 --no-pager

# Common causes:
# - kubelet OOM: check node memory
# - Disk pressure: df -h on node
# - PID pressure: ps aux | wc -l
# - Network issue: ping kube-apiserver from node
```

## Issue: High Pod Restart Count
```bash
# Find pods with > 5 restarts
kubectl get pods -A | awk '$5 > 5'

# Check restart reason
kubectl describe pod $POD -n $NS | grep -E "Restart|OOM|Killed|Exit"

# Check resource usage vs limits
kubectl top pod $POD -n $NS
kubectl get pod $POD -n $NS -o yaml | grep -A10 resources
```

## Quick Health Check Script
```bash
#!/bin/bash
echo "=== Cluster Health Check ==="
echo ""
echo "--- Not-Running Pods ---"
kubectl get pods -A | grep -v "Running\|Completed\|NAME"
echo ""
echo "--- Recent Events (Warnings) ---"
kubectl get events -A --field-selector type=Warning --sort-by='.lastTimestamp' | tail -20
echo ""
echo "--- Node Status ---"
kubectl get nodes -o wide
echo ""
echo "--- Resource Usage ---"
kubectl top nodes 2>/dev/null || echo "metrics-server not available"
echo ""
echo "--- Pending PVCs ---"
kubectl get pvc -A | grep -v Bound
```
