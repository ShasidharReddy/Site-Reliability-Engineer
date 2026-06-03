# Lab 03: Advanced PodDisruptionBudgets and Controlled Disruptions
## Lab Overview
This lab shows how SREs use PodDisruptionBudgets (PDBs) to make maintenance safer. You will create budgets using both `minAvailable` and `maxUnavailable`, observe `DISRUPTIONS ALLOWED`, test node drains, protect a StatefulSet, and align disruption policy with rolling-update settings.

**Estimated time:** 75-90 minutes  
**Difficulty:** Advanced  
**Focus:** Voluntary disruption safety during maintenance and rollouts
---
## Prerequisites
- A disposable Kubernetes cluster with at least 2 worker nodes
- `kubectl` access with permission to cordon and drain nodes
- Ability to create Deployments, StatefulSets, Services, and PDBs
- Familiarity with rolling updates, readiness, and ReplicaSets
- Optional but useful: `watch`, `jq`, and a second terminal

Check access before you start:
```bash
kubectl auth can-i create pods/eviction --all-namespaces
kubectl auth can-i patch nodes
```
> Use a non-production cluster. This lab intentionally blocks or slows disruptions to demonstrate PDB behavior.

---
## Learning Objectives
- Explain what a PDB protects and what it does not
- Create PDBs with `minAvailable` and `maxUnavailable`
- Observe budget state during voluntary disruptions
- Prove that `kubectl drain` respects a PDB
- Apply a safe PDB to a StatefulSet
- Explain how rollout strategy and PDBs complement, but do not replace, each other
- Write an SRE-friendly disruption policy for application teams

---
## Voluntary vs Involuntary Disruptions
A PDB protects against **voluntary** disruptions such as `kubectl drain`, cluster-autoscaler scale-down, and maintenance workflows that use the eviction API. A PDB does **not** stop involuntary disruptions such as node crashes, kernel panics, cloud host failures, or container OOM kills.

A second nuance matters just as much: a PDB is not your primary rollout throttle. For Deployments, rolling updates are mainly controlled by `spec.strategy.rollingUpdate.maxUnavailable`, `maxSurge`, and readiness. Use PDBs and rollout strategy together; do not assume one replaces the other.

---
## Scenario
Your platform team must drain nodes for patching, update stateless services without dropping capacity, and protect stateful replicas from excessive simultaneous eviction. During a previous maintenance window, multiple Pods were evicted from the same service and availability dropped below SLO. Your goal is to build and validate safer disruption rules.

---
## Architecture Diagram
```text
SRE operator -> eviction API -> checkout-api(minAvailable) + frontend(maxUnavailable) + ledger StatefulSet(maxUnavailable)
```
The lab uses one strict stateless service, one typical frontend, and one StatefulSet so you can compare disruption behavior under drain and rollout pressure.
---
## Step 1 - Create the Lab Namespace
```bash
kubectl create namespace sre-disruptions
kubectl config set-context --current --namespace=sre-disruptions
kubectl get ns sre-disruptions
```
Expected result:
```text
namespace/sre-disruptions created
```

---
## Step 2 - Deploy a Strict Stateless Service With `minAvailable`
This workload has 2 replicas and requires both to remain available. It is intentionally strict so you can see a blocked drain.
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout-api
  namespace: sre-disruptions
spec:
  replicas: 2
  selector:
    matchLabels:
      app: checkout-api
  template:
    metadata:
      labels:
        app: checkout-api
    spec:
      terminationGracePeriodSeconds: 30
      containers:
        - name: app
          image: hashicorp/http-echo:1.0.0
          args: ["-listen=:8080", "-text=checkout-api"]
          ports:
            - containerPort: 8080
          readinessProbe:
            httpGet:
              path: /
              port: 8080
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /
              port: 8080
            periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: checkout-api
  namespace: sre-disruptions
spec:
  selector:
    app: checkout-api
  ports:
    - port: 80
      targetPort: 8080
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: checkout-api-pdb
  namespace: sre-disruptions
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: checkout-api
```
Apply it:
```bash
kubectl apply -f checkout-api.yaml
kubectl rollout status deploy/checkout-api
kubectl get pdb checkout-api-pdb
```
Expected output:
```text
NAME               MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
checkout-api-pdb   2               N/A               0                     ...
```
Interpretation: 2 healthy replicas exist, all 2 must remain available, and no voluntary disruptions are currently allowed.

---
## Step 3 - Deploy a Frontend Protected by `maxUnavailable`
This workload represents a more typical stateless service. One Pod may be unavailable during maintenance.
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: sre-disruptions
spec:
  replicas: 4
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
        - name: app
          image: nginx:1.25-alpine
          ports:
            - containerPort: 80
          readinessProbe:
            httpGet:
              path: /
              port: 80
            periodSeconds: 5
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: frontend-pdb
  namespace: sre-disruptions
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      app: frontend
```
Apply it:
```bash
kubectl apply -f frontend.yaml
kubectl rollout status deploy/frontend
kubectl get pdb frontend-pdb
```
Expected output:
```text
NAME           MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS   AGE
frontend-pdb   N/A             1                 1                     ...
```
Interpretation: one matching Pod may be voluntarily disrupted at a time.

---
## Step 4 - Deploy a StatefulSet With Its Own PDB
Stateful services need their own budget because a safe value depends on quorum, failover time, and storage behavior.
```yaml
apiVersion: v1
kind: Service
metadata:
  name: ledger
  namespace: sre-disruptions
spec:
  clusterIP: None
  selector:
    app: ledger
  ports:
    - port: 80
      targetPort: 80
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ledger
  namespace: sre-disruptions
spec:
  serviceName: ledger
  replicas: 3
  selector:
    matchLabels:
      app: ledger
  template:
    metadata:
      labels:
        app: ledger
    spec:
      terminationGracePeriodSeconds: 30
      containers:
        - name: app
          image: nginx:1.25-alpine
          ports:
            - containerPort: 80
          command:
            - sh
            - -c
            - |
              echo "ledger replica $(hostname)" > /usr/share/nginx/html/index.html
              nginx -g 'daemon off;'
          readinessProbe:
            httpGet:
              path: /
              port: 80
            periodSeconds: 5
          volumeMounts:
            - name: data
              mountPath: /var/lib/ledger
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: ledger-pdb
  namespace: sre-disruptions
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      app: ledger
```
Apply it:
```bash
kubectl apply -f ledger.yaml
kubectl rollout status statefulset/ledger
kubectl get pods -l app=ledger -o wide
kubectl get pdb ledger-pdb
```
What to notice:
- each Pod keeps a stable ordinal name
- each replica gets its own PVC
- `maxUnavailable: 1` is a common starting point, but only if the application can tolerate one member down

---
## Step 5 - Inspect Budget State
```bash
kubectl get pdb -n sre-disruptions
kubectl describe pdb checkout-api-pdb -n sre-disruptions
kubectl describe pdb frontend-pdb -n sre-disruptions
kubectl describe pdb ledger-pdb -n sre-disruptions
```
Focus on `Current Healthy`, `Desired Healthy`, `Expected Pods`, and `Disruptions Allowed`; these tell you whether a maintenance action is safe before you start it.

---
## Step 6 - Test a Blocked Drain With `minAvailable`
Find a node hosting a `checkout-api` Pod:
```bash
kubectl get pods -l app=checkout-api -o wide
NODE=$(kubectl get pods -l app=checkout-api -o jsonpath='{.items[0].spec.nodeName}')
echo "$NODE"
```
Watch the budget and Pods in separate terminals:
```bash
kubectl get pdb checkout-api-pdb -w
kubectl get pods -l app=checkout-api -o wide -w
```
Now cordon and drain the node:
```bash
kubectl cordon "$NODE"
kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data --grace-period=30 --timeout=120s
```
Expected behavior:
- the node becomes cordoned
- drain attempts eviction
- eviction is denied because `minAvailable: 2` would be violated
- drain blocks or retries with a PDB error

Typical output:
```text
evicting pod sre-disruptions/checkout-api-xxxxxx-yyyyy
error when evicting pods/checkout-api-xxxxxx-yyyyy -n "sre-disruptions" (will retry after 5s): Cannot evict pod as it would violate the pod's disruption budget.
```
This is a success condition: the platform is preventing unsafe maintenance.
```bash
kubectl uncordon "$NODE"
```

---
## Step 7 - Test an Allowed Drain With `maxUnavailable`
Find a node hosting a `frontend` Pod:
```bash
kubectl get pods -l app=frontend -o wide
NODE=$(kubectl get pods -l app=frontend -o jsonpath='{.items[0].spec.nodeName}')
echo "$NODE"
```
Watch the budget and Pods:
```bash
kubectl get pdb frontend-pdb -w
kubectl get pods -l app=frontend -o wide -w
```
Drain the node:
```bash
kubectl cordon "$NODE"
kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data --grace-period=30 --timeout=180s
```
Expected behavior:
- one `frontend` Pod is evicted successfully
- `DISRUPTIONS ALLOWED` drops to `0` temporarily
- once a replacement Pod becomes Ready, `DISRUPTIONS ALLOWED` returns to `1`

Validate:
```bash
kubectl get pdb frontend-pdb
kubectl rollout status deploy/frontend
kubectl get pods -l app=frontend -o wide
kubectl uncordon "$NODE"
```

---
## Step 8 - Test a StatefulSet Drain
Find ledger Pod placement:
```bash
kubectl get pods -l app=ledger -o wide
NODE=$(kubectl get pods -l app=ledger -o jsonpath='{.items[0].spec.nodeName}')
echo "$NODE"
```
Watch the StatefulSet and budget:
```bash
kubectl get pods -l app=ledger -w
kubectl get pdb ledger-pdb -w
```
Drain the node:
```bash
kubectl cordon "$NODE"
kubectl drain "$NODE" --ignore-daemonsets --delete-emptydir-data --grace-period=30 --timeout=240s
```
Expected behavior:
- at most one ledger Pod is voluntarily disrupted
- the evicted ordinal is recreated elsewhere if scheduling allows
- `ledger-pdb` prevents additional voluntary disruptions until health returns

Validate ordinal recovery and storage continuity:
```bash
kubectl get pods -l app=ledger -o wide
kubectl get pvc -n sre-disruptions
kubectl describe pdb ledger-pdb -n sre-disruptions
kubectl uncordon "$NODE"
```
StatefulSet lesson: the PDB must match real application tolerance. If your database cannot safely lose one member, `maxUnavailable: 1` may already be too permissive.

---
## Step 9 - Understand PDBs During Rolling Updates
**PDBs are not the main Deployment rollout throttle.** Rollout pace is primarily governed by `Deployment.spec.strategy.rollingUpdate` plus readiness.

Bad rollout policy:
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 2
    maxSurge: 0
```
Why it is bad for a 4-replica frontend:
- two old Pods can disappear at once
- capacity may drop below your SLO margin
- a PDB does not guarantee the Deployment controller will pace itself the way you expect

Better rollout policy:
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 1
    maxSurge: 1
```
Why it is better:
- only one old Pod is removed at a time
- a new Pod can surge before more capacity is lost
- readiness gates progress
- the rollout intent now aligns with `frontend-pdb`

Recommended SRE policy:
- define PDBs for node drains and cluster maintenance
- define rollout strategy for Deployments
- keep the numbers aligned so operators and app teams have one clear availability model

---
## Step 10 - Run a Controlled Rolling Update
Update the frontend image and watch the rollout:
```bash
kubectl set image deployment/frontend app=nginx:1.26-alpine -n sre-disruptions
kubectl rollout status deployment/frontend -n sre-disruptions
kubectl get rs -n sre-disruptions
kubectl get pods -l app=frontend -w
```
Expected behavior with `maxUnavailable: 1` and `maxSurge: 1`:
- a new Pod starts
- readiness becomes true
- one old Pod terminates
- the sequence repeats until completion

Validation:
```bash
kubectl describe deploy frontend -n sre-disruptions | grep -A8 StrategyType
kubectl get pods -l app=frontend -o wide
```
The important lesson is that rollout safety depends on strategy plus readiness; the PDB remains most relevant for voluntary disruptions such as node drains.

---
## Step 11 - Write a Practical Disruption Policy
Use a simple policy template like this:
- **Small stateless services:** replicas 2-3, PDB `minAvailable: replicas - 1` or `maxUnavailable: 1`, rollout `maxUnavailable: 1`, `maxSurge: 1`
- **Large frontend fleets:** replicas 6+, PDB `maxUnavailable: 1` or a small validated percentage, rollout aligned with canary or surge policy
- **Stateful services:** derive budget from quorum, replication lag, and failover time; start conservative, often `maxUnavailable: 1`; validate drain behavior in staging
- **Singleton services:** a PDB cannot create availability you do not have; `minAvailable: 1` blocks voluntary disruption entirely; the real fix is often more replicas

---
## Validation Checklist
```bash
kubectl get pdb -n sre-disruptions
kubectl get deploy -n sre-disruptions
kubectl get statefulset -n sre-disruptions
kubectl get pods -n sre-disruptions -o wide
```
Verify all of the following:
- [ ] one PDB uses `minAvailable`
- [ ] one PDB uses `maxUnavailable`
- [ ] a drain is blocked when it would violate `checkout-api-pdb`
- [ ] a drain is allowed when it stays within `frontend-pdb`
- [ ] the StatefulSet budget protects against excessive voluntary disruption
- [ ] rollout strategy is documented separately from the PDB

---
## Troubleshooting
- `kubectl drain` fails immediately: check DaemonSets, local storage, and controller ownership before changing the budget
- `DISRUPTIONS ALLOWED` stays at `0`: one or more Pods may be unready, or the selector may match unexpected Pods
- StatefulSet Pods do not reschedule: check node capacity, storage class topology, and whether the node is still cordoned
- Service availability drops during rollouts: inspect readiness probes and Deployment strategy; do not assume the PDB alone protects rollout pace

---
## Cleanup
```bash
kubectl delete namespace sre-disruptions
```
If any nodes remain cordoned, uncordon them before finishing:
```bash
kubectl get nodes
kubectl uncordon <node-name>
```

---
## Reflection Questions
1. Which services in your environment should block a drain entirely until extra replicas are added?
2. Where have you confused rollout strategy with disruption policy?
3. Which StatefulSets need a budget derived from quorum rather than a default `maxUnavailable: 1`?
4. How would you explain to app teams that a blocked drain is a safety feature, not a Kubernetes bug?
5. Which maintenance workflows should check `DISRUPTIONS ALLOWED` before proceeding?

---
## Key Takeaways
- PDBs protect primarily against voluntary disruptions
- `minAvailable` and `maxUnavailable` express safety intent in different ways
- StatefulSets need budgets tied to real application tolerance
- PDBs do not replace Deployment rollout strategy
- A blocked drain is often the correct and safest outcome
- Good SRE policy aligns budgets, readiness, replicas, and maintenance procedures
