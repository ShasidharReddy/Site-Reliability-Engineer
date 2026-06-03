# Lab 01: Linux Performance Troubleshooting

This lab moves from simple host snapshots to realistic incident diagnosis.
The goal is not to memorize commands but to build a sequence: scope, baseline, compare, isolate, reproduce, validate.

## Lab rules

- Run destructive or high-load commands only on disposable lab systems.
- Put evidence in a working directory under the current directory, for example ./evidence.
- Favor short sampling intervals during active symptoms, then switch to lower-cost monitoring.
- Never change a kernel knob until you have a before-and-after metric that matters.
- Keep one note for observed facts and another for hypotheses so you do not confuse them.

## Tools used in this lab

| Area | Primary tools | Backup tools |
| --- | --- | --- |
| CPU | uptime, vmstat, mpstat, pidstat | top, ps, perf |
| Memory | free, vmstat, /proc/meminfo, PSI | smaps, sar -B |
| Disk | iostat, pidstat -d, df, lsof +L1 | lsblk, findmnt |
| Integrated triage | USE method table | journalctl, dmesg |

## 1. Baseline capture before touching the host

### Objective
Build a reusable performance snapshot so later conclusions are based on evidence, not memory.

### Safety and setup
- Run on a Linux host or VM where you are allowed to observe resource usage.
- Avoid benchmarking production systems without change-control approval.
- Create a working directory such as ./evidence for text notes and copied command output.
- If sysstat is installed, note the collection interval so you can compare with historical data.
- Record CPU count, RAM size, storage type, and whether the host is virtualized.

### Questions to answer
- What does normal look like for load, memory availability, disk latency, and socket counts?
- Which collectors are already present: sar, node exporter, cAdvisor, or application metrics?
- Are there cgroup limits that make host-wide metrics misleading?
- Do kernel logs already contain clues such as OOMs, ext4 errors, or NIC resets?

### Runbook
```bash
mkdir -p ./evidence
date
uname -a
uptime
free -h
vmstat 1 5
iostat -xz 1 5
ss -s
journalctl -k -n 50
```

### Interpretation guide
| Command | Primary signal | Why you care |
| --- | --- | --- |
| uptime | load average | queue depth relative to CPUs |
| free -h | available memory | headroom before reclaim |
| vmstat | r, b, si, so | scheduling and memory pressure |
| iostat | await, util, throughput | device queue behavior |
| ss -s | transport state summary | socket pressure and churn |

### What to look for
- Note whether load tracks CPU usage or instead tracks blocked tasks.
- Compare MemAvailable with application working set and cache size.
- Look for a device with rising await or a filesystem already close to full.
- Check whether TIME-WAIT or CLOSE-WAIT counts are unusual for the workload.
- Write down any kernel warnings before starting deeper tests.

### Completion checklist
- You can summarize current CPU, memory, disk, and network health in one paragraph.
- You know which metrics are host-wide and which are cgroup scoped.
- You stored timestamps so future measurements can be aligned with logs and traces.
- You can identify the noisiest subsystem even if you cannot yet explain why.

### Extension
- Repeat the same capture during a known busy period and compare deltas.
- Add sar history if available so you can contrast current behavior with the previous hour.
- Convert the baseline into a standard incident template for your team.

## 2. CPU analysis with load, run queues, and per-core hotspots

### Objective
Distinguish CPU saturation from CPU queueing, pinning, or throttling.

### Safety and setup
- Use a workload that can drive CPU above idle, such as a build, compression, or synthetic loop.
- If available, install stress-ng in a lab environment only.
- Confirm how many CPUs the service can actually use through affinity or cgroup quota.
- Keep a shell open for vmstat, another for mpstat, and another for pidstat.
- Do not change scheduler knobs until you can explain the baseline.

### Questions to answer
- Is the host CPU-bound, quota-bound, or single-core hot while others are idle?
- Does load average exceed the effective CPU count?
- Are context switches or migrations unusually high?
- Is steal time present because the workload is running in a VM?

### Runbook
```bash
uptime
vmstat 1 10
mpstat -P ALL 1 10
pidstat -u -w 1 10
ps -eo pid,psr,ni,%cpu,comm --sort=-%cpu | head -20
cat /sys/fs/cgroup/cpu.max 2>/dev/null
cat /sys/fs/cgroup/cpu.stat 2>/dev/null
perf top
```

### Interpretation guide
| Observation | Interpretation | Next action |
| --- | --- | --- |
| high r in vmstat | CPU demand is queueing | check per-core use and cgroup quota |
| one hot core only | affinity or single-thread bottleneck | inspect psr and app design |
| high %st | hypervisor contention | check host placement or instance type |
| high context switches | thread churn or lock contention | profile with perf or pidstat -w |
| cpu.stat throttled_usec rising | quota-induced latency | resize quota or reduce concurrency |

### What to look for
- Correlate load with run queue length instead of relying on top alone.
- Check whether the same PID stays on one CPU or is migrated frequently.
- If quota is low, note how bursty the application becomes as each period ends.
- Steal time above a few percent on a busy VM deserves escalation to the platform layer.
- Profile only after confirming that the process is actually on-CPU long enough to sample.

### Completion checklist
- You can explain why load is high in terms of runnable tasks or throttled tasks.
- You identified whether the hotspot is application code, kernel time, or virtualization.
- You know whether adding workers would help or simply deepen the queue.
- You recorded one candidate remediation and one candidate risk.

### Extension
- Use taskset to pin a test workload and observe how locality changes latency.
- Compare perf output before and after changing worker counts.
- Capture scheduler latency with perf sched timehist for a short run.

## 3. Memory analysis with reclaim, cache, and swap

### Objective
Separate healthy cache usage from true memory pressure and identify which processes are responsible.

### Safety and setup
- Choose a host with enough visibility to read /proc and cgroup files.
- Be careful with synthetic memory load; never trigger uncontrolled swapping on production systems.
- If using a container, identify the memory.max and memory.high values first.
- Prepare commands that show both host-wide and per-process memory.
- Have a plan to stop the load generator quickly if reclaim becomes disruptive.

### Questions to answer
- Is available memory shrinking because of anonymous growth, file cache growth, or both?
- Are kswapd and direct reclaim active?
- Is swap activity present and is it actually harming latency?
- Did a cgroup limit, not the host, trigger the alert?

### Runbook
```bash
free -h
cat /proc/meminfo | egrep "MemAvailable|Cached|Dirty|Anon|Swap"
vmstat 1 10
cat /proc/pressure/memory
ps -eo pid,%mem,rss,vsz,comm --sort=-rss | head -20
cat /sys/fs/cgroup/memory.current 2>/dev/null
cat /sys/fs/cgroup/memory.events 2>/dev/null
grep -E "pgscan|pgsteal|oom" /proc/vmstat | head -30
```

### Interpretation guide
| Signal | Good reading | Bad reading |
| --- | --- | --- |
| Cached high | cache available for reclaim | not enough if MemAvailable is collapsing |
| si and so zero | no swap pressure | does not guarantee no reclaim stalls |
| memory PSI near zero | little stall time | spikes matter under bursty load |
| rss growth in one PID | probable leak or cache growth | confirm with smaps or allocator stats |
| memory.events high | cgroup pressure or OOM | host totals may hide it |

### What to look for
- Focus on MemAvailable, PSI, and swap activity instead of “used memory.”
- Look for one or two dominant processes before speculating about kernel leaks.
- If the page cache is large but PSI is low, the system is probably still healthy.
- Direct reclaim often shows up as latency before total memory appears exhausted.
- In containers, RSS plus cache may exceed expectations because the workload shares a node.

### Completion checklist
- You can name the dominant consumers of anonymous and file-backed memory.
- You can say whether swap is a background mechanism or an active source of pain.
- You know whether the alert was cgroup-local or host-wide.
- You identified whether tuning, resizing, or application fixes are appropriate next steps.

### Extension
- Inspect /proc/<pid>/smaps_rollup for a suspicious process.
- If the app supports it, compare allocator metrics with RSS.
- Experiment with memory.high in a lab to see throttling before OOM kill.

## 4. Disk IO analysis with latency, queue depth, and filesystem context

### Objective
Find out whether an IO problem comes from the application pattern, filesystem, block queue, or storage backend.

### Safety and setup
- Identify the application mount points and the underlying block devices.
- Avoid synthetic write tests on important filesystems; use a safe lab file in the current directory.
- Know whether the device is local SSD, network-attached block, RAID, or virtual disk.
- Collect both host-level and process-level IO views.
- If possible, run a short read-only trace during a busy period.

### Questions to answer
- Which device shows the highest await and queue buildup?
- Is the issue random IO, writeback, journal activity, or backend latency?
- Are blocked tasks accumulating in D state?
- Is the application using buffered IO or direct IO?

### Runbook
```bash
findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS
lsblk -o NAME,SCHED,ROTA,SIZE,TYPE,MOUNTPOINT
iostat -xz 1 10
pidstat -d 1 10
ps -eo pid,stat,wchan:32,comm | awk "$2 ~ /D/" | head -20
df -h
df -i
lsof +L1 2>/dev/null | head -20
```

### Interpretation guide
| Pattern | Likely root cause | Next step |
| --- | --- | --- |
| await rising, util high | device or backend saturated | inspect queue depth and storage layer |
| await high, util low | remote latency or throttling upstream | check cloud volume metrics or SAN |
| D-state tasks | blocking below user space | inspect wchan and device errors |
| space low but deleted file open | stale file handles | restart or rotate culprit process |
| inode low, space fine | tiny-file explosion | find hot directory and cleanup policy |

### What to look for
- Map each busy filesystem back to the device actually carrying the load.
- Note whether writes are delayed in the page cache or blocked on synchronous flushes.
- A D-state process with a consistent wait channel often points directly at the subsystem involved.
- Deleted-but-open files can make df misleading until the writer closes the FD.
- Inode exhaustion is operationally similar to disk full but requires a different cleanup plan.

### Completion checklist
- You can identify the hottest device and the busiest process or cgroup.
- You know whether the issue is capacity, queueing, or media latency.
- You checked both block metrics and filesystem usage before declaring victory.
- You have at least one low-risk remediation to test first.

### Extension
- Run a controlled fio benchmark in the current directory of a lab filesystem.
- Compare buffered and direct IO modes to understand application behavior.
- Capture a short blktrace or bpftrace if available in a lab environment.

## 5. Applying the USE method end to end

### Objective
Convert scattered metrics into a structured triage table across CPU, memory, disk, and network.

### Safety and setup
- Choose one time window with a known symptom such as elevated latency or failed requests.
- Prepare a simple table in your notes with one row per resource and columns for utilization, saturation, and errors.
- Use deltas over short intervals whenever possible.
- Do not skip resources that look quiet; USE works only when the survey is complete.
- Prefer synchronized timestamps across commands.

### Questions to answer
- Which resource shows all three of utilization, saturation, and errors?
- Which resources show saturation without high utilization, implying queueing or dependency waits?
- What evidence rules out other resources early?
- What deeper tool should follow the USE pass?

### Runbook
```bash
uptime
mpstat -P ALL 1 3
vmstat 1 3
iostat -xz 1 3
ss -s
ip -s link
nstat -az | head -30
journalctl -k --since -10m
```

### Interpretation guide
| Resource | Utilization example | Saturation example | Error example |
| --- | --- | --- | --- |
| CPU | %busy | run queue | throttling or machine check |
| memory | working set | PSI or reclaim stalls | OOM kills |
| disk | throughput | await or queue depth | IO errors |
| network | bandwidth | socket backlog | drops or retransmits |
| filesystem | capacity | journal wait | corruption or ENOSPC |

### What to look for
- The USE table usually narrows the incident to one dominant resource and one dependent resource.
- A resource with saturation but little utilization often indicates waiting downstream.
- Errors with no saturation still matter when they reveal policy mismatches such as firewall blocks.
- If everything looks quiet, re-check the measurement window or the workload path being measured.
- Write the table down; it becomes the backbone of the incident timeline.

### Completion checklist
- You completed the table for every major resource, not just the suspected one.
- You can explain why the next debugging tool is appropriate.
- You avoided at least one blind alley because the USE survey ruled it out.
- You can brief another engineer in less than two minutes using your table.

### Extension
- Build a dashboard that displays USE signals side by side for common services.
- Add cgroup-specific USE rows for containerized workloads.
- Repeat the exercise using a historical outage to see what you missed the first time.

## 6. Reproducing and diagnosing CPU steal safely

### Objective
Understand how virtualization steal time looks from inside a guest and how it differs from CPU saturation.

### Safety and setup
- Use a lab VM only; steal time depends on shared-host contention and may not be easy to force on demand.
- If you cannot generate real steal, use historical samples or cloud provider metrics to study the pattern.
- Run one CPU-intensive workload inside the guest and compare it with known-normal throughput.
- Keep guest metrics and platform metrics side by side.
- Document the instance type, hypervisor, and placement details if known.

### Questions to answer
- Does guest %st rise when application latency rises?
- Is the guest runnable queue high while actual user or system CPU is modest?
- Do provider metrics show noisy-neighbor or host contention indicators?
- Would moving instance type or host solve more than tuning the guest?

### Runbook
```bash
mpstat -P ALL 1 20
top -b -d 1 | head -40
vmstat 1 20
stress-ng --cpu 2 --timeout 60s
date
echo "Compare timestamps with cloud CPU steal or ready metrics"
journalctl -k --since -15m
uptime
```

### Interpretation guide
| Guest signal | Interpretation | Not the same as |
| --- | --- | --- |
| %st high | hypervisor not scheduling your vCPU | process sleeping voluntarily |
| load high, cpu busy modest | tasks want CPU but guest waits externally | disk wait |
| throughput down without app code changes | shared host contention | application regression |
| all vCPUs affected similarly | host-wide issue likely | single-core pinning |

### What to look for
- Inside the guest, steal looks like missing time rather than expensive code.
- Applications often show broad latency inflation with little direct evidence in their own logs.
- Do not over-tune the guest for a platform-placement problem.
- If only one vCPU is impacted, also consider bad affinity or interrupt concentration.
- Capture provider-facing evidence early so escalation is credible.

### Completion checklist
- You can differentiate high %st from high %sy, high %wa, and high %us.
- You have at least one host-side or provider-side corroborating metric.
- You can justify whether the remediation belongs to the app team or the platform team.
- You preserved timestamps that line up guest and platform observations.

### Extension
- Repeat on different instance types to see how steal risk changes.
- Compare latency-sensitive and batch workloads under the same guest contention.
- Document what SLO symptoms appear before operators notice %st.

## 7. Reproducing and diagnosing a memory leak

### Objective
Practice distinguishing true leaks from healthy caching and from fragmentation.

### Safety and setup
- Use a lab process that can intentionally retain allocations, such as a short Python or Go test program.
- Keep the test bounded so the host remains responsive.
- Sample both process RSS and allocator or application metrics if available.
- Record memory.high or memory.max if the process runs inside a cgroup.
- Plan the stop condition before the test begins.

### Questions to answer
- Does RSS rise monotonically with no corresponding release?
- Does the application expose object counts or cache hit rates that explain growth?
- Are anonymous pages rising or only file-backed mappings?
- Is fragmentation making RSS look worse than live data size?

### Runbook
```bash
python3 -c "a=[]; import time; [a.append(bytearray(1024*1024)) or time.sleep(0.1) for _ in range(30)]"
ps -eo pid,rss,%mem,comm --sort=-rss | head -20
cat /proc/<pid>/status | egrep "VmRSS|VmSize|Threads"
cat /proc/<pid>/smaps_rollup
cat /proc/pressure/memory
vmstat 1 10
journalctl -k -g oom --since -10m
cat /sys/fs/cgroup/memory.current 2>/dev/null
```

### Interpretation guide
| Pattern | Interpretation | Action |
| --- | --- | --- |
| RSS and allocator both grow | likely live-object leak | profile allocations |
| RSS grows, allocator stable | fragmentation or mmap growth | inspect smaps and heap behavior |
| cache hit rate improves with growth | maybe intentional cache | check bounds and eviction |
| memory.events grows | cgroup pressure | raise limit only after leak source known |

### What to look for
- Leaked anonymous memory generally shows up in RSS and smaps anonymous sections.
- A healthy cache should have a clear eviction policy and some plateau.
- Fragmentation often appears after churn rather than steady growth in object counts.
- System memory pressure tells you whether the leak is already affecting neighbors.
- Use short sampling intervals early; long intervals hide growth shape.

### Completion checklist
- You can explain which pages grew and whether the growth is expected.
- You know whether an OOM is imminent or whether the issue is still only a trend.
- You identified one next-step profiler or allocator view to use.
- You captured enough data to compare before and after a fix.

### Extension
- Instrument the test process with a language-specific heap profile.
- Add memory.high to see how throttling changes behavior before OOM.
- Compare leak shape with a workload that only grows page cache.

## 8. Reproducing and diagnosing IO starvation

### Objective
Observe how one noisy writer or one sync-heavy job can raise load and latency for unrelated tasks.

### Safety and setup
- Use a disposable lab filesystem or a small file in the current directory.
- Avoid overwhelming shared storage used by other people.
- Run one baseline reader and one disruptive writer so you can see contention clearly.
- Know the device backing the test directory.
- Be ready to stop the writer if latency becomes excessive.

### Questions to answer
- Does the disruptive job increase await, %wa, or D-state tasks?
- Do unrelated reads slow down because writeback or queue depth dominates?
- Would throttling, ionice, or workload scheduling reduce collateral damage?
- Is the issue block-device contention or filesystem metadata contention?

### Runbook
```bash
dd if=/dev/zero of=./io-starve.bin bs=1M count=512 oflag=dsync
while true; do dd if=./io-starve.bin of=/dev/null bs=4M count=16 2>/dev/null; sleep 1; done
iostat -xz 1 20
pidstat -d 1 20
vmstat 1 20
ps -eo pid,stat,wchan:32,comm | awk "$2 ~ /D/"
ionice -p <writer-pid>
rm -f ./io-starve.bin
```

### Interpretation guide
| Signal | Meaning | Possible mitigation |
| --- | --- | --- |
| await up for all jobs | shared device saturation | throttle or reschedule writer |
| reader latency only on one FS | filesystem-specific lock or journal issue | inspect mount and metadata load |
| wa up, CPU idle | threads blocked on IO completion | reduce sync writes or queue depth |
| writer dominates pidstat | single offender identified | use ionice or move workload |

### What to look for
- This lab makes high load with modest CPU easy to reproduce.
- Look for rising blocked tasks and falling throughput on innocent readers.
- ionice changes may help batch jobs but cannot fix a broken storage backend.
- Metadata-heavy workloads can starve differently than large sequential writes.
- Always clean up the test file and stop loops after the exercise.

### Completion checklist
- You can identify the starvation source and its blast radius.
- You know whether scheduling, throttling, or storage scaling is the right response.
- You saw the relationship between iowait, load average, and D-state tasks.
- You captured before and after evidence for a mitigation.

### Extension
- Repeat with buffered writes and compare the symptom pattern.
- Try the same test on SSD versus network block storage.
- Add application-level latency measurements to connect kernel metrics to user impact.

## 9. Kernel tuning experiments with rollback discipline

### Objective
Practice making small, reversible tuning changes and validating them against explicit success criteria.

### Safety and setup
- Only tune a lab system or a dedicated test cgroup.
- Capture baseline metrics before every change.
- Change one knob at a time and note the expected effect.
- Record both the live change and the persistent configuration path.
- Define a rollback threshold before you begin.

### Questions to answer
- Does the chosen knob target the actual bottleneck or only its symptom?
- What resource trade-off does the knob introduce?
- How will you know the change helped instead of coincidentally aligning with load changes?
- What is the persistence mechanism on this distro?

### Runbook
```bash
sysctl vm.swappiness
sysctl net.core.somaxconn
sysctl vm.max_map_count
sysctl -w net.core.somaxconn=4096
sysctl -w vm.swappiness=10
grep -R . /etc/sysctl.conf /etc/sysctl.d 2>/dev/null
systemctl show <service> -p LimitNOFILE -p TasksMax
journalctl -k --since -5m
```

### Interpretation guide
| Knob | Expected benefit | Trade-off |
| --- | --- | --- |
| vm.swappiness | less anonymous paging | possibly less file cache flexibility |
| net.core.somaxconn | larger accept backlog | more queued memory |
| vm.max_map_count | more memory mappings | higher kernel bookkeeping |
| LimitNOFILE | more sockets/files per process | higher leak blast radius |

### What to look for
- A tuning change without a measurement plan is not a disciplined experiment.
- Many knobs only help after application concurrency and limits are aligned.
- Persistent config drift is common; always confirm which file actually wins on boot.
- Rollback readiness reduces fear and prevents cargo-cult tuning.
- Prefer service-level or cgroup-level controls when host-wide changes are unnecessary.

### Completion checklist
- You can state the hypothesis, the change, the metric, and the rollback threshold.
- You verified whether the live setting and persistent setting match.
- You can explain the downside of the change to another engineer.
- You would be comfortable presenting the experiment in a postmortem.

### Extension
- Build a small checklist template for future tuning changes.
- Compare a sysctl change with an application-level change that solves the same symptom.
- Audit one production host for undocumented tuning and clean it up safely.

## 10. Final debrief

- Write one paragraph for CPU, one for memory, one for IO, and one for the chosen fix.
- Note which signal gave the earliest warning and which signal confirmed the root cause.
- If you changed any knob, record the rollback command and what metric would trigger it.
- Translate your findings into one dashboard improvement and one runbook improvement.

## 11. Ready-for-production checklist

- [ ] I can explain high load with low CPU in terms of blocked tasks or steal time.
- [ ] I can identify whether memory pressure is real or just page cache growth.
- [ ] I can tell the difference between backend storage latency and local queue saturation.
- [ ] I can apply the USE method without skipping any major subsystem.
- [ ] I can justify why a tuning change is safer than an application or capacity change.

