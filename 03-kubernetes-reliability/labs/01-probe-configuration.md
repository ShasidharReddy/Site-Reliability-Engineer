# Lab 01: Advanced Probe Configuration and Graceful Shutdown
## Lab Overview
This lab is an SRE-focused guide to safe probe design in Kubernetes. You will deploy a slow-starting app, exercise `startupProbe`, `readinessProbe`, and `livenessProbe`, compare good and bad patterns, test HTTP/TCP/exec/gRPC probe styles, and validate graceful shutdown with readiness drain plus `preStop` lifecycle hooks.

**Estimated time:** 75-90 minutes  
**Difficulty:** Advanced  
**Focus:** Health signaling that helps Kubernetes make safe decisions

---
## Prerequisites
- A disposable Kubernetes cluster with at least 2 worker nodes
- `kubectl` access with permission to create Deployments, Services, and ConfigMaps
- Familiarity with Pod lifecycle, rollouts, and basic troubleshooting
- Optional but useful: `jq`, `watch`, `stern`
- For gRPC probes, Kubernetes v1.27+ is recommended

> Use a non-production cluster. Several exercises intentionally make Pods fail probes.

---
## Learning Objectives
- Separate startup, readiness, and liveness responsibilities correctly
- Explain why dependency-aware liveness often causes outages
- Use HTTP, TCP, exec, and gRPC probes in the right situations
- Tune probes for JVM, Python, and Node.js services
- Reproduce common failure modes and identify symptoms quickly
- Implement graceful shutdown with early readiness drop and lifecycle hooks

---
## Scenario
You support a payment API that starts slowly on cold nodes, warms dependencies after boot, and occasionally experiences GC pauses or event-loop stalls. Recent incidents showed three problems: Pods restarted during initialization, Services routed traffic before dependencies were ready, and rolling updates returned 502s because terminating Pods still received traffic. Your goal is to redesign health signaling so Kubernetes makes safer choices.

---
## Architecture Diagram
```text
                           +------------------------------+
                           |           kubelet            |
                           | startupProbe -> boot         |
                           | readinessProbe -> traffic    |
                           | livenessProbe -> restart     |
                           +---------------+--------------+
                                           |
                                           v
+-------------------+      ClusterIP   +---------------------------+
| clients / testpod | ---------------> | Service: probe-demo-svc   |
+-------------------+                  +-------------+-------------+
                                                     |
                            +------------------------+------------------------+
                            |                                                 |
                            v                                                 v
                +---------------------------+                   +---------------------------+
                | Pod A                     |                   | Pod B                     |
                | /health/live              |                   | /health/live              |
                | /health/ready             |                   | /health/ready             |
                | startup delay             |                   | startup delay             |
                | preStop drops readiness   |                   | preStop drops readiness   |
                +---------------------------+                   +---------------------------+
```

---
## Probe Design Rules
| Probe | Use it for | Healthy signal | Avoid checking |
|---|---|---|---|
| Startup | Slow boot protection | Process can bind and initialize | Shared dependencies |
| Readiness | Traffic admission | Pod can serve requests now | Expensive synthetic transactions |
| Liveness | Deadlock or unrecoverable hang | Restart is safer than waiting | Database/cache/network blips |

**Golden rule:** readiness failures should stop traffic; liveness failures should justify restart.

---
## Lab Setup
```bash
kubectl create namespace sre-probes
kubectl config set-context --current --namespace=sre-probes
kubectl get ns sre-probes
```
Expected result:
```text
namespace/sre-probes created
```

---
## Step 1 - Deploy a Probe-Aware Demo Application
Use a lab image that already exposes `/health/live`, `/health/ready`, and `/health/full`, sleeps during startup, and reacts to files in `/tmp` so you can trigger failures without rebuilding anything.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: probe-demo
  namespace: sre-probes
spec:
  replicas: 2
  selector:
    matchLabels:
      app: probe-demo
  template:
    metadata:
      labels:
        app: probe-demo
    spec:
      terminationGracePeriodSeconds: 45
      containers:
        - name: app
          image: ghcr.io/platform-labs/probe-demo:1.0
          env:
            - name: STARTUP_DELAY
              value: "35"
            - name: SHUTDOWN_DELAY
              value: "20"
          ports:
            - containerPort: 8080
          startupProbe:
            httpGet: { path: /health/live, port: 8080 }
            periodSeconds: 5
            failureThreshold: 12
          readinessProbe:
            httpGet: { path: /health/ready, port: 8080 }
            periodSeconds: 5
            failureThreshold: 2
          livenessProbe:
            httpGet: { path: /health/live, port: 8080 }
            periodSeconds: 10
            failureThreshold: 3
          lifecycle:
            preStop:
              exec:
                command: ["sh", "-c", "rm -f /tmp/ready && sleep 15"]
---
apiVersion: v1
kind: Service
metadata:
  name: probe-demo-svc
  namespace: sre-probes
spec:
  selector:
    app: probe-demo
  ports:
    - port: 80
      targetPort: 8080
```
Apply and watch:
```bash
kubectl apply -f probe-demo.yaml
kubectl rollout status deploy/probe-demo
kubectl get pods -w
kubectl get endpoints probe-demo-svc -w
```
Expected behavior: Pods stay `Running` but not `Ready` during startup, do not restart-loop, and eventually become `1/1 Ready`.

---
## Step 2 - Confirm Startup Probe Protection
Check restart counts during startup:
```bash
kubectl get pods -l app=probe-demo -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount
```
Expected output after stabilization:
```text
NAME                         READY   RESTARTS
probe-demo-xxxxxxxxxx-aaaaa  true    0
probe-demo-xxxxxxxxxx-bbbbb  true    0
```
`startupProbe` disables liveness and readiness until initialization finishes. This is critical for JVM cold starts, schema migrations, cache warm-up, and large dependency graphs.

---
## Step 3 - Validate Readiness Controls Traffic
Open a test Pod:
```bash
kubectl run curlbox --rm -it --image=curlimages/curl:8.7.1 -- sh
```
Inside it:
```bash
while true; do
  date +%T
  curl -s -o /dev/null -w "%{http_code}\n" http://probe-demo-svc/health/ready || true
  sleep 2
done
```
In another terminal, remove readiness from one Pod:
```bash
POD=$(kubectl get pod -l app=probe-demo -o jsonpath='{.items[0].metadata.name}')
kubectl exec "$POD" -- rm -f /tmp/ready
kubectl get endpoints probe-demo-svc -w
```
Expected result:
- The chosen Pod keeps running
- It is removed from Service endpoints
- Requests continue to the remaining ready Pod
- `RESTARTS` does not increase

Validation:
```bash
kubectl describe pod "$POD" | grep -A4 -E "Readiness|Liveness"
kubectl get endpointslices -l kubernetes.io/service-name=probe-demo-svc
```
Key lesson: readiness failure is a traffic-control signal, not a restart signal.

---
## Step 4 - Trigger a Liveness Failure
Restore markers first if needed:
```bash
kubectl exec "$POD" -- sh -c 'touch /tmp/ready && touch /tmp/live'
```
Now simulate a fatal condition:
```bash
kubectl exec "$POD" -- rm -f /tmp/live
kubectl get pod "$POD" -w
```
Expected result:
- Readiness becomes false
- Liveness fails
- The container is restarted by kubelet
- Restart count increments

Confirm with:
```bash
kubectl get pod "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}{"\n"}'
kubectl describe pod "$POD" | grep -A8 -E "Liveness|Back-off|Killing"
```
Expected event pattern:
```text
Warning  Unhealthy  kubelet  Liveness probe failed: HTTP probe failed with statuscode: 500
Normal   Killing    kubelet  Container app failed liveness probe, will be restarted
```

---
## Step 5 - Probe Patterns, Probe Types, and Runtime Tuning
### Good vs bad patterns
Bad: dependency-aware liveness restarts healthy processes during database or cache incidents.
```yaml
livenessProbe:
  httpGet:
    path: /health/full
    port: 8080
  periodSeconds: 5
  failureThreshold: 1
```
Better: keep liveness process-local and push dependency checks into readiness.
```yaml
livenessProbe:
  httpGet: { path: /health/live, port: 8080 }
  periodSeconds: 10
  failureThreshold: 3
readinessProbe:
  httpGet: { path: /health/ready, port: 8080 }
  periodSeconds: 5
  failureThreshold: 2
```
Bad: no startup probe for slow apps.
```yaml
livenessProbe:
  httpGet: { path: /health/live, port: 8080 }
  initialDelaySeconds: 5
  periodSeconds: 5
  failureThreshold: 3
```
Better:
```yaml
startupProbe:
  httpGet: { path: /health/live, port: 8080 }
  periodSeconds: 5
  failureThreshold: 24
```
Bad: readiness hits a deep transaction path such as `/checkout/place-order`; that is expensive, stateful, and too noisy.

### Exec probe example
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: exec-probe-demo
  namespace: sre-probes
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "touch /tmp/healthy && sleep 3600"]
      startupProbe:
        exec:
          command: ["sh", "-c", "test -f /tmp/healthy"]
      readinessProbe:
        exec:
          command: ["sh", "-c", "test -f /tmp/healthy"]
      livenessProbe:
        exec:
          command: ["sh", "-c", "test -f /tmp/healthy"]
```
Test it with `kubectl exec exec-probe-demo -- rm -f /tmp/healthy`. Exec probes are useful but more expensive than HTTP probes because each check forks a process.

### TCP probe example
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: tcp-probe-demo
  namespace: sre-probes
spec:
  containers:
    - name: app
      image: ghcr.io/platform-labs/tcp-probe-demo:1.0
      ports:
        - containerPort: 9090
      readinessProbe:
        tcpSocket:
          port: 9090
      livenessProbe:
        tcpSocket:
          port: 9090
```
Use TCP when the best signal is simply whether a socket accepts connections. A listening socket still tells you less than a proper HTTP readiness endpoint.

### gRPC probe example
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grpc-demo
  namespace: sre-probes
spec:
  replicas: 2
  selector:
    matchLabels:
      app: grpc-demo
  template:
    metadata:
      labels:
        app: grpc-demo
    spec:
      containers:
        - name: app
          image: ghcr.io/your-org/grpc-demo:latest
          ports:
            - containerPort: 50051
          startupProbe:
            grpc:
              port: 50051
          readinessProbe:
            grpc:
              port: 50051
          livenessProbe:
            grpc:
              port: 50051
```
Use native gRPC probes only when the app implements `grpc.health.v1.Health` and its readiness view really means “safe for traffic.”

### Runtime-specific tuning
- **JVM:** allow minutes of startup protection for class loading and JIT warm-up; keep liveness tolerant of GC pauses; pair probe tuning with memory settings such as `-XX:MaxRAMPercentage`
- **Python:** keep health endpoints independent of expensive ORM work; ensure Gunicorn or uWSGI workers are fully booted before readiness returns 200
- **Node.js:** avoid probing the main request path; implement `SIGTERM` handling so readiness drops before the event loop exits

Example starting points:
```yaml
# JVM
startupProbe: { httpGet: { path: /health/live, port: 8080 }, periodSeconds: 5, failureThreshold: 36 }
livenessProbe: { httpGet: { path: /health/live, port: 8080 }, periodSeconds: 15, timeoutSeconds: 2, failureThreshold: 3 }

# Python
startupProbe: { httpGet: { path: /health/live, port: 8000 }, periodSeconds: 5, failureThreshold: 12 }
readinessProbe: { httpGet: { path: /health/ready, port: 8000 }, periodSeconds: 5, timeoutSeconds: 1 }

# Node.js
startupProbe: { httpGet: { path: /health/live, port: 3000 }, periodSeconds: 3, failureThreshold: 20 }
livenessProbe: { httpGet: { path: /health/live, port: 3000 }, periodSeconds: 10, timeoutSeconds: 1 }
```
---
## Step 10 - Dependency Outage and Graceful Shutdown
Simulate a downstream outage to show why readiness may consider dependencies while liveness usually should not:
```bash
POD=$(kubectl get pod -l app=probe-demo -o jsonpath='{.items[0].metadata.name}')
kubectl exec "$POD" -- touch /tmp/dependency-down
kubectl describe pod "$POD" | grep -A4 -E "Readiness|Liveness"
kubectl get endpoints probe-demo-svc -w
```
Expected behavior:
- readiness fails
- the Pod is removed from Service endpoints
- liveness still succeeds
- no restart storm occurs

Now observe graceful shutdown. Start continuous traffic:
```bash
kubectl run traffic --rm -it --image=curlimages/curl:8.7.1 -- sh
```
Inside the Pod:
```bash
while true; do
  curl -s http://probe-demo-svc/ | tr -d '\n'; echo " $(date +%T)"
  sleep 1
done
```
Delete one application Pod from another terminal:
```bash
POD=$(kubectl get pod -l app=probe-demo -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod "$POD"
kubectl get endpoints probe-demo-svc -w
```
Expected sequence:
1. `preStop` removes `/tmp/ready`
2. Endpoint removal happens before final process exit
3. Remaining Pods continue serving traffic
4. Logs show readiness drop before shutdown delay completes

Inspect prior logs:
```bash
kubectl logs "$POD" --previous
```
Typical output:
```text
received signal 15; dropping readiness
sleeping 20s before exit
```

---
## Failure Scenarios to Rehearse
- Slow startup after node replacement: rollout stalls and restart counts rise; usually missing or undersized `startupProbe`
- Database outage: many Pods restart together; usually caused by dependency-aware liveness
- Graceful shutdown failure: 502s or resets during rollout; usually no readiness drop or too-short `terminationGracePeriodSeconds`
- Event-loop stall or deadlock: process is running but no progress; this may justify liveness-triggered restart

---
## Troubleshooting
```bash
kubectl describe pod -l app=probe-demo
kubectl logs deploy/probe-demo
kubectl get endpoints probe-demo-svc -o yaml
kubectl get events --sort-by=.lastTimestamp | tail -30
```
Common issues:
- Pods restart immediately: `startupProbe` threshold is too low
- Readiness never becomes true: the app script failed or `/tmp/ready` was not created
- Service still routes to terminating Pods: readiness drop happened too late
- Probe timeouts are intermittent: CPU throttling or node pressure may require higher `timeoutSeconds`
- gRPC probes never pass: health service missing, wrong port, or unsupported cluster version

---
## Cleanup
```bash
kubectl delete namespace sre-probes
```
Verify:
```bash
kubectl get ns sre-probes
```
Expected output:
```text
Error from server (NotFound): namespaces "sre-probes" not found
```

---
## Reflection Questions
1. Which failures in your environment should drop readiness but not trigger restart?
2. Which workloads need long startup protection, and how long is realistic?
3. Where do you still use a single `/health` endpoint for every purpose?
4. How would you validate graceful shutdown through ingress, service mesh, or external load balancers?
5. Which runtime in your platform is most vulnerable to bad probe defaults, and why?

---
## Key Takeaways
- Readiness is for traffic
- Liveness is for deadlock or unrecoverable hang
- Startup probes protect slow initialization
- Shared dependency checks belong in readiness, not liveness
- Graceful shutdown requires readiness drop, `preStop`, and enough termination grace
- Probe tuning is runtime-specific, not one-size-fits-all
