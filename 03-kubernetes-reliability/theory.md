# Advanced Kubernetes Reliability Theory Guide

> This guide is an SRE-focused theory reference for running Kubernetes reliably.
> It emphasizes failure domains, control loops, graceful degradation, and operational safety.
> Use it as a mental model document, not only as a syntax cheat sheet.

---

## Table of Contents

1. [Reliability Mindset](#1-reliability-mindset)
2. [Kubernetes Architecture Deep Dive](#2-kubernetes-architecture-deep-dive)
3. [Pod Lifecycle and Health Management](#3-pod-lifecycle-and-health-management)
4. [Workload Controllers](#4-workload-controllers)
5. [Resource Model and Evictions](#5-resource-model-and-evictions)
6. [Scheduling and Placement Control](#6-scheduling-and-placement-control)
7. [Services and Networking](#7-services-and-networking)
8. [Autoscaling Systems](#8-autoscaling-systems)
9. [Storage and Stateful Reliability](#9-storage-and-stateful-reliability)
10. [Security and Multi-Tenancy Safety](#10-security-and-multi-tenancy-safety)
11. [GKE Reliability Specifics](#11-gke-reliability-specifics)
12. [Reliability Patterns and Operational Guidance](#12-reliability-patterns-and-operational-guidance)
13. [High-Signal Command Reference](#13-high-signal-command-reference)
14. [Closing Principles](#14-closing-principles)

---

## 1. Reliability Mindset

Kubernetes is a distributed control system.
It is not a magic scheduler that eliminates failures.
It is a platform that continuously reconciles actual state toward desired state.

A reliable Kubernetes platform depends on four ideas:

- clear failure domains
- explicit health signals
- controlled change velocity
- enough redundancy to tolerate voluntary and involuntary disruption

### 1.1 Reliability Objectives in Kubernetes

A cluster is reliable when it can:

- keep critical APIs reachable
- place workloads predictably
- route traffic only to healthy backends
- preserve state safely
- recover from node, process, and zone failures
- scale without oscillation
- undergo upgrades without violating service objectives

### 1.2 Common Failure Domains

| Failure Domain | Examples | Typical Blast Radius | Primary Mitigation |
|---|---|---|---|
| Container | crash, deadlock, memory leak | single container | probes, restart policy, limits |
| Pod | bad init, sidecar issue, eviction | single pod | replicas, readiness, PDB |
| Node | kubelet down, disk full, kernel panic | many pods on one node | anti-affinity, autoscaling, zonal spread |
| Zone | power/network loss | subset of nodes | multi-zone placement, regional control plane |
| Control plane | API server overload, etcd quorum loss | cluster-wide management loss | HA control plane, request budgets, etcd care |
| Network | CNI failure, DNS outage, LB drift | partial or widespread | network policy hygiene, CoreDNS scaling, observability |
| Human change | bad rollout, wrong manifest, drain mistake | anywhere | progressive delivery, RBAC, reviews, runbooks |

### 1.3 Reliability Heuristics

- Prefer many small reversible changes over rare giant changes.
- Prefer graceful traffic removal over restarts.
- Prefer steady-state headroom over perfect utilization.
- Prefer odd-numbered etcd members.
- Prefer zonal balance for stateless apps and deliberate topology for stateful apps.
- Prefer clear ownership of service accounts, quotas, and policies.
- Prefer observability at every control point.

---

## 2. Kubernetes Architecture Deep Dive

Kubernetes separates desired state management from workload execution.
The control plane stores intent and makes decisions.
The data plane runs workloads and enforces network and storage behavior.

### 2.1 High-Level Architecture

```text
                        +-----------------------------------+
                        |            Control Plane          |
                        |-----------------------------------|
Users / CI / GitOps --->| kube-apiserver                    |
                        | scheduler                         |
                        | controller-manager                |
                        | cloud-controller-manager          |
                        | etcd                              |
                        +-----------------+-----------------+
                                          |
                               watches / writes / heartbeats
                                          |
        +---------------------------------+---------------------------------+
        |                                 |                                 |
+-------v--------+               +--------v-------+                +--------v-------+
| Worker Node A  |               | Worker Node B  |                | Worker Node C  |
|----------------|               |----------------|                |----------------|
| kubelet        |               | kubelet        |                | kubelet        |
| containerd     |               | containerd     |                | containerd     |
| kube-proxy     |               | kube-proxy     |                | kube-proxy     |
| CNI plugin     |               | CNI plugin     |                | CNI plugin     |
| Pods           |               | Pods           |                | Pods           |
+----------------+               +----------------+                +----------------+
```

### 2.2 Control Plane Components

| Component | Core Responsibility | Reliability Concern | Operational Note |
|---|---|---|---|
| kube-apiserver | front door for all cluster operations | latency, overload, authn/authz failures | horizontally scale and protect with LB |
| etcd | source of truth for cluster state | quorum loss, disk latency, corruption | keep fast disks, snapshots, odd quorum size |
| kube-scheduler | assigns unscheduled pods to nodes | pending pods, preemption surprises | tune priorities and placement rules |
| kube-controller-manager | runs reconciliation loops | drift from desired state, slow recovery | watch controller queues and errors |
| cloud-controller-manager | cloud integrations like routes and LBs | delayed infrastructure reconciliation | watch cloud API quotas and retries |
| admission webhooks | mutate or validate requests | API slowdown or request failures | keep timeouts low and highly available |

### 2.3 Data Plane Components

| Component | Function | Failure Symptoms | Reliability Notes |
|---|---|---|---|
| kubelet | node-level pod lifecycle manager | pods stuck Terminating or NotReady | monitor node heartbeats and kubelet logs |
| container runtime | launches containers | image pull errors, create sandbox failure | standardize runtime and image caching |
| kube-proxy | service VIP and backend translation | service traffic black holes | validate mode and rule sync health |
| CNI plugin | pod networking | pod sandbox creation failures, packet drops | understand plugin-specific failure modes |
| CSI node plugin | volume attach/mount on node | mount failures, stuck volumes | monitor attach/detach latency |

### 2.4 API Server Request Flow

The API server is the serialization point for cluster changes.
Every reliability conversation eventually reaches it.

```text
kubectl / controller / operator / kubelet
                  |
                  v
        +-----------------------+
        | External Load Balancer|
        +-----------+-----------+
                    |
                    v
            +---------------+
            | kube-apiserver|
            +---------------+
                    |
                    +--> Authentication
                    |
                    +--> Authorization
                    |
                    +--> Mutating Admission
                    |
                    +--> Validating Admission
                    |
                    +--> Schema Validation
                    |
                    +--> Resource Version / Preconditions
                    |
                    +--> etcd write or read path
                    |
                    +--> watch cache update
                    |
                    +--> notify watchers
                             |
                             +--> scheduler
                             +--> controller-manager
                             +--> kubelets
                             +--> custom controllers
```

### 2.5 Why API Server Flow Matters for Reliability

A request can fail at many layers:

- client timeout
- load balancer health issue
- API server saturation
- authentication backend issue
- authorization rule denial
- broken admission webhook
- storage latency in etcd
- stale clients using wrong resourceVersion

If admission webhooks are slow, the cluster behaves slow.
If etcd is slow, every write path becomes slow.
If watches are backed up, controllers react late.

### 2.6 etcd High Availability Theory

etcd uses the Raft consensus protocol.
Writes require quorum.
Reads may be served locally or linearly depending on the request path.

#### Key etcd HA rules

- Use an odd number of members.
- Three members is the normal HA baseline.
- Five members increases tolerance but also increases write coordination cost.
- Never run two-member etcd for production HA thinking.
- Disk latency matters as much as CPU.
- Snapshot regularly and test restore procedures.

#### Quorum math

| Members | Quorum Needed | Failure Tolerance |
|---|---|---|
| 1 | 1 | 0 |
| 3 | 2 | 1 |
| 5 | 3 | 2 |
| 7 | 4 | 3 |

#### etcd reliability risks

- WAL fsync latency spikes
- leader churn
- network partitions between members
- disk pressure on control plane nodes
- oversized object storage or excessive watch churn
- long-running compaction or defragmentation neglect

#### etcd operations guidance

```bash
# Kubernetes API health endpoints
kubectl get --raw='/readyz?verbose'
kubectl get --raw='/livez?verbose'

# If etcdctl is available in a managed control plane environment, examples are:
etcdctl endpoint health
etcdctl endpoint status -w table
etcdctl alarm list
```

### 2.7 API Priority and Fairness

Kubernetes protects the API server using request classification and fairness controls.
This prevents one traffic source from starving all others.

Reliable clusters treat the API as a finite resource.
Examples of abusive clients include:

- controllers with overly broad watches
- polling loops instead of watches
- scripts doing unbounded `kubectl get all -A` in tight loops
- admission webhooks that recursively call the API badly

### 2.8 Controller Pattern and Reconciliation

Almost every Kubernetes subsystem is a reconciliation loop:

1. watch desired and actual state
2. compare the two
3. perform actions to reduce drift
4. repeat forever

Reliability implication:

- Kubernetes is eventually consistent.
- Short windows of drift are normal.
- Fast convergence matters more than perfection at every instant.
- Controllers must be idempotent.

### 2.9 Node Heartbeats and Node Conditions

Nodes advertise health through heartbeats and status updates.
If the control plane stops hearing from a node, pods may remain shown as Running for a while even though the node is gone.

Important node conditions include:

- Ready
- DiskPressure
- MemoryPressure
- PIDPressure
- NetworkUnavailable

Operationally, kubelet health and node-level resource pressure are early indicators of reliability degradation.

### 2.10 Control Plane Failure Scenarios

| Failure | What Continues | What Breaks | SRE Response |
|---|---|---|---|
| one API server instance down | existing pods run, other API servers serve | reduced capacity | confirm LB routing and replica health |
| scheduler down | existing pods run | new pods stay Pending | restore scheduler and review leader election |
| controller-manager down | existing workloads may keep running | no reconciliation, no healing, no rollout progress | restore manager and inspect queues |
| etcd quorum lost | some already-running pods continue | most API writes fail, control plane effectively stalls | restore quorum before other actions |
| one worker node down | most cluster still works | pods on that node unavailable until rescheduled | ensure PDB-aware capacity and anti-affinity |

### 2.11 Architecture Reliability Checklist

- Multiple API server replicas behind a healthy load balancer
- etcd members distributed across failure domains when self-managed
- controller-manager and scheduler using leader election
- admission webhooks configured with sensible timeouts
- cluster DNS replicated and monitored
- control plane metrics and audit logs retained
- node pools sized for drains and repairs

---

## 3. Pod Lifecycle and Health Management

Pods are the smallest deployable units in Kubernetes.
A pod may contain one or more tightly coupled containers sharing network and storage namespaces.

Reliability depends on understanding the exact lifecycle transitions.

### 3.1 Pod Lifecycle Overview

```text
Pod Created
    |
    v
Pending
    |
    +--> scheduling
    +--> image pulls
    +--> init containers
    v
Running
    |
    +--> Ready / NotReady based on probes and conditions
    |
    +--> container restarts may happen inside Running phase
    v
Succeeded  OR  Failed
    |
    +--> deletion / garbage collection
```

### 3.2 Pod Phases

| Phase | Meaning | Typical Causes | Reliability Interpretation |
|---|---|---|---|
| Pending | accepted but not fully running | unscheduled, image pull, PVC wait | placement or startup bottleneck |
| Running | bound to node, at least one container started | steady state | not equal to healthy traffic readiness |
| Succeeded | all containers completed successfully | Jobs, init-style tasks | expected terminal state |
| Failed | at least one container terminated unsuccessfully | crash, command failure | investigate app or environment |
| Unknown | state cannot be obtained | node communication issue | suspect node or control-plane-to-node path |

### 3.3 Container States Inside a Pod

Pod phase is coarse.
Container state is more detailed.

| Container State | Meaning | Operational Meaning |
|---|---|---|
| Waiting | not yet running | image pull, CrashLoopBackOff, ContainerCreating |
| Running | process active | not automatically serving traffic |
| Terminated | process exited | look at reason, exit code, signal |

### 3.4 Pod Conditions

Pod conditions are more useful than phase when judging readiness.

| Condition | Meaning | Common Producer |
|---|---|---|
| PodScheduled | scheduler bound the pod to a node | scheduler |
| Initialized | init containers finished | kubelet |
| ContainersReady | all containers ready | kubelet |
| Ready | pod ready for services | kubelet and readiness checks |
| custom readiness gate | external condition satisfied | controller or operator |

### 3.5 Readiness, Liveness, and Startup Probes

These probes answer different questions.
Mixing them carelessly is a classic reliability mistake.

| Probe | Question | Failure Effect | Good Use | Bad Use |
|---|---|---|---|---|
| readinessProbe | should this pod receive traffic now | remove from endpoints | dependency warmup, backlog shedding | restarting pods for temporary downstream issues |
| livenessProbe | should this container be restarted | container restart | deadlock or unrecoverable stuck state | checking flaky external systems |
| startupProbe | has startup finished yet | restart during startup only | slow JVM or migration-heavy boot | replacing proper startup optimization |

### 3.6 Probe Design Rules

- Readiness should reflect ability to serve this request class now.
- Liveness should be conservative.
- Startup probe should shield slow boot from liveness kills.
- Probes must be cheap.
- Do not make probe handlers allocate heavily.
- Do not let liveness depend on a remote database unless restart is truly corrective.

### 3.7 Probe Example

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: api-probe-demo
spec:
  terminationGracePeriodSeconds: 45
  containers:
  - name: api
    image: ghcr.io/example/api:1.0.0
    ports:
    - containerPort: 8080
    startupProbe:
      httpGet:
        path: /startup
        port: 8080
      failureThreshold: 30
      periodSeconds: 5
      timeoutSeconds: 2
    readinessProbe:
      httpGet:
        path: /ready
        port: 8080
      periodSeconds: 5
      timeoutSeconds: 2
      failureThreshold: 3
      successThreshold: 2
    livenessProbe:
      httpGet:
        path: /healthz
        port: 8080
      initialDelaySeconds: 10
      periodSeconds: 10
      timeoutSeconds: 2
      failureThreshold: 3
```

### 3.8 Readiness is a Traffic Contract

A pod can be Running but not Ready.
Service routing should depend on Ready endpoints, not just running processes.

Readiness should often fail when:

- the process is draining
- critical caches are not warmed
- the app backlog is beyond safe service level
- the instance has not joined cluster membership yet

### 3.9 Termination Flow and Signals

Graceful shutdown is not optional.
It is the difference between a controlled rollout and a customer-visible error spike.

```text
kubectl delete pod
      |
      v
API sets deletionTimestamp
      |
      v
kubelet begins termination
      |
      +--> remove pod from Service endpoints (after readiness loss / endpoint update propagation)
      |
      +--> run preStop hook if defined
      |
      +--> send SIGTERM to PID 1 in each container
      |
      +--> wait terminationGracePeriodSeconds
      |
      +--> if process still alive, send SIGKILL
      v
containers exit, pod removed
```

### 3.10 SIGTERM and SIGKILL Sequence

| Step | Event | Reliability Concern |
|---|---|---|
| 1 | deletion requested | rollout and drain begin |
| 2 | endpoint removal propagates | in-flight traffic may still arrive briefly |
| 3 | preStop hook runs | hooks that sleep too long delay replacement |
| 4 | SIGTERM sent | app must stop accepting work and flush state |
| 5 | grace period counts down | must exceed worst-case request duration plus cleanup time |
| 6 | SIGKILL if needed | unflushed work and corruption risk for stateful apps |

### 3.11 Graceful Shutdown Example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      terminationGracePeriodSeconds: 60
      containers:
      - name: api
        image: ghcr.io/example/api:2.0.0
        lifecycle:
          preStop:
            exec:
              command:
              - /bin/sh
              - -c
              - |
                echo "marking unready"
                sleep 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          periodSeconds: 5
```

### 3.12 Practical Shutdown Guidance

- Fail readiness first.
- Stop new work.
- Drain in-flight requests.
- Commit or roll back state.
- Exit before grace period expires.
- Set grace period from measured latency, not guesswork.

### 3.13 Restart Policy

| Workload Type | Typical Restart Policy |
|---|---|
| Deployment / StatefulSet / DaemonSet pod template | Always |
| Job | OnFailure or Never |
| one-off debugging pod | Never or OnFailure |

### 3.14 Common Pod Failure Patterns

| Symptom | Likely Cause | First Checks |
|---|---|---|
| CrashLoopBackOff | app crash, bad config, overly aggressive liveness | `kubectl logs --previous`, events, last state |
| ImagePullBackOff | wrong image, auth failure, registry outage | image tag, pull secret, registry reachability |
| Pending | scheduler constraints, PVC wait, insufficient capacity | describe pod events |
| Terminating forever | finalizer, stuck preStop, hung runtime | pod yaml, node state, kubelet logs |
| Ready=false while Running | failing readiness, dependency not healthy | probe endpoint, app logs, endpoint slice |

### 3.15 Useful Lifecycle Commands

```bash
kubectl get pod -o wide
kubectl describe pod my-pod
kubectl logs my-pod --previous
kubectl get pod my-pod -o jsonpath='{.status.conditions}'
kubectl get endpointslices -l kubernetes.io/service-name=my-service
```

---

## 4. Workload Controllers

Controllers continuously drive pods toward a declared pattern.
Choosing the wrong controller often creates reliability problems later.

### 4.1 Deployment

Deployments manage stateless replicated pods via ReplicaSets.
They are the default controller for HTTP APIs, workers without sticky identity, and general stateless services.

#### Deployment strengths

- declarative rolling updates
- rollback support
- scale-out simplicity
- good fit for pod churn

#### Deployment limitations

- no stable pod identity
- no ordered startup guarantee
- not suitable for one-PVC-per-replica patterns by itself

### 4.2 Deployment Rollout Strategies

| Strategy | Behavior | Reliability Use Case | Risk |
|---|---|---|---|
| RollingUpdate | replace pods gradually | default for most services | bad readiness can still cause partial outage |
| Recreate | terminate all old pods then create new ones | singleton app with incompatible versions | full downtime window |

### 4.3 Rolling Update Controls

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 6
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 2
      maxUnavailable: 1
  minReadySeconds: 15
  progressDeadlineSeconds: 600
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: web
        image: ghcr.io/example/web:3.1.0
```

### 4.4 Deployment Reliability Notes

- `maxUnavailable: 0` is safest when capacity exists.
- `maxSurge` needs node headroom.
- `minReadySeconds` reduces false-success rollouts.
- `progressDeadlineSeconds` detects stuck rollouts.
- readiness probes determine rollout safety more than strategy name does.

### 4.5 Rollout Patterns Beyond Native Deployment

Blue/green and canary are usually composed from multiple Deployments plus routing controls.
Kubernetes does not natively give you canary analysis.
That comes from higher-level release tooling or service meshes.

### 4.6 DaemonSet

DaemonSets run one pod per eligible node.
They are used for node-local agents.

Common uses:

- log shippers
- metrics exporters
- security agents
- CNI components
- CSI node plugins

Reliability guidance:

- tolerate node taints only when needed
- keep resource usage small because every node pays the cost
- upgrade carefully because an agent bug hits the whole fleet

### 4.7 DaemonSet Example

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      tolerations:
      - operator: Exists
      containers:
      - name: node-exporter
        image: quay.io/prometheus/node-exporter:v1.8.2
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
```

### 4.8 StatefulSet

StatefulSets give ordered identity and stable storage attachments.
They are used for clustered databases, message brokers, and systems where instance identity matters.

StatefulSet guarantees include:

- stable pod names like `db-0`, `db-1`
- stable network identity via headless service
- stable volume association through PVCs
- ordered deployment and termination by ordinal by default

### 4.9 StatefulSet Reliability Notes

- slow pod recovery can delay higher ordinals
- quorum databases need zone-aware placement
- liveness must be extremely careful to avoid cascading restarts
- volume attach and detach latencies dominate recovery time

### 4.10 StatefulSet Example

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres-headless
  replicas: 3
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      terminationGracePeriodSeconds: 120
      containers:
      - name: postgres
        image: postgres:16
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 100Gi
```

### 4.11 Job

Jobs run pods to completion.
They are for batch work, not request-serving traffic.

Key fields:

- `completions`
- `parallelism`
- `backoffLimit`
- `activeDeadlineSeconds`
- `ttlSecondsAfterFinished`

### 4.12 Job Example

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: report-job
spec:
  backoffLimit: 3
  completions: 10
  parallelism: 2
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: report
        image: ghcr.io/example/report:1.4.0
```

### 4.13 CronJob

CronJobs create Jobs on a schedule.
They are excellent for periodic automation and terrible when treated as infinitely reliable timers without guardrails.

Important settings:

- `schedule`
- `concurrencyPolicy`
- `startingDeadlineSeconds`
- `successfulJobsHistoryLimit`
- `failedJobsHistoryLimit`

### 4.14 CronJob Example

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup
spec:
  schedule: "0 */6 * * *"
  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 300
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: backup
            image: ghcr.io/example/backup:2.1.0
```

### 4.15 Controller Selection Cheat Sheet

| Requirement | Best Controller |
|---|---|
| stateless replicas | Deployment |
| one pod per node | DaemonSet |
| stable identity and storage | StatefulSet |
| finite batch work | Job |
| scheduled batch | CronJob |

### 4.16 Controller Operational Guidance

- Use Deployments for most services.
- Use StatefulSets only when identity really matters.
- Keep Job retries bounded.
- Review CronJobs for missed schedules after control plane interruptions.
- Pause bad rollouts quickly with `kubectl rollout pause` when needed.

```bash
kubectl rollout status deployment/web
kubectl rollout history deployment/web
kubectl rollout undo deployment/web
kubectl get jobs
kubectl get cronjobs
```

---

## 5. Resource Model and Evictions

Kubernetes scheduling and eviction behavior depends on resources.
Resource declarations are not optional metadata.
They are admission to the economics of the cluster.

### 5.1 Requests and Limits

| Setting | Used For | Reliability Meaning |
|---|---|---|
| requests.cpu | scheduler reservation | baseline CPU share for placement |
| limits.cpu | cgroup throttling | too low can cause latency under load |
| requests.memory | scheduler reservation | helps avoid overpacking |
| limits.memory | hard cap | crossing it causes OOM kill |
| requests.ephemeral-storage | placement and accounting | protects node disks |
| limits.ephemeral-storage | local storage cap | excess may trigger eviction |

### 5.2 Example Resource Policy

```yaml
resources:
  requests:
    cpu: 250m
    memory: 512Mi
    ephemeral-storage: 1Gi
  limits:
    cpu: "1"
    memory: 1Gi
    ephemeral-storage: 2Gi
```

### 5.3 QoS Classes

| QoS Class | Rule | Reliability Behavior |
|---|---|---|
| Guaranteed | every container has requests==limits for cpu and memory | last evicted under pressure |
| Burstable | at least one request set but not all equal to limits | middle of eviction order |
| BestEffort | no requests or limits | first evicted |

### 5.4 Why QoS Matters

During memory pressure, Kubernetes prefers evicting less protected workloads first.
That does not mean Guaranteed pods are immortal.
It means they are protected longer.

### 5.5 Eviction Order Theory

Node pressure evictions are influenced by:

- node condition type
- QoS class
- whether current usage exceeds requests
- pod priority
- system-reserved and kube-reserved settings

A simplified memory-pressure order is often:

1. BestEffort pods
2. Burstable pods exceeding requests by the largest margin
3. Guaranteed pods only when pressure remains severe

### 5.6 Eviction Signals

Typical eviction triggers include:

- memory.available low
- node filesystem available low
- image filesystem available low
- inode exhaustion
- PID pressure

### 5.7 CPU Reliability Nuance

CPU limit breaches do not OOM kill the process.
They cause throttling.
For latency-sensitive services, too-low CPU limits can look like random slowness or timeouts.

### 5.8 Memory Reliability Nuance

Memory is not compressible in the same way CPU is shareable.
If a container exceeds its memory limit, the kernel kills it.
This produces abrupt failure.

### 5.9 LimitRange Example

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-container-limits
  namespace: production
spec:
  limits:
  - type: Container
    defaultRequest:
      cpu: 250m
      memory: 256Mi
    default:
      cpu: 500m
      memory: 512Mi
    max:
      cpu: "4"
      memory: 4Gi
```

### 5.10 ResourceQuota Example

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-a-quota
  namespace: team-a
spec:
  hard:
    requests.cpu: "20"
    requests.memory: 40Gi
    limits.cpu: "40"
    limits.memory: 80Gi
    persistentvolumeclaims: "20"
```

### 5.11 Right-Sizing Guidance

- Set requests from measured p50 to p95 steady state plus margin.
- Set limits from observed spikes and failure tolerance.
- Keep enough node headroom for drains and burst.
- Review throttling metrics before assuming app regression.

### 5.12 Commands for Resource Investigation

```bash
kubectl top nodes
kubectl top pods -A
kubectl describe node <node-name>
kubectl get pod my-pod -o jsonpath='{.status.qosClass}'
kubectl describe pod my-pod | grep -A5 -i oom
```

---

## 6. Scheduling and Placement Control

The scheduler does not merely find a node.
It chooses a node according to constraints and preferences.
Understanding this is crucial for reliability engineering.

### 6.1 Scheduling Framework Mental Model

Historically people described scheduling as predicates and priorities.
Modern Kubernetes calls them filters and scoring plugins.
Both terms are useful.

```text
Unscheduled Pod
     |
     v
QueueSort
     |
     v
PreFilter
     |
     v
Filter stage
  - resources fit?
  - taints tolerated?
  - node selector matched?
  - affinity rules satisfied?
  - volume constraints satisfied?
     |
     v
Score stage
  - spread preference
  - least allocated / most balanced
  - image locality
  - topology preference
     |
     v
Reserve
     |
     v
Permit / PreBind / Bind
     |
     v
Pod assigned to node
```

### 6.2 Filters and Predicates

Examples of hard placement checks:

- enough CPU and memory
- matching node labels
- required node affinity
- required pod affinity or anti-affinity
- taints tolerated
- volume zone compatibility
- max pod density and ports

If a hard rule fails, the pod remains Pending.

### 6.3 Priorities and Scoring

When multiple nodes pass filters, scoring decides placement.
Typical scoring goals:

- spread workloads
- pack workloads efficiently
- prefer nodes with images already present
- avoid violating soft anti-affinity

### 6.4 PriorityClass

Priority determines which workloads matter most under contention.
Higher priority can trigger preemption of lower-priority pods.

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: critical-api
value: 100000
preemptionPolicy: PreemptLowerPriority
globalDefault: false
description: "Critical API workloads that must win scheduling contention."
```

### 6.5 Preemption Risks

Preemption helps critical pods schedule.
It can also surprise operators by displacing lower-priority work.
Use it intentionally.

### 6.6 Node Affinity

Node affinity constrains or prefers nodes by labels.

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: topology.kubernetes.io/zone
          operator: In
          values: ["us-central1-a", "us-central1-b"]
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 50
      preference:
        matchExpressions:
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["n2-standard-4"]
```

### 6.7 Pod Affinity and Anti-Affinity

Pod affinity co-locates workloads.
Pod anti-affinity separates them.
For reliability, anti-affinity is more common.

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          app: api
      topologyKey: kubernetes.io/hostname
```

This rule says:

- do not place two `app=api` pods on the same node

### 6.8 Taints and Tolerations

Taints repel pods.
Tolerations allow pods to land on tainted nodes.

| Taint Effect | Meaning |
|---|---|
| NoSchedule | scheduler will not place untolerating pods |
| PreferNoSchedule | scheduler tries to avoid placement |
| NoExecute | existing untolerating pods are evicted and new ones blocked |

```yaml
tolerations:
- key: "dedicated"
  operator: "Equal"
  value: "batch"
  effect: "NoSchedule"
```

### 6.9 Topology Spread Constraints

Topology spread is a first-class reliability tool.
It helps avoid too many replicas concentrating in one node or zone.

```yaml
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule
  labelSelector:
    matchLabels:
      app: api
- maxSkew: 1
  topologyKey: kubernetes.io/hostname
  whenUnsatisfiable: ScheduleAnyway
  labelSelector:
    matchLabels:
      app: api
```

### 6.10 Spread Strategy Guidance

- Spread across zones for high availability.
- Spread across nodes to avoid single-node blast radius.
- Avoid over-constraining small clusters.
- Remember strict anti-affinity can block scheduling during failures.

### 6.11 Scheduling Failure Diagnosis

```bash
kubectl describe pod pending-pod
kubectl get events --sort-by=.lastTimestamp -A
kubectl get nodes --show-labels
kubectl describe node <node-name>
```

Typical messages include:

- `0/6 nodes are available: Insufficient cpu`
- `node(s) didn't match Pod's node affinity`
- `node(s) had untolerated taint`
- `node(s) had volume node affinity conflict`

### 6.12 Reliable Scheduling Practices

- Keep placement rules as simple as possible.
- Use soft preferences before hard rules when business allows.
- Use PriorityClasses for true criticality, not politics.
- Pair topology spread with PDBs and enough spare capacity.
- Test failure scenarios, not only happy path scheduling.

---

## 7. Services and Networking

A healthy pod that cannot be reached is still an outage.
Networking is where application health meets platform health.

### 7.1 Service Abstraction

A Service provides a stable virtual IP and DNS name for a changing set of pods.
It decouples client routing from pod identity.

### 7.2 Service Types

| Service Type | Exposure Model | Common Use | Reliability Notes |
|---|---|---|---|
| ClusterIP | internal virtual IP | in-cluster east-west traffic | default and safest |
| NodePort | opens port on every node | legacy external exposure, LB target | larger node attack surface |
| LoadBalancer | cloud load balancer fronting service | north-south production traffic | depends on cloud health checks and quotas |
| Headless | no virtual IP, direct DNS records | StatefulSet, service discovery | clients must handle multiple endpoints |

### 7.3 ClusterIP Example

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api
spec:
  type: ClusterIP
  selector:
    app: api
  ports:
  - name: http
    port: 80
    targetPort: 8080
```

### 7.4 LoadBalancer Example

```yaml
apiVersion: v1
kind: Service
metadata:
  name: public-api
spec:
  type: LoadBalancer
  selector:
    app: api
  ports:
  - port: 80
    targetPort: 8080
```

### 7.5 Headless Service Example

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-headless
spec:
  clusterIP: None
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
```

### 7.6 Endpoints and EndpointSlices

Services do not discover pods directly.
Kubernetes generates endpoint objects from matching ready pods.
Modern clusters use EndpointSlices for scale.

Reliability implications:

- readiness controls endpoint membership
- stale endpoints cause traffic to dead pods
- too many endpoints can pressure watchers if not sharded well

### 7.7 Service Packet Flow

```text
Client Pod
   |
   v
Service DNS -> ClusterIP
   |
   v
kube-proxy rules on node
   |
   +--> select ready backend endpoint
   |
   v
Destination Pod IP
```

### 7.8 kube-proxy Modes

| Mode | Mechanism | Strength | Weakness |
|---|---|---|---|
| iptables | packet rules in kernel tables | simple and common | many rules can slow large updates |
| IPVS | kernel virtual server load balancing | scales better for many services | extra complexity and feature nuances |
| eBPF-based replacement | some CNIs replace kube-proxy | high performance and observability | vendor/plugin specific behavior |

### 7.9 iptables vs IPVS Reliability Notes

- iptables is widely understood and battle-tested.
- IPVS usually handles very large service counts better.
- Rule sync delays can show up during rapid endpoint churn.
- Know what your CNI and distribution actually deploy.

### 7.10 CNI Basics

CNI is the plugin model for pod networking.
The CNI plugin is responsible for:

- assigning pod IPs
- wiring pod interfaces
- programming routes or overlays
- optionally enforcing network policy

Common CNI designs include:

- overlay networks
- routed L3 fabrics
- eBPF-based datapaths

### 7.11 CNI Reliability Considerations

- IP exhaustion blocks pod creation.
- broken CNI agents can make nodes appear healthy but unusable for pods
- network policy engines may add startup latency
- MTU mismatch causes subtle packet drops
- DNS dependency chains can amplify outages

### 7.12 DNS Reliability

CoreDNS is usually a small deployment with massive importance.
If DNS is slow, many apps look slow.
If DNS is down, many apps look dead.

Useful DNS guidance:

- scale CoreDNS horizontally
- monitor error rates and latency
- understand `ndots` behavior
- use FQDNs for latency-sensitive lookups when justified

### 7.13 NetworkPolicy as Reliability Control

NetworkPolicies are security controls, but they also limit blast radius.
They can stop noisy or compromised workloads from reaching critical services.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-web-to-api
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: web
    ports:
    - protocol: TCP
      port: 8080
```

### 7.14 Service Troubleshooting Commands

```bash
kubectl get svc
kubectl get endpoints
kubectl get endpointslices
kubectl describe svc api
kubectl exec -it debug -- nslookup api.default.svc.cluster.local
kubectl exec -it debug -- curl -sv http://api
```

### 7.15 Networking Reliability Practices

- Do not send traffic to pods before readiness is true.
- Use at least two replicas behind every user-facing service.
- Spread replicas across nodes and zones.
- Keep DNS and CNI components in priority classes if warranted.
- Validate cloud load balancer health checks align with pod readiness.

---

## 8. Autoscaling Systems

Autoscaling is a control loop.
Bad control loops oscillate.
Good control loops absorb demand safely.

### 8.1 Horizontal Pod Autoscaler

HPA scales replica count based on observed metrics.
It is best for elastic stateless workloads.

HPA commonly scales on:

- CPU utilization
- memory usage
- custom per-pod metrics
- external metrics such as queue depth

### 8.2 HPA CPU Example

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
  maxReplicas: 30
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 65
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 20
        periodSeconds: 60
```

### 8.3 HPA Custom and External Metrics

Custom metrics are associated with pods or objects.
External metrics come from systems outside Kubernetes objects.

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: worker-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: worker
  minReplicas: 2
  maxReplicas: 50
  metrics:
  - type: Pods
    pods:
      metric:
        name: requests_per_second
      target:
        type: AverageValue
        averageValue: "80"
  - type: External
    external:
      metric:
        name: queue_messages_visible
      target:
        type: Value
        value: "500"
```

### 8.4 HPA Reliability Notes

- CPU-based HPA depends on sane CPU requests.
- HPA reacts after metrics rise, so keep baseline replicas above zero-risk minimum.
- stabilization windows reduce flapping.
- scale-down should be slower than scale-up for most services.

### 8.5 Vertical Pod Autoscaler

VPA changes pod resource requests and optionally limits.
It is useful for right-sizing memory-heavy services and baseline tuning.

Modes:

- Off
- Initial
- Recreate
- Auto

### 8.6 VPA Example

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
    updateMode: Off
```

### 8.7 VPA Reliability Notes

- Recreate mode evicts pods, so use with PDB awareness.
- avoid fighting HPA on CPU or memory metrics for the same workload.
- start in recommendation mode before allowing automatic changes.

### 8.8 KEDA

KEDA extends autoscaling for event-driven workloads.
It bridges sources like queues, Kafka, Prometheus, and cloud event systems into scale decisions.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: queue-worker
spec:
  scaleTargetRef:
    name: worker
  minReplicaCount: 0
  maxReplicaCount: 100
  triggers:
  - type: prometheus
    metadata:
      serverAddress: http://prometheus.monitoring.svc:9090
      metricName: queue_depth
      query: sum(my_queue_depth)
      threshold: "100"
```

### 8.9 KEDA Reliability Notes

- scaling to zero is powerful but increases cold-start risk
- external scaler availability becomes part of system reliability
- queue depth alone may not reflect processing latency well

### 8.10 Cluster Autoscaler

Cluster Autoscaler changes node count when pods cannot schedule or nodes are underutilized.
It closes the loop between workload demand and cluster capacity.

It scales up when:

- pending pods cannot fit

It scales down when:

- nodes stay underutilized and their pods can move elsewhere safely

### 8.11 Cluster Autoscaler Reliability Notes

- scale-up is slower than HPA because nodes must boot and join
- PDBs and local storage can block scale-down
- over-constrained scheduling rules can make pending pods unschedulable forever
- reserve headroom so scale-up is not your first response to every spike

### 8.12 Autoscaling Layer Interaction

```text
Traffic / Queue Growth
        |
        +--> HPA or KEDA adds pods
        |
        +--> if pods remain Pending
                 |
                 v
          Cluster Autoscaler adds nodes
```

### 8.13 Autoscaling Operational Guidance

- choose one primary metric per workload that tracks pain well
- validate scaling under load tests
- keep warm capacity for critical services
- never rely on autoscaling to compensate for broken readiness or runaway memory leaks

```bash
kubectl get hpa
kubectl describe hpa api-hpa
kubectl get vpa
kubectl describe scaledobject queue-worker
```

---

## 9. Storage and Stateful Reliability

Storage reliability is about durability, attachment, access semantics, and recovery time.
Stateful failures are slower and more dangerous than stateless ones.

### 9.1 PersistentVolume and PersistentVolumeClaim

| Object | Role |
|---|---|
| PersistentVolume (PV) | cluster storage resource |
| PersistentVolumeClaim (PVC) | workload request for storage |
| StorageClass | dynamic provisioning policy |

### 9.2 Binding Flow

```text
PVC created
   |
   +--> dynamic provisioner via StorageClass creates backing volume
   |
   v
PVC bound to PV
   |
   v
pod scheduled with volume constraints
   |
   v
CSI attaches and mounts volume on node
```

### 9.3 StorageClass Example

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: pd.csi.storage.gke.io
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  type: pd-ssd
```

### 9.4 Why `WaitForFirstConsumer` Matters

This delays provisioning until scheduling knows the node or topology.
It helps avoid zone mismatch and stranded volumes.

### 9.5 CSI Basics

CSI is the standard interface for container storage drivers.
A CSI solution usually has:

- controller plugin for provisioning and attach logic
- node plugin for mount logic on each node
- sidecars for resizer, snapshotter, and attacher behavior

### 9.6 Access Modes

| Access Mode | Meaning | Typical Reliability Note |
|---|---|---|
| ReadWriteOnce | mounted read-write by one node | common for zonal block storage |
| ReadOnlyMany | many nodes read-only | useful for shared reference data |
| ReadWriteMany | many nodes read-write | depends on shared filesystem semantics |
| ReadWriteOncePod | one pod only | stronger single-writer safety |

### 9.7 PVC Example

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: fast-ssd
  resources:
    requests:
      storage: 50Gi
```

### 9.8 StatefulSet `volumeClaimTemplates`

For replicated stateful workloads, each ordinal usually needs its own PVC.
That is what `volumeClaimTemplates` provide.

```yaml
volumeClaimTemplates:
- metadata:
    name: data
  spec:
    accessModes: ["ReadWriteOnce"]
    storageClassName: fast-ssd
    resources:
      requests:
        storage: 200Gi
```

### 9.9 Storage Reliability Concerns

- slow attach and mount times extend recovery
- zonal disks constrain placement
- filesystem corruption risk rises with hard kills
- snapshots are not backup strategy unless restore is tested
- resizing may require filesystem expansion awareness

### 9.10 Stateful Operational Guidance

- use StatefulSet for stable identity
- set longer termination grace periods
- avoid aggressive liveness probes on databases
- understand quorum math before scaling down
- validate backup and restore regularly

### 9.11 Storage Debug Commands

```bash
kubectl get pv
kubectl get pvc -A
kubectl describe pvc app-data
kubectl describe pod stateful-pod
kubectl get storageclass
```

---

## 10. Security and Multi-Tenancy Safety

Security controls are also reliability controls.
A compromised cluster is unreliable.
A noisy tenant without boundaries is also unreliable.

### 10.1 RBAC

Role-Based Access Control limits who can do what.
Reliability benefit:

- fewer accidental deletions
- fewer dangerous drains or edits
- clear operational boundaries

### 10.2 RBAC Example

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: production
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
  namespace: production
subjects:
- kind: ServiceAccount
  name: app-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: pod-reader
```

### 10.3 ServiceAccounts

Pods authenticate to the API using ServiceAccounts.
Best practice is least privilege.
Do not mount elevated permissions into every pod by default.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: api-sa
  namespace: production
```

### 10.4 Secrets Management

Secrets in Kubernetes are base64-encoded objects, not automatically encrypted end-to-end by magic.
Reliability and security guidance:

- enable encryption at rest
- restrict secret access with RBAC
- prefer external secret managers for rotation and auditability
- avoid baking secrets into images
- rotate credentials without forcing unsafe emergency changes

### 10.5 Secret Example

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
type: Opaque
stringData:
  username: appuser
  password: change-me
```

### 10.6 External Secrets Pattern

Common production patterns include:

- Secret Manager plus External Secrets Operator
- Vault agent or CSI provider
- cloud-native secret CSI integrations

These reduce long-lived static secret sprawl.

### 10.7 NetworkPolicies

NetworkPolicies restrict pod-to-pod communication.
They are essential in multi-tenant clusters and valuable in single-tenant clusters.

Reliability benefit:

- limit lateral blast radius
- reduce accidental dependency sprawl
- make service boundaries explicit

### 10.8 Pod Security Standards

Pod Security Standards define policy profiles:

| Profile | Goal |
|---|---|
| Privileged | broad permissions, least restrictive |
| Baseline | prevent known privilege escalations |
| Restricted | strong hardening defaults |

Reliable clusters usually target Baseline or Restricted for most namespaces.

### 10.9 Pod Security Admission Guidance

Control risky pod settings such as:

- privileged containers
- host network usage
- host PID/IPC access
- unsafe capabilities
- writable hostPath mounts

### 10.10 Security Reliability Checklist

- each app has its own ServiceAccount
- RBAC grants only required verbs
- secrets come from managed systems where possible
- namespaces have Pod Security policies appropriate to risk
- network policy defaults are explicit, not accidental

### 10.11 Security Commands

```bash
kubectl auth can-i list pods --as=system:serviceaccount:production:api-sa -n production
kubectl get role,rolebinding -n production
kubectl get serviceaccounts -A
kubectl get networkpolicy -A
```

---

## 11. GKE Reliability Specifics

GKE adds managed control plane behaviors and Google Cloud integration.
Understanding those managed layers is part of reliable operations.

### 11.1 Regional Clusters

A regional GKE cluster spreads control plane components across multiple zones in a region.
This improves control plane availability versus single-zonal control planes.

Reliability benefits:

- better tolerance to single-zone outages
- higher control plane availability during maintenance
- better fit for production SLOs

Trade-offs:

- slightly higher cost
- more network paths and resource planning complexity

### 11.2 Standard vs Autopilot

| Dimension | Standard | Autopilot |
|---|---|---|
| Node control | you manage node pools | Google manages nodes |
| Flexibility | highest | opinionated |
| Pricing model | node-based | pod/resource-based |
| DaemonSet freedom | broad | constrained by platform rules |
| Debugging at node layer | more direct | less direct |
| Operational burden | higher | lower |
| Best fit | custom platform teams | teams wanting managed guardrails |

### 11.3 Autopilot Reliability Notes

Autopilot reduces some categories of node management error.
It also reduces customization.
You trade control for consistency.

### 11.4 Standard Reliability Notes

Standard gives you full node pool strategy control.
That means you own:

- machine type selection
- surge and upgrade policy
- taints and labels
- autoscaling details
- daemon resource impact

### 11.5 Node Pool Upgrade Strategies

GKE supports safer node upgrades using surge behavior.
A reliability-focused strategy keeps disruption low.

```bash
gcloud container node-pools update primary-pool \
  --cluster prod-cluster \
  --region us-central1 \
  --max-surge-upgrade 1 \
  --max-unavailable-upgrade 0
```

This means:

- create extra node capacity during upgrade
- do not take an existing node unavailable before replacement exists

### 11.6 Upgrade Strategy Guidance

- use surge upgrades for user-facing workloads
- verify PDBs before maintenance windows
- ensure Cluster Autoscaler limits allow temporary surge
- avoid upgrading all pools simultaneously if workloads are tightly coupled

### 11.7 Workload Identity

Workload Identity binds Kubernetes ServiceAccounts to Google Service Accounts.
It eliminates static key distribution to pods.

```bash
kubectl create serviceaccount api-sa -n production

gcloud iam service-accounts add-iam-policy-binding \
  api-gsa@PROJECT_ID.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:PROJECT_ID.svc.id.goog[production/api-sa]"

kubectl annotate serviceaccount api-sa \
  -n production \
  iam.gke.io/gcp-service-account=api-gsa@PROJECT_ID.iam.gserviceaccount.com
```

Reliability benefit:

- simpler credential rotation
- fewer secret distribution mistakes
- reduced key leak blast radius

### 11.8 Regional Placement Guidance on GKE

- use regional clusters for production where possible
- spread node pools across zones
- pair topology spread constraints with regional capacity
- verify cloud load balancer health checks during upgrades

### 11.9 GKE Commands

```bash
gcloud container clusters describe prod-cluster --region us-central1 \
  --format='value(currentMasterVersion,currentNodeVersion)'

gcloud container node-pools list --cluster prod-cluster --region us-central1
kubectl get nodes -L topology.kubernetes.io/zone
```

---

## 12. Reliability Patterns and Operational Guidance

This section ties the primitives together into production patterns.

### 12.1 PodDisruptionBudgets

PDBs protect against too much voluntary disruption at once.
They do not protect against involuntary failures like node crashes.

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: api-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: api
```

Alternative form:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: worker-pdb
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      app: worker
```

### 12.2 PDB Design Rules

- ensure replica count exceeds budget requirement
- do not set `minAvailable: 100%` unless you want drains to stall
- test drains before maintenance day
- remember PDBs affect Cluster Autoscaler scale-down

### 12.3 Readiness Gates

Readiness gates let external conditions participate in pod readiness.
This is useful when built-in probes are insufficient.

Examples:

- service mesh sidecar fully programmed
- certificate issued
- cloud load balancer registration confirmed
- application-specific cluster membership complete

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gated-pod
spec:
  readinessGates:
  - conditionType: "example.com/TrafficReady"
  containers:
  - name: app
    image: ghcr.io/example/app:1.0.0
```

### 12.4 Health Gates as an Operational Pattern

In practice, teams also use health gates outside the Pod spec.
Examples include:

- CI/CD pauses rollout if error rate rises
- service mesh or ingress controller promotes traffic gradually
- synthetic probes must pass before progressing rollout

The theory is simple:

- deployment success should depend on observed health, not merely object creation

### 12.5 Graceful Termination Pattern

```text
1. mark pod unready
2. wait for endpoint propagation
3. stop accepting new traffic
4. finish in-flight work
5. flush state / commit offsets
6. exit before SIGKILL deadline
```

### 12.6 Graceful Termination Checklist

- readiness endpoint fails fast on drain signal
- preStop hook is short and purposeful
- app handles SIGTERM directly
- grace period exceeds worst-case request or transaction duration
- load balancer and ingress idle timeouts are understood

### 12.7 Multi-Replica Reliability Pattern

For user-facing stateless services:

- minimum 3 replicas for production critical paths when possible
- anti-affinity or topology spread across nodes
- spread across at least 2 zones, ideally 3
- PDB with at most 1 unavailable
- rolling update with surge capacity

### 12.8 Stateful Reliability Pattern

For quorum systems:

- odd number of members
- zone-aware placement
- stable storage per member
- deliberate liveness semantics
- rolling updates only after quorum impact review

### 12.9 Backpressure and Readiness

If a pod is overloaded, failing readiness is often better than crashing.
That lets upstream routing move traffic while the process survives.

### 12.10 Release Safety Pattern

A safe production rollout often includes:

- startup probe for long boot
- readiness probe for traffic safety
- minReadySeconds to prevent instant promotion
- progressive traffic shift
- rollback trigger on SLO regression

### 12.11 Drain and Maintenance Pattern

Before draining a node:

- confirm spare capacity exists
- confirm PDBs are realistic
- confirm topology rules will still allow scheduling
- confirm local state is replicated or safely movable

Drain carefully:

```bash
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```

After maintenance:

```bash
kubectl uncordon <node-name>
```

### 12.12 Runbook Questions for Any Reliability Review

- What happens if one pod dies?
- What happens if one node dies?
- What happens if one zone disappears?
- Can we roll forward and backward safely?
- What blocks a node drain?
- What metric tells us users are hurt?
- How quickly do we detect unhealthy pods and remove traffic?

### 12.13 Reliability Anti-Patterns

- one replica with a PDB
- liveness probe checks remote database health
- no resource requests on production workloads
- strict anti-affinity in a cluster too small to satisfy it
- stateful app on Deployment with shared mutable volume assumptions
- secret sprawl through environment variables without rotation plan
- HPA with CPU target but no meaningful CPU requests

### 12.14 SRE Review Template

| Area | Question | Good Sign | Bad Sign |
|---|---|---|---|
| rollout | can change happen gradually | surge + readiness + rollback | recreate by default for API |
| placement | are replicas isolated | zone spread and anti-affinity | all replicas land on one node |
| disruption | can maintenance proceed safely | sane PDB | drains blocked or too permissive |
| startup | can app boot safely | startup probe and clear init | liveness kills booting app |
| shutdown | can app drain cleanly | SIGTERM handled and grace tuned | SIGKILL during every rollout |
| scaling | is scaling metric meaningful | direct link to saturation | scaling on vanity metrics |
| state | is storage durable and restorable | tested restore path | no restore rehearsal |

---

## 13. High-Signal Command Reference

Use these commands to validate reliability assumptions quickly.

### 13.1 Control Plane and API Health

```bash
kubectl cluster-info
kubectl version --short
kubectl get --raw='/readyz?verbose'
kubectl get --raw='/livez?verbose'
```

### 13.2 Workload Health

```bash
kubectl get deploy,statefulset,daemonset -A
kubectl get pods -A -o wide
kubectl describe deployment web
kubectl rollout status deployment/web
```

### 13.3 Scheduling and Capacity

```bash
kubectl top nodes
kubectl top pods -A
kubectl describe pod pending-pod
kubectl get nodes -L topology.kubernetes.io/zone
```

### 13.4 Networking

```bash
kubectl get svc,endpoints,endpointslices -A
kubectl describe svc api
kubectl exec -it debug -- nslookup api
kubectl exec -it debug -- curl -sv http://api
```

### 13.5 Storage

```bash
kubectl get pv,pvc -A
kubectl describe pvc app-data
kubectl get storageclass
```

### 13.6 Security and Identity

```bash
kubectl auth can-i get secrets -n production --as=system:serviceaccount:production:api-sa
kubectl get sa,role,rolebinding -n production
kubectl get networkpolicy -A
```

### 13.7 Autoscaling

```bash
kubectl get hpa,vpa -A
kubectl describe hpa api-hpa
kubectl describe vpa api-vpa
kubectl get events --sort-by=.lastTimestamp -A
```

---

## 14. Closing Principles

Kubernetes reliability is not achieved by memorizing objects.
It is achieved by understanding control loops, failure domains, and the time it takes systems to converge.

Remember these core principles:

- the control plane must stay available enough to manage change
- the data plane must keep serving during component churn
- readiness protects users better than liveness
- resource declarations shape both scheduling and survival
- topology is a reliability feature, not decoration
- autoscaling is a feedback loop, so tune it like one
- storage needs restoration plans, not only provisioning plans
- security boundaries reduce both risk and blast radius
- graceful termination is a production requirement
- every maintenance event is a test of your design

If you can explain how your workload behaves during:

- rollout
- scale spike
- node drain
- zone failure
- credential rotation
- storage failover

then you are operating Kubernetes as a reliability engineer, not merely as a YAML author.

