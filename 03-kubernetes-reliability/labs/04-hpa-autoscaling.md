# Lab 04: Advanced Autoscaling in Kubernetes

## Objective
Build and validate a production-style autoscaling stack that combines:
- CPU-based Horizontal Pod Autoscaling (HPA)
- Custom metrics HPA through Prometheus Adapter
- KEDA event-driven scaling for queue consumers
- Vertical Pod Autoscaler (VPA) in recommendation mode
- Cluster Autoscaler behavior validation for node scale-out

## Why this lab matters
Real SRE work rarely depends on a single autoscaler. Production clusters often use:
- HPA for fast reactive scaling on CPU or memory
- Prometheus-backed custom metrics for user-facing load signals
- KEDA for external queues, streams, and background jobs
- VPA recommendations to fix poor requests and limits
- Cluster Autoscaler to add nodes when pods become unschedulable

If one layer is missing or misconfigured, scaling either becomes too slow, too noisy, or simply stops working.

## Lab topology
```text
                    +-----------------------------+
                    |         User traffic        |
                    +--------------+--------------+
                                   |
                                   v
                     +---------------------------+
                     |        api Deployment     |
                     |  CPU requests: 200m       |
                     |  HPA target: 60% CPU      |
                     +-------------+-------------+
                                   |
                    +--------------+---------------+
                    |                              |
                    v                              v
     +----------------------------+   +------------------------------+
     | Prometheus + Adapter       |   | KEDA Operator                |
     | exposes custom metrics     |   | watches queue length         |
     +--------------+-------------+   +---------------+--------------+
                    |                                 |
                    v                                 v
      +----------------------------+   +-----------------------------+
      | HPA on http_rps            |   | worker Deployment           |
      | scales api or workers      |   | scales from queue events    |
      +----------------------------+   +-----------------------------+
                                   |
                                   v
                        +-----------------------+
                        | Cluster Autoscaler    |
                        | adds nodes if needed  |
                        +-----------+-----------+
                                    |
                                    v
                        +-----------------------+
                        | Node group / ASG / VM |
                        +-----------------------+
```

## Prerequisites
| Requirement | Why it matters | Verification |
|---|---|---|
| metrics-server | Needed for CPU and memory metrics | `kubectl top nodes` |
| Prometheus | Needed for custom metrics | `kubectl get pods -n monitoring` |
| Prometheus Adapter | Maps Prometheus series to Custom Metrics API | `kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | jq` |
| KEDA | Watches event sources and drives HPA objects | `kubectl get pods -n keda` |
| VPA CRDs | Required for VPA recommendations | `kubectl get crd | grep verticalpodautoscalers` |
| Cluster Autoscaler | Adds nodes for pending pods | `kubectl get pods -n kube-system | grep cluster-autoscaler` |

## Target namespace
```bash
kubectl create namespace autoscaling-lab
kubectl label namespace autoscaling-lab purpose=autoscaling --overwrite
```

## Quick baseline checks
```bash
kubectl top nodes
kubectl top pods -A | head
kubectl api-resources | grep -E 'horizontalpodautoscaler|scaledobject|verticalpodautoscaler'
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | head
kubectl get --raw /apis/external.metrics.k8s.io/v1beta1 | head
```

## Part 1 - Deploy the sample API
Use `manifests/hpa-example.yaml` for the API Deployment, Service, and baseline CPU HPA. The workload is intentionally small but includes resource requests, probes, and Prometheus annotations.

```yaml
kind: Deployment
metadata:
  name: api
  namespace: autoscaling-lab
spec:
  replicas: 3
  template:
    metadata:
      annotations:
        prometheus.io/scrape: "true"
```

Apply it:
```bash
kubectl apply -f manifests/hpa-example.yaml
kubectl rollout status deploy/api -n autoscaling-lab
kubectl get pods -n autoscaling-lab -l app=api -o wide
```

## Part 2 - CPU-based HPA
### HPA manifest
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-cpu-hpa
  namespace: autoscaling-lab
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 3
  maxReplicas: 15
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      selectPolicy: Max
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30
      - type: Pods
        value: 4
        periodSeconds: 30
    scaleDown:
      stabilizationWindowSeconds: 300
      selectPolicy: Min
      policies:
      - type: Percent
        value: 25
        periodSeconds: 60
```

Apply it:
```bash
kubectl apply -f manifests/hpa-example.yaml
kubectl describe hpa api-cpu-hpa -n autoscaling-lab
```

### Generate CPU load
```bash
kubectl run cpu-loader -n autoscaling-lab \
  --image=busybox:1.36 \
  --restart=Never \
  --rm -it -- /bin/sh

while true; do
  wget -q -O- http://api.autoscaling-lab.svc.cluster.local/work >/dev/null
  wget -q -O- http://api.autoscaling-lab.svc.cluster.local/work >/dev/null
  wget -q -O- http://api.autoscaling-lab.svc.cluster.local/work >/dev/null
  sleep 0.2
done
```

### Observe HPA behavior
```bash
kubectl get hpa -n autoscaling-lab -w
kubectl get deploy api -n autoscaling-lab -w
kubectl top pods -n autoscaling-lab -l app=api --containers
kubectl describe hpa api-cpu-hpa -n autoscaling-lab
```

### Expected observations
| Signal | Expected result |
|---|---|
| CPU utilization rises above 60% | HPA increases desired replicas |
| Deployment starts new pods | `CURRENT` moves toward `DESIRED` |
| Load stops | HPA holds for 5 minutes before scale-down |
| metrics-server unavailable | `unknown` targets or no scale decision |

### Validation checklist
- [ ] `kubectl top pods` shows live CPU values.
- [ ] `kubectl describe hpa` shows successful metric retrieval.
- [ ] Replica count increases under sustained load.
- [ ] Scale-down does not happen immediately after load ends.
- [ ] No `FailedGetResourceMetric` events appear.

## Part 3 - HPA with custom metrics via Prometheus Adapter
### Data path
```text
App /metrics --> Prometheus scrape --> Adapter rules --> Custom Metrics API --> HPA --> Deployment
```

### Example adapter rule
```yaml
rules:
  default: false
  custom:
  - seriesQuery: 'http_requests_total{namespace!="",pod!=""}'
    resources:
      overrides:
        namespace:
          resource: namespace
        pod:
          resource: pod
    name:
      matches: "^(.*)_total"
      as: "${1}_per_second"
    metricsQuery: |
      sum(rate(<<.Series>>{<<.LabelMatchers>>}[2m])) by (<<.GroupBy>>)
```

### ServiceMonitor example
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: api
  namespace: autoscaling-lab
spec:
  selector:
    matchLabels:
      app: api
  endpoints:
  - port: http
    interval: 15s
    path: /metrics
  namespaceSelector:
    matchNames:
    - autoscaling-lab
```

### HPA using pod custom metric
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-rps-hpa
  namespace: autoscaling-lab
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Pods
    pods:
      metric:
        name: http_requests_per_second
      target:
        type: AverageValue
        averageValue: "25"
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 30
      policies:
      - type: Pods
        value: 5
        periodSeconds: 30
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 20
        periodSeconds: 60
```

Apply or compare against `manifests/custom-metrics-hpa.yaml`:
```bash
kubectl apply -f manifests/custom-metrics-hpa.yaml
kubectl describe hpa api-rps-hpa -n autoscaling-lab
kubectl get --raw \
  "/apis/custom.metrics.k8s.io/v1beta1/namespaces/autoscaling-lab/pods/*/http_requests_per_second" | jq
```

### Generate request rate
```bash
kubectl run rps-loader -n autoscaling-lab \
  --image=rakyll/hey \
  --restart=Never \
  --rm -it -- \
  -z 5m -c 50 http://api.autoscaling-lab.svc.cluster.local/
```

### What good looks like
| Check | Good output | Bad output |
|---|---|---|
| Custom Metrics API | metric list returns values | 404 or empty list |
| HPA events | `SuccessfulRescale` | `FailedGetPodsMetric` |
| Prometheus target | endpoint is `UP` | target is `DOWN` |
| Replica scaling | tracks request rate | remains static under load |

### Common failure modes
| Symptom | Likely cause | First command |
|---|---|---|
| HPA target says `<unknown>` | Adapter missing or rules wrong | `kubectl logs -n monitoring deploy/prometheus-adapter` |
| Custom metric exists but no values | Scrape path mismatch | `kubectl port-forward svc/api 8080:80 -n autoscaling-lab` |
| Prometheus has series, HPA cannot read | Rule mapping wrong | `kubectl get cm -n monitoring prometheus-adapter -o yaml` |
| Scale is delayed | Query window too long | inspect `rate()[2m]` vs shorter range |

## Part 4 - Event-driven autoscaling with KEDA
Use KEDA when work arrives through a queue and CPU is not a reliable leading signal.

### Event-driven flow
```text
Producer --> Queue length increases --> KEDA ScaledObject --> HPA --> worker replicas --> queue drains
```

### Worker deployment and ScaledObject
Use `manifests/keda-scaledobject.yaml` for the full worker Deployment and ScaledObject. The important KEDA contract is the queue trigger and the scale-to-zero behavior.

```yaml
kind: ScaledObject
spec:
  minReplicaCount: 0
  maxReplicaCount: 30
  triggers:
  - type: rabbitmq
    metadata:
      queueName: orders
      value: "20"
```

Apply it:
```bash
kubectl apply -f manifests/keda-scaledobject.yaml
kubectl get scaledobject -n autoscaling-lab
kubectl get hpa -n autoscaling-lab | grep keda
```

### Simulate queue growth
```bash
kubectl exec -it deploy/rabbitmq -n autoscaling-lab -- \
  rabbitmqadmin publish routing_key=orders payload='{"job":"1"}'

for i in $(seq 1 500); do
  kubectl exec deploy/rabbitmq -n autoscaling-lab -- \
    rabbitmqadmin publish routing_key=orders payload="{\"job\":$i}" >/dev/null
  if [ $((i % 50)) -eq 0 ]; then echo published:$i; fi
done
```

### Validate KEDA
```bash
kubectl describe scaledobject worker-rabbitmq -n autoscaling-lab
kubectl get hpa -n autoscaling-lab -w
kubectl get deploy worker -n autoscaling-lab -w
kubectl logs -n keda deploy/keda-operator --tail=100
```

### Expected observations
- Worker stays at 0 when the queue is empty.
- Replica count rises only when queue length crosses the threshold.
- KEDA creates and manages an HPA object for the worker.
- Scale-down waits for cooldown instead of dropping instantly.

## Part 5 - VPA recommendation mode
Use VPA in `Off` mode when you want safe recommendations without automated restarts.

Use `manifests/vpa-example.yaml` for the full VPA objects.

```yaml
kind: VerticalPodAutoscaler
spec:
  updatePolicy:
    updateMode: Off
```

Apply it:
```bash
kubectl apply -f manifests/vpa-example.yaml
kubectl get vpa -n autoscaling-lab
kubectl describe vpa api-vpa -n autoscaling-lab
```

### Interpreting recommendations
| Field | Meaning | Action |
|---|---|---|
| Lower Bound | minimum safe request | good for bursty low risk services |
| Target | recommended steady-state request | best default starting point |
| Upper Bound | defensive ceiling | useful before raising limits |
| Uncapped Target | raw model output | compare against policy caps |

### Guidance
- Do not let HPA and VPA both control CPU request on the same workload unless you understand the interaction.
- Common safe pattern: HPA on CPU, VPA on memory recommendations only, then humans update requests.
- Revisit VPA after major code, cache, or traffic pattern changes.

## Part 6 - Cluster Autoscaler configuration and testing
HPA only changes desired pod count. If no nodes can host new pods, cluster capacity must scale too.

### Simplified Cluster Autoscaler values
Use `manifests/cluster-autoscaler-values.yaml` for the Helm values and `manifests/cluster-autoscaler-burst-test.yaml` for the unschedulable pod test.

```yaml
autoDiscovery:
  clusterName: sre-lab
extraArgs:
  expander: least-waste
  scan-interval: 10s
```

### Unschedulable pod test
```yaml
kind: Deployment
metadata:
  name: inflate
spec:
  replicas: 10
```

Run the test:
```bash
kubectl apply -f manifests/cluster-autoscaler-burst-test.yaml
kubectl get pods -n autoscaling-lab -l app=inflate
kubectl describe pod -n autoscaling-lab -l app=inflate | egrep 'Unschedulable|Insufficient|FailedScheduling'
kubectl logs -n kube-system deploy/cluster-autoscaler --tail=200 | egrep 'scale|unschedulable|node group'
kubectl get nodes -w
```

### Expected observations
| Stage | Observation |
|---|---|
| Before scale-up | several `inflate` pods remain Pending |
| Autoscaler detection | logs mention unschedulable pods and chosen node group |
| After node joins | pending pods become Running |
| After deleting test | scale-down happens only after configured delay |

### If scale-up does not happen
| Check | Command | Healthy result |
|---|---|---|
| Pods are truly unschedulable | `kubectl describe pod <pending>` | `0/3 nodes are available` style reason |
| ASG / MIG tags | inspect cloud provider config | node group discovered |
| Resource requests realistic | `kubectl get deploy inflate -o yaml` | requests exceed current free capacity |
| Autoscaler RBAC | `kubectl auth can-i list nodes --as system:serviceaccount:kube-system:cluster-autoscaler` | yes |
| Max nodes not reached | check cloud autoscaling group | room to add nodes |

## Combined validation sequence
```bash
kubectl get hpa,vpa,scaledobject -n autoscaling-lab
kubectl describe hpa api-cpu-hpa -n autoscaling-lab
kubectl describe hpa api-rps-hpa -n autoscaling-lab
kubectl describe vpa api-vpa -n autoscaling-lab
kubectl describe scaledobject worker-rabbitmq -n autoscaling-lab
kubectl get events -n autoscaling-lab --sort-by=.lastTimestamp | tail -30
```

## Decision matrix
| Workload type | Best scaler | Primary signal | Notes |
|---|---|---|---|
| Stateless HTTP API | HPA | CPU or RPS | pair with requests tuned by VPA |
| Batch worker reading queue | KEDA | queue length / lag | enables scale to zero |
| Memory-heavy service | VPA recommendations | sustained usage | avoid HPA on memory alone without careful testing |
| Bursty multi-tenant platform | HPA + Cluster Autoscaler | CPU + pending pods | validate end-to-end latency |

## Prevention guidance
- Set realistic resource requests first; HPA math is poor if requests are wrong.
- Keep metrics scrape intervals and HPA sync periods aligned with reaction goals.
- Use stabilization windows to avoid flapping after short bursts.
- Test autoscaling with synthetic load before major launches.
- Record scale events alongside latency, saturation, and error rate dashboards.
- Treat autoscaling as a full stack: application, metrics, scheduler, and nodes.

## Cleanup
```bash
kubectl delete ns autoscaling-lab
```

## Lab exit checklist
- [ ] CPU HPA scaled under synthetic load.
- [ ] Prometheus Adapter exposed custom metrics consumed by HPA.
- [ ] KEDA created an HPA and scaled worker replicas from queue depth.
- [ ] VPA produced actionable recommendations.
- [ ] Cluster Autoscaler responded to unschedulable pods.
- [ ] Scale-up and scale-down behavior matched stabilization expectations.
