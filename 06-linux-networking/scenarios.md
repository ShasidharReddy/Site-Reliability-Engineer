# Incident Scenarios

These scenarios are written as full investigations rather than short checklists.
Use them to rehearse how an SRE should think under pressure: verify the symptom, create branches, collect discriminating evidence, resolve safely, and harden the system afterward.

## Common operating rules

- Start with the simplest command that can falsify a hypothesis.
- Preserve evidence before restarts whenever customer impact allows.
- Keep time alignment between system metrics, application logs, and packet captures.
- Do not tune the kernel until you know which queue or limit is hurting the workload.
- Every scenario should end with monitoring and runbook improvements, not only a point fix.

## 1. Load average 48 on an 8-CPU box

A page reports load average 48 on a server with 8 CPUs, but dashboards show average CPU usage under 35 percent. The job is to determine whether the box is CPU bound, blocked on IO, or throttled by something outside the simple CPU graph.

### Initial signals
- uptime shows load 48, 42, 30 on an 8-CPU host.
- Application latency and timeout rate are rising.
- Top-level CPU utilization does not look catastrophic.
- Pager notes mention one storage-backed service on the same node.

### Likely branches
| Branch | What would prove it | What would disprove it |
| --- | --- | --- |
| CPU saturation | high run queue and high %us or %sy | CPU mostly idle or in %wa |
| IO wait buildup | high b in vmstat, high await, D-state tasks | devices quiet and no blocked tasks |
| CPU steal or quota | high %st or rising cpu.stat throttled_usec | bare metal host with no throttling |
| lock contention | high context switches and app-specific waits | threads mostly blocked on device wait |

### First 10 minutes
- Run uptime, vmstat 1 10, mpstat -P ALL 1 10, and iostat -xz 1 10 immediately.
- Check for D-state tasks with ps and wchan to see whether load is blocked work.
- Look at cpu.stat or service cgroup CPU quota if the workload is containerized.
- Capture journalctl -k for storage or filesystem errors before making changes.

### Primary command set
```bash
uptime
vmstat 1 10
mpstat -P ALL 1 10
iostat -xz 1 10
pidstat -d 1 10
ps -eo pid,stat,wchan:32,comm | awk "$2 ~ /D/" | head -20
```

### Deep-dive command set
```bash
cat /sys/fs/cgroup/cpu.stat 2>/dev/null
cat /sys/fs/cgroup/cpu.max 2>/dev/null
findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS
lsblk -o NAME,SCHED,ROTA,SIZE,MOUNTPOINT
lsof +L1 2>/dev/null | head -20
journalctl -k --since -15m
```

### Investigation flow
- If vmstat shows high b and iostat shows rising await, prioritize storage and blocked tasks.
- If one device stands out, map the affected filesystem and process owners.
- If %st is high inside a VM, escalate to platform and compare guest timestamps with provider metrics.
- If cpu.stat shows throttling, compare worker count and request concurrency to quota size.
- Inspect application metrics to see whether request latency aligns with blocked backend calls.
- Check df -h and df -i because capacity or inode issues often amplify IO latency.

### Turning point clues
- A surge in D-state tasks and await with modest %us strongly indicates IO wait rather than CPU saturation.
- The one noisy storage-backed service shares the same device as the paged application.
- Deleted-open log files keep the filesystem near full, worsening writeback latency.
- Once the noisy job is paused, load falls quickly without any CPU tuning.

### Resolution
- Throttle or pause the noisy writer or batch job.
- Clear deleted-open logs and recover filesystem headroom.
- Reschedule the batch workload or move it to separate storage.
- Add IO-specific alerts and dashboards so the next page does not start as a CPU mystery.

### Evidence to capture
- vmstat and iostat snapshots before and after the writer pause.
- List of D-state tasks with wait channels.
- Filesystem usage and deleted-open file evidence.
- Timeline linking application latency to storage metrics.

### Hardening
- Alert on iowait, D-state count, and filesystem headroom together.
- Separate batch IO from latency-sensitive services.
- Document that high load does not always mean CPU saturation.
- Review log rotation and deleted-open file handling.

## 2. Application intermittently cannot connect to the database

The app occasionally times out connecting to the database, but retries usually succeed. There is pressure to blame the database immediately, yet intermittent connect failures could come from DNS, routing, firewall policy, conntrack, backlog, or ephemeral port exhaustion on the app side.

### Initial signals
- Application errors are intermittent, not constant.
- Database dashboards look mostly healthy.
- Retries hide some failures from users.
- Connection failures spike during load bursts or deployments.

### Likely branches
| Branch | Evidence | Counter-evidence |
| --- | --- | --- |
| DNS or endpoint churn | getent and dig show changing answers or delays | IP fixed and resolution fast |
| network or firewall drop | SYN leaves but no reply returns | refusal or app-level error instead |
| DB backlog or max connections | SYN-RECV or listener counters rise | listener queues quiet |
| app-side port or FD pressure | EMFILE or TIME_WAIT and port pressure | plenty of ports and FDs |

### First 10 minutes
- Confirm the exact error text: timeout, refused, reset, TLS, or auth.
- Run getent hosts on the DB name and compare with direct-IP connect tests.
- Use ss, nc, and route lookup from the app host while the symptom is active.
- Check app FD counts, socket states, and TIME_WAIT volume.

### Primary command set
```bash
getent hosts <db-hostname>
dig <db-hostname> +short
ip route get <db-ip>
nc -vz <db-ip> <db-port>
ss -tan dst <db-ip>:<db-port> | head -40
ss -s
```

### Deep-dive command set
```bash
lsof -p <app-pid> 2>/dev/null | head -40
cat /proc/<app-pid>/limits 2>/dev/null | grep files
sysctl net.ipv4.ip_local_port_range
conntrack -S 2>/dev/null
tcpdump -ni any host <db-ip> and port <db-port>
journalctl -k --since -15m | egrep -i "conntrack|drop|reject"
```

### Investigation flow
- If name resolution is slow or inconsistent, compare app behavior using the FQDN and the resolved IP.
- If connect by IP still times out, route and packet capture become the next priority.
- If refusal occurs, inspect whether the DB listener or proxy is at connection limits.
- If app FD count is near the limit or TIME_WAIT is huge, look for connection churn or leaks.
- Check conntrack saturation on NAT or firewall nodes if many clients fail together.
- Correlate failures with deploys or autoscaling events that may rotate endpoints or source IPs.

### Turning point clues
- Packet capture shows outbound SYN with no response only during bursts.
- App TIME_WAIT count is very high and ephemeral ports are under pressure.
- The application creates a fresh DB connection per request instead of pooling.
- After enabling pooling in staging, timeout frequency drops sharply.

### Resolution
- Enable or increase connection pooling in the application or sidecar.
- Raise per-process FD limits if they were part of the failure path.
- Adjust database listener backlog or connection cap only if the server was actually the bottleneck.
- Keep direct-IP and DNS evidence in the incident report to rule out the wrong layer.

### Evidence to capture
- Socket state snapshots from ss before and during the burst.
- FD count and limit for the application process.
- Packet capture or nc output showing timeout versus refusal.
- Connection pool settings before and after remediation.

### Hardening
- Monitor connection churn, pooling hit rate, and TIME_WAIT count.
- Alert on FD headroom for the application process.
- Keep a synthetic DB connect check that uses the same DNS path as the app.
- Document the exact DB connect error taxonomy in runbooks.

## 3. Production server runs out of file descriptors

A production service starts failing accepts and logging EMFILE. The fix must restore service without simply masking a leak, and operators need to distinguish per-process limits from host-wide file table exhaustion.

### Initial signals
- Application logs show Too many open files or EMFILE.
- New inbound connections fail while existing ones continue.
- The service may have recently gained more traffic or a new feature using watchers or sockets.
- Manual shell tests may not reproduce because shell ulimit differs from service limits.

### Likely branches
| Branch | Evidence | Counter-evidence |
| --- | --- | --- |
| process leak | one PID FD count rises steadily | all processes affected equally |
| system-wide limit | fs.file-max pressure | only one service failing |
| traffic-driven legitimate growth | FDs rise with steady connection growth | leak continues after traffic drops |
| service limit mismatch | systemd LimitNOFILE low | high limit already configured |

### First 10 minutes
- Check the service process FD count and LimitNOFILE immediately.
- Determine whether the host-wide file table is also near exhaustion.
- Use lsof to categorize descriptors into sockets, files, pipes, or watchers.
- Decide whether a controlled restart is needed to recover service quickly.

### Primary command set
```bash
cat /proc/<pid>/limits 2>/dev/null | grep files
ls /proc/<pid>/fd 2>/dev/null | wc -l
lsof -p <pid> 2>/dev/null | head -80
systemctl show <service> -p LimitNOFILE
ss -s
ulimit -n
```

### Deep-dive command set
```bash
cat /proc/sys/fs/file-max 2>/dev/null
cat /proc/sys/fs/file-nr 2>/dev/null
lsof -n | awk "NR>1 {print $5}" | sort | uniq -c | sort -nr | head -20
journalctl -u <service> --since -30m
grep -i "too many open files" ./app.log 2>/dev/null | tail -40
ss -tan | head -60
```

### Investigation flow
- If only one process is near its limit, focus on that service first.
- Classify descriptors by type to find whether the leak is sockets, logs, temp files, or watchers.
- Compare FD count during low traffic to see whether it plateaus or keeps climbing.
- If systemd limit is lower than expected, confirm unit override files and daemon reload state.
- If the issue is connection churn, pair FD evidence with TIME_WAIT and backlog metrics.
- Use a restart only after capturing enough data to avoid losing the root-cause trail.

### Turning point clues
- The service holds many stale client sockets because failed requests never close cleanly.
- FD count continues rising after traffic subsides, indicating a leak not just growth.
- systemd LimitNOFILE is lower than the value operators assumed from shell testing.
- Raising the limit buys time but does not remove the upward trend.

### Resolution
- Apply a controlled restart to recover if customer impact is ongoing and evidence is captured.
- Raise LimitNOFILE to a justified value in the unit and reload systemd.
- Fix the application leak or connection cleanup path.
- Add FD count monitoring per process and alert on percentage of limit.

### Evidence to capture
- Per-process FD count over time.
- Representative lsof sample showing descriptor types.
- systemd unit limit output and any override file content.
- Error-rate timeline aligned with FD exhaustion.

### Hardening
- Add process FD metrics and leak regression tests.
- Review service limits during every major rollout.
- Pool and reuse connections where possible.
- Document when a restart is acceptable and what evidence must be captured first.

## 4. Mysterious memory growth

A service slowly consumes more memory each day. There is no immediate OOM, but the trend threatens node stability. The challenge is to decide whether the growth is a leak, a bounded cache, fragmentation, or page cache behavior around the workload.

### Initial signals
- RSS or container memory.current grows steadily over days.
- Latency is still acceptable but headroom is shrinking.
- Restarting the service resets the trend.
- No single alert says exactly what part of memory is growing.

### Likely branches
| Branch | Evidence | Counter-evidence |
| --- | --- | --- |
| live-object leak | allocator and object counts grow with RSS | cache metrics stable |
| bounded cache | growth aligns with hit-rate or key count until plateau | continues with no plateau |
| fragmentation | RSS high but live allocations flatter | smaps shows true object growth |
| page cache effect | file-backed growth not anonymous | anon RSS dominates |

### First 10 minutes
- Collect process RSS, smaps_rollup, and any application heap metrics.
- Check MemAvailable and memory PSI to see whether the trend is already harming the host.
- Determine whether the process runs in a cgroup with a strict limit.
- Review recent deploys or config changes that altered cache size or request mix.

### Primary command set
```bash
ps -eo pid,rss,%mem,comm --sort=-rss | head -20
cat /proc/<pid>/status | egrep "VmRSS|VmSize|Threads"
cat /proc/<pid>/smaps_rollup
free -h
cat /proc/pressure/memory
cat /sys/fs/cgroup/memory.current 2>/dev/null
```

### Deep-dive command set
```bash
grep -E "MemAvailable|Cached|Anon" /proc/meminfo
journalctl -k -g oom --since -7d
grep -i "cache\|evict\|heap" ./app.log 2>/dev/null | tail -40
cat /sys/fs/cgroup/memory.events 2>/dev/null
vmstat 1 10
date
```

### Investigation flow
- If anonymous memory dominates and keeps rising, suspect a leak or fragmentation.
- If file-backed memory or cache metrics explain the growth and a plateau exists, it may be intentional.
- Compare restarts, traffic patterns, and deploys to see whether the slope changed with a release.
- Inspect application-level heap profiles or object counts if available.
- Check whether memory.high or soft limits could provide safer backpressure before the next peak.
- Avoid cache-clearing or global tuning until you know what kind of memory is growing.

### Turning point clues
- RSS growth aligns with one feature rollout that added an unbounded cache.
- smaps_rollup shows anonymous private memory dominating the increase.
- Application logs contain no eviction events even as item count rises.
- Setting a cache limit in staging creates a plateau without hurting hit rate much.

### Resolution
- Bound or fix the offending cache or leak path.
- Deploy with an explicit memory budget and eviction policy.
- Add memory.high or autoscaling headroom if appropriate.
- Keep the temporary restart workaround only until the code fix is verified.

### Evidence to capture
- RSS or memory.current trend over time.
- smaps_rollup or heap profile snapshots.
- Feature or config change timeline.
- Host-level MemAvailable and PSI context.

### Hardening
- Expose cache size, heap usage, and eviction metrics from the application.
- Review memory budgets in design and load testing.
- Alert on slope of memory growth, not only absolute usage.
- Use staged canaries to catch memory regressions before broad rollout.

## 5. Disk filling silently

A host suddenly alerts on low disk, yet no team claims a recent large write. The incident turns out to involve a combination of oversized logs, deleted-open files, and an overlooked retention path, making standard du output initially misleading.

### Initial signals
- Low-disk alert fires late because growth was gradual and mostly hidden.
- du output does not match df usage exactly.
- Applications begin failing on writes or log rotation.
- One filesystem carries logs, temp data, and service state together.

### Likely branches
| Branch | Evidence | Counter-evidence |
| --- | --- | --- |
| large visible files | du quickly shows top directories | df still much higher than du |
| deleted-open files | lsof +L1 shows big deleted entries | no deleted entries and du matches df |
| inode exhaustion | df -i high with bytes free | byte usage actually near full |
| retention failure | rotation config missing or broken | logs rotate and compress normally |

### First 10 minutes
- Run df -h, df -i, du on the top directories, and lsof +L1.
- Check whether the affected filesystem is also used by logs or temporary work files.
- Look at logrotate or journald retention settings immediately.
- Decide whether cleanup, restart, or capacity expansion is the safest short-term action.

### Primary command set
```bash
df -h
df -i
du -sh ./* 2>/dev/null | sort -h | tail -20
find /var/log -type f -size +100M 2>/dev/null | head -40
journalctl --disk-usage
lsof +L1 2>/dev/null | head -40
```

### Deep-dive command set
```bash
grep -R "rotate\|compress\|size\|daily\|weekly" /etc/logrotate.conf /etc/logrotate.d 2>/dev/null
systemctl status systemd-journald 2>/dev/null
find . -xdev -type f | sed "s#/[^/]*$##" | sort | uniq -c | sort -nr | head -20
ls -lh /var/log | head -40
date
journalctl -u <service> --since -1d
```

### Investigation flow
- If du and df differ substantially, suspect deleted-open files or mount-path confusion.
- If bytes are fine but inodes are exhausted, target small-file directories rather than large logs.
- If journald or app logs dominate, compare actual growth with configured retention.
- Review deploy changes that may have increased log verbosity or created new dump files.
- Do not delete live files blindly if an application expects them to exist; prefer rotation or coordinated restart.
- Capture evidence before cleanup so the growth mechanism can be fixed permanently.

### Turning point clues
- lsof +L1 shows a deleted log still held open by the main service.
- logrotate missed that file because the service changed its log path in a recent release.
- journald retention is uncapped on the same filesystem.
- After restart and retention fixes, disk usage stabilizes.

### Resolution
- Restart or signal the process holding deleted-open files after ensuring impact is acceptable.
- Repair log rotation or journald retention configuration.
- Reduce log verbosity or move heavy logs to a separate filesystem.
- Add both byte and inode alerts with earlier thresholds.

### Evidence to capture
- df and du comparison before cleanup.
- lsof +L1 output showing hidden usage.
- Retention configuration excerpts.
- Post-fix usage trend proving stabilization.

### Hardening
- Alert separately on deleted-open file usage if your tooling supports it.
- Review log retention whenever service paths or formats change.
- Keep data, logs, and temp space separated for important services.
- Practice disk-full recovery steps before they happen in production.

## 6. Post-incident review prompts

- Which metric would have detected the issue earlier?
- Which metric or log line most clearly confirmed the root cause?
- Which part of the investigation took longest because evidence was missing?
- What can be automated into a health check, alert, or dashboard panel?
- Which assumption was wrong at the start, and how will the team avoid repeating it?

## 7. Drill ideas

- Re-run each scenario in a lab with someone else acting as incident commander.
- Swap the root cause while keeping the symptom the same to practice hypothesis discipline.
- Time-box the first 10 minutes and review whether the team gathered discriminating evidence quickly.
- Update the module scripts to print the key checks you reached for repeatedly.

