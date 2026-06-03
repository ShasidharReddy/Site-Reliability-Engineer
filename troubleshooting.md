# SRE Troubleshooting Master Guide

Quick reference for production issues. Jump to the relevant section or use Ctrl+F.
For deep dives, follow the links to module-specific troubleshooting guides.

## How to use this guide

- Start with the symptom that matches the customer-visible problem, not the tool that is already open.
- Run the first command pack exactly as written before changing configuration.
- Confirm blast radius: single workload, namespace, cluster, region, or provider.
- Follow the module guide link when the quick fix is not enough or the service owner needs a deeper runbook.

## Quick Triage Matrix

| Symptom | Most Likely Cause | First Commands | Module Guide |
|---|---|---|---|
| Pod crash loops | A bad image, broken startup dependency, or failing init/migration causes the main container to exit before readiness succeeds. | `kubectl get pods -A \| grep CrashLoopBackOff; kubectl describe pod <pod> -n <ns>` | [Kubernetes & Infrastructure](03-kubernetes-reliability/troubleshooting.md) |
| OOMKilled containers | The container crossed its memory limit because of a real leak, a burstier workload, or requests that no longer match reality. | `kubectl get pods -A \| grep OOMKilled; kubectl describe pod <pod> -n <ns>` | [Kubernetes & Infrastructure](03-kubernetes-reliability/troubleshooting.md) |
| Pending pods | Insufficient CPU, memory, ephemeral storage, or zone-specific capacity prevents scheduling. | `kubectl get pods -A \| grep Pending; kubectl describe pod <pod> -n <ns>` | [Kubernetes & Infrastructure](03-kubernetes-reliability/troubleshooting.md) |
| ImagePullBackOff | The image tag is wrong, the registry is unavailable, or imagePullSecrets/service-account permissions are missing. | `kubectl get pods -A \| grep ImagePullBackOff; kubectl describe pod <pod> -n <ns>` | [Kubernetes & Infrastructure](03-kubernetes-reliability/troubleshooting.md) |
| Node NotReady | Kubelet heartbeats are failing because of node reboot, network isolation, disk exhaustion, or cloud-host degradation. | `kubectl get nodes; kubectl describe node <node>` | [Kubernetes & Infrastructure](03-kubernetes-reliability/troubleshooting.md) |
| Disk pressure on nodes | Container logs, image layers, emptyDir volumes, or compaction backlogs consumed node ephemeral storage. | `kubectl describe node <node>; kubectl get events -A --sort-by=.lastTimestamp \| egrep 'DiskPressure\|Evicted' \| tail -30` | [Kubernetes & Infrastructure](03-kubernetes-reliability/troubleshooting.md) |
| Memory pressure on nodes | One noisy workload, too many undersized requests, or missing system reservations can overwhelm the node. | `kubectl describe node <node>; kubectl top node <node>` | [Kubernetes & Infrastructure](03-kubernetes-reliability/troubleshooting.md) |
| HPA not scaling | Missing resource requests, broken custom metrics, or stale metrics-server data prevent the HPA controller from making decisions. | `kubectl get hpa -A; kubectl describe hpa <hpa> -n <ns>` | [Kubernetes & Infrastructure](03-kubernetes-reliability/troubleshooting.md) |
| PDB blocking rollout | The PodDisruptionBudget is stricter than the current replica count or health state allows. | `kubectl get pdb -A; kubectl describe pdb <pdb> -n <ns>` | [Kubernetes & Infrastructure](03-kubernetes-reliability/troubleshooting.md) |
| Service unreachable inside the cluster | Selector drift, wrong targetPort, failing readiness probes, or network policy drops prevent backends from receiving traffic. | `kubectl get svc,endpoints,endpointslices -n <ns> <service>; kubectl describe svc <service> -n <ns>` | [Kubernetes & Infrastructure](03-kubernetes-reliability/troubleshooting.md) |
| DNS failure in cluster | CoreDNS crash loops, upstream resolver latency, or bad stub-domain configuration break service discovery. | `kubectl -n kube-system get pods -l k8s-app=kube-dns; kubectl -n kube-system logs deploy/coredns --tail=200` | [Kubernetes & Infrastructure](03-kubernetes-reliability/troubleshooting.md) |
| Alert firing but the service looks healthy | The alert may be measuring a proxy signal, using stale labels, or missing traffic-volume guards that distinguish noise from customer pain. | `kubectl -n monitoring port-forward svc/prometheus-operated 9090:9090; curl -s http://127.0.0.1:9090/api/v1/rules \| jq '.data.groups[]?.rules[] \| select(.state=="firing") \| {name: .name, query: .query}'` | [Monitoring & Alerting](01-monitoring-observability/troubleshooting.md) |
| Alert not firing when it should | The rule expression may never become true because of missing series, wrong labels, absent recording rules, or an overly strict `for` clause. | `kubectl -n monitoring get prometheusrule; curl -s http://127.0.0.1:9090/api/v1/rules \| jq '.data.groups[]?.rules[] \| select(.name=="<ALERT_NAME>")'` | [Monitoring & Alerting](01-monitoring-observability/troubleshooting.md) |
| Prometheus high memory usage | A new metric label with unbounded values, too many scrape targets, or long remote-write backpressure is exploding head-block memory. | `kubectl top pod -n monitoring \| grep prometheus; kubectl -n monitoring exec sts/prometheus-kube-prometheus-stack-prometheus -- promtool tsdb analyze /prometheus \| head -50` | [Monitoring & Alerting](01-monitoring-observability/troubleshooting.md) |
| Prometheus TSDB corruption | Unclean shutdown during disk pressure, storage faults, or WAL replay bugs left an unreadable block or WAL segment. | `kubectl -n monitoring logs statefulset/prometheus-kube-prometheus-stack-prometheus --tail=300; kubectl -n monitoring describe pod prometheus-kube-prometheus-stack-prometheus-0` | [Monitoring & Alerting](01-monitoring-observability/troubleshooting.md) |
| Grafana panels show No Data | Datasource credentials, UID drift, bad templating variables, or empty label matches are the usual causes. | `kubectl -n monitoring get pods \| grep grafana; kubectl -n monitoring logs deploy/kube-prometheus-stack-grafana --tail=200` | [Monitoring & Alerting](01-monitoring-observability/troubleshooting.md) |
| Alertmanager not sending notifications | Bad receiver credentials, routing mistakes, inhibition rules, or network egress blocks prevent notifications from leaving Alertmanager. | `kubectl -n monitoring get pods \| grep alertmanager; kubectl -n monitoring logs statefulset/alertmanager-kube-prometheus-stack-alertmanager --tail=200` | [Monitoring & Alerting](01-monitoring-observability/troubleshooting.md) |
| Error budget exhausted unexpectedly | The SLI denominator or numerator changed, hidden low-volume endpoints started failing, or a silent burn was not mapped to a visible incident. | `curl -s "http://127.0.0.1:9090/api/v1/query?query=(1-sum(rate(http_requests_total{job=\"api\",status!~\"5..\"}[30d]))/sum(rate(http_requests_total{job=\"api\"}[30d])))" \| jq .; curl -s "http://127.0.0.1:9090/api/v1/query?query=sum(rate(http_requests_total{job=\"api\",status=~\"5..\"}[5m]))" \| jq .` | [SLO & Error Budget](02-sre-principles/troubleshooting.md) |
| SLO dashboard shows conflicting numbers | The dashboards use different label sets, burn windows, or definitions of success. | `curl -s "http://127.0.0.1:9090/api/v1/query?query=<DASHBOARD_QUERY_A>" \| jq .; curl -s "http://127.0.0.1:9090/api/v1/query?query=<DASHBOARD_QUERY_B>" \| jq .` | [SLO & Error Budget](02-sre-principles/troubleshooting.md) |
| Fast burn alert firing constantly | Burn-rate thresholds may be correct mathematically but missing a traffic floor, route filter, or maintenance exclusion. | `curl -s "http://127.0.0.1:9090/api/v1/query?query=<FAST_BURN_EXPR>" \| jq .; curl -s "http://127.0.0.1:9090/api/v1/query?query=<SLOW_BURN_EXPR>" \| jq .` | [SLO & Error Budget](02-sre-principles/troubleshooting.md) |
| Incident escalation path broken | Pager policies, Alertmanager routing labels, or contact escalation rules are stale or misconfigured. | `gh api /users >/dev/null; kubectl -n monitoring logs statefulset/alertmanager-kube-prometheus-stack-alertmanager --tail=200 \| grep -i pagerduty` | [Incident Management](04-incident-management/troubleshooting.md) |
| Postmortem action items not tracked | The organization writes postmortems but lacks a durable system of record linking action items to owners and deadlines. | `gh issue list --label postmortem --state open; grep -R "Action Items" -n 04-incident-management 09-production-readiness` | [Incident Management](04-incident-management/troubleshooting.md) |
| On-call engineer not reachable | Phone, push, or SMS contact methods are outdated, or the engineer lacks the access needed to act even after paging. | `gh api /user >/dev/null; grep -R "on-call" -n 04-incident-management` | [Incident Management](04-incident-management/troubleshooting.md) |
| GKE node pool out of capacity | Regional CPU quota, zonal stockouts, or max-nodes limits stop GKE from adding workers. | `gcloud container clusters describe <cluster> --region <region>; gcloud container node-pools describe <pool> --cluster <cluster> --region <region>` | [GCP & Cloud Infrastructure](05-gcp-operations/troubleshooting.md) |
| IAM permission denied errors | A role binding was removed, workload identity mapping drifted, or a service account key/secret was rotated without propagation. | `gcloud projects get-iam-policy <project-id> --flatten=bindings[].members --format='table(bindings.role,bindings.members)'; gcloud iam service-accounts get-iam-policy <sa>@<project-id>.iam.gserviceaccount.com` | [GCP & Cloud Infrastructure](05-gcp-operations/troubleshooting.md) |
| Cloud Logging missing entries | Agent backpressure, dropped permissions, bad exclusion filters, or ingestion delays are preventing logs from landing. | `gcloud logging read "resource.type=k8s_container AND resource.labels.cluster_name=<cluster>" --limit 20 --freshness=10m; kubectl -n kube-system get pods \| grep -E 'fluent\|logging'` | [GCP & Cloud Infrastructure](05-gcp-operations/troubleshooting.md) |
| GCS or Pub/Sub latency spike | Regional service latency, misrouted traffic, backlog growth, or client retry storms are delaying managed-service operations. | `gcloud monitoring time-series list --filter='metric.type="storage.googleapis.com/api/request_latencies"' --limit=5; gcloud monitoring time-series list --filter='metric.type="pubsub.googleapis.com/subscription/oldest_unacked_message_age"' --limit=5` | [GCP & Cloud Infrastructure](05-gcp-operations/troubleshooting.md) |
| High load average | The runnable queue is long because of CPU saturation, blocked threads, or heavy kernel work. | `uptime; top -o cpu -l 1 \| head -40` | [Linux & Networking](06-linux-networking/troubleshooting.md) |
| High I/O wait | Disk saturation, filesystem errors, or runaway log writes are stalling processes in uninterruptible sleep. | `iostat -xz 1 5; df -h` | [Linux & Networking](06-linux-networking/troubleshooting.md) |
| Surprise OOM process death | The kernel OOM killer terminated the process because the host ran out of reclaimable memory. | `dmesg \| egrep -i 'killed process\|out of memory' \| tail -20; ps aux --sort=-rss \| head -20` | [Linux & Networking](06-linux-networking/troubleshooting.md) |
| Packet loss or intermittent timeouts | Network policy, load balancer health, MTU mismatch, or regional path instability can all produce intermittent loss. | `ping -c 5 <target>; traceroute <target>` | [Linux & Networking](06-linux-networking/troubleshooting.md) |
| Disk full: bytes versus inodes | Either bytes are exhausted by a few large files or inodes are exhausted by huge numbers of tiny files. | `df -h; df -i` | [Linux & Networking](06-linux-networking/troubleshooting.md) |
| Connection pool exhaustion | Pool size is too small for concurrency, leaked connections are never returned, or the database slowed down enough to keep the pool occupied. | `kubectl logs deploy/<app> -n <ns> --since=15m \| egrep 'timeout\|pool\|connection'; kubectl exec -n <ns> <pod> -- ss -tan \| head -40` | [Application & Database](08-application-support-l2l3/troubleshooting.md) |
| Slow queries degrading service | A new query plan, missing index, lock contention, or replica lag is slowing request completion. | `kubectl logs deploy/<app> -n <ns> --since=15m \| grep -i slow; kubectl exec -n <ns> <db-pod> -- sh -c "psql -c 'select now();'"` | [Application & Database](08-application-support-l2l3/troubleshooting.md) |
| Memory leak diagnosis | A real heap leak, cache with no eviction, file-descriptor growth, or stuck request objects is retaining memory across traffic cycles. | `kubectl top pods -n <ns> --sort-by=memory; kubectl describe pod <pod> -n <ns>` | [Application & Database](08-application-support-l2l3/troubleshooting.md) |
| Rollout stuck | Readiness never succeeds, unavailable-budget settings are too tight, or replacement pods cannot schedule. | `kubectl rollout status deploy/<deploy> -n <ns>; kubectl describe deploy <deploy> -n <ns>` | [Deployment & Release](03-kubernetes-reliability/troubleshooting.md) |
| Canary not advancing | Automated analysis found a regression, metrics were missing, or promotion gates are waiting on a manual approval step. | `kubectl get analysisrun,rollout -n <ns>; kubectl describe rollout <rollout> -n <ns>` | [Deployment & Release](03-kubernetes-reliability/troubleshooting.md) |
| ConfigMap or Secret not updating in pods | Env-var sourced secrets require a pod restart, volume projections have not refreshed yet, or a reloader controller is missing/broken. | `kubectl get configmap,secret -n <ns> <name> -o yaml; kubectl describe pod <pod> -n <ns>` | [Deployment & Release](03-kubernetes-reliability/troubleshooting.md) |
| Helm chart upgrade failed | Template errors, immutable field changes, hook failures, or RBAC gaps interrupted the release. | `helm list -A; helm status <release> -n <ns>` | [Deployment & Release](03-kubernetes-reliability/troubleshooting.md) |

## 1. Kubernetes & Infrastructure

Use this section when the page points to scheduling, kubelet health, service discovery, or rollout safety.

Module deep dive: [03-kubernetes-reliability/troubleshooting.md](03-kubernetes-reliability/troubleshooting.md)

### Pod crash loops

**Common symptom**
- Pods enter `CrashLoopBackOff` immediately after a rollout or node move.
- Availability drops even though nodes and services still exist.

**Diagnosis commands**
```bash
kubectl get pods -A | grep CrashLoopBackOff
kubectl describe pod <pod> -n <ns>
kubectl logs <pod> -n <ns> --previous
kubectl get deploy <deploy> -n <ns> -o yaml | sed -n '/image:/,/env:/p'
```

**Most likely root cause**
- A bad image, broken startup dependency, or failing init/migration causes the main container to exit before readiness succeeds.
- Recent configuration or secret changes usually explain why the loop started now.

**Immediate fix**
1. Rollback to the last known good ReplicaSet or image digest.
2. Disable the failing startup hook, migration, or feature flag if the service supports it.
3. Restart only after the root cause is identified so you do not erase the previous logs.

**Validate**
- New pods remain `Running` and `Ready` for multiple probe intervals.
- Restart counts stop increasing and the error rate returns to baseline.

**Escalate when**
- Multiple services crash at once, which usually means a shared dependency or cluster-wide config problem.

**Module guide**
- [Deep dive and service-specific checks](03-kubernetes-reliability/troubleshooting.md)

### OOMKilled containers

**Common symptom**
- Pod status shows `OOMKilled` or exit code 137.
- Latency spikes before the process dies because memory reclaim is already hurting the node.

**Diagnosis commands**
```bash
kubectl get pods -A | grep OOMKilled
kubectl describe pod <pod> -n <ns>
kubectl top pod <pod> -n <ns> --containers
kubectl top nodes
kubectl logs <pod> -n <ns> --previous | tail -50
```

**Most likely root cause**
- The container crossed its memory limit because of a real leak, a burstier workload, or requests that no longer match reality.
- If many pods die together, node memory pressure can make a single-service problem look like a platform incident.

**Immediate fix**
1. Raise memory requests and limits only if profiling shows the new steady-state is legitimate.
2. Scale out temporarily to reduce per-pod heap growth and queue depth.
3. Rollback memory-hungry code paths, caches, or debug logging introduced in the recent deployment.

**Validate**
- Resident memory stabilizes below the new limit with safe headroom.
- HPA behavior and node memory pressure normalize after the change.

**Escalate when**
- The same image is OOMing across clusters or regions, which suggests an application regression rather than local capacity.

**Module guide**
- [Deep dive and service-specific checks](03-kubernetes-reliability/troubleshooting.md)

### Pending pods

**Common symptom**
- Desired replicas exist but several pods stay `Pending` for minutes.
- HPA may continue requesting more replicas even though the scheduler cannot place them.

**Diagnosis commands**
```bash
kubectl get pods -A | grep Pending
kubectl describe pod <pod> -n <ns>
kubectl get nodes -o wide
kubectl top nodes
kubectl get quota -A && kubectl get limitrange -A
```

**Most likely root cause**
- Insufficient CPU, memory, ephemeral storage, or zone-specific capacity prevents scheduling.
- Affinity rules, taints, or quota policies can silently narrow placement options until no eligible node remains.

**Immediate fix**
1. Free capacity, scale the node pool, or lower oversized requests to fit the real node shape.
2. Patch impossible affinity, topology spread, or toleration settings introduced by the rollout.
3. Reduce noncritical workloads before forcing critical pods onto already saturated nodes.

**Validate**
- The scheduler places all pending pods and warning events stop repeating.
- Service latency improves because queued work is no longer stuck behind missing capacity.

**Escalate when**
- Critical stateful workloads are pending because zonal or storage constraints may require cloud-provider intervention.

**Module guide**
- [Deep dive and service-specific checks](03-kubernetes-reliability/troubleshooting.md)

### ImagePullBackOff

**Common symptom**
- New pods never start because the image cannot be downloaded.
- Existing replicas may still serve traffic, hiding the failure until a node drains or rollout progresses.

**Diagnosis commands**
```bash
kubectl get pods -A | grep ImagePullBackOff
kubectl describe pod <pod> -n <ns>
kubectl get secret -n <ns> | grep -i docker
kubectl get serviceaccount <sa> -n <ns> -o yaml
```

**Most likely root cause**
- The image tag is wrong, the registry is unavailable, or imagePullSecrets/service-account permissions are missing.
- Recent digest pinning and private registry policy changes are common triggers.

**Immediate fix**
1. Correct the image reference or revert to the last successful digest.
2. Restore registry credentials on the namespace service account or pod spec.
3. If the registry is degraded, pause the rollout to preserve the working replicas you still have.

**Validate**
- Pods transition from `ContainerCreating` to `Running` without repeated pull failures.
- A manual `kubectl rollout status` finishes successfully after the image fix.

**Escalate when**
- Several namespaces fail to pull from the same registry, indicating an external dependency outage or global auth break.

**Module guide**
- [Deep dive and service-specific checks](03-kubernetes-reliability/troubleshooting.md)

### Node NotReady

**Common symptom**
- One or more nodes move to `NotReady` and workloads start draining or flapping.
- DaemonSet, kubelet, or network alerts often fire around the same time.

**Diagnosis commands**
```bash
kubectl get nodes
kubectl describe node <node>
kubectl get pods -A -o wide --field-selector spec.nodeName=<node>
kubectl get events -A --sort-by=.lastTimestamp | grep <node> | tail -20
```

**Most likely root cause**
- Kubelet heartbeats are failing because of node reboot, network isolation, disk exhaustion, or cloud-host degradation.
- When many nodes flip together, control-plane reachability and CNI health are the prime suspects.

**Immediate fix**
1. Cordon the node and drain it if the host is reachable but unhealthy.
2. If the host is gone, force-delete the node object only after you confirm replacement capacity exists.
3. Open cloud-provider investigation if the VM itself is impaired or unreachable from serial console tools.

**Validate**
- The node returns to `Ready` with stable heartbeats or is replaced by a healthy new node.
- Evicted workloads reschedule cleanly and service-level alerts clear.

**Escalate when**
- Control-plane or network symptoms affect multiple nodes because the incident is larger than a single worker failure.

**Module guide**
- [Deep dive and service-specific checks](03-kubernetes-reliability/troubleshooting.md)

### Disk pressure on nodes

**Common symptom**
- Pods are evicted with disk-related messages and nodes show `DiskPressure=True`.
- Image pulls, log writes, and container startup become inconsistent or fail.

**Diagnosis commands**
```bash
kubectl describe node <node>
kubectl get events -A --sort-by=.lastTimestamp | egrep 'DiskPressure|Evicted' | tail -30
kubectl top nodes
kubectl get pods -A -o wide --field-selector spec.nodeName=<node>
```

**Most likely root cause**
- Container logs, image layers, emptyDir volumes, or compaction backlogs consumed node ephemeral storage.
- A rollout that increases image size can trigger pressure even when application code itself is healthy.

**Immediate fix**
1. Drain the worst node if you need immediate workload relief.
2. Reduce chatty logging, clear runaway ephemeral volumes, or move large scratch data to durable storage.
3. Right-size node boot disks and image retention policy after service is stable again.

**Validate**
- Kubelet clears `DiskPressure` and evictions stop.
- Fresh pods can pull images and mount ephemeral storage normally.

**Escalate when**
- Pressure returns immediately after drain because a system DaemonSet or cluster-wide log flood is filling every node.

**Module guide**
- [Deep dive and service-specific checks](03-kubernetes-reliability/troubleshooting.md)

### Memory pressure on nodes

**Common symptom**
- Several unrelated pods are evicted and node conditions show `MemoryPressure=True`.
- Latency rises before eviction because the kernel is already reclaiming aggressively.

**Diagnosis commands**
```bash
kubectl describe node <node>
kubectl top node <node>
kubectl top pods -A --sort-by=memory | tail -20
kubectl get events -A --sort-by=.lastTimestamp | egrep 'MemoryPressure|Evicted' | tail -30
```

**Most likely root cause**
- One noisy workload, too many undersized requests, or missing system reservations can overwhelm the node.
- If autoscaling is slow, HPA keeps pushing more work onto already constrained nodes.

**Immediate fix**
1. Cordon the impacted node and reduce pressure by scaling down or isolating the highest consumers.
2. Raise requests for known heavy workloads so the scheduler stops overpacking them.
3. Expand cluster capacity before reopening regular deploys.

**Validate**
- Node pressure clears and new evictions stop.
- Top offenders no longer sit near the limit and restart counts flatten.

**Escalate when**
- Pressure spans multiple nodes because the issue may be caused by a broad traffic surge or bad deployment.

**Module guide**
- [Deep dive and service-specific checks](03-kubernetes-reliability/troubleshooting.md)

### HPA not scaling

**Common symptom**
- Traffic and latency climb, but replica count stays flat.
- The deployment may look healthy while the queue or p95 grows steadily.

**Diagnosis commands**
```bash
kubectl get hpa -A
kubectl describe hpa <hpa> -n <ns>
kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes | head
kubectl get deploy <deploy> -n <ns> -o yaml | sed -n '/resources:/,/env:/p'
```

**Most likely root cause**
- Missing resource requests, broken custom metrics, or stale metrics-server data prevent the HPA controller from making decisions.
- Conservative scaling policies can also make the HPA technically healthy but operationally too slow.

**Immediate fix**
1. Restore CPU or custom metric visibility and make sure requests exist on every scaled container.
2. Temporarily scale the workload manually while you repair the HPA signal path.
3. Tune stabilization windows and scale-up policies only after the immediate demand spike is under control.

**Validate**
- Desired replicas follow load again and recent HPA events show successful recommendations.
- Latency drops as new capacity reaches `Ready` state.

**Escalate when**
- Metrics APIs are unhealthy cluster-wide because autoscaling failure may affect many services simultaneously.

**Module guide**
- [Deep dive and service-specific checks](03-kubernetes-reliability/troubleshooting.md)

### PDB blocking rollout

**Common symptom**
- A rollout or node drain stalls even though replacement pods are available.
- Operators see repeated disruption-denied messages in events or deployment status.

**Diagnosis commands**
```bash
kubectl get pdb -A
kubectl describe pdb <pdb> -n <ns>
kubectl rollout status deploy/<deploy> -n <ns>
kubectl get events -A --sort-by=.lastTimestamp | grep -i disruption | tail -20
```

**Most likely root cause**
- The PodDisruptionBudget is stricter than the current replica count or health state allows.
- Stateful services often inherit a PDB written for normal operations, not maintenance or degraded conditions.

**Immediate fix**
1. Increase healthy replicas before draining or rolling the workload.
2. Temporarily relax `minAvailable` or switch to `maxUnavailable` during the controlled change window.
3. Coordinate with database or quorum owners before overriding protection on stateful services.

**Validate**
- Rollout or drain resumes without violating quorum or availability objectives.
- The temporary PDB change is reverted after the cluster is stable.

**Escalate when**
- Quorum risk exists for stateful systems because the fix may require application-specific failover procedures.

**Module guide**
- [Deep dive and service-specific checks](03-kubernetes-reliability/troubleshooting.md)

### Service unreachable inside the cluster

**Common symptom**
- Pods resolve the service name but requests time out or get connection refused.
- Ingress or external load balancers may look fine while east-west traffic fails.

**Diagnosis commands**
```bash
kubectl get svc,endpoints,endpointslices -n <ns> <service>
kubectl describe svc <service> -n <ns>
kubectl get pods -n <ns> -l app=<app> -o wide
kubectl exec -n <ns> <debug-pod> -- curl -sv http://<service>:<port>/health
```

**Most likely root cause**
- Selector drift, wrong targetPort, failing readiness probes, or network policy drops prevent backends from receiving traffic.
- The service object can exist while its endpoints list is empty or stale.

**Immediate fix**
1. Correct labels or ports so endpoints populate with the intended pods.
2. Repair readiness probes if healthy pods are being excluded from the service.
3. Temporarily allow traffic in network policy if the block was introduced by a recent change.

**Validate**
- Endpoints show the expected pod IPs and in-cluster curls succeed.
- Application logs confirm the service is receiving traffic again.

**Escalate when**
- The issue crosses namespaces or clusters because service-discovery or network-platform teams may need to engage.

**Module guide**
- [Deep dive and service-specific checks](03-kubernetes-reliability/troubleshooting.md)

### DNS failure in cluster

**Common symptom**
- Applications fail with name-resolution errors even though pods and services are healthy.
- Impact usually appears broad because many dependencies are discovered by DNS.

**Diagnosis commands**
```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl -n kube-system logs deploy/coredns --tail=200
kubectl exec -n <ns> <debug-pod> -- nslookup kubernetes.default.svc.cluster.local
kubectl exec -n <ns> <debug-pod> -- cat /etc/resolv.conf
```

**Most likely root cause**
- CoreDNS crash loops, upstream resolver latency, or bad stub-domain configuration break service discovery.
- Node-local DNS cache issues can make failures appear node-specific at first.

**Immediate fix**
1. Restore CoreDNS capacity and remove recent config changes that affect forwarding or rewrites.
2. Reschedule or restart node-local DNS components if the problem is isolated to one node pool.
3. If DNS latency is the issue, reduce unnecessary retries that are amplifying traffic to CoreDNS.

**Validate**
- Lookups for cluster services and external dependencies succeed from multiple namespaces.
- Timeout and `SERVFAIL` counters drop back to baseline.

**Escalate when**
- External corporate DNS or cloud DNS resolvers are failing because cluster-only changes will not fully resolve the issue.

**Module guide**
- [Deep dive and service-specific checks](03-kubernetes-reliability/troubleshooting.md)

## 2. Monitoring & Alerting

Use this section when telemetry is misleading, incomplete, or unable to notify the responders who need it.

Module deep dive: [01-monitoring-observability/troubleshooting.md](01-monitoring-observability/troubleshooting.md)

### Alert firing but the service looks healthy

**Common symptom**
- An alert is active, but dashboards and customer checks do not show corresponding user impact.
- Teams argue about whether the alert is noise or a real early warning signal.

**Diagnosis commands**
```bash
kubectl -n monitoring port-forward svc/prometheus-operated 9090:9090
curl -s http://127.0.0.1:9090/api/v1/rules | jq '.data.groups[]?.rules[] | select(.state=="firing") | {name: .name, query: .query}'
curl -s "http://127.0.0.1:9090/api/v1/query?query=<ALERT_EXPR>" | jq .
kubectl get events -A --sort-by=.lastTimestamp | tail -20
```

**Most likely root cause**
- The alert may be measuring a proxy signal, using stale labels, or missing traffic-volume guards that distinguish noise from customer pain.
- Healthy dashboards can also be wrong when they use different filters or longer windows than the alert.

**Immediate fix**
1. Verify the exact firing series and compare it to the dashboard query and service ownership labels.
2. Add traffic floors, `for` duration, or better label scoping if the alert is genuinely too sensitive.
3. Do not silence until you know whether the alert found a blind spot in the dashboard.

**Validate**
- The reconciled query matches real service behavior and false positives stop recurring.
- Dashboards, rules, and ownership labels all point to the same target set.

**Escalate when**
- Several unrelated alerts look inconsistent, suggesting a common metrics or label pipeline issue.

**Module guide**
- [Deep dive and service-specific checks](01-monitoring-observability/troubleshooting.md)

### Alert not firing when it should

**Common symptom**
- Operators can see a breach in dashboards or logs, but the expected page never arrived.
- This is especially dangerous during slow burns and detector drift.

**Diagnosis commands**
```bash
kubectl -n monitoring get prometheusrule
curl -s http://127.0.0.1:9090/api/v1/rules | jq '.data.groups[]?.rules[] | select(.name=="<ALERT_NAME>")'
curl -s "http://127.0.0.1:9090/api/v1/query?query=<ALERT_EXPR>" | jq .
kubectl -n monitoring logs statefulset/prometheus-kube-prometheus-stack-prometheus --tail=200 | grep -i <ALERT_NAME>
```

**Most likely root cause**
- The rule expression may never become true because of missing series, wrong labels, absent recording rules, or an overly strict `for` clause.
- Silences, inhibited alerts, or Alertmanager routing errors can also hide a valid fire.

**Immediate fix**
1. Test the raw PromQL expression against the exact production labels and evaluation window.
2. Repair recording rules or label joins before relaxing the threshold.
3. Audit Alertmanager silences and inhibition rules if Prometheus says the alert is firing.

**Validate**
- A synthetic or replayed condition now triggers the alert within the expected interval.
- Notification history shows the alert reaching the intended destination.

**Escalate when**
- The detection gap affects critical SLO or availability alerts because leadership may need a freeze or backfill analysis.

**Module guide**
- [Deep dive and service-specific checks](01-monitoring-observability/troubleshooting.md)

### Prometheus high memory usage

**Common symptom**
- Prometheus memory rises rapidly, queries slow down, and pods risk OOM.
- Usually follows new high-cardinality metrics or target explosion.

**Diagnosis commands**
```bash
kubectl top pod -n monitoring | grep prometheus
kubectl -n monitoring exec sts/prometheus-kube-prometheus-stack-prometheus -- promtool tsdb analyze /prometheus | head -50
curl -s http://127.0.0.1:9090/api/v1/status/tsdb | jq .data.labelValueCountByLabelName[:15]
curl -s "http://127.0.0.1:9090/api/v1/query?query=topk(20,count%20by(__name__)(%7B__name__!=""%7D))" | jq .
```

**Most likely root cause**
- A new metric label with unbounded values, too many scrape targets, or long remote-write backpressure is exploding head-block memory.
- Cardinality spikes often start at the application but show up first as Prometheus stress.

**Immediate fix**
1. Disable or relabel the offending metric source and reduce series churn immediately.
2. Scale Prometheus vertically only as a safety move, not the permanent fix.
3. Throttle remote-write or split scrape jobs if ingestion bursts are starving compaction.

**Validate**
- RSS and TSDB head series counts return to a stable range.
- Query latency and rule evaluation duration recover after the change.

**Escalate when**
- The same metric pattern appears in long-term storage because retention and cost impacts extend beyond Prometheus.

**Module guide**
- [Deep dive and service-specific checks](01-monitoring-observability/troubleshooting.md)

### Prometheus TSDB corruption

**Common symptom**
- Prometheus fails to start, shows WAL replay errors, or returns gaps around restart time.
- Rules and alerts may stop entirely until the database is repaired.

**Diagnosis commands**
```bash
kubectl -n monitoring logs statefulset/prometheus-kube-prometheus-stack-prometheus --tail=300
kubectl -n monitoring describe pod prometheus-kube-prometheus-stack-prometheus-0
kubectl -n monitoring exec prometheus-kube-prometheus-stack-prometheus-0 -- ls -lah /prometheus
kubectl -n monitoring exec prometheus-kube-prometheus-stack-prometheus-0 -- promtool tsdb list /prometheus | tail -20
```

**Most likely root cause**
- Unclean shutdown during disk pressure, storage faults, or WAL replay bugs left an unreadable block or WAL segment.
- Corruption is often a symptom of underlying storage or node instability, not only a Prometheus issue.

**Immediate fix**
1. Preserve the PVC, snapshot it if possible, and remove only the corrupted block or WAL segment that prevents startup.
2. Bring up a replacement from remote-write or replicated storage if local repair is too risky during the incident.
3. Investigate node, disk, and filesystem events before declaring the incident closed.

**Validate**
- Prometheus starts cleanly and target/rule health return to normal.
- Recent data resumes without continuous WAL or block-read errors.

**Escalate when**
- The underlying disk or CSI layer is unhealthy because other stateful workloads may be at risk.

**Module guide**
- [Deep dive and service-specific checks](01-monitoring-observability/troubleshooting.md)

### Grafana panels show No Data

**Common symptom**
- Dashboards return `No Data` or blank graphs even though services are still running.
- This can be a datasource, query, auth, or time-range problem rather than a real outage.

**Diagnosis commands**
```bash
kubectl -n monitoring get pods | grep grafana
kubectl -n monitoring logs deploy/kube-prometheus-stack-grafana --tail=200
kubectl -n monitoring get configmap -l grafana_datasource=1 -o yaml
curl -s http://127.0.0.1:9090/api/v1/query?query=up | jq .data.result[0:5]
```

**Most likely root cause**
- Datasource credentials, UID drift, bad templating variables, or empty label matches are the usual causes.
- If only one dashboard breaks after a provisioning change, the panel JSON is more suspect than Prometheus.

**Immediate fix**
1. Test the datasource directly, then compare panel query variables to raw PromQL results.
2. Reapply datasource provisioning if Grafana lost the correct datasource UID or permissions.
3. Fix dashboard variable defaults that evaluate to an empty selector in production.

**Validate**
- Panels render the same data as direct datasource queries.
- Recently provisioned dashboards load without datasource warnings in logs.

**Escalate when**
- Multiple datasources fail at once because Grafana itself may be healthy while backend observability is down.

**Module guide**
- [Deep dive and service-specific checks](01-monitoring-observability/troubleshooting.md)

### Alertmanager not sending notifications

**Common symptom**
- Prometheus shows alerts as firing, but Slack, email, or PagerDuty remains silent.
- During incidents this creates a secondary failure: responders believe detection is working when it is not.

**Diagnosis commands**
```bash
kubectl -n monitoring get pods | grep alertmanager
kubectl -n monitoring logs statefulset/alertmanager-kube-prometheus-stack-alertmanager --tail=200
kubectl -n monitoring port-forward svc/alertmanager-operated 9093:9093
curl -s http://127.0.0.1:9093/api/v2/status | jq .
```

**Most likely root cause**
- Bad receiver credentials, routing mistakes, inhibition rules, or network egress blocks prevent notifications from leaving Alertmanager.
- A config reload can succeed syntactically while still routing alerts to the wrong receiver tree.

**Immediate fix**
1. Check the receiver tree, silence list, and notification log for the affected alert labels.
2. Restore working credentials or egress access before editing thresholds or rules.
3. Send a manual test alert through the same labels to verify end-to-end delivery.

**Validate**
- A test alert reaches the correct channel with the expected grouping and severity.
- Notification failures stop appearing in Alertmanager logs.

**Escalate when**
- External paging providers are degraded because local config changes will not restore delivery on their own.

**Module guide**
- [Deep dive and service-specific checks](01-monitoring-observability/troubleshooting.md)

## 3. SLO & Error Budget

Use this section when policy, measurement, and user reality diverge.

Module deep dive: [02-sre-principles/troubleshooting.md](02-sre-principles/troubleshooting.md)

### Error budget exhausted unexpectedly

**Common symptom**
- The team wakes up to a nearly empty budget even though nobody recalls a major outage.
- Release governance suddenly blocks deploys without a clear incident narrative.

**Diagnosis commands**
```bash
curl -s "http://127.0.0.1:9090/api/v1/query?query=(1-sum(rate(http_requests_total{job=\"api\",status!~\"5..\"}[30d]))/sum(rate(http_requests_total{job=\"api\"}[30d])))" | jq .
curl -s "http://127.0.0.1:9090/api/v1/query?query=sum(rate(http_requests_total{job=\"api\",status=~\"5..\"}[5m]))" | jq .
curl -s "http://127.0.0.1:9090/api/v1/query?query=topk(10,sum by (status,route)(rate(http_requests_total{job=\"api\"}[30m])))" | jq .
```

**Most likely root cause**
- The SLI denominator or numerator changed, hidden low-volume endpoints started failing, or a silent burn was not mapped to a visible incident.
- Backfills, replay jobs, and synthetic probes are frequent causes of surprise budget spend.

**Immediate fix**
1. Audit raw traffic classes included in the SLI before freezing every deployment.
2. Separate synthetic, admin, and replay traffic from customer-facing availability calculations.
3. Recalculate the budget using the canonical query before deciding on release policy.

**Validate**
- The recomputed budget matches the dashboard and documented SLI definition.
- Policy decisions reference the corrected SLI scope, not the stale chart.

**Escalate when**
- Contractual reporting or executive review depends on the metric because historical recalculation may be required.

**Module guide**
- [Deep dive and service-specific checks](02-sre-principles/troubleshooting.md)

### SLO dashboard shows conflicting numbers

**Common symptom**
- Two dashboards claim different availability for the same service and time range.
- Teams lose confidence in SLO policy because nobody knows which number is canonical.

**Diagnosis commands**
```bash
curl -s "http://127.0.0.1:9090/api/v1/query?query=<DASHBOARD_QUERY_A>" | jq .
curl -s "http://127.0.0.1:9090/api/v1/query?query=<DASHBOARD_QUERY_B>" | jq .
kubectl -n monitoring get configmap -l grafana_dashboard=1 -o yaml | grep -n "availability" -n
```

**Most likely root cause**
- The dashboards use different label sets, burn windows, or definitions of success.
- One may be using recording rules while the other runs raw PromQL against a different datasource or retention tier.

**Immediate fix**
1. Pick a single canonical recording rule and make dashboards consume that output rather than hand-written variants.
2. Document excluded traffic and keep the dashboard legend explicit about numerator and denominator.
3. Delete or deprecate legacy panels that still use pre-migration labels.

**Validate**
- Both dashboards converge on the same recording rule output for the same range.
- Ownership docs clearly state where the official SLO comes from.

**Escalate when**
- The mismatch affects release gates or customer reports because historical dashboards may need correction.

**Module guide**
- [Deep dive and service-specific checks](02-sre-principles/troubleshooting.md)

### Fast burn alert firing constantly

**Common symptom**
- Fast-burn pages repeat every few minutes even when user impact seems limited.
- On-call gets desensitized and starts muting a potentially important detector.

**Diagnosis commands**
```bash
curl -s "http://127.0.0.1:9090/api/v1/query?query=<FAST_BURN_EXPR>" | jq .
curl -s "http://127.0.0.1:9090/api/v1/query?query=<SLOW_BURN_EXPR>" | jq .
curl -s "http://127.0.0.1:9090/api/v1/query?query=sum(rate(http_requests_total{job=\"api\"}[5m]))" | jq .
```

**Most likely root cause**
- Burn-rate thresholds may be correct mathematically but missing a traffic floor, route filter, or maintenance exclusion.
- Low request volume can make error percentages oscillate wildly and page too often.

**Immediate fix**
1. Add request-volume guards and ensure only user-facing traffic participates in the alert.
2. Review short and long windows together so the alert reflects sustained harm, not a handful of retries.
3. Keep the page live until a validated replacement rule exists.

**Validate**
- The alert still catches meaningful incidents while false positives on low traffic disappear.
- On-call can explain exactly which requests now trigger the page.

**Escalate when**
- The burn alert is part of automated release blocking because policy and tooling may both need updates.

**Module guide**
- [Deep dive and service-specific checks](02-sre-principles/troubleshooting.md)

## 4. Incident Management

Use this section when the process around the incident is failing as badly as the system itself.

Module deep dive: [04-incident-management/troubleshooting.md](04-incident-management/troubleshooting.md)

### Incident escalation path broken

**Common symptom**
- Primary on-call acknowledges, but secondary, leadership, or specialist escalation never triggers.
- The technical issue may be under investigation while coordination quietly fails.

**Diagnosis commands**
```bash
gh api /users >/dev/null
kubectl -n monitoring logs statefulset/alertmanager-kube-prometheus-stack-alertmanager --tail=200 | grep -i pagerduty
grep -R "PagerDuty" -n 04-incident-management 01-monitoring-observability
```

**Most likely root cause**
- Pager policies, Alertmanager routing labels, or contact escalation rules are stale or misconfigured.
- Mismatched severity labels between alerts and paging policy are common during new-service onboarding.

**Immediate fix**
1. Page the backup engineer manually while you repair the automation.
2. Audit the exact alert labels and escalation policy mapping end to end.
3. Record the process failure as an incident issue, not just an operational annoyance.

**Validate**
- A controlled test alert follows the intended escalation ladder.
- Runbook ownership pages and contact records reflect the current org structure.

**Escalate when**
- The broken path affects SEV1 or regulated services because manual coordination may need leadership involvement.

**Module guide**
- [Deep dive and service-specific checks](04-incident-management/troubleshooting.md)

### Postmortem action items not tracked

**Common symptom**
- Recurring incidents reference the same known fix, but no one can prove ownership or due date.
- RCA quality drops because follow-up work disappears after the incident closes.

**Diagnosis commands**
```bash
gh issue list --label postmortem --state open
grep -R "Action Items" -n 04-incident-management 09-production-readiness
grep -R "Owner:" -n 04-incident-management
```

**Most likely root cause**
- The organization writes postmortems but lacks a durable system of record linking action items to owners and deadlines.
- Work tracked in chat or docs alone is hard to audit and even harder to prioritize later.

**Immediate fix**
1. Create or update tracked issues for every remediation item before the postmortem is approved.
2. Link the incident record, owner, due date, and risk class in a single project board or tracker.
3. Review overdue reliability actions during weekly ops cadence, not only during the next outage.

**Validate**
- Every open postmortem item has an owner, status, and target date.
- Recurrence reviews can trace old incidents to completed or missed actions.

**Escalate when**
- Repeated misses affect the same risk area because leadership prioritization may be the real blocker.

**Module guide**
- [Deep dive and service-specific checks](04-incident-management/troubleshooting.md)

### On-call engineer not reachable

**Common symptom**
- Alerts page, but the scheduled responder does not acknowledge and backup response is slow.
- Incidents lengthen because access, device, or contact prerequisites were not maintained.

**Diagnosis commands**
```bash
gh api /user >/dev/null
grep -R "on-call" -n 04-incident-management
grep -R "escalation" -n 04-incident-management
```

**Most likely root cause**
- Phone, push, or SMS contact methods are outdated, or the engineer lacks the access needed to act even after paging.
- The schedule may also be wrong because rota changes were not synced to the paging platform.

**Immediate fix**
1. Trigger manual backup escalation immediately instead of waiting for repeated retries.
2. Validate paging devices, VPN/MFA, kubectl, and cloud access during daylight hours, not during the outage.
3. Update handoff checklists so rota changes include access and contact verification.

**Validate**
- A test page reaches the intended engineer and the backup path works if primary is unavailable.
- The on-call checklist includes access verification for all critical systems.

**Escalate when**
- No reachable engineer has production access because this is both a staffing and access-control incident.

**Module guide**
- [Deep dive and service-specific checks](04-incident-management/troubleshooting.md)

## 5. GCP & Cloud Infrastructure

Use this section when the failure domain extends beyond Kubernetes into GKE, IAM, networking, or managed services.

Module deep dive: [05-gcp-operations/troubleshooting.md](05-gcp-operations/troubleshooting.md)

### GKE node pool out of capacity

**Common symptom**
- Unschedulable pods persist and cluster autoscaler logs mention quota or unavailable resources.
- This often appears during regional surges, upgrades, or large rollouts.

**Diagnosis commands**
```bash
gcloud container clusters describe <cluster> --region <region>
gcloud container node-pools describe <pool> --cluster <cluster> --region <region>
gcloud compute regions describe <region> --format='yaml(quotas)'
kubectl get events -A --sort-by=.lastTimestamp | grep -i FailedScheduling | tail -20
```

**Most likely root cause**
- Regional CPU quota, zonal stockouts, or max-nodes limits stop GKE from adding workers.
- Autoscaler can be healthy while the cloud capacity boundary is the real blocker.

**Immediate fix**
1. Raise quota, expand to alternate zones or machine families, or temporarily reduce demand from noncritical workloads.
2. If the cluster design allows it, add a secondary pool with a compatible but more available shape.
3. Pause aggressive rollouts until replacement capacity is confirmed.

**Validate**
- New nodes join and pending pods schedule without repeating quota errors.
- Autoscaler logs stop reporting cloud-provider failures.

**Escalate when**
- Regional stockouts persist because cloud-provider support or workload relocation may be required.

**Module guide**
- [Deep dive and service-specific checks](05-gcp-operations/troubleshooting.md)

### IAM permission denied errors

**Common symptom**
- Applications, CI jobs, or operators suddenly receive `PERMISSION_DENIED` from GCP APIs.
- Outage scope often follows service-account reuse rather than service boundaries.

**Diagnosis commands**
```bash
gcloud projects get-iam-policy <project-id> --flatten=bindings[].members --format='table(bindings.role,bindings.members)'
gcloud iam service-accounts get-iam-policy <sa>@<project-id>.iam.gserviceaccount.com
kubectl describe serviceaccount <ksa> -n <ns>
kubectl describe pod <pod> -n <ns> | grep -i gcp-service-account -n
```

**Most likely root cause**
- A role binding was removed, workload identity mapping drifted, or a service account key/secret was rotated without propagation.
- The change may be intentional from security posture but operationally incomplete.

**Immediate fix**
1. Restore least-privilege access for the broken path first, then review the broader IAM change safely.
2. Repair Workload Identity annotations and namespace bindings if pods no longer impersonate the intended GSA.
3. Record every temporary permission grant so it is not forgotten after incident pressure drops.

**Validate**
- The failing GCP API call succeeds from the pod or service account context again.
- Audit logs confirm the correct principal and role are in use.

**Escalate when**
- The denied action is security-sensitive or cross-project because approval and audit stakeholders may need to sign off.

**Module guide**
- [Deep dive and service-specific checks](05-gcp-operations/troubleshooting.md)

### Cloud Logging missing entries

**Common symptom**
- Support and engineers know requests happened, but Cloud Logging has gaps or delayed ingestion.
- This can break incident response because logs are often the only high-cardinality source left.

**Diagnosis commands**
```bash
gcloud logging read "resource.type=k8s_container AND resource.labels.cluster_name=<cluster>" --limit 20 --freshness=10m
kubectl -n kube-system get pods | grep -E 'fluent|logging'
kubectl -n kube-system logs ds/fluentbit-gke --tail=200
gcloud logging sinks list
```

**Most likely root cause**
- Agent backpressure, dropped permissions, bad exclusion filters, or ingestion delays are preventing logs from landing.
- If only one namespace is missing, label-based routing or exclusion is more likely than platform-wide loss.

**Immediate fix**
1. Check agent health and output errors before changing filters blindly.
2. Restore required writer permissions on sinks and buckets if routing broke.
3. Reduce log volume from noisy services so the pipeline can recover backlog.

**Validate**
- Fresh application logs appear in Cloud Logging within the expected latency window.
- Dropped or retry counters on the logging agents return to normal.

**Escalate when**
- Audit or compliance-relevant logs are missing because retention and forensics may be impacted.

**Module guide**
- [Deep dive and service-specific checks](05-gcp-operations/troubleshooting.md)

### GCS or Pub/Sub latency spike

**Common symptom**
- Static asset fetches, uploads, or async processing lag jump sharply while compute looks healthy.
- User impact may be regional and hard to correlate if only one managed service is slow.

**Diagnosis commands**
```bash
gcloud monitoring time-series list --filter='metric.type="storage.googleapis.com/api/request_latencies"' --limit=5
gcloud monitoring time-series list --filter='metric.type="pubsub.googleapis.com/subscription/oldest_unacked_message_age"' --limit=5
gcloud storage ls -L gs://<bucket>
gcloud pubsub subscriptions describe <subscription>
```

**Most likely root cause**
- Regional service latency, misrouted traffic, backlog growth, or client retry storms are delaying managed-service operations.
- These incidents often surface first as application timeouts rather than obvious infra alerts.

**Immediate fix**
1. Shift traffic or reads to a healthier region if the architecture supports it.
2. Slow publishers or consumers on purpose until backlog drains and retries stop amplifying the latency.
3. Cache or serve critical static assets from alternate paths while the dependency recovers.

**Validate**
- Managed-service latency metrics and application timeouts both return to baseline.
- Backlog age, retry counts, and synthetic checks confirm end-to-end recovery.

**Escalate when**
- The managed service is having a provider-side incident or multi-region degradation.

**Module guide**
- [Deep dive and service-specific checks](05-gcp-operations/troubleshooting.md)

## 6. Linux & Networking

Use this section when host-level resource contention or packet path issues are the fastest route to the truth.

Module deep dive: [06-linux-networking/troubleshooting.md](06-linux-networking/troubleshooting.md)

### High load average

**Common symptom**
- Hosts or nodes show very high load and application latency climbs even when CPU graphs are inconclusive.
- Load average alone does not tell you whether the system is CPU, disk, or lock bound.

**Diagnosis commands**
```bash
uptime
top -o cpu -l 1 | head -40
ps aux | sort -rk 3,3 | head -20
vm_stat 1 5
```

**Most likely root cause**
- The runnable queue is long because of CPU saturation, blocked threads, or heavy kernel work.
- On nodes running containers, a single noisy process can distort host-level load for many services.

**Immediate fix**
1. Identify the actual wait source before restarting processes blindly.
2. Throttle or isolate the top offenders and move discretionary jobs off the node.
3. Right-size concurrency settings if thread oversubscription is the pattern.

**Validate**
- Load average trends down and application latency follows, not just CPU percentage.
- The same host does not immediately refill with queued work after restart.

**Escalate when**
- Multiple hosts show identical load patterns because the issue may be upstream of the node itself.

**Module guide**
- [Deep dive and service-specific checks](06-linux-networking/troubleshooting.md)

### High I/O wait

**Common symptom**
- CPU appears idle but the system feels frozen and storage-bound work times out.
- Pods may fail readiness because the process cannot read config, logs, or local caches fast enough.

**Diagnosis commands**
```bash
iostat -xz 1 5
df -h
lsof | head -50
vm_stat 1 5
```

**Most likely root cause**
- Disk saturation, filesystem errors, or runaway log writes are stalling processes in uninterruptible sleep.
- Containerized platforms often mask this as generic slowness unless you inspect the node directly.

**Immediate fix**
1. Reduce or stop the workload causing the write/read storm.
2. Move scratch or cache usage off the impacted disk if possible.
3. If the disk is failing, drain the node and replace the underlying host or volume.

**Validate**
- I/O wait drops and read/write latency normalizes.
- Application health checks recover without repeated timeouts.

**Escalate when**
- Storage errors or kernel messages suggest hardware or CSI faults, not just application noise.

**Module guide**
- [Deep dive and service-specific checks](06-linux-networking/troubleshooting.md)

### Surprise OOM process death

**Common symptom**
- A process disappears without a clean shutdown path and service logs stop abruptly.
- Container orchestration may restart it so quickly that the operator misses the original event.

**Diagnosis commands**
```bash
dmesg | egrep -i 'killed process|out of memory' | tail -20
ps aux --sort=-rss | head -20
vm_stat
sysctl vm.overcommit_memory
```

**Most likely root cause**
- The kernel OOM killer terminated the process because the host ran out of reclaimable memory.
- This is distinct from container-limit OOMKilled events and usually points to host oversubscription or a privileged process.

**Immediate fix**
1. Stabilize the host by reducing top memory consumers and shedding nonessential load.
2. Increase swap or memory only if the platform standard permits it and the risk is understood.
3. Capture evidence before reboot because the kernel log is part of the incident record.

**Validate**
- No new OOM killer entries appear after the workload adjustment.
- Host free memory and file cache return to a sustainable level.

**Escalate when**
- The killed process is part of the node agent or security stack, which can destabilize many services.

**Module guide**
- [Deep dive and service-specific checks](06-linux-networking/troubleshooting.md)

### Packet loss or intermittent timeouts

**Common symptom**
- Connections succeed sometimes and fail other times, often only from certain zones or nodes.
- Retries may hide the issue in application logs while user latency climbs.

**Diagnosis commands**
```bash
ping -c 5 <target>
traceroute <target>
netstat -s | egrep -i 'retrans|drop'
kubectl exec -n <ns> <debug-pod> -- curl -sv --connect-timeout 2 http://<service>:<port>/health
```

**Most likely root cause**
- Network policy, load balancer health, MTU mismatch, or regional path instability can all produce intermittent loss.
- When only large responses fail, suspect fragmentation or proxy buffer constraints instead of DNS.

**Immediate fix**
1. Localize the fault domain first: pod, node, zone, region, or external path.
2. Rollback the most recent network, firewall, or service-mesh change on the affected path.
3. Shift traffic away from the bad zone or backend until packet delivery is stable.

**Validate**
- Retransmits, failed probes, and user timeout rates fall back to normal.
- Connectivity tests succeed from multiple nodes and namespaces.

**Escalate when**
- The path crosses cloud edges or ISPs because provider engagement may be required.

**Module guide**
- [Deep dive and service-specific checks](06-linux-networking/troubleshooting.md)

### Disk full: bytes versus inodes

**Common symptom**
- The node or host reports disk-full behavior even though there appears to be free space.
- Loggers, temp-file writers, and package operations fail first.

**Diagnosis commands**
```bash
df -h
df -i
du -xhd 1 /var | sort -h | tail -20
find /var -xdev -type f | wc -l
```

**Most likely root cause**
- Either bytes are exhausted by a few large files or inodes are exhausted by huge numbers of tiny files.
- Container log rotation failures and temp-file leaks commonly trigger the inode form.

**Immediate fix**
1. Delete or rotate the dominant files only after confirming they are not needed for forensics.
2. Clear inode-heavy temp directories and fix the application creating unbounded small files.
3. If the node is shared, drain workloads before aggressive cleanup.

**Validate**
- Both `df -h` and `df -i` show safe headroom after cleanup.
- Applications can write logs, temp files, and checkpoints again.

**Escalate when**
- Disk growth comes from a system daemon or forensic-sensitive data set that needs specialist handling.

**Module guide**
- [Deep dive and service-specific checks](06-linux-networking/troubleshooting.md)

## 7. Application & Database

Use this section when the user-visible symptom sits above the platform and inside the workload itself.

Module deep dive: [08-application-support-l2l3/troubleshooting.md](08-application-support-l2l3/troubleshooting.md)

### Connection pool exhaustion

**Common symptom**
- Application logs show timeout waiting for DB or upstream connections while pods remain up.
- CPU may be low because threads are blocked, not busy.

**Diagnosis commands**
```bash
kubectl logs deploy/<app> -n <ns> --since=15m | egrep 'timeout|pool|connection'
kubectl exec -n <ns> <pod> -- ss -tan | head -40
kubectl exec -n <ns> <pod> -- env | grep -i POOL
kubectl top pod -n <ns> <pod>
```

**Most likely root cause**
- Pool size is too small for concurrency, leaked connections are never returned, or the database slowed down enough to keep the pool occupied.
- During incidents, a pool problem can masquerade as total database failure.

**Immediate fix**
1. Reduce incoming concurrency or scale out the application tier to spread waiting clients.
2. Increase the pool only if the database has headroom for more simultaneous sessions.
3. Fix leak paths or long transactions before making the larger pool permanent.

**Validate**
- Pool wait time falls and request latency drops without simply moving saturation to the database.
- Connection counts stabilize near a predictable steady state.

**Escalate when**
- Several services share the same database and all show pool starvation, indicating a deeper DB or network issue.

**Module guide**
- [Deep dive and service-specific checks](08-application-support-l2l3/troubleshooting.md)

### Slow queries degrading service

**Common symptom**
- p95 latency rises, queue depth grows, and application threads appear blocked on the database.
- Users may report partial slowness rather than complete failure.

**Diagnosis commands**
```bash
kubectl logs deploy/<app> -n <ns> --since=15m | grep -i slow
kubectl exec -n <ns> <db-pod> -- sh -c "psql -c 'select now();'"
kubectl exec -n <ns> <db-pod> -- sh -c "psql -c 'select query, state, wait_event from pg_stat_activity order by query_start asc limit 10;'"
curl -s "http://127.0.0.1:9090/api/v1/query?query=histogram_quantile(0.95,sum(rate(http_request_duration_seconds_bucket{job=\"api\"}[5m])) by (le))" | jq .
```

**Most likely root cause**
- A new query plan, missing index, lock contention, or replica lag is slowing request completion.
- The application often shows the symptom first, but the bottleneck is downstream in the database.

**Immediate fix**
1. Abort or throttle the worst query pattern and reroute read traffic if a replica is healthy.
2. Rollback the code path or feature flag that introduced the expensive query.
3. Add or restore the supporting index only through the normal safe DBA workflow if the table is large.

**Validate**
- Slow-query logs, DB wait events, and application latency all return toward baseline.
- Connection pool waiters drain instead of growing.

**Escalate when**
- The fix requires schema or lock intervention on a critical database cluster.

**Module guide**
- [Deep dive and service-specific checks](08-application-support-l2l3/troubleshooting.md)

### Memory leak diagnosis

**Common symptom**
- RSS climbs monotonically over hours or days until pods recycle or nodes pressure out.
- Traffic may be steady, which makes the growth look mysterious unless you compare by process lifetime.

**Diagnosis commands**
```bash
kubectl top pods -n <ns> --sort-by=memory
kubectl describe pod <pod> -n <ns>
kubectl logs <pod> -n <ns> --since=1h | tail -100
curl -s "http://127.0.0.1:9090/api/v1/query?query=max_over_time(container_memory_working_set_bytes{pod=\"<pod>\"}[24h])" | jq .
```

**Most likely root cause**
- A real heap leak, cache with no eviction, file-descriptor growth, or stuck request objects is retaining memory across traffic cycles.
- The pattern becomes clearer when you plot memory against process age and deploy time.

**Immediate fix**
1. Rollback the regressed build or disable the leaking code path first.
2. Capture heap or pprof evidence from one canary pod before mass restarts erase the signal.
3. Set safer memory limits and alerting so the next occurrence is detected earlier.

**Validate**
- Memory usage flattens after the rollback or code-path disablement.
- Canary pods survive for the normal lifetime without approaching the limit.

**Escalate when**
- The leak appears in multiple languages or sidecars, which may indicate a shared library or agent issue.

**Module guide**
- [Deep dive and service-specific checks](08-application-support-l2l3/troubleshooting.md)

## 8. Deployment & Release

Use this section when the change-management path itself is the incident or the fastest mitigation route.

Module deep dive: [03-kubernetes-reliability/troubleshooting.md](03-kubernetes-reliability/troubleshooting.md)

### Rollout stuck

**Common symptom**
- A deployment stays in-progress indefinitely and new pods never reach the available count.
- This often overlaps with readiness failures, PDB blocks, or missing dependencies.

**Diagnosis commands**
```bash
kubectl rollout status deploy/<deploy> -n <ns>
kubectl describe deploy <deploy> -n <ns>
kubectl get rs -n <ns> -l app=<app>
kubectl get events -n <ns> --sort-by=.lastTimestamp | tail -30
```

**Most likely root cause**
- Readiness never succeeds, unavailable-budget settings are too tight, or replacement pods cannot schedule.
- The rollout controller is usually telling the truth; the hidden issue is downstream in pods or capacity.

**Immediate fix**
1. Pause the rollout and decide whether rollback or manual mitigation is safer.
2. Fix the underlying readiness or scheduling failure before resuming.
3. Document whether the bad state is already serving traffic before forcing progress.

**Validate**
- The deployment reaches the desired available replica count.
- Old ReplicaSets are cleaned up only after the new version proves stable.

**Escalate when**
- The stuck rollout is part of a broad release train affecting many services.

**Module guide**
- [Deep dive and service-specific checks](03-kubernetes-reliability/troubleshooting.md)

### Canary not advancing

**Common symptom**
- Progressive delivery holds the canary at a low percentage even though operators expect auto-promotion.
- Business teams may pressure for manual promotion before analysis is complete.

**Diagnosis commands**
```bash
kubectl get analysisrun,rollout -n <ns>
kubectl describe rollout <rollout> -n <ns>
kubectl logs deploy/argo-rollouts -n argo-rollouts --tail=200
curl -s "http://127.0.0.1:9090/api/v1/query?query=<CANARY_METRIC_EXPR>" | jq .
```

**Most likely root cause**
- Automated analysis found a regression, metrics were missing, or promotion gates are waiting on a manual approval step.
- Canary tooling failure and canary signal failure are different incidents; prove which one you have.

**Immediate fix**
1. Inspect the analysis result before overriding it; the gate may be protecting you from a real outage.
2. Repair missing metrics or webhook callbacks if the canary controller itself is blind.
3. Rollback instead of forcing promotion when customer harm is plausible.

**Validate**
- Canary analysis runs complete with explicit success or rollback, not indefinite pending state.
- Promotion status matches the health evidence from metrics and logs.

**Escalate when**
- Manual promotion is being requested under uncertainty because release governance needs a clear decision record.

**Module guide**
- [Deep dive and service-specific checks](03-kubernetes-reliability/troubleshooting.md)

### ConfigMap or Secret not updating in pods

**Common symptom**
- The source object changed, but running pods still use old config or credentials.
- This commonly breaks after secret rotation or runtime flag changes.

**Diagnosis commands**
```bash
kubectl get configmap,secret -n <ns> <name> -o yaml
kubectl describe pod <pod> -n <ns>
kubectl exec -n <ns> <pod> -- env | grep -i <KEY>
kubectl rollout history deploy/<deploy> -n <ns>
```

**Most likely root cause**
- Env-var sourced secrets require a pod restart, volume projections have not refreshed yet, or a reloader controller is missing/broken.
- Many teams assume Kubernetes hot-reloads env vars; it does not.

**Immediate fix**
1. Roll the affected workloads if they consume the value as an environment variable.
2. Confirm the mount path and refresh interval if using projected volumes.
3. Repair or deploy a config-reloader mechanism if the platform standard expects automatic restarts.

**Validate**
- New pods observe the updated config and stop logging auth or feature-flag errors.
- The platform runbook now states clearly which config patterns need rollout versus live reload.

**Escalate when**
- The change spans many services because bulk restarts and prioritization may be required.

**Module guide**
- [Deep dive and service-specific checks](03-kubernetes-reliability/troubleshooting.md)

### Helm chart upgrade failed

**Common symptom**
- A `helm upgrade` ends in failed, pending, or partial state and cluster resources are inconsistent.
- Operators may have to choose between rollback and completing the release manually.

**Diagnosis commands**
```bash
helm list -A
helm status <release> -n <ns>
helm history <release> -n <ns>
kubectl get events -n <ns> --sort-by=.lastTimestamp | tail -30
```

**Most likely root cause**
- Template errors, immutable field changes, hook failures, or RBAC gaps interrupted the release.
- A chart can partially apply, so the cluster state may no longer match either the old or new release manifest cleanly.

**Immediate fix**
1. Capture `helm status` and events first, then choose `helm rollback` or a corrected `helm upgrade --atomic` rerun.
2. If immutable fields changed, replace only the affected resource with an explicit controlled rollout plan.
3. Do not hand-edit live objects unless you also document how Helm state will be reconciled afterward.

**Validate**
- Helm history shows a healthy deployed revision and workloads reflect that revision consistently.
- Subsequent dry-runs are clean and no leftover failed hooks remain.

**Escalate when**
- Shared platform charts or CRDs are involved because other teams may be impacted by the same release artifact.

**Module guide**
- [Deep dive and service-specific checks](03-kubernetes-reliability/troubleshooting.md)

## Emergency Cheatsheet

Use these one-liners only after you confirm scope and blast radius.

- **Rollback deployment**

```bash
kubectl rollout undo deploy/<deploy> -n <ns>
```

- **Scale up replicas**

```bash
kubectl scale deploy/<deploy> -n <ns> --replicas=<count>
```

- **Drain a node**

```bash
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --force
```

- **Kill a runaway process**

```bash
sudo kill -9 <pid>
```

- **Check cluster-wide events**

```bash
kubectl get events -A --sort-by=.lastTimestamp | tail -100
```

- **Enable maintenance mode / feature flag off**

```bash
curl -X POST https://flags.example.internal/api/v1/flags/<flag>/disable
```

- **Page someone manually via PagerDuty API**

```bash
curl -X POST https://api.pagerduty.com/incidents -H "Authorization: Token token=$PAGERDUTY_TOKEN" -H "Content-Type: application/json" -d @incident.json
```

