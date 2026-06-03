# Lab 06: Kubernetes Debugging Runbook

## Purpose
Use this runbook when a Kubernetes workload is unhealthy, unschedulable, unreachable, or causing cluster instability. It is designed for incident response, not theory-first learning.

## Core principles
- Start wide: cluster health, node health, and recent warnings.
- Narrow quickly: exact namespace, workload, pod, node, and event.
- Trust evidence in this order: events, describe output, logs, metrics, then assumptions.
- Always separate application failure from platform failure.

## Universal debug flow
```text
Alert or user report
       |
       v
+---------------------+
| What is failing?    |
| Pod / Service / Node|
+----------+----------+
           |
           v
+-------------------------------+
| Is scope single app or broad? |
+-----------+-------------------+
            |
   +--------+--------+
   |                 |
   v                 v
Single workload     Many workloads
   |                 |
   |                 +--> check nodes, CNI, DNS, API server, etcd
   |
   +--> get pod state, events, logs, metrics
            |
            v
+-----------------------------+
| Classify symptom            |
| CrashLoop / Pending / Pull  |
| Routing / NotReady / OOM    |
+-------------+---------------+
              |
              v
+-------------------------------------------+
| Run issue-specific branch in this runbook |
+-------------------------------------------+
```

## Fast triage commands
```bash
kubectl get nodes -o wide
kubectl get pods -A | egrep -v 'Running|Completed'
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -50
kubectl top nodes
kubectl top pods -A --sort-by=memory | tail -20
kubectl top pods -A --sort-by=cpu | tail -20
kubectl get pvc -A
kubectl get hpa -A
```

## Symptom-to-command map
| Symptom | First command | Next command |
|---|---|---|
| `CrashLoopBackOff` | `kubectl describe pod` | `kubectl logs --previous` |
| `OOMKilled` | `kubectl describe pod` | `kubectl top pod --containers` |
| `Pending` | `kubectl describe pod` | `kubectl describe nodes` |
| `ImagePullBackOff` | `kubectl describe pod` | inspect image, secret, registry |
| Service unreachable | `kubectl get endpoints` | `kubectl exec ... curl` |
| Node `NotReady` | `kubectl describe node` | node kubelet logs |
| Many apps failing | `kubectl get events -A` | check DNS, CNI, control plane |
| API errors or timeouts | `kubectl get componentstatuses` if available | inspect API server and etcd |

## Golden collection block
Run this before changing anything:
```bash
NS=default
POD=<pod>
NODE=$(kubectl get pod $POD -n $NS -o jsonpath='{.spec.nodeName}')

kubectl get pod $POD -n $NS -o wide
kubectl describe pod $POD -n $NS
kubectl logs $POD -n $NS --all-containers --tail=200
kubectl logs $POD -n $NS --all-containers --previous --tail=200
kubectl get events -n $NS --sort-by=.lastTimestamp | tail -30
kubectl top pod $POD -n $NS --containers || true
kubectl describe node $NODE
```

## 1. CrashLoopBackOff
### What it means
The container starts, exits, and kubelet backs off before restarting it again.

### Common causes
| Cause | Evidence | Fix |
|---|---|---|
| application startup failure | exit code 1, stack trace | fix config or app bug |
| bad command or args | `exec format error`, unknown flag | correct image entrypoint or args |
| missing secret/config | env var or file not found | restore secret/configmap mount |
| failing liveness probe | restarts after probe failures | tune probe path, port, thresholds |
| OOMKilled disguised as loop | exit code 137 | increase memory or reduce usage |

### Debug path
```text
CrashLoopBackOff
    |
    +--> Check Last State and exit code
    |
    +--> Check previous logs
    |
    +--> Check probe failures in events
    |
    +--> Check secret/config mounts
    |
    +--> Check resource limits and OOM evidence
```

### Commands
```bash
kubectl describe pod $POD -n $NS | sed -n '/Containers:/,/Conditions:/p'
kubectl describe pod $POD -n $NS | sed -n '/Last State:/,/Events:/p'
kubectl logs $POD -n $NS --previous --tail=200
kubectl get events -n $NS --field-selector involvedObject.name=$POD --sort-by=.lastTimestamp
kubectl get pod $POD -n $NS -o yaml | sed -n '/livenessProbe:/,/resources:/p'
kubectl get pod $POD -n $NS -o yaml | sed -n '/env:/,/volumeMounts:/p'
```

### Expected observations
- App bug: logs show exception or invalid config at startup.
- Probe issue: events show repeated `Liveness probe failed` before restart.
- Secret issue: file or env value missing during init.
- Resource issue: last termination reason is `OOMKilled` or exit code `137`.

### Fix patterns
```bash
kubectl rollout history deploy/<deploy> -n $NS
kubectl rollout undo deploy/<deploy> -n $NS
kubectl set env deploy/<deploy> -n $NS FEATURE_FLAG=false
kubectl patch deploy/<deploy> -n $NS --type='json' \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/initialDelaySeconds","value":30}]'
```

### Prevention
- Add startup probes for slow boot applications.
- Keep liveness probes strict enough to detect deadlock, not slow startup.
- Fail fast on config validation with clear logs.
- Store release metadata so rollout rollback is easy.

## 2. OOMKilled diagnosis
### What it means
The Linux kernel or kubelet terminated the container because it crossed a memory boundary.

### Commands
```bash
kubectl describe pod $POD -n $NS | sed -n '/Last State:/,/Ready:/p'
kubectl top pod $POD -n $NS --containers
kubectl get pod $POD -n $NS -o jsonpath='{.spec.containers[*].resources}'
kubectl get pod $POD -n $NS -o jsonpath='{.status.containerStatuses[*].lastState.terminated.reason}'
kubectl get events -n $NS --field-selector involvedObject.name=$POD --sort-by=.lastTimestamp
```

### Decision table
| Observation | Interpretation | Action |
|---|---|---|
| usage approaches limit quickly | limit too low | raise limit after confirming node headroom |
| request much lower than actual usage | scheduler underestimates pod size | raise request or use VPA recommendations |
| usage grows every few hours | likely memory leak | collect heap/profile and escalate |
| node memory pressure across many pods | noisy neighbor or overcommit | inspect node-wide usage and evictions |

### Useful follow-up
```bash
NODE=$(kubectl get pod $POD -n $NS -o jsonpath='{.spec.nodeName}')
kubectl top node $NODE
kubectl describe node $NODE | sed -n '/Allocated resources:/,/Events:/p'
kubectl get pods -A --field-selector spec.nodeName=$NODE -o wide
```

### Prevention
- Use realistic requests and limits.
- Keep memory dashboards with 95th and 99th percentile views.
- Use VPA recommendation mode to tune requests.
- Alert on rising restart count before a service hard-fails.

## 3. Pending pods
### High-level flow
```text
Pending pod
   |
   +--> FailedScheduling event?
   |       |
   |       +--> Insufficient CPU/memory -> cluster full or requests too high
   |       +--> node selector / affinity mismatch -> no eligible nodes
   |       +--> taints not tolerated -> add toleration or move workload
   |       +--> PVC unbound -> storage issue
   |       +--> quota exceeded -> namespace governance issue
   |
   +--> No scheduling event?
           |
           +--> API/controller delay or admission webhook problem
```

### Core commands
```bash
kubectl describe pod $POD -n $NS
kubectl get events -n $NS --field-selector involvedObject.name=$POD --sort-by=.lastTimestamp
kubectl get pod $POD -n $NS -o yaml | sed -n '/nodeSelector:/,/tolerations:/p'
kubectl describe quota -n $NS
kubectl get pvc -n $NS
kubectl describe pvc -n $NS
kubectl describe nodes | sed -n '/Allocated resources:/,/Events:/p'
```

### Pending due to insufficient resources
Evidence:
```bash
kubectl describe pod $POD -n $NS | egrep 'Insufficient cpu|Insufficient memory|FailedScheduling'
kubectl top nodes
```
Fix:
- reduce requests
- add capacity
- allow Cluster Autoscaler to scale

### Pending due to affinity or nodeSelector
Evidence:
```bash
kubectl get pod $POD -n $NS -o yaml | sed -n '/affinity:/,/tolerations:/p'
kubectl get nodes --show-labels | head
```
Fix:
- correct labels
- relax affinity
- update node pool labels

### Pending due to PVC
Evidence:
```bash
kubectl get pvc -n $NS
kubectl describe pvc <claim> -n $NS
kubectl get storageclass
```
Fix:
- restore storage class
- increase capacity
- fix access mode mismatch

### Pending due to quota or LimitRange
Evidence:
```bash
kubectl describe quota -n $NS
kubectl describe limitrange -n $NS
```
Fix:
- reduce requests
- raise quota
- move workload to correct namespace

### Prevention
- keep namespace quota dashboards
- standardize node labels and affinity policies
- monitor storage provisioning latency
- test autoscaler with realistic requests

## 4. ImagePullBackOff / ErrImagePull
### Typical causes
| Cause | Example evidence | Fix |
|---|---|---|
| tag missing | `manifest unknown` | correct tag or publish image |
| registry auth failed | `unauthorized` | fix imagePullSecret |
| DNS/network to registry | timeouts | fix node egress or proxy |
| rate limiting | `too many requests` | mirror image or authenticate |

### Commands
```bash
kubectl describe pod $POD -n $NS | sed -n '/Events:/,$p'
kubectl get pod $POD -n $NS -o jsonpath='{.spec.containers[*].image}'
kubectl get sa default -n $NS -o yaml | sed -n '/imagePullSecrets:/,/secrets:/p'
kubectl get secret -n $NS
```

### Expected observations
- Bad tag: immediate `ErrImagePull` with manifest error.
- Bad credentials: repeated unauthorized events.
- Network issue: timeouts from multiple nodes, not just one pod.

### Prevention
- pin images deliberately
- validate image existence in CI
- keep registry auth rotation documented

## 5. Service not routing traffic
### Service flow
```text
Client --> DNS --> Service ClusterIP --> EndpointSlice/Endpoints --> Pod IP --> App listens on targetPort
```

### Debug sequence
```bash
SVC=<service>
kubectl get svc $SVC -n $NS -o wide
kubectl get endpoints $SVC -n $NS -o wide
kubectl get endpointslice -n $NS -l kubernetes.io/service-name=$SVC
kubectl get svc $SVC -n $NS -o yaml | sed -n '/selector:/,/type:/p'
kubectl get pods -n $NS --show-labels
kubectl exec -n $NS deploy/<client> -- nslookup $SVC.$NS.svc.cluster.local
kubectl exec -n $NS deploy/<client> -- curl -v --connect-timeout 3 http://$SVC.$NS.svc.cluster.local:<port>
```

### Root causes
| Symptom | Evidence | Fix |
|---|---|---|
| no endpoints | selector mismatch or pods not Ready | fix labels or readiness |
| DNS resolves, timeout | NetworkPolicy or app not listening | inspect policy and container port |
| connection refused | targetPort mismatch | align Service and container ports |
| only some requests fail | subset of bad pods | check readiness and pod logs |

### Prevention
- keep service selectors simple
- use readiness probes so broken pods do not receive traffic
- verify ports after each deployment change

## 6. Node NotReady
### What to inspect first
```bash
kubectl describe node $NODE
kubectl get events --field-selector involvedObject.kind=Node,involvedObject.name=$NODE --sort-by=.lastTimestamp
```

### Node issue matrix
| Condition | Likely cause | First node-level check |
|---|---|---|
| `MemoryPressure=True` | memory exhaustion | `free -h`, kubelet logs |
| `DiskPressure=True` | image/log buildup | `df -h`, container runtime cleanup |
| `PIDPressure=True` | process explosion | `ps -eLf | wc -l` |
| `Ready=False` | kubelet stopped, network, cert | `systemctl status kubelet` |

### Node commands if SSH or node shell is available
```bash
ssh <node>
systemctl status kubelet
journalctl -u kubelet -n 200 --no-pager
df -h
free -h
crictl ps
crictl images
```

### Expected observations
- Kubelet crash: node heartbeats stop, pods drift to `Unknown`.
- Disk pressure: image pulls fail and eviction begins.
- Memory pressure: best-effort pods evicted first.

### Prevention
- alert on node conditions before workloads fail
- rotate logs and prune unused images
- reserve system resources with kubelet configuration

## 7. etcd and control plane issues
Use this section when many controllers misbehave, API latency spikes, or writes fail.

### Signals
| Signal | What it suggests |
|---|---|
| `kubectl` times out | API server or network issue |
| leader election flapping | API or etcd instability |
| many stale objects/events | controller backlog |
| control plane warnings | etcd disk or quorum issue |

### Commands
```bash
kubectl get --raw='/readyz?verbose'
kubectl get --raw='/livez?verbose'
kubectl get apiservices
kubectl get events -A --sort-by=.lastTimestamp | tail -50
kubectl -n kube-system get pods -o wide | egrep 'etcd|kube-apiserver|controller|scheduler'
kubectl -n kube-system logs etcd-$(hostname) --tail=200  # if control plane access pattern matches
```

### etcd-specific clues
| Clue | Interpretation | Response |
|---|---|---|
| `database space exceeded` | backend quota exhausted | compact/defrag or expand storage |
| fsync latency high | storage too slow | move etcd to faster disk |
| quorum loss | member down or network partition | restore member connectivity urgently |
| leader changes repeatedly | unstable network/storage | inspect control-plane health |

### Prevention
- keep etcd on fast, isolated disks
- monitor fsync latency, DB size, leader changes, and API latency
- back up etcd and test restore procedures

## 8. Useful one-liners
```bash
# non-running pods
kubectl get pods -A | egrep -v 'Running|Completed'

# pods with restart count > 3
kubectl get pods -A --no-headers | awk '$5+0 > 3 {print $1,$2,$5}'

# warning events newest last
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -40

# top memory consumers
kubectl top pods -A --sort-by=memory | tail -20

# top CPU consumers
kubectl top pods -A --sort-by=cpu | tail -20

# show pods on one node
NODE=<node>
kubectl get pods -A -o wide --field-selector spec.nodeName=$NODE

# services without endpoints
for s in $(kubectl get svc -A --no-headers | awk '{print $1"/"$2}'); do \
  ns=${s%/*}; name=${s#*/}; \
  ep=$(kubectl get endpoints $name -n $ns -o jsonpath='{.subsets}' 2>/dev/null); \
  [ -z "$ep" ] && echo "$ns/$name has no endpoints"; \
done

# pending PVCs
kubectl get pvc -A | egrep -v 'Bound|STATUS'
```

## Runbook checklist
- [ ] Determine if impact is one workload or many.
- [ ] Collect pod, events, logs, metrics, and node context.
- [ ] Confirm exact failure mode before applying a fix.
- [ ] Validate the fix with rollout status, probes, and client traffic.
- [ ] Capture root cause, blast radius, and prevention work.

## Expected investigator behavior
- Do not restart everything first.
- Do not delete evidence before collecting logs and events.
- Do not blame the application until service, scheduling, and node checks are done.
- Do not trust a single signal when events and metrics disagree.

## Prevention summary
| Failure class | Best prevention |
|---|---|
| CrashLoopBackOff | startup probe tuning, config validation, safe rollback |
| OOMKilled | better requests/limits, profiling, VPA recommendations |
| Pending pods | quota review, autoscaler coverage, storage monitoring |
| Image pull issues | CI validation and credential hygiene |
| Service routing issues | readiness probes and selector reviews |
| Node failures | node condition alerts and system reservations |
| Control plane issues | etcd monitoring, backups, and latency alerts |
