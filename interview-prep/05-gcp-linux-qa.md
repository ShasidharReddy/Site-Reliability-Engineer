# GCP & Linux Q&A

**Q1: Service account keys vs Workload Identity.**
Workload Identity is more secure: no long-lived credential files, short-lived tokens auto-rotate, can't be exfiltrated from pods, follows least privilege per workload. Key files: long-lived, need manual rotation, stored in secrets (can leak), rotation is operationally expensive. Within GKE: always use Workload Identity. Only use key files for external systems that can't authenticate via GCP metadata server.

**Q2: GCP VPC Peering limitations.**
Non-transitive: A↔B and B↔C does not give A↔C access. No overlapping CIDRs (plan IP space carefully). Max 25 peering connections per VPC. No subnet-level granularity (all subnets accessible). Must be set up on both sides. For hub-and-spoke: use Shared VPC (centrally managed, transitive through host VPC). For cross-org: use VPN or Interconnect.

**Q3: What is Cloud NAT?**
Managed outbound NAT for VMs/pods without public IPs. Fully managed (no single gateway VM to maintain), HA by design. Use for: private VMs that need to pull packages, call external APIs, or download container images from Docker Hub. Monitor: nat/nat_allocation_failed — if non-zero, add more NAT IPs. Configure on Cloud Router, not on VMs directly.

**Q4: GKE Autopilot vs Standard.**
Autopilot: Google manages nodes (patching, scaling, sizing), pay per pod, no SSH to nodes. Best for: teams focused on apps, production workloads following standard K8s patterns, cost optimization. Standard: you manage nodes, custom node pools, SSH access, privileged containers, GPU/TPU, DaemonSets on specific nodes. Best for: complex infrastructure requirements, need for node-level access, specialized hardware.

**Q5: High load average but low CPU utilization.**
Classic I/O wait pattern. Load average includes processes blocked on I/O, not just CPU. Check: top → %wa column. If >20%: I/O bound. Diagnose: iostat -x 1 5 → %util and await per device. iotop -ao → which process is causing I/O. Causes: DB full table scans, backup jobs, slow NFS/EBS, VM disk throttling. Fix: optimize queries, use faster storage, schedule backups off-peak, increase I/O limits.

**Q6: Explain TCP TIME_WAIT at scale.**
After TCP close, initiator waits 2×MSL (60-120s) before reusing port. High-throughput servers opening many short connections can exhaust ephemeral port range (32k-60k ports). Fix: enable SO_REUSEADDR, use connection pooling (HTTP keep-alive, pgBouncer for DB), use HTTP/2 (multiplexed), tune net.ipv4.tcp_fin_timeout (reduce to 15-30s), increase ephemeral port range (net.ipv4.ip_local_port_range).

**Q7: Pod can't resolve DNS — troubleshooting.**
(1) kubectl get pods -n kube-system -l k8s-app=kube-dns (is CoreDNS running?). (2) kubectl logs -n kube-system -l k8s-app=kube-dns (CoreDNS errors). (3) kubectl run debug --image=busybox -it --rm -- nslookup kubernetes.default. (4) kubectl exec <pod> -- cat /etc/resolv.conf (correct nameserver?). (5) Test external: nslookup google.com (works? = K8s-specific issue). (6) Check NetworkPolicy blocking UDP/TCP 53 to kube-system. (7) Check CoreDNS ConfigMap for configuration errors.

**Q8: Investigate OOMKilled container.**
(1) kubectl describe pod → Last State: OOMKilled, exit code 137. (2) kubectl get pod -o yaml | grep -A5 resources → what is the memory limit? (3) Grafana: container_memory_working_set_bytes trend → steady growth (leak) or sudden spike (large request). (4) Leak: get heap dump from app, check for unbounded caches or connection pools. (5) Spike: find the request pattern causing large memory allocation. (6) Short-term: increase limit 2x. Long-term: fix the root cause.

**Q9: What does vmstat output tell you?**
vmstat 1 5: r=run queue (>ncpus=CPU bound), b=blocked on I/O (>0=I/O bottleneck), swpd=swap used (non-zero=memory pressure), si/so=swap in/out per second (non-zero=memory pressure), us/sy/id/wa/st=CPU user/system/idle/iowait/steal. Diagnose: high r + low wa = CPU bound. Low r + high wa = I/O bound. High si/so = memory pressure. High st = hypervisor stealing — check cloud provider.

**Q10: Disk space full but du doesn't explain it.**
Deleted-but-open file problem. Process holds FD to a deleted file — disk space not freed until process closes it. df shows actual disk usage (including held files), du only counts files with directory entries. Find: lsof +L1 (files with link count < 1 = deleted but held open). Fix: restart the holding process, or send SIGHUP to make it reopen log files. Prevention: configure log rotation with copytruncate option, or app should use reopening log mechanism.

**Q11: Key GCP IAM roles for SRE.**
roles/monitoring.admin (full Cloud Monitoring), roles/monitoring.viewer (read-only), roles/logging.viewer (read-only logs), roles/container.developer (deploy to GKE), roles/container.viewer (read-only GKE), roles/compute.viewer (view GCE). SRE daily needs: monitoring.viewer + logging.viewer + container.viewer at minimum. For alert management: monitoring.admin. Follow least privilege: grant viewer until you need admin.

**Q12: How does Cloud Monitoring alerting work?**
Alerting policies: conditions (threshold, absent, rate of change) on metrics + notification channels. Conditions evaluated on managed metric data (not Prometheus). Uptime checks: probes from Google's global network to your endpoints. Alert policy can combine conditions (AND/OR). Notification channels: PagerDuty, Slack, email, Pub/Sub (for custom routing). Monitor your alerting: gcloud alpha monitoring policies list to verify policies exist and aren't accidentally disabled.

**Q13: strace — what is it and when do you use it?**
strace traces system calls made by a process. Use when: app is slow/hanging and you don't know why, debugging file permission issues, understanding what files/sockets an app opens. Commands: strace -p PID (attach to running), strace -c -p PID (summary of syscall time), strace -e trace=network -p PID (only network calls), strace -e open,read,write -p PID (only file ops). Warning: strace adds overhead (up to 10x slowdown) — use briefly and remove.

**Q14: How do you check open file descriptors?**
lsof -p PID (all files for a process), lsof -i :8080 (what's listening on port 8080), lsof -u username (all files for a user), lsof +D /var/log (all files in directory), cat /proc/PID/fd | wc -l (FD count for process), ulimit -n (max FDs for current shell), cat /proc/sys/fs/file-max (system-wide max). High FD count may indicate FD leak in application — connections not being closed.

**Q15: How do you investigate high CPU steal on a GCP VM?**
CPU steal (st in top) = hypervisor giving your VM's CPU time to other VMs. Check: top → %st column. If consistently >5%: noisy neighbor problem. Diagnosis: check if it correlates with time of day (shared infrastructure). Options: (1) Move to a dedicated instance (sole-tenant node on GCP); (2) Upgrade to a larger machine type (more CPU = proportionally less contention); (3) Move to a different zone; (4) Consider Spot/preemptible instances if you need performance guarantees for non-critical workloads.
