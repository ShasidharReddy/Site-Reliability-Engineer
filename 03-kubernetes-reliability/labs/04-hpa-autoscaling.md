# Lab 04: Horizontal Pod Autoscaling

## Basic CPU-based HPA
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 2
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60   # Wait 60s before more scale-up
    scaleDown:
      stabilizationWindowSeconds: 300  # Wait 5min before scale-down
```

## Custom Metric HPA (RPS)
```yaml
  metrics:
  - type: Pods
    pods:
      metric:
        name: http_requests_per_second
      target:
        type: AverageValue
        averageValue: "100"
```

## Verify
```bash
kubectl get hpa api-hpa -n production -w

# Generate load
kubectl run load --image=busybox --rm -it -- sh -c   "while true; do wget -q -O- http://api-service/; done"

# Watch scale-up
kubectl get pods -n production -w
```

## Verification
- [ ] HPA created and shows TARGETS
- [ ] CPU utilization triggers scale-up
- [ ] ScaleDown stabilization window prevents flapping
