# Lab 02: Resource Management and QoS

## Check Current QoS
```bash
kubectl get pods -o json | jq '.items[] | {name: .metadata.name, qos: .status.qosClass}'
kubectl get pods -o json | jq '.items[] | select(.status.qosClass=="BestEffort") | .metadata.name'
```

## Right-Size Using Metrics
```bash
kubectl top pods -n default
# Grafana: container_cpu_usage_seconds_total, container_memory_working_set_bytes
```

## Apply Resources
```yaml
containers:
- name: api
  resources:
    requests:
      cpu: "100m"
      memory: "256Mi"
    limits:
      cpu: "500m"
      memory: "512Mi"
```

## Namespace Quota
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    requests.cpu: "10"
    requests.memory: "20Gi"
    limits.cpu: "20"
    limits.memory: "40Gi"
    pods: "100"
```

```bash
kubectl apply -f quota.yaml
kubectl describe quota production-quota -n production
```

## Verification
- [ ] No BestEffort pods (all have requests+limits)
- [ ] Namespace quota applied
- [ ] Usage < requests (not over-allocated)
