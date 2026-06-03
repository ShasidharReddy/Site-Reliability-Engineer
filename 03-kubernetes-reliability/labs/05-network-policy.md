# Lab 05: Advanced Network Policy and Namespace Isolation

## Objective
Implement a realistic zero-trust policy model for Kubernetes namespaces using:
- default deny ingress and egress
- explicit allow rules for DNS, frontend-to-API, and API-to-database
- namespace isolation between application, monitoring, and untrusted namespaces
- active validation with `curl`, `nc`, and `kubectl exec`
- troubleshooting steps for blocked flows and policy mismatches

## Why this lab matters
NetworkPolicy is one of the easiest Kubernetes controls to misread. Traffic may fail because of:
- an ingress policy on the destination
- an egress policy on the source
- wrong namespace labels
- CNI plugin limitations
- DNS accidentally blocked
- port or protocol mismatches

This lab builds the habit of proving each allowed path and denying everything else.

## Topology
```text
                   +------------------------------+
                   |        ingress/client        |
                   +--------------+---------------+
                                  |
                                  v
                    +----------------------------+
                    | frontend namespace: app    |
                    | frontend pods              |
                    +-------------+--------------+
                                  |
                        allow TCP 8080 only
                                  |
                                  v
                    +----------------------------+
                    | api namespace: app         |
                    | api pods                   |
                    +-------------+--------------+
                                  |
                       allow TCP 5432 only
                                  |
                                  v
                    +----------------------------+
                    | data namespace: app        |
                    | postgres pods              |
                    +----------------------------+

       monitoring namespace --> scrape /metrics only if explicitly allowed
       untrusted namespace  --> blocked by default deny and namespace isolation
```

## Prerequisites
| Requirement | Why it matters | Command |
|---|---|---|
| CNI with NetworkPolicy support | policies do nothing without enforcement | `kubectl get pods -n kube-system -o wide` |
| Namespace labels | selectors rely on labels | `kubectl get ns --show-labels` |
| Test images with curl/nc | needed to validate allowed and denied flows | `curlimages/curl`, `busybox`, `nicolaka/netshoot` |

## Create namespaces and labels
```bash
kubectl create namespace app
kubectl create namespace data
kubectl create namespace monitoring
kubectl create namespace untrusted

kubectl label namespace app access=application tier=frontend --overwrite
kubectl label namespace data access=database tier=backend --overwrite
kubectl label namespace monitoring access=monitoring --overwrite
kubectl label namespace untrusted access=none --overwrite
```

## Deploy sample workloads
Use small frontend, API, database, and toolbox deployments. The full manifests are intentionally simple; the learning value in this lab is in the policies and validation.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: app
spec:
  replicas: 2
  template:
    metadata:
      labels:
        app: frontend
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: app
spec:
  replicas: 2
  template:
    metadata:
      labels:
        app: api
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: data
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: postgres
```

Example apply sequence:
```bash
kubectl rollout status deploy/frontend -n app
kubectl rollout status deploy/api -n app
kubectl rollout status deploy/postgres -n data
kubectl rollout status deploy/toolbox -n untrusted
```

## Baseline connectivity before policies
```bash
kubectl exec -n app deploy/frontend -- curl -sS api.app.svc.cluster.local:8080
kubectl exec -n app deploy/api -- nc -vz postgres.data.svc.cluster.local 5432
kubectl exec -n untrusted deploy/toolbox -- curl -m 3 -sS api.app.svc.cluster.local:8080
kubectl exec -n untrusted deploy/toolbox -- nslookup kubernetes.default.svc.cluster.local
```

Expected baseline: everything can usually talk to everything if no policies exist.

## Part 1 - Default deny all ingress and egress
This must be the starting point.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: app
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: data
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

Apply it:
```bash
kubectl apply -f manifests/network-policy-default-deny.yaml
kubectl get networkpolicy -A
```

### Validate the deny
```bash
kubectl exec -n app deploy/frontend -- curl -m 3 -sS api.app.svc.cluster.local:8080 || echo blocked
kubectl exec -n app deploy/api -- nc -vz -w 3 postgres.data.svc.cluster.local 5432 || echo blocked
kubectl exec -n app deploy/frontend -- nslookup kubernetes.default.svc.cluster.local || echo dns-blocked
```

Expected result: API traffic and DNS both fail until allowed explicitly.

## Part 2 - Restore DNS egress
DNS is the first allow rule most teams forget.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: app
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns-egress
  namespace: data
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

Apply it:
```bash
kubectl apply -f manifests/network-policy-allow-dns.yaml
```

Validate DNS:
```bash
kubectl exec -n app deploy/frontend -- nslookup api.app.svc.cluster.local
kubectl exec -n app deploy/api -- nslookup postgres.data.svc.cluster.local
```

## Part 3 - Allow frontend to call API only on TCP/8080
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow-from-frontend
  namespace: app
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
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-allow-egress-to-api
  namespace: app
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: api
    ports:
    - protocol: TCP
      port: 8080
```

Apply it:
```bash
kubectl apply -f manifests/network-policy-frontend-api.yaml
```

Validate allowed and denied paths:
```bash
kubectl exec -n app deploy/frontend -- curl -m 3 -sS api.app.svc.cluster.local:8080
kubectl exec -n app deploy/api -- curl -m 3 -sS frontend.app.svc.cluster.local || echo blocked
kubectl exec -n untrusted deploy/toolbox -- curl -m 3 -sS api.app.svc.cluster.local:8080 || echo blocked
kubectl exec -n app deploy/frontend -- nc -vz -w 3 api.app.svc.cluster.local 9999 || echo blocked
```

## Part 4 - Allow API to reach Postgres only
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: postgres-allow-api
  namespace: data
spec:
  podSelector:
    matchLabels:
      app: postgres
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          access: application
      podSelector:
        matchLabels:
          app: api
    ports:
    - protocol: TCP
      port: 5432
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow-egress-postgres
  namespace: app
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          access: database
      podSelector:
        matchLabels:
          app: postgres
    ports:
    - protocol: TCP
      port: 5432
```

Apply it:
```bash
kubectl apply -f manifests/network-policy-api-postgres.yaml
```

Validate DB path:
```bash
kubectl exec -n app deploy/api -- nc -vz -w 3 postgres.data.svc.cluster.local 5432
kubectl exec -n app deploy/frontend -- nc -vz -w 3 postgres.data.svc.cluster.local 5432 || echo blocked
kubectl exec -n untrusted deploy/toolbox -- nc -vz -w 3 postgres.data.svc.cluster.local 5432 || echo blocked
```

## Part 5 - Namespace isolation for monitoring and untrusted traffic
Example: allow monitoring to scrape API metrics without opening the API to everybody.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow-monitoring-metrics
  namespace: app
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          access: monitoring
    ports:
    - protocol: TCP
      port: 8080
```

If you run Prometheus in `monitoring` namespace, it can scrape the API while `untrusted` remains blocked.

Apply it:
```bash
kubectl apply -f manifests/network-policy-monitoring.yaml
```

Validate namespace isolation:
```bash
kubectl run mon-curl -n monitoring --image=curlimages/curl --restart=Never -- sleep 3600
kubectl wait --for=condition=Ready pod/mon-curl -n monitoring --timeout=60s
kubectl exec -n monitoring mon-curl -- curl -m 3 -sS api.app.svc.cluster.local:8080/metrics | head
kubectl exec -n untrusted deploy/toolbox -- curl -m 3 -sS api.app.svc.cluster.local:8080/metrics || echo blocked
```

## Connectivity test matrix
| Source | Destination | Port | Expected |
|---|---|---|---|
| frontend.app | api.app | 8080/TCP | allowed |
| frontend.app | postgres.data | 5432/TCP | denied |
| api.app | postgres.data | 5432/TCP | allowed |
| toolbox.untrusted | api.app | 8080/TCP | denied |
| toolbox.untrusted | postgres.data | 5432/TCP | denied |
| frontend.app | kube-dns | 53/UDP,TCP | allowed |
| monitoring | api.app `/metrics` | 8080/TCP | allowed if metrics policy applied |

## Useful test commands
```bash
kubectl get netpol -A
kubectl describe netpol api-allow-from-frontend -n app
kubectl exec -n app deploy/frontend -- curl -v --connect-timeout 3 api.app.svc.cluster.local:8080
kubectl exec -n app deploy/frontend -- nc -vz -w 3 api.app.svc.cluster.local 8080
kubectl exec -n app deploy/frontend -- nc -vz -w 3 postgres.data.svc.cluster.local 5432
kubectl exec -n untrusted deploy/toolbox -- dig +short api.app.svc.cluster.local
kubectl exec -n untrusted deploy/toolbox -- tcpdump -ni any port 53 or port 8080
```

## Debugging blocked connections
### Fast flow
```text
Connection fails
   |
   +--> Check DNS works?
   |      |
   |      +--> No -> allow egress to kube-dns
   |
   +--> Check service resolves but times out?
   |      |
   |      +--> likely policy or target not listening
   |
   +--> Check source egress policy
   |
   +--> Check destination ingress policy
   |
   +--> Check labels and namespace labels used by selectors
   |
   +--> Check CNI supports policy and policyTypes are correct
```

### Troubleshooting table
| Symptom | Likely cause | Command | Fix |
|---|---|---|---|
| `curl: Could not resolve host` | DNS egress blocked | `kubectl exec ... -- nslookup api.app.svc.cluster.local` | allow egress to CoreDNS |
| connection timeout | packet dropped by policy | `kubectl describe netpol -A` | add source egress or destination ingress rule |
| connection refused | app reachable but port closed | `kubectl get endpoints svc -A` | fix app port or service targetPort |
| policy seems ignored | CNI lacks support | inspect CNI docs and DaemonSet | enable supported plugin |
| namespace rule not matching | missing labels | `kubectl get ns --show-labels` | add expected namespace labels |

### Debugging sequence
```bash
SRC_NS=app
SRC_POD=$(kubectl get pod -n app -l app=frontend -o jsonpath='{.items[0].metadata.name}')
DST_NS=app
DST_SVC=api

kubectl exec -n $SRC_NS $SRC_POD -- nslookup ${DST_SVC}.${DST_NS}.svc.cluster.local
kubectl exec -n $SRC_NS $SRC_POD -- nc -vz -w 3 ${DST_SVC}.${DST_NS}.svc.cluster.local 8080
kubectl get svc $DST_SVC -n $DST_NS -o wide
kubectl get endpoints $DST_SVC -n $DST_NS -o wide
kubectl describe netpol -n $SRC_NS
kubectl describe netpol -n $DST_NS
kubectl get pod -n $SRC_NS $SRC_POD --show-labels
kubectl get ns $SRC_NS --show-labels
kubectl get ns $DST_NS --show-labels
```

## Expected observations
- Default deny breaks east-west connectivity immediately.
- DNS fails until egress to CoreDNS is restored.
- Allow rules must exist on the source for egress and on the destination for ingress.
- Namespace selectors are powerful, but only if namespace labels are stable.
- Timeouts usually indicate dropped packets; refusals usually indicate application or service issues.

## Validation checklist
- [ ] CNI plugin supports NetworkPolicy.
- [ ] Both `app` and `data` namespaces have default deny applied.
- [ ] DNS works after allow policy is added.
- [ ] `frontend -> api:8080` succeeds.
- [ ] `api -> postgres:5432` succeeds.
- [ ] `frontend -> postgres:5432` fails.
- [ ] `untrusted -> api` fails.
- [ ] monitoring traffic is only allowed when explicitly whitelisted.

## Prevention guidance
- Start each namespace with a deny-all baseline.
- Label namespaces intentionally and treat labels like policy API contracts.
- Keep DNS allow rules reusable and standardized.
- Test both success and failure paths after every policy change.
- Prefer small, purpose-driven policies over one giant policy object.
- Add runbook examples showing exact source, destination, namespace, and port.

## Cleanup
```bash
kubectl delete ns app data monitoring untrusted
```
