# Kubernetes Q&A

## Basic

**Q: [Basic] What is the lifecycle of a Pod?**
A Pod is created in the API server, scheduled onto a node, started by the kubelet, and then transitions through states such as Pending, Running, Succeeded, or Failed. During startup it may also go through image pulling, container creation, and probe checks before it is ready for traffic. Understanding these phases helps explain why a Pod can exist but still not be serving requests.

**Q: [Basic] What do `kubectl get`, `kubectl describe`, and `kubectl logs` each tell you?**
`kubectl get` gives you the current object state and is best for fast summaries across many resources. `kubectl describe` shows deeper detail, including events, conditions, probes, and controller information, which is usually where first-pass troubleshooting starts. `kubectl logs` shows the container output and is the fastest way to confirm whether the application itself is crashing or misbehaving.

**Q: [Basic] What is the difference between a Deployment, DaemonSet, and StatefulSet?**
A Deployment manages interchangeable stateless replicas and is the default choice for most web or API workloads. A DaemonSet ensures one Pod runs on each selected node, which is useful for agents like log collectors or node exporters. A StatefulSet gives stable identity, ordered rollout behavior, and persistent storage association for stateful systems such as databases or brokers.

**Q: [Basic] What are Kubernetes Services and why do they matter?**
A Service gives a stable virtual endpoint in front of a changing set of Pods. It decouples clients from Pod IP churn and lets controllers safely replace replicas without breaking consumers. Interviews often expect you to mention ClusterIP, DNS, and endpoint selection through labels.

**Q: [Basic] What is the difference between a ConfigMap and a Secret?**
A ConfigMap stores non-sensitive configuration such as feature flags, port values, or service URLs. A Secret is meant for sensitive data such as passwords, tokens, or certificates, though in plain Kubernetes it is only base64-encoded unless encryption at rest is configured. Good answers also mention that both should be versioned and rolled out carefully to avoid surprise restarts or broken configs.

**Q: [Basic] How do you inspect a failing Pod quickly?**
Start by checking `kubectl get pods` to see the state and restart count. Then use `kubectl describe pod` for events and `kubectl logs --previous` if the container is restarting too quickly to catch current output. This sequence usually tells you whether the issue is scheduling, configuration, probes, or the application itself.

## Intermediate

**Q: [Intermediate] What is the difference between readiness, liveness, and startup probes?**
Readiness probes decide whether a Pod should receive traffic, while liveness probes decide whether the container should be restarted. Startup probes protect slow-starting applications by delaying liveness enforcement until the process has fully initialized. A common mistake is using a liveness probe to check an external dependency, which can turn a partial outage into a full restart storm.

**Q: [Intermediate] What does the Horizontal Pod Autoscaler do?**
The HPA increases or decreases the number of Pod replicas based on CPU, memory, or custom metrics. It is best for workloads where more replicas can actually spread load effectively. A strong answer mentions that scaling only works well when resource requests are set properly and the application can handle distributed traffic.

**Q: [Intermediate] What is a PodDisruptionBudget?**
A PodDisruptionBudget limits how many replicas can be voluntarily disrupted at once during actions like node drains or cluster upgrades. It protects service availability by forcing the platform to keep a minimum number of healthy Pods running. It does not protect against involuntary failures such as node crashes or OOM kills.

**Q: [Intermediate] What is RBAC in Kubernetes?**
RBAC, or Role-Based Access Control, controls who can perform which actions on which resources. It uses Roles or ClusterRoles plus RoleBindings or ClusterRoleBindings to grant permissions to users, groups, or service accounts. Good Kubernetes security starts with least privilege and service-account-specific access.

**Q: [Intermediate] What is the relationship between Services and Endpoints?**
A Service defines the stable access point and the selector logic, while Endpoints or EndpointSlices track the actual Pod IPs behind it. When Pods fail readiness, they are removed from the backend list so the Service stops routing new traffic to them. This is why probe design directly affects whether traffic reaches a Pod.

**Q: [Intermediate] Why do resource requests and limits matter?**
Requests influence scheduling because they tell the cluster how much CPU and memory the Pod needs reserved. Limits cap how much the Pod can consume, which affects throttling and OOM behavior under pressure. Without sane requests and limits, autoscaling, bin-packing, and incident diagnosis all get harder.

**Q: [Intermediate] What are Kubernetes QoS classes?**
Kubernetes classifies Pods as Guaranteed, Burstable, or BestEffort based on how requests and limits are set. These classes affect eviction priority when the node is under memory pressure. Production services should usually avoid BestEffort because those Pods are the first to be evicted.

**Q: [Intermediate] How do you troubleshoot a Pod stuck in Pending?**
Look at the Pod events first because the scheduler usually explains why placement failed. Common causes include insufficient CPU or memory, unsatisfied node selectors, taints without tolerations, quota limits, or missing persistent volumes. Pending Pods are usually a scheduling problem, not an application problem.

**Q: [Intermediate] How do you troubleshoot CrashLoopBackOff?**
CrashLoopBackOff means the container started and then exited repeatedly, so logs and last-exit details matter most. Check `kubectl logs --previous`, the container exit code, probe failures, and whether environment variables or mounted files are missing. Common causes include startup exceptions, bad commands, OOM kills, and overly aggressive liveness probes.

## Advanced

**Q: [Advanced] How does the Kubernetes scheduler decide where to place Pods?**
The scheduler first filters nodes that cannot run the Pod based on resource availability, taints, affinity rules, topology constraints, and other hard requirements. It then scores the remaining nodes using strategies such as spreading, resource balance, and affinity preferences before choosing the best fit. Older interviewers may still call these steps predicates and priorities, but the modern terms are filtering and scoring.

**Q: [Advanced] How does etcd high availability work in Kubernetes?**
etcd is the source of truth for cluster state, so it should run as an odd-numbered quorum, usually three or five members. HA depends on keeping quorum healthy, using fast durable disks, and protecting the cluster from network partitions and disk latency spikes. Backups and restore testing matter because an HA control plane does not replace disaster recovery.

**Q: [Advanced] How do common CNIs differ?**
Different Container Network Interface implementations make different tradeoffs around simplicity, policy enforcement, and dataplane performance. Calico is widely used for mature policy support, Cilium is popular for eBPF-based networking and observability, and Flannel is simpler but more limited in advanced policy features. A strong answer ties the choice back to scale, security requirements, and operational skill.

**Q: [Advanced] What do NetworkPolicies do?**
NetworkPolicies define which Pods can talk to which other Pods or destinations at L3 and L4. They are a key control for reducing blast radius and enforcing default-deny segmentation between workloads. They only work if the chosen CNI actually implements policy enforcement.

**Q: [Advanced] What is a safe Kubernetes upgrade strategy?**
A safe upgrade strategy starts with version skew checks, add-on compatibility checks, and testing in a lower environment first. In production, use surge or rolling node upgrades, ensure workloads have at least two replicas where needed, and verify PodDisruptionBudgets and probes before starting. During the upgrade, watch control plane health, error rates, and workload rescheduling behavior closely.

**Q: [Advanced] How do GKE Autopilot and Standard differ?**
Autopilot hides node management and charges at the workload level, which reduces operational overhead but limits node-level customization. Standard gives you more control over node pools, system DaemonSets, machine types, and debugging access, but it also gives you more responsibility. The right choice depends on whether the team values control or operational simplicity more.

**Q: [Advanced] What is KEDA and when would you use it?**
KEDA extends autoscaling by letting workloads scale on event-driven signals such as queue depth, Kafka lag, or cloud service metrics. It is useful when CPU is not a good proxy for demand, especially for asynchronous workers and bursty background jobs. KEDA often complements HPA by translating external event sources into scaling signals.

**Q: [Advanced] What does the Vertical Pod Autoscaler do?**
The VPA recommends or updates CPU and memory requests and limits based on observed usage. It is useful for right-sizing workloads that have stable but poorly chosen resource settings. Teams must be careful when combining VPA with HPA because changing requests can alter HPA behavior.

**Q: [Advanced] How does the Cluster Autoscaler help the platform?**
The Cluster Autoscaler adds nodes when Pods cannot schedule and removes underused nodes when their workloads can move elsewhere safely. It improves cost efficiency and availability, but only if workloads are evictable and resource requests reflect reality. Misconfigured requests, strict affinity, or blocking PodDisruptionBudgets can make autoscaling look broken.

**Q: [Advanced] What are the main Kubernetes Service types?**
ClusterIP is the internal-only default, NodePort exposes a port on each node, and LoadBalancer asks the cloud provider for an external load balancer. Headless Services skip the virtual IP and expose Pod identities directly through DNS, which is useful for stateful systems. Choosing the right type depends on whether traffic is internal, external, stateful, or cloud-managed.

**Q: [Advanced] How does Kubernetes DNS work?**
CoreDNS provides service discovery so Pods can resolve names such as `api.default.svc.cluster.local`. Service records point to the stable Service IP, while headless Services can resolve directly to individual Pod addresses. DNS issues often show up as application timeouts, so they should be part of standard incident triage.

**Q: [Advanced] What is the right way to manage Secrets and configuration in production clusters?**
Teams should separate config from code, use least-privilege access, and avoid baking secrets directly into images or manifests. External secret stores, secret rotation, and encrypted storage at rest improve the security posture significantly. Strong answers also mention rollout safety because config errors can cause just as many incidents as code errors.

**Q: [Advanced] What happens during a node drain?**
When a node is drained, it is first cordoned so no new Pods schedule there, and then existing Pods are evicted in a controlled way. Controllers create replacements on other nodes, while PodDisruptionBudgets may slow or block eviction if availability would be harmed. Drain behavior is critical to understand for maintenance, autoscaling, and upgrade planning.

**Q: [Advanced] How do you debug a NotReady node?**
Start with `kubectl describe node` to inspect conditions such as memory pressure, disk pressure, and kubelet health. Then check kubelet logs, system logs, disk space, network reachability to the control plane, and whether certificates or runtime services failed. Node issues are often caused by basic host problems like full disks, dead kubelets, or broken networking.
