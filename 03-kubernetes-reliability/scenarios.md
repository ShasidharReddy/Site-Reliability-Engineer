# Kubernetes Reliability Scenarios

## Purpose
These scenarios simulate realistic SRE incidents. Each scenario is written like an operational drill with:
- context
- symptoms
- investigation steps
- exact commands
- expected observations
- resolution
- prevention guidance

## How to use this file
- Run the commands in a disposable lab cluster.
- Assign an incident commander and a driver.
- Time-box triage to 15 minutes before broader escalation.
- Compare your findings with the expected observations.

## Shared incident flow
```text
Page received
    |
    v
Confirm blast radius
    |
    v
Form hypothesis from metrics, events, and recent changes
    |
    v
Run targeted kubectl checks
    |
    v
Apply smallest safe fix
    |
    v
Validate traffic, health, and scale
    |
    v
Capture prevention action
```

## Scenario 1: Black Friday scale from 5 to 50 replicas in 2 minutes
### Story
An e-commerce API normally runs at 5 replicas. A promotional campaign starts, request volume jumps sharply, and the SLO requires scaling to 50 replicas within 2 minutes without causing a backlog or node starvation.

### Architecture view
```text
Users --> Ingress --> api Deployment --> HPA --> scheduler --> nodes --> Cluster Autoscaler
                                 |
                                 +--> Prometheus / metrics-server
```

### Starting point
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
  minReplicas: 5
  maxReplicas: 50
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
        periodSeconds: 15
      - type: Pods
        value: 10
        periodSeconds: 15
```

### Symptoms
- request rate spikes by 10x
- latency climbs above SLO
- HPA starts scaling, but some pods remain Pending
- node utilization hits 85-90%

### Investigation steps
```bash
kubectl get hpa api-hpa -n production -w
kubectl get deploy api -n production -w
kubectl top pods -n production -l app=api
kubectl top nodes
kubectl get pods -n production | grep Pending
kubectl describe pod -n production <pending-pod>
kubectl logs -n kube-system deploy/cluster-autoscaler --tail=200 | egrep 'scale|unschedulable|node group'
```

### Expected observations
| Observation | Meaning |
|---|---|
| HPA desired replicas climbs rapidly | HPA loop is healthy |
| `FailedScheduling` shows insufficient CPU | pods need more nodes |
| autoscaler logs show scale-up decision | node expansion path is healthy |
| new nodes join within 1-2 minutes | cluster capacity catches up |

### Resolution steps
1. Confirm HPA behavior is aggressive enough for the event.
2. Verify resource requests are not too large for node shape.
3. Confirm Cluster Autoscaler max node count can absorb the burst.
4. If scaling is too slow, temporarily raise `maxReplicas` and node group limits.

```bash
kubectl patch hpa api-hpa -n production --type merge -p '{"spec":{"maxReplicas":60}}'
gh issue list >/dev/null 2>&1 || true
kubectl get nodes -w
kubectl rollout status deploy/api -n production
```

### Validation checklist
- [ ] replicas reached target range
- [ ] pending pods became Running
- [ ] p95 latency recovered
- [ ] no mass evictions occurred on new nodes
- [ ] error rate returned to baseline

### Prevention
- rehearse flash-sale load in pre-production
- keep node group headroom or use overprovisioning pods
- tune HPA scale-up policy for steep bursts
- ensure image pull time is low enough for burst capacity

---

## Scenario 2: Recurring OOMKilled every 6 hours
### Story
A worker deployment restarts almost exactly every 6 hours. The business impact is moderate at first, but queue lag grows during each restart window.

### Timeline sketch
```text
00:00 normal
06:00 memory rises --> container OOMKilled --> restart --> queue lag spikes
12:00 repeats
18:00 repeats
```

### Symptoms
- restart count increases predictably
- exit code 137
- queue length rises before each restart
- node memory is otherwise healthy

### Investigation steps
```bash
NS=production
APP=worker
POD=$(kubectl get pod -n $NS -l app=$APP -o jsonpath='{.items[0].metadata.name}')

kubectl describe pod $POD -n $NS | sed -n '/Last State:/,/Events:/p'
kubectl top pod $POD -n $NS --containers
kubectl logs $POD -n $NS --previous --tail=200
kubectl get cronjob -n $NS
kubectl get events -n $NS --sort-by=.lastTimestamp | tail -30
kubectl get deploy/$APP -n $NS -o yaml | sed -n '/resources:/,/env:/p'
```

### Expected observations
| Observation | Meaning |
|---|---|
| logs show batch compaction or sync work before death | memory surge tied to periodic task |
| request much lower than peak usage | scheduler underestimates workload |
| node healthy | issue isolated to workload, not host pressure |

### Example fix manifest
```yaml
resources:
  requests:
    cpu: 250m
    memory: 768Mi
  limits:
    cpu: "1"
    memory: 1536Mi
```

### Resolution steps
```bash
kubectl patch deploy/worker -n $NS --type='json' \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"768Mi"},{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"1536Mi"}]'
kubectl rollout restart deploy/worker -n $NS
kubectl rollout status deploy/worker -n $NS
kubectl apply -f manifests/vpa-example.yaml
```

### Validation checklist
- [ ] no OOMKilled event in the next 6-hour cycle
- [ ] queue lag remains stable
- [ ] working set stays below new memory limit
- [ ] VPA recommendation aligns with new request range

### Prevention
- profile background jobs separately from steady-state traffic
- alarm on cyclic restart patterns, not just total restart count
- use VPA recommendation mode for memory-heavy workers

---

## Scenario 3: Rollout stuck at 50%
### Story
A new backend release is deployed during business hours. The Deployment moves halfway, then progress stops. Half the pods are on the new version, half remain old.

### Rollout picture
```text
old ReplicaSet: ██████----
new ReplicaSet: ----██████
                     ^
          stuck here because new pods not Ready
```

### Symptoms
- `kubectl rollout status` reports timeout
- new pods are Running but not Ready, or crash repeatedly
- traffic may be split across old and new versions

### Investigation steps
```bash
NS=production
DEPLOY=backend
kubectl rollout status deploy/$DEPLOY -n $NS
kubectl describe deploy/$DEPLOY -n $NS
kubectl get rs -n $NS -l app=backend
kubectl get pods -n $NS -l app=backend -o wide
kubectl describe pod -n $NS <new-pod>
kubectl logs -n $NS <new-pod> --tail=200
kubectl get events -n $NS --sort-by=.lastTimestamp | tail -30
```

### Expected observations
| Observation | Meaning |
|---|---|
| readiness probe fails | application started but is not healthy enough for traffic |
| `ImagePullBackOff` on new pods | bad image or registry auth |
| `CrashLoopBackOff` only on new version | release regression |
| `ProgressDeadlineExceeded` | deployment controller gave up waiting |

### Resolution steps
```bash
kubectl rollout undo deploy/$DEPLOY -n $NS
kubectl set image deploy/$DEPLOY -n $NS backend=ghcr.io/org/backend:stable
kubectl rollout status deploy/$DEPLOY -n $NS
```

### Alternative fix if only probe is wrong
```bash
kubectl patch deploy/$DEPLOY -n $NS --type='json' \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/initialDelaySeconds","value":20}]'
```

### Validation checklist
- [ ] rollout completes
- [ ] service endpoints contain only Ready pods
- [ ] error rate drops to baseline
- [ ] new version passes smoke tests

### Prevention
- test readiness probes against the release candidate image
- use canary or progressive delivery for high-risk services
- monitor rollout progress as a first-class deployment metric

---

## Scenario 4: All pods evicted from one node
### Story
A node suddenly loses all application pods. Some reschedule, some remain Pending, and the incident appears random until you inspect node conditions.

### Failure flow
```text
Node issue
   |
   +--> kubelet sets pressure or NotReady condition
   |
   +--> pods evicted or become Unknown
   |
   +--> replicas rescheduled elsewhere
   |
   +--> cluster may run short on capacity
```

### Symptoms
- multiple namespaces report pod loss at once
- one node shows `NotReady`, `MemoryPressure`, or `DiskPressure`
- evicted pods may not come back if capacity is full

### Investigation steps
```bash
NODE=<node>
kubectl describe node $NODE
kubectl get pods -A -o wide --field-selector spec.nodeName=$NODE
kubectl get events -A --sort-by=.lastTimestamp | egrep "$NODE|Evicted|NotReady|Pressure" | tail -40
kubectl top node $NODE || true
kubectl get nodes -w
```

### Expected observations
| Observation | Meaning |
|---|---|
| `DiskPressure=True` | image or log growth exhausted disk |
| `MemoryPressure=True` | eviction due to low memory |
| `Ready=False` | kubelet or network failure |
| many pods from one node rescheduled | blast radius is node-scoped |

### Resolution steps
1. Cordon the node to stop new placements.
2. Drain if the node is reachable and unhealthy.
3. Restore capacity if replacements remain Pending.
4. Investigate node-level logs and runtime state.

```bash
kubectl cordon $NODE
kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data --force
kubectl get pods -A | grep Pending
kubectl logs -n kube-system deploy/cluster-autoscaler --tail=100 | egrep 'scale|unschedulable'
```

### Validation checklist
- [ ] workloads rescheduled on healthy nodes
- [ ] no new pods land on the bad node
- [ ] node condition root cause identified
- [ ] capacity is sufficient after drain

### Prevention
- alert on node conditions before eviction begins
- keep image cleanup and log rotation healthy
- reserve node resources for system daemons
- regularly rehearse node drain procedures

---

## Summary command bank
```bash
kubectl get nodes -o wide
kubectl get pods -A | egrep -v 'Running|Completed'
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -40
kubectl top nodes
kubectl top pods -A --sort-by=memory | tail -20
kubectl get hpa -A
kubectl get pvc -A
kubectl rollout status deploy/<name> -n <ns>
kubectl describe hpa <name> -n <ns>
kubectl logs -n kube-system deploy/cluster-autoscaler --tail=200
```

## Scenario completion checklist
- [ ] blast radius identified
- [ ] correct scenario matched
- [ ] commands executed and evidence collected
- [ ] minimal safe fix applied
- [ ] service health validated after fix
- [ ] prevention item recorded
