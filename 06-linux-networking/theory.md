# Linux & Networking — Advanced Theory

This module expands the original notes into an operator-focused reference for Linux internals and production troubleshooting.
Every section emphasizes what the kernel is doing, how to observe it, and how to reason from symptoms to root cause.

## How to use this file

- Read the sections in order if you are building fundamentals from scratch.
- Jump directly to the command tables when you are in incident mode.
- Pair each theory section with the matching lab in the labs directory.
- Prefer measuring before tuning; most sysctl examples are starting points, not universal defaults.
- Keep in mind that containerized workloads still share one Linux kernel with the host.

## Core mental model

- CPU problems are usually queueing problems.
- Memory problems are usually reclaim, locality, or sizing problems.
- Disk problems are usually latency distribution and queue depth problems.
- Network problems are usually path, policy, retransmission, or buffering problems.
- Stable systems come from understanding where the kernel queues work and how it applies backpressure.

## 1. Linux kernel fundamentals

Linux is a preemptive monolithic kernel with modular drivers, a stable syscall surface, and a design centered on queues, caches, and fairness. SRE work improves when every alert is mapped to a kernel queue or resource controller instead of treated as a mystery.

```text
+----------------------+  user space: apps, shells, daemons
| libc, runtimes, app  |
+----------+-----------+
           | syscalls
+----------v-----------+  kernel space: scheduler, VM, VFS, TCP/IP
| process, memory, IO  |
+----------+-----------+
           | drivers
+----------v-----------+  hardware: CPU, RAM, NIC, block devices
```

### Key points
- The kernel owns privilege transitions, interrupt handling, memory mapping, and device arbitration.
- System calls are the contract between applications and the kernel; latency often appears as slow syscalls.
- Work enters the kernel through syscalls, exceptions, interrupts, softirqs, and kernel threads.
- The kernel scales by batching work, caching data, and queueing requests when capacity is exhausted.
- Most Linux observability is available through procfs, sysfs, eBPF, tracepoints, perf events, and logs.
- When debugging, ask which queue is growing: run queue, socket backlog, page reclaim, block queue, or conntrack.

### Operator map
| Kernel surface | What it controls | Useful question |
| --- | --- | --- |
| syscall path | user to kernel transitions | Which syscall is slow or blocked? |
| scheduler | CPU time allocation | Is work runnable or sleeping? |
| memory manager | pages, reclaim, swap | Is latency reclaim related? |
| VFS and block layer | filesystem and disk IO | Is data stuck in cache or on disk? |
| network stack | packets and sockets | Is loss before or after the host? |

### Command examples
```bash
uname -a
cat /proc/version
lsmod | head
cat /proc/cmdline
dmesg | tail -50
```

### Common pitfalls
- Blaming the application before checking whether the kernel is throttling it with cgroups or reclaim.
- Treating load average as CPU-only instead of a count of runnable plus uninterruptible tasks.
- Ignoring kernel logs that already explain dropped packets, OOM kills, or filesystem errors.

### SRE checklist
- Know the kernel version, distro defaults, and whether the host is virtualized or bare metal.
- Confirm whether the issue is limited to one cgroup, one namespace, one NUMA node, or the whole host.
- Capture steady-state metrics before changing sysctls or service limits.

## 2. Process model and execution lifecycle

Linux represents tasks with task_struct objects. Processes, threads, kernel threads, zombies, and orphans are all scheduling entities with different namespaces, parentage, and resource accounting. Understanding that model explains what ps, top, and /proc are showing.

### Key points
- fork creates a child with copy-on-write memory; exec replaces the image while PID usually stays the same.
- Threads share an address space and many resources but still have individual task IDs and scheduling state.
- A zombie is an exited child waiting for the parent to reap its status; it consumes PID table entries, not CPU.
- Orphaned children are adopted by PID 1 or a configured subreaper, which is why init behavior matters in containers.
- Signals, open file descriptors, credentials, cgroup membership, and namespaces influence process behavior.
- procfs exposes per-process state in /proc/<pid>/status, /proc/<pid>/fd, /proc/<pid>/sched, and /proc/<pid>/smaps.

### Operator map
| Concept | Meaning | Command |
| --- | --- | --- |
| PID | process identifier | ps -ef |
| PPID | parent process ID | ps -o pid,ppid,cmd |
| TID | thread ID | ps -eLf |
| state | R,S,D,T,Z etc | cat /proc/<pid>/status |
| FD table | open files and sockets | ls -l /proc/<pid>/fd |

### Command examples
```bash
ps -eo pid,ppid,stat,ni,cls,comm --sort=pid | head -25
pstree -alp | head -40
cat /proc/1/status
ls -l /proc/$$/fd
grep -E "State|Threads|VmRSS" /proc/$$/status
```

### Common pitfalls
- Assuming high thread count means parallel progress; many thread pools spend most of their time sleeping.
- Forgetting that D-state tasks do not respond to SIGKILL until the underlying wait finishes.
- Missing FD inheritance during exec, which can keep sockets or files open unexpectedly.

### SRE checklist
- Differentiate runnable, sleeping, uninterruptible, stopped, and zombie tasks before acting.
- When a service fails to restart, check for stale PID files, un-reaped children, and exhausted PID limits.
- Inspect /proc/<pid>/limits when an app behaves differently under systemd than in a shell.

## 3. Namespaces and isolation boundaries

Namespaces virtualize global kernel resources so containers can look like independent hosts while still sharing one kernel. Every incident involving containers should begin by asking which namespace boundary hides the evidence you expect to see.

### Key points
- PID namespaces virtualize process IDs, so PID 1 inside a container is not PID 1 on the host.
- Network namespaces isolate interfaces, routes, ARP tables, conntrack, and firewall rules unless explicitly shared.
- Mount namespaces provide each workload with a separate filesystem view and propagation rules.
- UTS, IPC, time, and user namespaces isolate hostnames, IPC objects, clocks, and user IDs.
- Namespace joins happen with clone, unshare, and setns; container runtimes automate those calls.
- The same kernel still enforces cgroups, LSMs, and sysctls, so namespaces are isolation, not full virtualization.

### Operator map
| Namespace | Primary isolation | Fast check |
| --- | --- | --- |
| pid | process tree | lsns -t pid |
| net | interfaces and sockets | ip netns list |
| mnt | mount table | findmnt |
| user | UID and GID mapping | cat /proc/<pid>/uid_map |
| uts | hostname | hostname |

### Command examples
```bash
lsns
readlink /proc/$$/ns/net
ip netns list
nsenter --target <pid> --mount --uts --ipc --net --pid
cat /proc/<pid>/cgroup
```

### Common pitfalls
- Running host commands and assuming they reflect a container netns or mount namespace.
- Changing a sysctl without checking whether it is namespaced or host-wide.
- Debugging a pod network issue from the wrong namespace and missing the veth pair entirely.

### SRE checklist
- When traffic is missing, enter the workload network namespace before checking routes or sockets.
- Confirm whether PID 1 inside the container reaps children and handles termination signals correctly.
- Document which settings are shared with the host, such as kernel version and non-namespaced sysctls.

## 4. cgroups v1 and cgroups v2

Control groups account and limit resources. cgroups v1 exposed separate controller hierarchies, while v2 provides a unified tree with consistent semantics for CPU, memory, IO, and pressure accounting. Many “the host is fine but my service is slow” cases are cgroup stories.

### Key points
- v1 often had one mount per controller, which made accounting and delegation awkward for containers.
- v2 uses a single hierarchy rooted at /sys/fs/cgroup and adds cleaner resource distribution rules.
- cpu.max defines quota and period; cpu.weight controls proportional sharing when CPUs are contended.
- memory.max hard-limits usage, memory.high throttles before the hard limit, and memory.current shows charge.
- io.max and io.weight shape block IO in v2; older v1 deployments used blkio throttles.
- Pressure Stall Information pairs especially well with cgroups because it quantifies resource delay before failure.

### Operator map
| Controller concept | v1 example | v2 example |
| --- | --- | --- |
| CPU quota | cpu.cfs_quota_us | cpu.max |
| CPU share | cpu.shares | cpu.weight |
| Memory limit | memory.limit_in_bytes | memory.max |
| IO throttle | blkio.throttle.* | io.max |
| OOM grouping | controller specific | memory.oom.group |

### Command examples
```bash
stat -fc %T /sys/fs/cgroup
cat /proc/self/cgroup
cat /sys/fs/cgroup/cpu.max
cat /sys/fs/cgroup/memory.current
cat /sys/fs/cgroup/memory.events
```

### Common pitfalls
- Reading host-wide CPU and memory metrics without checking whether the service is capped inside a cgroup.
- Setting only hard limits and skipping memory.high, which removes an early-pressure safety valve.
- Assuming v1 and v2 file names are interchangeable in scripts and runbooks.

### SRE checklist
- Inspect cpu.stat, memory.events, and io.stat before blaming the kernel or the application.
- Tune quota, weight, and concurrency together; a tiny quota plus large worker pools amplifies latency spikes.
- For Kubernetes, map Pod QoS and requests or limits back to the cgroup files the kubelet created.

## 5. Memory management, virtual memory, page cache, and swap

Linux memory management is built around pages, page tables, reclaim, and caches. Good operators avoid “used memory” panic by separating anonymous memory from file cache and by understanding when swapping is a symptom versus a design choice.

### Key points
- Every process sees virtual memory; page tables translate virtual addresses to physical frames.
- Anonymous pages back heap and stack data; file-backed pages represent mmap data and page cache.
- Minor page faults populate mappings without disk access, while major faults require disk or remote memory.
- The page cache speeds repeated reads and delayed writes; buff cache being large is usually healthy.
- Swap extends the eviction surface for cold anonymous pages but can destroy latency-sensitive workloads when overused.
- Reclaim activity shows up as kswapd work, direct reclaim stalls, PSI memory pressure, and swap IO.

### Operator map
| Metric | Meaning | Where to check |
| --- | --- | --- |
| MemAvailable | best estimate of reclaimable headroom | cat /proc/meminfo |
| Cached | file cache that may be reclaimable | cat /proc/meminfo |
| Dirty | written but not flushed pages | cat /proc/meminfo |
| si/so | swap in or out rates | vmstat 1 |
| some/full memory PSI | stall time under pressure | cat /proc/pressure/memory |

### Command examples
```bash
free -h
cat /proc/meminfo | egrep "MemAvailable|Cached|Dirty|Swap"
vmstat 1 5
cat /proc/pressure/memory
sar -B 1 5
```

### Sysctl examples
```bash
sysctl -w vm.swappiness=10
sysctl -w vm.dirty_background_ratio=5
sysctl -w vm.dirty_ratio=20
```

### Common pitfalls
- Using only free memory as the health signal and ignoring MemAvailable.
- Dropping caches in production to “fix” memory graphs without understanding the workload.
- Mistaking page cache growth for a leak when the reclaim metrics are still calm.

### SRE checklist
- Correlate rising latency with major faults, PSI, and swap IO instead of memory percent alone.
- Check per-process RSS, PSS, and anonymous growth before concluding the leak is in the kernel.
- Record reclaim, fault, and swap counters before and after any tuning change.

## 6. OOM killer, oom_score, and oom_score_adj

When reclaim cannot recover enough memory, the kernel invokes the OOM killer. It scores processes according to memory footprint, privilege, and adjustments, then kills one or more victims to restore progress. SREs need to know whether the kill was system-wide or cgroup-local.

### Key points
- oom_score estimates how desirable a process is as a victim; higher scores die first.
- oom_score_adj ranges from -1000 to 1000 and shifts kill preference; -1000 is effectively immune.
- Container runtimes often set oom_score_adj so kubelet or sshd survive while best-effort pods are killable.
- Exit code 137 commonly indicates SIGKILL, which frequently but not always means an OOM kill.
- memory.events and dmesg reveal whether a cgroup limit fired before the host became globally exhausted.
- Repeated OOM kills often mean bad limit sizing, allocator fragmentation, or uncontrolled caches.

### Operator map
| Signal | Meaning | Action |
| --- | --- | --- |
| dmesg OOM line | global or cgroup kill event | capture victim and node state |
| oom_score | kill preference | inspect top candidates |
| oom_score_adj | policy override | verify critical daemons are protected |
| memory.events oom_kill | cgroup-local kill count | check pod or service limits |
| journal restart loop | service repeatedly killed | reduce concurrency or raise limit |

### Command examples
```bash
dmesg | egrep -i "out of memory|killed process|oom" | tail -20
cat /proc/<pid>/oom_score
cat /proc/<pid>/oom_score_adj
cat /sys/fs/cgroup/memory.events
journalctl -k -g oom --since -1h
```

### Common pitfalls
- Lowering oom_score_adj for too many daemons until only critical system services remain killable.
- Calling every SIGKILL an OOM kill without checking audit logs, orchestration events, or humans.
- Fixing symptoms by raising limits while leaving leaks or cache growth unbounded.

### SRE checklist
- Keep login, monitoring, and control-plane processes protected enough to preserve access.
- Prefer memory.high plus application-level backpressure over repeated hard-limit kills.
- Store the full dmesg OOM excerpt in incident notes because it contains crucial context.

## 7. Huge pages, transparent huge pages, and NUMA locality

Huge pages reduce TLB pressure by mapping larger memory chunks, while NUMA splits memory into node-local pools near specific CPUs. Both features can dramatically help or hurt latency depending on allocation patterns and scheduler behavior.

### Key points
- Transparent Huge Pages usually back eligible anonymous memory with 2 MiB pages instead of 4 KiB pages.
- THP improves CPU efficiency for large sequential memory access but can introduce compaction or collapse latency.
- Explicit hugetlb pages are reserved ahead of time and are common for databases and packet processing.
- NUMA locality matters because remote node memory has higher access latency and can increase queueing.
- numactl and per-node meminfo reveal imbalance, while perf and application metrics expose remote access costs.
- Pinning CPUs without considering memory policy can create fast cores waiting on remote memory.

### Operator map
| Feature | Benefit | Risk |
| --- | --- | --- |
| THP | fewer TLB misses | compaction latency |
| hugetlbfs | predictable large pages | reservation overhead |
| NUMA balancing | automatic page migration | background overhead |
| CPU pinning | cache locality | remote memory access if mismatched |
| memory interleave | spread allocations | less locality for hot data |

### Command examples
```bash
cat /sys/kernel/mm/transparent_hugepage/enabled
grep -E "Huge|AnonHuge" /proc/meminfo
numactl --hardware
numastat -p <pid>
cat /sys/devices/system/node/node*/meminfo | head -40
```

### Sysctl examples
```bash
sysctl -w vm.zone_reclaim_mode=0
```

### Common pitfalls
- Leaving THP at distro defaults for latency-critical databases without testing collapse behavior.
- Assuming a CPU-affine process is local to memory when the allocator placed pages elsewhere.
- Ignoring NUMA entirely on large boxes and wondering why one node swaps while others are idle.

### SRE checklist
- Measure remote memory and page migration activity before and after affinity changes.
- Use madvise or explicit huge pages when the application supports them instead of blind host-wide changes.
- Keep IRQ, process CPU affinity, and memory policy aligned for packet-heavy services.

## 8. CPU scheduling and the Completely Fair Scheduler

CFS models CPU sharing with virtual runtime. Tasks that received less service run sooner, weighted by nice level and cgroup weight. That mental model is essential when high latency appears on systems that are not pegged at 100 percent CPU.

### Key points
- Each runnable task accrues vruntime; lower vruntime wins the next slice on a CPU run queue.
- nice and cpu.weight do not reserve CPU time, they bias competition when contention exists.
- Latency sensitive tasks suffer when long run queues and CPU quotas create bursty throttling.
- Per-CPU run queues improve scaling, but migrations between CPUs can harm cache locality.
- schedstat, pidstat, and perf sched help explain run delay, migrations, and context-switch cost.
- Real-time classes exist above CFS and can starve normal work if misused.

### Operator map
| Signal | Meaning | Command |
| --- | --- | --- |
| load average | queued runnable or D-state work | uptime |
| run queue length | instantaneous CPU demand | vmstat 1 |
| context switches | scheduler churn | pidstat -w 1 |
| throttled_usec | cgroup CPU quota impact | cat cpu.stat |
| migrations | cross-CPU movement | perf sched record |

### Command examples
```bash
uptime
vmstat 1 5
pidstat -u -w 1 5
cat /proc/schedstat | head
perf sched timehist --summary
```

### Common pitfalls
- Interpreting a low average CPU percent as “not CPU related” while tasks are spending time waiting for slices.
- Using nice to solve hard isolation problems that really require affinity or separate cgroups.
- Applying real-time priorities to application threads without a rollback plan.

### SRE checklist
- Correlate latency spikes with run queue growth, context switches, and CPU throttling counters.
- Inspect per-core hot spots instead of host averages; one busy core can stall a sharded workload.
- Tune worker counts to CPU quota, not just to physical core count.

## 9. CPU affinity, IRQs, softirqs, CPU states, and load average

Affinity and interrupt distribution control where work runs. CPU states explain how time is spent, and load average reveals queue depth, not utilization. Most “CPU issue” pages actually require reading all three together.

### Key points
- taskset, cpuset cgroups, and irqbalance affect whether application threads and interrupts share cores.
- Hard IRQs are top-half interrupt handlers; softirqs and ksoftirqd finish deferred work such as packet processing.
- Busy networking hosts can show high softirq CPU even when user-space looks quiet.
- CPU states such as us, sy, wa, hi, si, st, and id describe where time went during sampling.
- Load average counts runnable tasks plus tasks stuck in uninterruptible sleep, so IO can inflate load.
- Steal time indicates the hypervisor scheduled someone else on the physical CPU while your VM waited.

### Operator map
| CPU field | Interpretation | Primary tool |
| --- | --- | --- |
| %us | user-space execution | mpstat -P ALL |
| %sy | kernel execution | top or mpstat |
| %wa | CPU idle while tasks wait on IO completion | iostat or top |
| %si/%hi | software or hardware interrupt time | mpstat -I CPU |
| %st | virtualization steal | mpstat or top |

### Command examples
```bash
taskset -pc <pid>
cat /proc/interrupts | head -25
mpstat -P ALL 1 5
mpstat -I SUM 1 5
cat /proc/loadavg
```

### Common pitfalls
- Pinning an app to a core that also handles the busiest NIC queue and then blaming the app.
- Ignoring %st on cloud VMs during noisy-neighbor incidents.
- Reading %wa as the percentage of time disks are busy rather than CPU idle with pending IO.

### SRE checklist
- Balance IRQ affinity across CPUs that are allowed to process network or storage work.
- Verify whether high load is from runnable work, D-state tasks, or a mix of both.
- On virtualized hosts, compare guest and hypervisor metrics before concluding the guest is saturated.

## 10. Disk IO stack and schedulers

A read or write moves through the VFS, page cache, filesystem, block layer, device queue, and storage hardware. Latency can be introduced at each layer, so you need to know whether the delay is due to cache misses, queue depth, controller saturation, or remote storage.

### Key points
- The VFS normalizes file operations while filesystems map logical files to physical blocks and metadata.
- Buffered writes usually land in the page cache first, then writeback threads flush dirty data later.
- The block layer merges and dispatches requests to hardware queues; modern devices may use multiqueue blk-mq.
- NVMe, SATA, network block devices, RAID, and cloud volumes all expose different latency and queue behaviors.
- IO schedulers trade fairness, latency, and throughput; the best choice depends on device type and workload.
- Filesystem journaling, barriers, and metadata contention can dominate even when raw device latency looks acceptable.

### Operator map
| Scheduler | Typical use | Watch out for |
| --- | --- | --- |
| none | fast SSD or NVMe with device-side scheduling | no fairness magic under mixed workloads |
| mq-deadline | predictable latency on blk-mq devices | may reduce peak throughput |
| bfq | interactive fairness | higher overhead for some servers |
| kyber | latency-oriented mixed workloads | less common on some distros |
| filesystem journal | metadata ordering rather than a scheduler | journal stalls masking device health |

### Command examples
```bash
lsblk -o NAME,ROTA,SCHED,SIZE,TYPE,MOUNTPOINT
cat /sys/block/<device>/queue/scheduler
iostat -xz 1 5
findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS
cat /proc/diskstats | head -10
```

### Common pitfalls
- Changing the scheduler before proving the bottleneck is below the page cache or filesystem.
- Comparing await across devices with very different queue depths and media types without context.
- Ignoring filesystem errors and focusing only on block metrics.

### SRE checklist
- Identify the full path from file to device, including RAID, LVM, dm-crypt, or network storage layers.
- Check whether queue depth, service time, or writeback throttling is the first sign of trouble.
- Treat filesystem mount options as part of performance tuning, not an afterthought.

## 11. iostat interpretation, iowait, load, and direct versus buffered IO

iostat is useful only when you translate its columns into queueing behavior. Buffered and direct IO influence what the kernel can merge or cache, and iowait only tells you that CPUs had nothing useful to run while some tasks waited on IO.

### Key points
- r/s and w/s show operation rates, while rkB/s and wkB/s show throughput; high throughput can still be healthy.
- await approximates end-to-end request latency as seen by the block layer and includes queue time plus service time.
- svctm is often misleading or absent on modern kernels, so do not build decisions around it.
- %util near 100 on old single-queue devices meant saturation, but multiqueue devices need deeper context.
- Buffered IO benefits from readahead and write coalescing; direct IO bypasses most page cache effects.
- High load with high iowait usually means blocked tasks are piling up, not that CPUs are doing expensive work.

### Operator map
| Observation | Likely story | Next step |
| --- | --- | --- |
| high await, low util | backend latency or queue imbalance | check storage network and filesystem |
| high util, low throughput | small random IO or queue saturation | inspect request size and process mix |
| high load, high wa | D-state buildup on IO | find blocked tasks and hottest device |
| high read cache hit | page cache serving workload | focus on memory pressure not disk |
| direct IO slowdown | app sees raw device behavior | tune queue depth and filesystem alignment |

### Command examples
```bash
iostat -xz 1 5
pidstat -d 1 5
vmstat 1 5
grep -R . /sys/block/<device>/queue/{nr_requests,read_ahead_kb} 2>/dev/null
fio --name=sample --filename=./fio.test --rw=randread --size=256M --runtime=30
```

### Common pitfalls
- Calling a device “fine” because CPU usage is low while threads are blocked on it.
- Using O_DIRECT benchmarks to predict buffered database behavior without clarifying the access pattern.
- Assuming %util is comparable across rotating disks, SSDs, and virtual disks.

### SRE checklist
- Match the benchmark mode to the application mode: synchronous, buffered, direct, sequential, or random.
- Always pair iostat with process-level views such as pidstat, iotop, or per-cgroup metrics.
- When load is high but CPU is not, inspect D-state tasks before changing application thread counts.

## 12. Linux networking stack overview

Packets traverse the NIC driver, NAPI polling, GRO or GSO transformations, routing, conntrack, socket queues, and finally user space. Drops can happen before a packet ever becomes visible to the application, so a stack model prevents blind debugging.

```text
wire -> NIC -> driver/NAPI -> ingress qdisc -> netfilter -> routing
     -> local socket receive queue -> app read()
app write() -> socket send queue -> qdisc -> driver -> NIC -> wire
```

### Key points
- NAPI reduces interrupt storms by switching high-rate packet processing to polling.
- GRO coalesces inbound packets, while GSO and TSO defer segmentation outbound to save CPU.
- The routing lookup and policy rules decide whether traffic is local, forwarded, or dropped.
- Netfilter hooks enable conntrack, NAT, and firewall policies at multiple points in the path.
- Each socket has receive and send buffers; if readers or writers fall behind, drops or backpressure occur.
- Queueing disciplines shape egress behavior and can become invisible bottlenecks on busy links.

### Operator map
| Path stage | What to inspect | Command |
| --- | --- | --- |
| driver | link state and errors | ip -s link |
| NAPI and softirq | packet processing CPU | mpstat -I CPU |
| routing | next hop decision | ip route get |
| conntrack | state tracking and limits | conntrack -S |
| socket queues | send q and recv q | ss -tinm |

### Command examples
```bash
ip -br addr
ip route
ss -s
ethtool -S <iface> | head -40
nstat -az | head -30
```

### Common pitfalls
- Looking only at application logs when packets are already being dropped in the driver or firewall.
- Ignoring GRO or offload effects and misreading packet captures taken on the host.
- Debugging throughput without checking NIC ring sizes, qdisc drops, or socket backlogs.

### SRE checklist
- Start with link, route, ARP or neighbor, conntrack, and socket queues before diving into packets.
- Correlate packet loss with interface counters and softirq CPU to separate host issues from path issues.
- Capture which namespace and interface the packet should traverse before running tcpdump.

## 13. Socket lifecycle and TCP states

Sockets move through creation, bind, listen, accept, connect, established transfer, and teardown. TCP state counts are operational gold because they show where a connection is stalled: handshake, application processing, retransmission, or cleanup.

### Key points
- Servers call socket, bind, listen, and accept; clients call socket and connect, then exchange data via read and write.
- The three-way handshake creates SYN-SENT, SYN-RECV, and ESTABLISHED state transitions.
- Teardown uses FIN and ACK transitions such as FIN-WAIT-1, CLOSE-WAIT, LAST-ACK, and TIME-WAIT.
- CLOSE-WAIT means the remote side closed and the local application has not closed yet.
- TIME-WAIT protects against delayed packets and is normal after active close, though very high counts may need tuning or connection reuse.
- Listen backlog, accept queue overflow, and SYN backlog drops are common causes of intermittent connect failures.

### Operator map
| TCP state | Interpretation | Typical action |
| --- | --- | --- |
| SYN-SENT | client waiting for SYN-ACK | check path, firewall, SYN cookies, or target |
| SYN-RECV | server saw SYN but handshake not finished | check backlog and packet loss |
| ESTAB | connection active | inspect send or recv queues |
| CLOSE-WAIT | app has not closed after peer FIN | look for application leak or stuck worker |
| TIME-WAIT | kernel waiting out MSL | check connection churn and client reuse |

### Command examples
```bash
ss -tan state all | head -40
ss -lnt
ss -tin sport = :443
nstat -az | egrep "Listen|Retrans|Reset|Timeout"
cat /proc/net/tcp | head
```

### Common pitfalls
- Killing a process to remove TIME-WAIT sockets, which are kernel-managed and short-lived by design.
- Treating CLOSE-WAIT as a kernel problem when it usually means the application failed to close.
- Increasing backlogs without also checking file descriptor limits and application accept rate.

### SRE checklist
- Look at Recv-Q and Send-Q in ss output to determine whether the app or network is the bottleneck.
- Track retransmits, resets, and backlog overflows together instead of in isolation.
- For incident timelines, note which side actively closed the connection.

## 14. Conntrack, socket buffers, and TCP tuning sysctls

Conntrack tracks flows for NAT and stateful firewalls. Socket buffers and TCP sysctls influence how much data the kernel can queue, how quickly it retransmits, and how it handles high-bandwidth or high-latency paths. Tuning helps only after the bottleneck is identified.

### Key points
- nf_conntrack stores per-flow state; when the table is full, new connections may fail even if the app is healthy.
- rmem and wmem defaults auto-tune socket buffers, but applications can cap or override them.
- tcp_rmem and tcp_wmem define min, default, and max auto-tuning ranges for sockets.
- somaxconn limits the listen backlog visible to applications, while tcp_max_syn_backlog covers half-open SYNs.
- tcp_fin_timeout, tcp_tw_reuse, and keepalive settings affect teardown and stale connection handling.
- Aggressive tuning can hide symptoms temporarily while increasing memory usage or creating unfairness.

### Operator map
| Knob | Why it exists | Use carefully when |
| --- | --- | --- |
| net.core.somaxconn | caps listen backlog | SYN or accept queues overflow |
| net.ipv4.tcp_max_syn_backlog | half-open queue length | bursty inbound connects |
| net.ipv4.tcp_rmem | receive auto-tuning | high BDP links |
| net.ipv4.tcp_wmem | send auto-tuning | high throughput senders |
| net.netfilter.nf_conntrack_max | flow table limit | NAT or firewall nodes |

### Command examples
```bash
ss -tinm
conntrack -S
sysctl net.core.somaxconn
sysctl net.ipv4.tcp_rmem net.ipv4.tcp_wmem
sysctl net.netfilter.nf_conntrack_max
```

### Sysctl examples
```bash
sysctl -w net.core.somaxconn=4096
sysctl -w net.ipv4.tcp_max_syn_backlog=4096
sysctl -w net.ipv4.tcp_fin_timeout=15
```

### Common pitfalls
- Increasing socket buffers on every host and silently consuming large amounts of RAM.
- Raising conntrack limits without checking RAM and timeout behavior.
- Turning on tcp_tw_reuse or similar tweaks without understanding client and NAT interactions.

### SRE checklist
- Size TCP buffers for the path and workload, not from random internet snippets.
- Graph conntrack count, insert failures, retransmits, and listen drops together.
- Document every sysctl change with a rollback threshold and success metric.

## 15. Deep network tools for SREs

The best network debugging workflow escalates from cheap, broad tools to expensive, precise tools. Link counters, routes, ss, and nstat often answer the question before tcpdump or Wireshark are needed.

### Key points
- ip and ss are the first stop for addresses, routes, neighbors, listening sockets, and queue depth.
- mtr and tracepath blend reachability and path loss information better than isolated ping or traceroute runs.
- tcpdump captures packets at the host, but interface choice, namespace choice, and offloads matter.
- ethtool surfaces link settings, driver statistics, coalescing, and ring configuration.
- nstat and sar -n show TCP, IP, and interface counters over time for trend analysis.
- eBPF tools such as tcplife, tcpconnect, and dropsnoop can reveal events without full packet capture volume.

### Operator map
| Question | Tool | Why |
| --- | --- | --- |
| Is the route correct? | ip route get | shows actual next hop decision |
| Is the port open? | ss or nc | separates listen issue from path issue |
| Are packets dropped on host? | ip -s link or ethtool -S | driver and interface counters |
| Is TCP retransmitting? | nstat or ss -i | transport-level health |
| Do I need packets? | tcpdump | last-mile proof of what hit the host |

### Command examples
```bash
ip route get 1.1.1.1
ss -tina
mtr --report --report-cycles 10 example.com
tcpdump -ni any host 10.0.0.5 and port 443
ethtool -k <iface>
```

### Common pitfalls
- Capturing on any when you really need the specific veth or bond member interface.
- Running huge tcpdump sessions with no filter and then drowning in irrelevant packets.
- Using only ping to judge application health; ICMP policy and TCP policy are often different.

### SRE checklist
- Start with counters and queue state before taking packet captures.
- Capture clocks, interfaces, filters, and namespaces alongside every tcpdump snippet.
- Prefer narrow reproductions with timestamps so packet capture can be aligned to logs.

## 16. DNS behavior and debugging

DNS incidents are rarely just “DNS is broken.” You need to distinguish resolver configuration errors, transport failures, stale caches, delegation mistakes, split-horizon behavior, TTL surprises, and application stub resolver quirks.

### Key points
- Applications may use libc, c-ares, Java, Go, Envoy, or systemd-resolved caches, each with different behaviors.
- A or AAAA response order influences dual-stack connection timing and happy eyeballs behavior.
- Negative caching means NXDOMAIN or SERVFAIL can persist beyond the exact instant of failure.
- dig +trace isolates authoritative delegation issues from recursive resolver issues.
- resolv.conf search domains and ndots can cause unexpected query storms and delays.
- Reverse lookup failures often affect logs, ACLs, or TLS checks even when forward lookup works.

### Operator map
| Symptom | Likely cause | Useful command |
| --- | --- | --- |
| NXDOMAIN | wrong name or search path | dig fqdn |
| SERVFAIL | upstream or DNSSEC problem | dig +dnssec |
| slow lookup | resolver latency or retries | time dig |
| wrong IP | split-horizon or stale cache | dig @resolver name |
| intermittent connect delay | AAAA fallback or TTL churn | dig A AAAA |

### Command examples
```bash
cat /etc/resolv.conf
getent hosts example.com
dig example.com A +short
dig +trace example.com
resolvectl query example.com
```

### Common pitfalls
- Flushing one cache and assuming every process uses that same cache.
- Testing with dig against a public resolver when the app actually uses a local stub or sidecar.
- Ignoring search domains and ndots during Kubernetes name resolution incidents.

### SRE checklist
- Record the exact resolver IP, query type, response code, and TTL during incidents.
- Compare app behavior with getent or the language runtime used by the app, not just dig output.
- Validate both forward and reverse lookup when identity or allow-lists are involved.

## 17. TLS and SSL in practice

TLS failures can arise from certificate trust, name mismatch, time drift, protocol version mismatch, cipher policy, SNI, ALPN, or middleboxes. A good operator treats TLS as a multi-step negotiation rather than a single opaque error.

### Key points
- The client validates the certificate chain, hostname, validity period, and sometimes revocation status.
- SNI selects the certificate on shared endpoints, and ALPN negotiates HTTP/1.1 versus HTTP/2 or other protocols.
- TLS handshake errors may occur before any HTTP request reaches the server logs.
- Expired intermediates or missing chain files often break some clients but not others depending on trust stores.
- Clock skew can create not-yet-valid or expired errors even when the cert itself is correct.
- Performance tuning includes session reuse, modern cipher suites, and avoiding needless handshakes.

### Operator map
| Failure mode | Typical symptom | Tool |
| --- | --- | --- |
| hostname mismatch | certificate common name error | openssl s_client -servername |
| expired cert | verify failure or browser warning | openssl x509 -dates |
| protocol mismatch | handshake alert | openssl s_client -tls1_2 |
| missing intermediate | works on some clients only | openssl s_client -showcerts |
| SNI issue | wrong certificate presented | curl --resolve or openssl -servername |

### Command examples
```bash
openssl s_client -connect example.com:443 -servername example.com </dev/null
openssl x509 -noout -dates -issuer -subject -in cert.pem
curl -vkI https://example.com/health
gnutls-cli -p 443 example.com
date -u
```

### Common pitfalls
- Checking only the leaf certificate and forgetting chain completeness or key usage extensions.
- Treating TLS alerts as application errors when the request never left the handshake stage.
- Turning off verification as a “fix” and normalizing insecure behavior.

### SRE checklist
- Test with the real hostname, SNI, and trust bundle used by the failing client.
- Confirm system time and timezone before chasing certificate ghosts.
- Track certificate expiry and renewal path long before incidents happen.

## 18. Firewalls, packet filters, and policy debugging

Host firewalls, cloud security groups, network ACLs, and service mesh policies can all block the same flow. The job is to determine at which policy layer the packet disappears and whether stateful tracking is involved.

### Key points
- iptables and nftables implement filtering, NAT, and state matching at netfilter hooks.
- Stateful rules rely on conntrack, so dropped state or conntrack exhaustion can look like random packet loss.
- Default drop policies are safer, but they make observability and counters essential.
- Cloud firewalls and host firewalls may both permit or deny traffic independently.
- Kubernetes adds service, kube-proxy, CNI, and sometimes policy engines on top of host rules.
- Rule order matters; the first matching drop or reject can explain intermittent behavior.

### Operator map
| Layer | Example | How to inspect |
| --- | --- | --- |
| host firewall | nftables or iptables | nft list ruleset |
| cloud perimeter | security group or ACL | provider console or CLI |
| container policy | Kubernetes NetworkPolicy | kubectl describe networkpolicy |
| L7 policy | service mesh RBAC | mesh config and proxies |
| conntrack state | ESTABLISHED or RELATED matches | conntrack -L |

### Command examples
```bash
nft list ruleset
iptables -L -n -v --line-numbers
iptables -t nat -L -n -v
conntrack -L | head -40
ip rule show
```

### Common pitfalls
- Checking only INPUT rules when the packet is forwarded or DNATed elsewhere.
- Assuming REJECT and DROP look the same to clients; they lead to very different symptoms.
- Editing firewall rules during an incident without saving the pre-change counter state.

### SRE checklist
- Use packet counters to find the exact rule a packet matched or failed to match.
- Verify whether NAT changed the tuple before the rule you are inspecting.
- Treat host firewall, cloud firewall, and overlay policy as one end-to-end chain.

## 19. The USE method

The USE method asks for utilization, saturation, and errors on every resource. It is not a single tool but a disciplined way to avoid tunnel vision. For Linux, the main resources are CPU, memory, disks, filesystems, NICs, sockets, and kernel queues.

### Key points
- Utilization measures how busy a resource is relative to capacity.
- Saturation measures queued work or delay waiting for capacity.
- Errors capture failed operations, drops, resets, retries, or corruption.
- USE works best when you apply it top-down across every major subsystem, not just the one that paged.
- It is especially good for high-level triage before detailed tracing or profiling.
- The method forces you to look at saturation signals such as run queue, backlog, queue depth, and PSI.

### Operator map
| Resource | Utilization | Saturation | Errors |
| --- | --- | --- | --- |
| CPU | %busy | run queue length | throttling or machine checks |
| memory | used or working set | reclaim stalls or PSI | OOM kills |
| disk | %util or throughput | queue depth or await | IO errors |
| network | bandwidth | socket backlog or qdisc queue | drops or retransmits |
| filesystem | space usage | inode pressure or journal waits | corruption or ENOSPC |

### Command examples
```bash
mpstat -P ALL 1 3
vmstat 1 3
iostat -xz 1 3
ss -s
ip -s link
```

### Common pitfalls
- Stopping at utilization and never checking whether a queue is building.
- Gathering one screenshot instead of a short time series that exposes bursts.
- Ignoring errors because they are non-zero but “old”; deltas matter.

### SRE checklist
- Fill a USE table for every major subsystem during incident triage.
- Prioritize the resource with simultaneous utilization, saturation, and errors.
- Use USE to decide whether you need logs, profiles, packet capture, or storage tracing next.

## 20. Performance tools and observability surfaces

Linux exposes several layers of observability. procfs and sysfs offer counters, perf samples CPU activity, ftrace and tracepoints show kernel events, and eBPF enables dynamic low-overhead instrumentation. SREs should choose the least invasive tool that answers the question.

### Key points
- top, ps, vmstat, iostat, pidstat, sar, and ss provide broad, low-cost first-pass views.
- perf samples call stacks, cache misses, scheduling delay, and many hardware or software events.
- ftrace and trace-cmd expose scheduler, syscall, block, and network events with high fidelity.
- eBPF tools attach to kprobes, tracepoints, and cgroup hooks for precise event capture.
- strace answers syscall latency questions quickly, especially for hanging processes or permission issues.
- Choose tools based on whether you need counts, time-series, call stacks, events, or packet contents.

### Operator map
| Tool | Best for | Caution |
| --- | --- | --- |
| strace | hung or slow syscalls | can perturb extremely hot paths |
| perf top or record | CPU hot functions | needs symbols for best value |
| bpftool or bcc | dynamic event tracing | requires kernel support and privilege |
| sar | historical host trends | only useful if collection is enabled |
| tcpdump | wire proof | capture only what you need |

### Command examples
```bash
strace -tt -T -p <pid>
perf top
perf record -g -p <pid> -- sleep 30
bpftool prog show
trace-cmd record -e sched_switch sleep 5
```

### Common pitfalls
- Jumping to invasive tracing before collecting cheap counters and reproducing the issue cleanly.
- Profiling CPU when the process is mostly blocked on IO or locks.
- Capturing without timestamps or process IDs, making later correlation impossible.

### SRE checklist
- Prefer counters first, profiles second, traces third, packet capture last.
- Preserve the exact command line and duration used to gather evidence for reproducibility.
- Know your kernel and distro support for perf events and eBPF before an incident starts.

## 21. Signals, systemd, file descriptors, and kernel tuning workflow

Operational work often ends with process control, service supervision, descriptor management, and tuning. These topics are grouped because they represent the final bridge between diagnosis and a durable production fix.

### Key points
- Signals deliver asynchronous control such as TERM for graceful shutdown, HUP for reload, and KILL for forceful termination.
- systemd adds units, dependencies, restart policies, slices, environment handling, and sandboxing on top of raw processes.
- File descriptors are the kernel handles for files, sockets, pipes, epoll instances, and many more objects.
- Per-process and system-wide FD limits can cause accept failures, log write errors, or broken watchers long before disks are full.
- Kernel tuning should be hypothesis driven, measured, reversible, and documented with workload context.
- sysctl, unit overrides, ulimit, and cgroup configuration should be aligned rather than changed independently.

### Operator map
| Area | Key files or commands | Typical symptom |
| --- | --- | --- |
| signals | kill -TERM, trap, /proc/<pid>/status | service ignores shutdown |
| systemd | systemctl status, systemctl cat, journalctl -u | restart loop or bad unit defaults |
| file descriptors | ulimit -n, /proc/sys/fs/file-max, lsof | EMFILE or ENFILE errors |
| sysctl | /etc/sysctl.d and sysctl -a | host-level tuning drift |
| limits | systemctl show and /etc/security/limits.conf | works in shell, fails in service |

### Command examples
```bash
kill -TERM <pid>
systemctl status <service>
systemctl show <service> -p LimitNOFILE -p MemoryMax -p CPUQuota
ls -l /proc/<pid>/fd | wc -l
sysctl -a | egrep "somaxconn|swappiness|max_map_count|file-max"
```

### Sysctl examples
```bash
sysctl -w fs.file-max=2097152
sysctl -w vm.max_map_count=262144
sysctl -w kernel.pid_max=4194304
```

### Common pitfalls
- Reloading a service with HUP when the application actually requires a full restart to apply limits.
- Raising LimitNOFILE on the unit but forgetting the app or container runtime also imposes limits.
- Applying sysctl changes by copy-paste without a rollback condition or baseline metrics.

### SRE checklist
- When a process hangs on shutdown, inspect which signal it handles and whether children or sockets keep it alive.
- Audit LimitNOFILE, TasksMax, MemoryMax, and CPUQuota on important services before incidents happen.
- Treat kernel tuning as code: versioned, explained, peer reviewed, and validated against workload metrics.

## 21. Fast operator recap

| If you see | Ask first | First command |
| --- | --- | --- |
| high load but low CPU | Are tasks stuck in D state or throttled? | vmstat 1 |
| memory full graph | Is MemAvailable low and reclaim noisy? | cat /proc/meminfo |
| slow disk | Is await high because of queueing or backend latency? | iostat -xz 1 |
| connection timeouts | Is the packet dropped, delayed, or never replied to? | ss -tinm |
| too many open files | Is the leak in one process or system-wide? | lsof -p <pid> |

## 22. Suggested practice order

1. Learn to read uptime, vmstat, iostat, ss, and journalctl quickly.
2. Practice mapping each symptom to the responsible queue or controller.
3. Reproduce safe versions of CPU, memory, disk, and network incidents in a lab environment.
4. Add perf, tcpdump, and eBPF only after you can explain the basic counters.
5. Build dashboards around utilization, saturation, and errors for every core resource.

