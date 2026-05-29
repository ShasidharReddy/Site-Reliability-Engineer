# Kubernetes Reliability — Theory

## 1. Kubernetes Architecture & Failure Modes

### 1.1 Control Plane Components
| Component | Role | Failure Impact |
|-----------|------|---------------|
| **API Server** | All K8s operations go through here | No kubectl, no new pods, existing pods keep running |
| **etcd** | Distributed KV store for all cluster state | Total cluster brain damage — most critical component |
| **Scheduler** | Assigns pods to nodes | New pods stay Pending indefinitely |
| **Controller Manager** | Runs reconciliation loops (Deployment, ReplicaSet, etc.) | No automatic healing, no scaling |
| **kubelet** | Node agent — manages pods on each node | Pods on that node not managed; new containers can't start |
| **kube-proxy** | Network rules for Services | Service routing breaks on that node |

### 1.2 etcd HA Requirements
- Minimum 3 nodes for quorum (can survive 1 failure)
- 5 nodes survive 2 failures
- Uses Raft consensus: needs (n/2 + 1) nodes for writes
- **Monitor**: `etcd_server_is_leader`, `etcd_disk_wal_fsync_duration_seconds`

### 1.3 API Server Availability
```promql
# API server request error rate
sum(rate(apiserver_request_total{code=~"5.."}[5m]))
/
sum(rate(apiserver_request_total[5m]))

# API server latency p99
histogram_quantile(0.99, sum(rate(apiserver_request_duration_seconds_bucket[5m])) by (le, verb))
```

---

## 2. Pod Lifecycle & Probes

### 2.1 Pod Phases
```
Pending → Running → Succeeded (completed)
                 → Failed (crashed, non-zero exit)
                 → Unknown (node communication lost)
```

### 2.2 Probe Types
| Probe | Timing | Failure Action | When to Use |
|-------|--------|----------------|-------------|
| **liveness** | Continuous | Restart container | When app can get stuck (deadlock, OOM) |
| **readiness** | Continuous | Remove from Service endpoints | When app is busy and can't handle traffic |
| **startup** | Once at start | Restart container | Slow-starting apps (JVM, legacy) |

### 2.3 Probe Best Practices
```yaml
livenessProbe:
  httpGet:
    path: /healthz      # Must be a LIGHTWEIGHT endpoint
    port: 8080
  initialDelaySeconds: 30   # Give app time to start
  periodSeconds: 10
  failureThreshold: 3       # Restart after 3 consecutive failures
  timeoutSeconds: 5

readinessProbe:
  httpGet:
    path: /ready        # Check dependency health (DB, cache)
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
  failureThreshold: 3

startupProbe:               # For slow starters (JVM, legacy apps)
  httpGet:
    path: /healthz
    port: 8080
  failureThreshold: 30      # 30 × 10s = 5 min to start
  periodSeconds: 10
```

**⚠️ Warning**: Never make liveness probe check external dependencies (DB, cache).
If DB is down, you don't want ALL pods restarting in a loop — that makes it worse.

---

## 3. Resource Management

### 3.1 Requests vs Limits
- **Requests**: Minimum guaranteed resources. Used for scheduling.
- **Limits**: Maximum allowed. CPU is throttled; memory causes OOM kill.

```yaml
resources:
  requests:
    cpu: "100m"      # 0.1 CPU core
    memory: "128Mi"
  limits:
    cpu: "500m"      # 0.5 CPU core — throttled if exceeded
    memory: "256Mi"  # Container killed (OOMKilled) if exceeded
```

### 3.2 QoS Classes (affects eviction order)
| Class | Condition | Eviction Priority |
|-------|-----------|-------------------|
| **Guaranteed** | requests == limits for all containers | Last to be evicted |
| **Burstable** | requests < limits (or only one set) | Middle |
| **BestEffort** | No requests or limits set | First to be evicted |

```bash
# Check QoS class of a pod
kubectl get pod my-pod -o jsonpath='{.status.qosClass}'
```

### 3.3 LimitRange (namespace defaults)
```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: production
spec:
  limits:
  - type: Container
    default:          # Applied if not specified
      cpu: 200m
      memory: 256Mi
    defaultRequest:   # Applied if requests not specified
      cpu: 100m
      memory: 128Mi
    max:              # Hard ceiling
      cpu: "2"
      memory: 2Gi
```

---

## 4. Pod Disruption Budgets (PDB)

### 4.1 Why PDBs Matter
Without PDB: node drain kills all replicas of your deployment simultaneously → outage.
With PDB: K8s waits before evicting pods until the budget allows.

### 4.2 PDB Syntax
```yaml
# Minimum available: always keep at least 2 pods running
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: api-pdb
spec:
  minAvailable: 2              # Can also use % like "50%"
  selector:
    matchLabels:
      app: api

---
# Maximum unavailable: allow at most 1 pod down at a time
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: api-pdb-maxunavailable
spec:
  maxUnavailable: 1            # Or "25%"
  selector:
    matchLabels:
      app: api
```

### 4.3 When PDBs Are Checked
- `kubectl drain` (voluntary)
- Cluster Autoscaler scale-down (voluntary)
- Node upgrades (GKE, EKS managed upgrades)
- **NOT checked for**: pod crashes, OOM kills, node failures (involuntary)

---

## 5. Horizontal Pod Autoscaler (HPA)

### 5.1 HPA v2 with Metrics
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 3
  maxReplicas: 50
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60     # Scale up when avg CPU > 60%
  - type: Resource
    resource:
      name: memory
      target:
        type: AverageValue
        averageValue: "400Mi"
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60    # Wait 60s before scaling up again
      policies:
      - type: Percent
        value: 100                       # Max double replicas per scaleUp
        periodSeconds: 15
    scaleDown:
      stabilizationWindowSeconds: 300   # Wait 5min before scaling down (prevent flapping)
      policies:
      - type: Percent
        value: 10                        # Scale down slowly
        periodSeconds: 60
```

### 5.2 Custom Metrics HPA
```yaml
# Scale on HTTP request rate (from Prometheus via KEDA or custom metrics adapter)
metrics:
- type: Pods
  pods:
    metric:
      name: http_requests_per_second
    target:
      type: AverageValue
      averageValue: "100"             # Scale up when avg > 100 RPS per pod
```

---

## 6. Vertical Pod Autoscaler (VPA)

### 6.1 VPA Modes
| Mode | Behavior | Use Case |
|------|----------|----------|
| **Off** | Collects data, makes recommendations only | Audit current requests/limits |
| **Initial** | Sets requests/limits at pod creation | Good default |
| **Recreate** | Evicts and recreates pods to update resources | Use with caution |
| **Auto** | Like Recreate but may change to in-place updates | Experimental |

### 6.2 VPA Example
```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: api-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  updatePolicy:
    updateMode: "Off"           # Start with Off to get recommendations
  resourcePolicy:
    containerPolicies:
    - containerName: api
      minAllowed:
        cpu: 100m
        memory: 128Mi
      maxAllowed:
        cpu: "4"
        memory: 4Gi
```

```bash
# Check VPA recommendations
kubectl describe vpa api-vpa
# Look for: Lower Bound, Target, Upper Bound, Uncapped Target
```

**⚠️ VPA + HPA conflict**: Don't use both on the same metric (CPU/memory). Use HPA for CPU/memory scaling, VPA for right-sizing, or use KEDA with custom metrics.

---

## 7. GKE-Specific Operations

### 7.1 Cluster Modes
| Feature | Standard | Autopilot |
|---------|----------|-----------|
| Node management | Manual | Google managed |
| Billing | Per node | Per pod |
| Node access | SSH possible | No node access |
| Custom node pools | Yes | Limited |
| Best for | Complex workloads | Simplicity |

### 7.2 Workload Identity (replaces service account keys)
```bash
# Create K8s service account
kubectl create serviceaccount my-app -n production

# Link to GCP service account
gcloud iam service-accounts add-iam-policy-binding \
  my-gcp-sa@PROJECT.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:PROJECT.svc.id.goog[production/my-app]"

# Annotate K8s SA
kubectl annotate serviceaccount my-app \
  -n production \
  iam.gke.io/gcp-service-account=my-gcp-sa@PROJECT.iam.gserviceaccount.com
```

### 7.3 GKE Node Pool Upgrade Strategy
```bash
# Check cluster version
gcloud container clusters describe my-cluster --zone us-central1-a \
  --format="value(currentMasterVersion,currentNodeVersion)"

# Upgrade node pool (with surge upgrade)
gcloud container node-pools update default-pool \
  --cluster my-cluster \
  --zone us-central1-a \
  --max-surge-upgrade 1 \
  --max-unavailable-upgrade 0    # Zero downtime upgrade
```

---

## 8. Kubernetes Networking Reliability

### 8.1 DNS in Kubernetes
Every pod gets:
```
/etc/resolv.conf:
  nameserver 10.96.0.10   # CoreDNS ClusterIP
  search default.svc.cluster.local svc.cluster.local cluster.local
  options ndots:5
```

**ndots:5** means: if hostname has < 5 dots, try search domains first (slow!)
```
Fix: use FQDN: my-service.my-namespace.svc.cluster.local
Or: reduce ndots to 2 in pod spec
```

### 8.2 CoreDNS Tuning
```yaml
# ConfigMap for CoreDNS
data:
  Corefile: |
    .:53 {
      errors
      health
      ready
      kubernetes cluster.local in-addr.arpa ip6.arpa {
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
        ttl 30
      }
      prometheus :9153
      forward . /etc/resolv.conf {
        max_concurrent 1000
      }
      cache 30        # Cache DNS responses for 30s — reduces CoreDNS load
      loop
      reload
      loadbalance
    }
```

---

## 9. Common K8s Issues & Debugging

### 9.1 CrashLoopBackOff
**Root Causes**:
1. App crashes on startup (bad config, missing env var)
2. OOMKilled (memory limit too low)
3. Liveness probe fails immediately
4. Bad image or entrypoint

**Debug steps**:
```bash
kubectl describe pod <pod> | grep -A10 "Last State"
kubectl logs <pod> --previous            # Logs from crashed container
kubectl logs <pod> -c <container> --previous
kubectl get events --field-selector involvedObject.name=<pod>
```

### 9.2 Pending Pods
**Root Causes**:
1. Insufficient CPU/memory on nodes
2. Node selector / affinity not satisfied
3. PVC not bound
4. Taint not tolerated

```bash
kubectl describe pod <pod> | grep -A20 Events
# Look for: "Insufficient cpu", "didn't match node selector"
kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU:.status.allocatable.cpu,MEM:.status.allocatable.memory
```

### 9.3 OOMKilled
```bash
kubectl describe pod <pod> | grep -i "oom\|killed\|memory"
# Look for: "OOMKilled" in Last State Reason
# Solution: increase memory limit or fix memory leak
```

### 9.4 ImagePullBackOff
```bash
kubectl describe pod <pod> | grep -A5 "Failed"
# Root causes: wrong image name, wrong tag, private registry auth missing
kubectl create secret docker-registry regcred \
  --docker-server=gcr.io \
  --docker-username=_json_key \
  --docker-password="$(cat key.json)"
```
