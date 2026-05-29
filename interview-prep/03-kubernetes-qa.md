# Kubernetes Q&A

**Q1: Explain pod lifecycle from scheduling to running.**
API server stores pod → Scheduler assigns node → kubelet on node pulls image via containerd → runs startup probe (if set) → then readiness probe → on readiness pass: pod added to Service endpoints. Key: image pull happens on node, not centrally. Pulling large images can delay scheduling. Use imagePullPolicy: IfNotPresent and pre-pull images via DaemonSet for time-sensitive scaling.

**Q2: What happens step-by-step when you kubectl delete pod?**
(1) deletionTimestamp set on pod. (2) Pod status: Terminating. (3) Endpoint controller removes pod from Service endpoints (stops new traffic). (4) kubelet sends SIGTERM. (5) Pre-stop hook runs (if configured). (6) terminationGracePeriodSeconds timer starts (default 30s). (7) If process still alive after grace period: SIGKILL. (8) Pod deleted from etcd. CRITICAL: steps 3 and 4 happen concurrently. Add a pre-stop sleep (5s) to handle the race condition between endpoint removal and traffic draining.

**Q3: Readiness vs Liveness vs Startup probes.**
Readiness: "can this pod receive traffic?" Failure: remove from endpoints, no restart. Use for: dependency checks, warming up, overload protection. Liveness: "is this pod stuck?" Failure: restart container. Use for: deadlock detection. Never check external deps in liveness (DB down → all pods restart = worse outage). Startup: runs once at start before liveness activates — use for slow starters (JVM). failureThreshold × periodSeconds = max startup time.

**Q4: What is a PodDisruptionBudget?**
PDB sets minimum available or maximum unavailable pods during voluntary disruptions (drain, upgrade, autoscaler). Without PDB: node drain can kill all replicas simultaneously. With minAvailable: 2, K8s waits between evictions. Checked by: kubectl drain, cluster autoscaler scale-down, GKE/EKS node upgrades. NOT checked by: node failures, OOM kills (involuntary). Every production Deployment with >= 2 replicas should have a PDB.

**Q5: HPA vs VPA — can they conflict?**
HPA scales replicas based on CPU/memory/custom metrics. VPA changes requests/limits on pods. Conflict: VPA changing CPU requests changes HPA's utilization calculation → feedback loop. Solution: use VPA in Off mode (recommendations only), OR use HPA on CPU/memory + VPA only on memory, OR use KEDA (HPA based on custom metrics) + VPA for right-sizing. Never run both HPA and VPA on the same metric simultaneously.

**Q6: What are QoS classes? How do they affect eviction?**
Guaranteed: requests == limits for all containers → last evicted, never speculatively throttled. Burstable: at least one container has requests < limits → evicted after BestEffort. BestEffort: no requests or limits → first evicted. Production services: always Guaranteed or Burstable. Check: kubectl get pod -o jsonpath='{.status.qosClass}'. High memory pressure: kernel OOM kills BestEffort first, then Burstable with highest OOM score, then Guaranteed.

**Q7: How does DNS work in K8s?**
CoreDNS (ClusterIP 10.96.0.10) is the nameserver for all pods. Every Service gets: service.namespace.svc.cluster.local. Pod's /etc/resolv.conf has ndots:5 and search domains. With ndots:5, hostname "api.example.com" triggers 3 failed local lookups before external DNS. Fix: set ndots:2 in pod dnsConfig, or use FQDNs. CoreDNS caches responses (30s default). Scale CoreDNS for high-traffic clusters (1 replica per 500 nodes).

**Q8: CrashLoopBackOff — 5 root causes and diagnosis.**
(1) App crash on start: kubectl logs <pod> --previous → look for error at startup. (2) OOMKilled (exit 137): kubectl describe pod → Last State: OOMKilled → increase memory limit. (3) Liveness probe failing immediately: add initialDelaySeconds. (4) Bad entrypoint/command: describe pod events → exec format error. (5) Missing env/secret: logs show "env var X not found" → check ConfigMap/Secret existence. Always start with: kubectl logs --previous and kubectl describe pod.

**Q9: How do Services route traffic to pods?**
Service has ClusterIP (virtual IP). kube-proxy (or Cilium/kube-proxy replacement) programs iptables DNAT rules on every node. Traffic to ClusterIP gets randomly DNAT'd to one of the pod IPs in Endpoints. Readiness probe failure = pod removed from Endpoints = no traffic. LoadBalancer type: cloud controller provisions external LB → NodePort on nodes → iptables to pod IP. Headless (clusterIP: None): DNS returns pod IPs directly (used by StatefulSets).

**Q10: What is Workload Identity in GKE?**
Links K8s ServiceAccount to GCP ServiceAccount without mounting JSON key files. Pod uses K8s SA token to call GKE metadata server → exchanges for short-lived GCP token. No credentials to leak/rotate. Setup: enable on cluster (--workload-pool), annotate K8s SA with GCP SA email, grant workloadIdentityUser role. Required for: pods accessing Cloud Storage, Pub/Sub, Firestore, Secret Manager, etc.

**Q11: Node drain with PDB — what happens?**
kubectl drain marks node unschedulable (cordon) then evicts pods. For each pod: checks PDB. If evicting would violate minAvailable, drain blocks and waits. Retries every 5s. If pod can be evicted: evicts it, waits for replacement to become Ready on another node, then evicts next pod. kubectl drain --force skips PDB checks (dangerous). kubectl drain --timeout sets max wait time.

**Q12: How does the Cluster Autoscaler work?**
CA scans every 10s for: (1) Pending pods that can't schedule due to insufficient resources → scale up a node pool. (2) Nodes where all pods could fit elsewhere for 10+ minutes → scale down (drain + delete node). Scale-down respects: PDBs, local storage pods, pods with safe-to-evict: false annotation. Common issues: non-evictable pod blocking scale-down → add annotation. CA doesn't scale down if any node utilization > 50% by default.

**Q13: What is a NetworkPolicy? Default behavior?**
Default (no NetworkPolicy): all pods can reach all pods across all namespaces. NetworkPolicy adds firewall rules (enforced by CNI: Calico, Cilium). Typical pattern: default-deny-all (podSelector:{}, no ingress/egress rules) → allow-same-namespace → allow-dns (UDP/TCP 53 to kube-system) → explicit cross-namespace allows. Without a CNI that supports it (Flannel doesn't), NetworkPolicies are ignored silently.

**Q14: Deployment vs StatefulSet — when to use each?**
Deployment: interchangeable pods (random names, same PVC not guaranteed), scale in any order, rolling updates. Use for stateless apps. StatefulSet: stable ordinal names (db-0, db-1), stable DNS (db-0.db-service), stable per-pod PVCs (each pod keeps its data), ordered start/stop. Use for: databases (Postgres, MySQL), Kafka, ZooKeeper, Redis Sentinel, any app needing stable identity.

**Q15: How do you debug a node showing NotReady?**
(1) kubectl describe node → Conditions section (MemoryPressure, DiskPressure, PIDPressure, NetworkUnavailable). (2) SSH to node (if accessible): systemctl status kubelet → check for errors. (3) journalctl -u kubelet -n 100 → kubelet crash reason. (4) Check disk: df -h → disk full? (5) Check memory: free -h → OOM? (6) Check network: ping kube-apiserver IP from node. (7) dmesg | tail -20 → kernel-level events. Common: disk full (/var/lib/docker or /var/log), kubelet OOMKilled, certificate expired.
