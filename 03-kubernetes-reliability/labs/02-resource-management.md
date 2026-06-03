# Lab 02: Advanced Resource Management, QoS, and Right-Sizing
## Lab Overview
This lab treats resource management as an SRE control surface. You will inspect QoS classes, deploy intentionally mis-sized workloads, collect Vertical Pod Autoscaler (VPA) recommendations in safe recommendation mode, enforce namespace defaults with `LimitRange`, cap tenant consumption with `ResourceQuota`, simulate node pressure, and review Goldilocks recommendations before converting them into policy.

**Estimated time:** 90 minutes  
**Difficulty:** Advanced  
**Focus:** Efficient scheduling and safer multi-tenant operations

---
## Prerequisites
- A disposable cluster with metrics-server enabled
- `kubectl` access with permission for namespaces, quotas, and autoscaling resources
- At least 2 worker nodes recommended for safer pressure testing
- Optional but useful: `jq`, `watch`, `helm`, `stern`
- VPA CRDs and controller available, or a platform that already supports recommendation mode
- Goldilocks optional but recommended for the later section

> Run the node-pressure section only in a non-production cluster. It intentionally pushes a worker toward eviction behavior.

---
## Learning Objectives
- Explain BestEffort, Burstable, and Guaranteed QoS classes
- Verify QoS directly from live Pods
- Use VPA with `updateMode: Off` for right-sizing decisions
- Translate VPA and Goldilocks output into requests and limits
- Enforce per-namespace defaults with `LimitRange`
- Enforce tenant boundaries with `ResourceQuota`
- Simulate resource pressure and observe eviction order
- Balance efficiency, headroom, and reliability as an SRE

---
## Scenario
A shared cluster hosts workloads from multiple teams. Recent incidents showed noisy neighbors, tiny requests that hide real scheduling demand, and oversized limits that waste capacity. Your task is to build a repeatable operating model: measure, recommend, constrain, test, then turn the result into policy.

---
## Architecture Diagram
```text
Operators -> VPA/Goldilocks -> team namespaces -> scheduler -> worker nodes -> kubelet QoS/eviction
```
This lab moves from measurement to policy: observe workload demand, collect recommendations, set defaults and quotas, then pressure a node to see which Pods survive.

---
## Preflight Checks
```bash
kubectl top nodes
kubectl top pods -A | head
kubectl api-resources | grep -i verticalpodautoscaler
kubectl get crd | grep verticalpodautoscalers
kubectl get ns goldilocks-system
kubectl get deploy -n goldilocks-system
```
If no VPA CRD is present, stop and install it using your platform-standard method before continuing.

---
## Step 1 - Create Working Namespaces
```bash
kubectl create namespace team-a
kubectl create namespace team-b
kubectl get ns team-a team-b
```
Expected result:
```text
NAME     STATUS   AGE
team-a   Active   ...
team-b   Active   ...
```

---
## Step 2 - Deploy Intentionally Imperfect Workloads
These workloads are deliberately mis-sized so metrics, VPA, and Goldilocks have something meaningful to show.
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: resource-demo-api
  namespace: team-a
spec:
  replicas: 2
  selector:
    matchLabels:
      app: resource-demo-api
  template:
    metadata:
      labels:
        app: resource-demo-api
    spec:
      containers:
        - name: api
          image: ghcr.io/platform-labs/resource-demo:1.0
          ports:
            - containerPort: 8080
          env:
            - name: CPU_BURN
              value: "medium"
            - name: MEMORY_MB
              value: "180"
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "1000m"
              memory: "512Mi"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: resource-demo-worker
  namespace: team-a
spec:
  replicas: 1
  selector:
    matchLabels:
      app: resource-demo-worker
  template:
    metadata:
      labels:
        app: resource-demo-worker
    spec:
      containers:
        - name: worker
          image: polinux/stress
          args: ["--cpu", "1", "--vm", "1", "--vm-bytes", "96M"]
          resources:
            requests:
              cpu: "10m"
              memory: "16Mi"
            limits:
              cpu: "1500m"
              memory: "128Mi"
```
Apply and observe:
```bash
kubectl apply -f resource-demo.yaml
kubectl rollout status deploy/resource-demo-api -n team-a
kubectl rollout status deploy/resource-demo-worker -n team-a
kubectl top pods -n team-a
```
What to notice: requests are far below actual usage, limits are much higher than steady-state needs, and the workloads run with poor efficiency and poor pressure behavior.

---
## Step 3 - Verify QoS and Add VPA Recommendation Mode
QoS is derived from requests and limits; it is never set directly.
```bash
kubectl get pods -n team-a -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass
```
Expected result: both demo workloads are **Burstable**.

Create one Pod of each QoS class:
```yaml
apiVersion: v1
kind: Pod
metadata: { name: best-effort-demo, namespace: team-b }
spec: { containers: [{ name: app, image: busybox:1.36, command: ["sh", "-c", "sleep 3600"] }] }
---
apiVersion: v1
kind: Pod
metadata: { name: burstable-demo, namespace: team-b }
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      resources: { requests: { cpu: "100m", memory: "64Mi" }, limits: { cpu: "500m", memory: "256Mi" } }
---
apiVersion: v1
kind: Pod
metadata: { name: guaranteed-demo, namespace: team-b }
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      resources: { requests: { cpu: "250m", memory: "128Mi" }, limits: { cpu: "250m", memory: "128Mi" } }
```
Validate:
```bash
kubectl apply -f qos-demo.yaml
kubectl get pods -n team-b -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass
```
Expected output: `BestEffort`, `Burstable`, and `Guaranteed`. BestEffort usually gets evicted first; Guaranteed usually survives longest.

Now enable VPA recommendation mode:
```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: resource-demo-api-vpa
  namespace: team-a
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: resource-demo-api
  updatePolicy:
    updateMode: "Off"
  resourcePolicy:
    containerPolicies:
      - containerName: api
        controlledResources: ["cpu", "memory"]
        minAllowed: { cpu: 100m, memory: 128Mi }
        maxAllowed: { cpu: 2, memory: 1Gi }
```
Apply and inspect after a few minutes:
```bash
kubectl apply -f team-a-vpa.yaml
kubectl get vpa -n team-a
kubectl describe vpa resource-demo-api-vpa -n team-a
```
Look for `lowerBound`, `target`, `uncappedTarget`, and `upperBound`.
Example shape:
```text
Recommendation:
  Container Recommendations:
    Container Name: api
    Target:
      Cpu: 350m
      Memory: 260Mi
```
Interpretation: requests near `target` usually improve scheduling accuracy, while limits should not simply copy `upperBound`.

---
## Step 5 - Create a Right-Sizing Proposal
Compare live metrics with the current spec and the VPA target:
```bash
kubectl top pods -n team-a
kubectl get deploy resource-demo-api -n team-a -o jsonpath='{.spec.template.spec.containers[0].resources}'
kubectl describe vpa resource-demo-api-vpa -n team-a | sed -n '/Recommendation/,$p'
```
A plausible revision for the API might be:
```yaml
resources:
  requests:
    cpu: "350m"
    memory: "256Mi"
  limits:
    cpu: "700m"
    memory: "384Mi"
```
Why not simply set limits equal to requests?
- burst headroom is useful for latency-sensitive APIs
- low CPU limits can cause throttling
- memory limits too close to working set can cause OOMKilled events

Why not leave the original values?
- `50m` CPU request understates scheduler demand
- `64Mi` memory request worsens eviction risk
- `1000m` CPU limit may be acceptable only if SLOs justify the burst allowance

---
## Step 6 - Enforce Namespace Defaults with LimitRange
`LimitRange` gives teams sane defaults and minimum/maximum boundaries.
```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: team-a-defaults
  namespace: team-a
spec:
  limits:
    - type: Container
      defaultRequest:
        cpu: 100m
        memory: 128Mi
      default:
        cpu: 500m
        memory: 512Mi
      min:
        cpu: 50m
        memory: 64Mi
      max:
        cpu: "2"
        memory: 2Gi
```
Apply it:
```bash
kubectl apply -f team-a-limitrange.yaml
kubectl describe limitrange team-a-defaults -n team-a
```
Test default injection with a Pod that omits resources:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: defaults-demo
  namespace: team-a
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
```
```bash
kubectl apply -f defaults-demo.yaml
kubectl get pod defaults-demo -n team-a -o yaml | sed -n '/resources:/,/imagePullPolicy:/p'
```
Expected result: requests and limits are injected and the Pod becomes Burstable instead of BestEffort.

---
## Step 7 - ResourceQuota and Node Pressure
Use quotas to cap total namespace consumption.
```yaml
apiVersion: v1
kind: ResourceQuota
metadata: { name: team-a-quota, namespace: team-a }
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 4Gi
    limits.cpu: "8"
    limits.memory: 8Gi
    pods: "20"
---
apiVersion: v1
kind: ResourceQuota
metadata: { name: team-b-quota, namespace: team-b }
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 2Gi
    limits.cpu: "4"
    limits.memory: 4Gi
    pods: "10"
```
Apply and inspect:
```bash
kubectl apply -f tenant-quotas.yaml
kubectl describe quota team-a-quota -n team-a
kubectl describe quota team-b-quota -n team-b
```
Test quota rejection with an oversized Pod:
```yaml
apiVersion: v1
kind: Pod
metadata: { name: quota-violation-demo, namespace: team-b }
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      resources:
        requests: { cpu: "3", memory: 3Gi }
        limits: { cpu: "3", memory: 3Gi }
```
```bash
kubectl apply -f quota-violation-demo.yaml
```
Expected output:
```text
Error from server (Forbidden): exceeded quota: team-b-quota, requested: requests.cpu=3,requests.memory=3Gi, used: ..., limited: requests.cpu=2,requests.memory=2Gi
```
Quota is a reliability control, not only a cost control; it prevents one namespace from monopolizing the cluster.

Now simulate node resource pressure. Use a disposable cluster, pick a worker that does not host critical components, and run one stress Pod at a time.
```bash
kubectl get nodes
kubectl describe node <worker-node> | grep -A5 Allocatable
kubectl top node <worker-node>
```
For a 4Gi worker, `2500M-2800M` is a sensible starting point:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: memory-pressure-demo
  namespace: team-b
spec:
  nodeName: <worker-node>
  restartPolicy: Never
  containers:
    - name: stress
      image: polinux/stress
      args: ["--cpu", "2", "--vm", "1", "--vm-bytes", "2800M", "--timeout", "180s"]
      resources:
        requests: { cpu: "100m", memory: "128Mi" }
        limits: { cpu: "2", memory: "3Gi" }
```
Apply and watch:
```bash
kubectl apply -f memory-pressure-demo.yaml
kubectl top node <worker-node>
kubectl get events -A --sort-by=.lastTimestamp | tail -30
kubectl describe node <worker-node> | grep -A6 Conditions
```
Possible observations:
- node memory usage spikes
- `MemoryPressure` becomes `True`
- kubelet considers eviction candidates
- BestEffort Pods are evicted before Burstable, and Burstable before Guaranteed if pressure persists

Check for evictions:
```bash
kubectl get pods -A --field-selector=status.phase=Failed
kubectl describe pod best-effort-demo -n team-b
```
Typical events:
```text
Warning  Evicted   kubelet  The node was low on resource: memory.
Warning  SystemOOM kubelet  System OOM encountered
```
If nothing happens, the node has more free headroom than expected; increase stress gradually, not aggressively.

---
## Step 9 - Compare Eviction Risk by QoS
```bash
kubectl get pods -n team-b -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass,PHASE:.status.phase
kubectl describe pod guaranteed-demo -n team-b | grep -A4 -E "QoS Class|Status"
```
Interpretation: **BestEffort** is easiest to evict, **Burstable** survives longer when usage stays near requests, and **Guaranteed** gets the strongest protection. BestEffort is easy to create, but risky during incidents.

---
## Step 10 - Use Goldilocks for Namespace-Level Recommendations
Goldilocks wraps VPA output into a friendlier operator workflow. If it is not already installed in the lab cluster, install it with Helm:
```bash
helm repo add fairwinds-stable https://charts.fairwinds.com/stable
helm repo update
helm upgrade --install goldilocks fairwinds-stable/goldilocks \
  --namespace goldilocks-system \
  --create-namespace
kubectl label namespace team-a goldilocks.fairwinds.com/enabled=true --overwrite
kubectl get vpa -n team-a
kubectl port-forward svc/goldilocks-dashboard -n goldilocks-system 8080:80
```
Open `http://127.0.0.1:8080` and inspect requests, limits, target recommendations, missing specs, and namespace overprovisioning. Goldilocks is useful because teams can consume recommendations without reading raw VPA YAML.

---
## Step 11 - Convert Recommendations Into Policy
Do not auto-apply every recommendation. Review each proposal against SLOs, peak traffic, startup spikes, failover behavior, and latency sensitivity.

A practical decision framework:
1. Compare VPA target with steady-state metrics
2. Compare VPA upper bound with peak windows
3. Add memory safety margin for startup and cache warm-up
4. Decide whether CPU limits help fairness or only create throttling
5. Keep memory limits high enough to avoid normal-path OOMKills

Example policy notes for an API:
- set CPU request near p50-p75 observed usage
- set memory request near steady-state working set plus margin
- use CPU limits only if the cluster truly needs fairness enforcement
- set memory limit above peak but below runaway-failure territory

---
## Validation Checklist
```bash
kubectl get pods -n team-a -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass
kubectl get limitrange -n team-a
kubectl get quota -n team-a
kubectl get quota -n team-b
kubectl get vpa -n team-a
kubectl top pods -n team-a
```
Verify all of the following:
- [ ] team workloads have explicit QoS classes
- [ ] VPA recommendation mode is active without mutating live workloads
- [ ] `LimitRange` injects defaults for Pods without resources
- [ ] `ResourceQuota` rejects oversized namespace requests
- [ ] node pressure leads to behavior that matches QoS expectations
- [ ] Goldilocks surfaces readable sizing recommendations

---
## Troubleshooting
- `kubectl top` shows no data: verify metrics-server and wait a few minutes after workload creation
- VPA has no recommendation: ensure the recommender is installed and the target Pods are running
- Goldilocks shows nothing: check the namespace label, controller status, and generated VPA objects
- LimitRange did not inject defaults: inspect the admitted Pod spec, not only the original manifest
- Pressure test triggered OOMKilled instead of eviction: the container limit was reached before node-level pressure escalated
- Pressure test triggered no eviction: the selected node had more free capacity than expected

---
## Cleanup
Delete lab namespaces when finished:
```bash
kubectl delete namespace team-a
kubectl delete namespace team-b
```
If you installed Goldilocks only for this lab, remove it separately:
```bash
helm uninstall goldilocks -n goldilocks-system
kubectl delete namespace goldilocks-system
```
If Goldilocks already existed in the shared cluster, leave it in place.

---
## Reflection Questions
1. Which workloads in your environment are oversized because requests were copied from old incidents?
2. Which workloads should be Guaranteed and which are better kept Burstable?
3. Where would CPU limits hurt latency more than they help fairness?
4. How would you turn Goldilocks or VPA output into a review workflow instead of automatic mutation?
5. Which namespaces should have stricter quotas than the examples in this lab?

---
## Key Takeaways
- Right-sizing starts with measurement, not guesswork
- VPA recommendation mode is the safest first step
- QoS directly affects eviction order during node pressure
- `LimitRange` and `ResourceQuota` are core multi-tenant reliability controls
- Goldilocks improves visibility, but SRE judgment is still required
- Pressure testing reveals whether your resource model survives real failure modes
