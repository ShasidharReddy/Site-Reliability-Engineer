# Kubernetes Reliability Troubleshooting Guide

## Purpose
Use this document for fast operational troubleshooting of the most common reliability failures in this module. Every scenario includes:
- symptoms
- exact commands
- likely root causes
- fixes
- validation steps
- prevention guidance

## Triage flow
```text
Incident reported
      |
      v
+------------------------+
| Is scope broad or      |
| workload-specific?     |
+-----------+------------+
            |
    +-------+--------+
    |                |
    v                v
 Broad impact      Single workload
    |                |
 check nodes,       check rollout,
 control plane,     pod state,
 storage, CNI       events, logs
    |                |
    +-------+--------+
            |
            v
+-----------------------------+
| Match against scenario      |
| and run targeted commands   |
+-----------------------------+
```

## Quick baseline command pack
```bash
kubectl get nodes -o wide
kubectl get pods -A | egrep -v 'Running|Completed'
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -50
kubectl top nodes
kubectl top pods -A --sort-by=memory | tail -20
kubectl top pods -A --sort-by=cpu | tail -20
kubectl get pvc -A
kubectl get hpa -A
kubectl get deploy,statefulset -A
```

## Scenario index
| Scenario | Typical signal | First command |
|---|---|---|
| Node memory pressure cascade eviction | many pods evicted on one node | `kubectl describe node <node>` |
| Deployment stuck in rollout | desired replicas never become available | `kubectl rollout status deploy/<name>` |
| HPA not scaling | load is high but replicas stay flat | `kubectl describe hpa <name>` |
| Repeated OOMKilled | restart count grows with reason 137 | `kubectl describe pod <pod>` |
| Service traffic not routing | DNS resolves but app unreachable | `kubectl get endpoints <svc>` |
| Cluster Autoscaler not scaling up | pending pods remain unschedulable | `kubectl logs deploy/cluster-autoscaler -n kube-system` |
| StatefulSet pod stuck Pending | ordinal cannot schedule or mount | `kubectl describe pod <pod>` |

---

## 1. Node memory pressure cascade eviction
### Symptoms
- Alerts show `MemoryPressure=True` on one or more nodes.
- Many best-effort or burstable pods are evicted from the same node.
- Application errors spike across several namespaces.
- New pods may schedule elsewhere but latency remains elevated.

### Investigation diagram
```text
High memory on node
      |
      +--> kubelet sets MemoryPressure=True
      |
      +--> eviction manager starts reclaiming
      |
      +--> pods evicted by QoS priority
      |
      +--> replicas reschedule elsewhere or remain Pending
```

### Commands
```bash
NODE=<node>
kubectl describe node $NODE
kubectl get pods -A -o wide --field-selector spec.nodeName=$NODE
kubectl top node $NODE
kubectl top pods -A --field-selector spec.nodeName=$NODE --sort-by=memory
kubectl get events -A --sort-by=.lastTimestamp | egrep "$NODE|Evicted|MemoryPressure" | tail -30
```

### Expected observations
| Observation | Meaning |
|---|---|
| `MemoryPressure=True` | kubelet is under sustained memory stress |
| `Evicted` reason on many pods | kubelet eviction manager acted |
| high usage by one or two pods | likely noisy neighbor or under-sized node |
| many low-request pods packed on node | scheduler underestimated actual demand |

### Likely causes
- container memory leak
- requests too low for real usage
- insufficient system reservation on the node
- spike from log processing, cache growth, or batch jobs

### Immediate fix
```bash
kubectl cordon $NODE
kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data --force
kubectl scale deploy/<offender> -n <ns> --replicas=0
kubectl patch deploy/<offender> -n <ns> --type='json' \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"1Gi"}]'
```

### Validation
- [ ] `MemoryPressure` clears on the node.
- [ ] Evicted workloads are rescheduled and become Ready.
- [ ] Offending pod memory trend stabilizes.
- [ ] No additional eviction events appear for 10-15 minutes.

### Prevention
- set realistic memory requests
- use VPA recommendation mode for memory tuning
- reserve memory for kubelet and system daemons
- alert on node memory headroom, not just pod restarts

---

## 2. Deployment stuck in rollout
### Symptoms
- `kubectl rollout status` hangs or times out.
- Available replicas stay below desired replicas.
- One new ReplicaSet exists but pods are not becoming Ready.

### Example inspection manifest
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0
minReadySeconds: 10
progressDeadlineSeconds: 600
```

### Commands
```bash
NS=<ns>
DEPLOY=<name>
kubectl rollout status deploy/$DEPLOY -n $NS
kubectl describe deploy/$DEPLOY -n $NS
kubectl get rs -n $NS -l app=<label>
kubectl get pods -n $NS -l app=<label> -o wide
kubectl describe pod -n $NS <new-pod>
kubectl logs -n $NS <new-pod> --previous --tail=100
kubectl get events -n $NS --sort-by=.lastTimestamp | tail -30
```

### Decision points
| Signal | Interpretation | Fix |
|---|---|---|
| readiness probe failing | pod is running but not ready | fix probe path, port, thresholds |
| image pull failing | pod never starts | correct image or secret |
| no capacity | new pod Pending | reduce requests or add nodes |
| old pods cannot terminate | PDB or finalizer blocking | inspect PDB, graceful shutdown |
| app crashes on startup | CrashLoopBackOff | rollback or fix config |

### Immediate fix commands
```bash
kubectl rollout undo deploy/$DEPLOY -n $NS
kubectl patch deploy/$DEPLOY -n $NS --type='json' \
  -p='[{"op":"replace","path":"/spec/progressDeadlineSeconds","value":900}]'
kubectl set image deploy/$DEPLOY -n $NS app=ghcr.io/org/app:stable
```

### Expected observations
- Healthy rollout: new ReplicaSet increases while old one decreases.
- Stuck rollout: desired and available counts diverge for several minutes.
- If `maxUnavailable: 0`, any readiness issue can freeze progress.

### Prevention
- verify readiness probes in staging with rollout settings identical to production
- keep rollback tags available
- monitor `ProgressDeadlineExceeded`

---

## 3. HPA not scaling
### Symptoms
- CPU or request rate is high, but replicas do not increase.
- `kubectl get hpa` shows `unknown` or old metric values.
- Pending pods may already exist and HPA appears ineffective.

### Autoscaling flow
```text
Metric source --> metrics API --> HPA control loop --> desired replicas --> scheduler --> nodes
```

### Commands
```bash
NS=<ns>
HPA=<name>
kubectl get hpa $HPA -n $NS
kubectl describe hpa $HPA -n $NS
kubectl top pods -n $NS
kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes | head
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1 | head || true
kubectl get deploy -n $NS <target> -o yaml | sed -n '/resources:/,/env:/p'
```

### Troubleshooting table
| Symptom | Likely cause | Fix |
|---|---|---|
| target shows `<unknown>` | metrics-server or adapter issue | restore metrics pipeline |
| utilization low despite load | requests too high or app not CPU-bound | switch metric or tune requests |
| desired replicas increases but pods Pending | no cluster capacity | fix Cluster Autoscaler or add nodes |
| custom metric empty | adapter rule or scrape issue | fix Prometheus series mapping |
| scale flaps | stabilization too low | tune HPA behavior |

### Validation commands
```bash
kubectl get hpa -n $NS -w
kubectl get deploy -n $NS <target> -w
kubectl get events -n $NS --sort-by=.lastTimestamp | tail -20
```

### Prevention
- tune resource requests before enabling HPA
- test HPA with load and record observed scale latency
- monitor metrics API health continuously

---

## 4. Repeated OOMKilled
### Symptoms
- same workload restarts on a schedule or under known peaks
- exit code 137 or `OOMKilled`
- latency spikes before restart and recovers briefly after restart

### Commands
```bash
NS=<ns>
POD=<pod>
kubectl describe pod $POD -n $NS | sed -n '/Last State:/,/Events:/p'
kubectl top pod $POD -n $NS --containers
kubectl get pod $POD -n $NS -o jsonpath='{.spec.containers[*].resources}'
kubectl logs $POD -n $NS --previous --tail=200
kubectl get events -n $NS --sort-by=.lastTimestamp | grep OOM
```

### Root-cause table
| Pattern | Interpretation | Next step |
|---|---|---|
| every 6 hours | cron, batch, compaction, cache rollover | inspect scheduled jobs or timed tasks |
| during traffic spikes | limit too low or leak under load | increase limit, profile memory |
| only on one node | node pressure contributes | inspect node memory and co-tenants |
| after deploy | regression in code or config | compare version and rollback |

### Fixes
```bash
kubectl patch deploy/<name> -n $NS --type='json' \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"1Gi"}]'
kubectl rollout restart deploy/<name> -n $NS
kubectl apply -f manifests/vpa-example.yaml
```

### Expected observations
- higher limit without request update may stop kills but worsen node packing
- better request value improves scheduling quality
- if OOM persists after raising limit, suspect leak rather than sizing only

### Prevention
- profile memory in pre-prod
- use VPA recommendation mode
- alert on restart count and working set growth

---

## 5. Service traffic not routing
### Symptoms
- service DNS resolves but connection times out or is refused
- only some requests fail, or all traffic fails after rollout
- ingress is healthy but backend service appears dead

### Commands
```bash
NS=<ns>
SVC=<service>
kubectl get svc $SVC -n $NS -o wide
kubectl get endpoints $SVC -n $NS -o wide
kubectl get endpointslice -n $NS -l kubernetes.io/service-name=$SVC
kubectl get pods -n $NS --show-labels
kubectl exec -n $NS deploy/<client> -- nslookup $SVC.$NS.svc.cluster.local
kubectl exec -n $NS deploy/<client> -- curl -v --connect-timeout 3 http://$SVC.$NS.svc.cluster.local:<port>
```

### Common causes
| Observation | Root cause | Fix |
|---|---|---|
| no endpoints | selector mismatch or pods not Ready | fix labels or readiness |
| endpoints exist but timeout | NetworkPolicy or pod not listening | inspect netpol and targetPort |
| connection refused | wrong targetPort | align service and container port |
| intermittent failure | subset of bad pods | inspect pod readiness and logs |

### Validation checklist
- [ ] service selector matches pod labels
- [ ] endpoints exist and map to Ready pods
- [ ] client can resolve DNS
- [ ] client reaches correct port
- [ ] no policy is silently blocking traffic

### Prevention
- keep services simple
- validate selectors in CI or review
- expose metrics for endpoint count and ready endpoints

---

## 6. Cluster Autoscaler not scaling up
### Symptoms
- pending pods remain for several minutes
- scheduler reports `Insufficient cpu` or `Insufficient memory`
- HPA desired replicas rise but workloads remain unscheduled

### Commands
```bash
kubectl get pods -A | grep Pending
kubectl describe pod <pending-pod>
kubectl logs -n kube-system deploy/cluster-autoscaler --tail=200 | egrep 'unschedulable|scale|node group'
kubectl get nodes -o wide
```

### Troubleshooting table
| Symptom | Likely cause | Fix |
|---|---|---|
| autoscaler ignores pod | requests impossible or node selector too strict | fix pod spec |
| logs show max size reached | node group limit hit | raise max nodes |
| no suitable node group | labels/taints mismatch | align node group and pod constraints |
| pending pod uses local PVC | autoscaler cannot solve placement | redesign storage or topology |
| autoscaler lacks cloud discovery | missing tags or config | fix provider integration |

### Example unschedulable test manifest
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
  namespace: autoscaling-lab
spec:
  replicas: 5
  selector:
    matchLabels:
      app: inflate
  template:
    metadata:
      labels:
        app: inflate
    spec:
      containers:
      - name: pause
        image: registry.k8s.io/pause:3.9
        resources:
          requests:
            cpu: 1500m
            memory: 2Gi
```

### Prevention
- test autoscaler after node group changes
- keep node labels and taints documented
- monitor unschedulable pod age and autoscaler decisions

---

## 7. StatefulSet pod stuck Pending
### Symptoms
- specific ordinal such as `db-2` stays Pending
- PVC remains `Pending` or bound to wrong topology
- only one replica blocks the whole rollout

### Commands
```bash
NS=<ns>
POD=<stateful-pod>
kubectl describe pod $POD -n $NS
kubectl get pvc -n $NS
kubectl describe pvc -n $NS <claim>
kubectl get storageclass
kubectl get pv
kubectl get nodes --show-labels
```

### Common causes
| Cause | Evidence | Fix |
|---|---|---|
| unbound PVC | claim Pending | fix StorageClass or capacity |
| zone/affinity conflict | pod requires zone without node | align node pools and storage topology |
| quota exceeded | PVC or storage quota hit | raise quota or clean unused claims |
| strict anti-affinity | no eligible node for ordinal | relax affinity or add nodes |

### Expected observations
- StatefulSet often stalls on the first blocked ordinal.
- Storage problems appear in PVC events before pod events.
- Topology conflicts are common in multi-zone clusters.

### Prevention
- use StorageClasses tested with StatefulSets
- monitor PVC provisioning latency
- document zone and anti-affinity rules for stateful workloads

---

## Final validation block
```bash
kubectl get nodes
kubectl get pods -A | egrep -v 'Running|Completed'
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -30
kubectl get deploy,statefulset,hpa -A
kubectl get pvc -A
```

## Operational checklist
- [ ] Symptom classified correctly.
- [ ] Root cause confirmed from events, logs, and metrics.
- [ ] Fix applied with minimal blast radius.
- [ ] Workload and dependencies validated after fix.
- [ ] Prevention action captured for later follow-up.
