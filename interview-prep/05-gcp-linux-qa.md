# GCP & Linux Q&A

## GCP Basics

**Q: [Basic] What is the purpose of IAM roles in GCP?**
IAM roles define which actions an identity can perform on which resources in a Google Cloud project, folder, or organization. Basic interview answers should mention predefined roles, custom roles, and the principle of least privilege. SREs usually care most about granting enough access to operate safely without overexposing production systems.

**Q: [Basic] How do GKE and GCE differ?**
GCE gives you virtual machines and leaves orchestration, deployment patterns, and much of the lifecycle management to you. GKE adds managed Kubernetes control plane capabilities, cluster primitives, and automation for containerized workloads. The choice usually depends on whether the workload benefits from container orchestration and platform abstractions.

**Q: [Basic] What are the main Cloud Storage classes?**
Standard is for frequent access, Nearline is for infrequent monthly access, Coldline is for rarer access, and Archive is for long-term retention with the lowest storage cost. The tradeoff is that colder classes have higher retrieval costs and stricter access expectations. Good answers connect the class choice to backup, analytics, or content-serving patterns.

**Q: [Basic] How do Cloud SQL and Spanner differ?**
Cloud SQL is a managed relational database for engines like MySQL and PostgreSQL, and it fits many traditional application workloads well. Spanner is a globally distributed relational database designed for horizontal scale, strong consistency, and high availability across regions. Spanner is more powerful at scale, but it also introduces a different cost and design model.

**Q: [Basic] What is Workload Identity in GKE?**
Workload Identity lets a Kubernetes service account act as a Google service account without storing long-lived key files inside Pods. This improves security, simplifies credential rotation, and aligns access with workload identity rather than with node identity. It is the preferred pattern for GKE workloads that need to call GCP APIs.

## GCP Intermediate

**Q: [Intermediate] What are the core building blocks of GCP VPC networking?**
A VPC includes subnets, routes, firewall rules, and optional components such as Cloud NAT, Cloud Router, or load balancers. Subnets are regional, firewall rules are stateful, and connectivity design should be planned before growth makes it painful to change. Strong answers mention both east-west traffic control and north-south internet access.

**Q: [Intermediate] What is the difference between Shared VPC and VPC Peering?**
Shared VPC centralizes network administration by letting multiple service projects use subnets from a host project. VPC Peering connects separate VPCs privately but keeps them administratively separate and has limitations such as non-transitive routing. Shared VPC is often the better fit for large organizations that want consistent guardrails.

**Q: [Intermediate] How do Cloud Monitoring alerts work in GCP?**
Cloud Monitoring alerts evaluate conditions on metrics, logs-based metrics, or uptime checks and then notify configured channels. Policies can include thresholds, absence detection, and multi-condition logic depending on the use case. Good answers mention that alerts should reflect customer impact and include enough context for fast response.

**Q: [Intermediate] What are good GKE upgrade practices?**
Start by checking version support, add-on compatibility, and release notes for breaking changes. Use surge upgrades, healthy PodDisruptionBudgets, and replica counts that allow workloads to keep serving while nodes roll. Upgrades should be tested in lower environments first and watched with both cluster and application health signals.

**Q: [Intermediate] What load balancing options does GCP provide?**
GCP offers global and regional HTTP(S) load balancing, TCP or UDP load balancing, and internal load balancers for private traffic. The platform can distribute traffic across regions and integrates well with managed certificates, Cloud Armor, and health checks. Choosing the right balancer depends on protocol, scope, and whether clients are internal or internet-facing.

**Q: [Intermediate] How would you design high availability on GCP?**
High availability starts with eliminating single points of failure across zones and, for critical services, across regions. Typical designs include regional managed instance groups or GKE node pools, managed databases with failover, load balancers, and resilient storage. HA design should also include tested failover behavior and operational runbooks, not just redundant diagrams.

## GCP Advanced

**Q: [Advanced] What does Cloud Armor do?**
Cloud Armor is Google Cloud’s edge security service for protecting applications from common web attacks and abusive traffic. It supports WAF rules, geo-based filtering, IP allow or deny logic, and rate limiting in front of load-balanced services. In interviews, explain it as a traffic control and protection layer rather than as a complete security program by itself.

**Q: [Advanced] What are the tradeoffs in a multi-region GCP deployment?**
Multi-region designs improve resilience and can reduce latency for geographically distributed users. They also add complexity around data consistency, failover logic, deployment coordination, and cost. Strong answers discuss active-active versus active-passive choices and how stateful systems affect the architecture.

**Q: [Advanced] How do you approach cost optimization on GCP?**
Cost optimization starts with rightsizing, shutting down unused resources, using committed use discounts where appropriate, and matching storage or machine types to the actual workload profile. On GKE, it also means tuning requests, enabling autoscaling, and avoiding chronic overprovisioning. The best answers connect cost work to reliability by showing how waste and fragility often come from the same design mistakes.

**Q: [Advanced] What are common GCP security practices for production workloads?**
Use least-privilege IAM, private networking where possible, workload identity instead of static keys, and strong audit logging. Production systems also benefit from organization policies, secrets management, image signing, and clear separation of environments. Good SRE answers explain that secure defaults reduce operational risk and incident frequency.

## Linux Basics

**Q: [Basic] How do you manage processes on Linux?**
Common tools include `ps`, `top`, `htop`, `pgrep`, `kill`, and `nice` or `renice` for priority changes. The usual workflow is to identify the process, inspect its resource usage, and then stop or reprioritize it carefully. Strong answers also mention checking logs and parent-child relationships before killing a production process.

**Q: [Basic] How do Linux file permissions work?**
Linux permissions are built around read, write, and execute bits for owner, group, and others. Commands like `chmod`, `chown`, and `ls -l` are used to inspect and change access. A good interview answer also notes that directory execute permission controls traversal, not just file execution.

**Q: [Basic] What is `systemd` used for?**
`systemd` is the service manager on most modern Linux distributions and handles service startup, restart, ordering, and logging integration. Commands like `systemctl status`, `start`, `stop`, `restart`, and `enable` are essential for day-to-day operations. It is also useful during incidents because unit files often show the intended runtime configuration.

## Linux Intermediate

**Q: [Intermediate] What does `iptables` do?**
`iptables` manages packet-filtering and network address translation rules in the Linux kernel. It is commonly used to allow, block, or rewrite traffic at different points in the packet flow. Even when higher-level tools manage rules for you, understanding chains and rule order is important for debugging.

**Q: [Intermediate] What are the common TCP connection states?**
TCP states include LISTEN, SYN-SENT, SYN-RECV, ESTABLISHED, FIN-WAIT, CLOSE-WAIT, LAST-ACK, and TIME-WAIT. These states help you diagnose connection leaks, port exhaustion, slow handshakes, or clients that are not closing connections properly. Tools like `ss -tanp` or `netstat` are often used to inspect them.

**Q: [Intermediate] How does Linux memory management affect application behavior?**
Linux uses free memory aggressively for page cache, so high memory usage alone is not automatically a problem. What matters more is reclaim pressure, swapping, OOM kills, and whether the application can keep enough working set in memory. Strong answers mention checking `free`, `vmstat`, cgroup limits, and the OOM killer history.

**Q: [Intermediate] What is the `/proc` filesystem?**
`/proc` is a virtual filesystem that exposes kernel and process information at runtime. It includes files for CPU, memory, mounts, open file descriptors, network statistics, and per-process details such as command line and limits. Many troubleshooting commands are really reading and formatting data from `/proc`.

**Q: [Intermediate] What are cgroups?**
Control groups let the kernel account for and limit resources such as CPU, memory, and I/O for a group of processes. They are a key building block for containers because they create resource isolation boundaries. In practice, cgroups explain why a process may be OOM killed even when the host still appears to have free memory.

**Q: [Intermediate] What is namespace isolation in Linux?**
Namespaces isolate views of system resources such as processes, networking, mounts, hostnames, users, and IPC objects. Containers depend on namespaces so workloads can believe they have their own environment while still sharing the same kernel. Good answers often mention that containers are built from namespaces plus cgroups and filesystem layering.

## Linux Advanced

**Q: [Advanced] What is eBPF and why is it useful to SREs?**
eBPF allows safe programs to run inside the Linux kernel to observe or influence system behavior with very low overhead. It is useful for network visibility, syscall tracing, security controls, and performance analysis without rebuilding the kernel or restarting applications. Tools like Cilium, bpftrace, and modern observability agents rely heavily on it.

**Q: [Advanced] What kinds of kernel tuning matter most in production?**
Kernel tuning should be targeted at known bottlenecks, such as connection backlog limits, ephemeral port ranges, file descriptor limits, or dirty page settings for storage-heavy workloads. Random tuning without measurement is risky because kernel parameters often trade one failure mode for another. Strong answers mention testing, baselining, and keeping changes documented and reversible.

**Q: [Advanced] What does the `perf` tool help you understand?**
`perf` helps analyze where CPU time is being spent in both user space and kernel space. It can sample hot functions, identify lock contention, and show whether a workload is CPU-bound, syscall-heavy, or affected by specific kernel paths. It is especially powerful when combined with flame graphs and workload context.

**Q: [Advanced] How would you investigate a high load average with low CPU usage?**
High load with low CPU often points to tasks blocked on I/O rather than pure compute saturation. You would check `vmstat`, `iostat`, disk latency, NFS behavior, and process state to see whether threads are waiting on storage or another dependency. This is a classic example of why load average alone is not enough to diagnose performance issues.

**Q: [Advanced] How do you investigate an OOM kill?**
Start with kernel logs and service logs to confirm the OOM killer acted and which process was chosen. Then compare the process’s memory growth with host memory pressure, swap activity, and any container or cgroup limits that may have applied. The long-term fix could be code changes, resource tuning, or architecture changes depending on whether the problem is a leak, a spike, or bad limits.

**Q: [Advanced] How do you debug a disk-full incident when `du` and `df` disagree?**
That mismatch usually means a deleted file is still held open by a running process, so disk blocks are not yet released. Tools like `lsof +L1` help find those orphaned file handles quickly. The fix is typically to restart or signal the holding process so it closes the file and frees the space.

**Q: [Advanced] How do file descriptors become a reliability problem?**
Applications can fail in surprising ways when they exhaust open file descriptors, including broken network connections, failed log writes, and inability to open new files. Responders should check per-process counts, system-wide limits, and whether the application is leaking sockets or descriptors over time. Raising the limit may buy time, but you still need to fix the underlying leak or connection management issue.
