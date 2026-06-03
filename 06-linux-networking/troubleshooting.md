# Linux & Networking Troubleshooting Guide

Use this guide when you already have a symptom and need a fast diagnosis path.
Each section follows the same sequence: recognize the pattern, run the minimum useful commands, interpret results, fix safely, and validate.

## Fast triage matrix

| Symptom | First command | Most likely subsystem |
| --- | --- | --- |
| load average high, CPU modest | vmstat 1 5 | blocked IO or steal time |
| random restarts with code 137 | dmesg or memory.events | memory pressure or OOM |
| timeout vs refused vs no route | ip route get and nc | path, listener, or policy |
| name lookup fails | getent hosts | resolver or DNS delegation |
| many TIME_WAIT sockets | ss -s | connection churn and pooling |
| EMFILE errors | cat /proc/<pid>/limits | file descriptor leak or limit |
| defunct processes | ps -eo pid,ppid,stat,comm | missing wait or bad PID 1 |
| no space left on device | df -h and df -i | bytes, inodes, or deleted-open files |

## 1. High load average but low CPU usage because of IO wait

Load average counts runnable tasks and tasks in uninterruptible sleep. When many threads wait on disk or network block IO, load can be huge while CPUs spend much of the interval idle or in iowait.

### Symptoms
- uptime shows load far above CPU count.
- top or mpstat shows modest user and system CPU but noticeable %wa.
- Request latency rises and thread pools appear full.
- Processes show D state in ps output.
- Disk or storage alerts may appear before CPU alerts.

### Diagnosis commands
```bash
uptime
vmstat 1 10
iostat -xz 1 10
pidstat -d 1 10
ps -eo pid,stat,wchan:32,comm | awk "$2 ~ /D/" | head -20
df -h && df -i
lsof +L1 2>/dev/null | head -20
```

### Decision table
| If you see | It usually means | Then do |
| --- | --- | --- |
| high b in vmstat | many blocked tasks | identify device and wait channel |
| await high | queueing or backend latency | check storage layer and noisy writers |
| %wa high | CPU idle while waiting for IO | do not chase CPU tuning first |
| D-state tasks | kernel wait below user space | inspect wchan and filesystem or device |

### Interpretation
- Compare load to CPUs, then immediately verify whether the excess is runnable or blocked work.
- A single bad network block device can create host-wide symptoms even when local disks look fine.
- Deleted-open files and inode exhaustion can amplify IO symptoms by forcing strange error paths.
- If await is high but util is not, suspect backend latency or throttling rather than local queue saturation.

### Fix
- Throttle or stop the noisy writer causing the queue buildup.
- Free space or inodes if the filesystem is near exhaustion.
- Resolve the underlying storage issue such as cloud volume throttling, array latency, or stuck NFS.
- Reschedule batch jobs or lower their IO priority with ionice where appropriate.

### Validation
- Load average falls toward CPU count.
- D-state task count drops.
- await and %wa decline.
- Application latency returns to baseline.

### Prevention
- Monitor load, iowait, await, and D-state task count together.
- Separate batch and latency-sensitive IO onto different devices or windows.
- Alert on filesystem bytes and inodes before hard exhaustion.
- Keep a runbook for deleted-open files and noisy writers.

## 2. Memory pressure and OOM kills

OOM incidents happen when reclaim cannot free enough memory for forward progress. They may be host-wide or cgroup-local, and they often look like random restarts until you inspect kernel evidence.

### Symptoms
- Processes exit with status 137 or restart unexpectedly.
- Kernel logs mention Out of memory or Killed process.
- Memory PSI, swap activity, or reclaim counters rise before death.
- Latency spikes even before the OOM event due to reclaim.
- One cgroup or pod may fail while the host still appears mostly fine.

### Diagnosis commands
```bash
free -h
cat /proc/meminfo | egrep "MemAvailable|Swap|Anon|Cached"
vmstat 1 10
cat /proc/pressure/memory
dmesg | egrep -i "out of memory|killed process|oom" | tail -20
cat /sys/fs/cgroup/memory.events 2>/dev/null
cat /proc/<pid>/oom_score /proc/<pid>/oom_score_adj 2>/dev/null
```

### Decision table
| Signal | Meaning | Action |
| --- | --- | --- |
| oom_kill in memory.events | cgroup limit hit | resize or fix app memory use |
| swap in or out active | pressure before OOM | reduce footprint or add memory |
| MemAvailable collapsing | headroom nearly gone | identify top consumers |
| high oom_score victim | kernel chose largest or least protected target | review oom_score_adj policy |

### Interpretation
- Start with the kernel log because it often identifies the victim and the context.
- Repeated pod restarts with no host OOM usually indicate a cgroup limit problem.
- A protected critical daemon should not be the easiest victim if the host must remain accessible.
- Memory pressure often harms latency long before the final kill event.

### Fix
- Stop or scale down the leaking or overcommitted workload.
- Increase memory limits only after validating that growth is legitimate.
- Use memory.high or application backpressure to reduce abrupt kills.
- Adjust oom_score_adj carefully so control-plane and access daemons survive.

### Validation
- No new OOM log lines appear.
- MemAvailable stabilizes or rises.
- Swap activity and memory PSI fall.
- The service remains up through the expected peak.

### Prevention
- Trend RSS, cache size, MemAvailable, and memory PSI.
- Set realistic cgroup limits instead of defaulting to hard caps only.
- Protect critical daemons with sensible oom_score_adj values.
- Profile leaks before they become emergency capacity incidents.

## 3. Network timeout versus connection refused versus no route to host

These errors point to different failure layers. Timeouts usually mean silent drop or no reply, connection refused means a reachable host actively rejected the TCP connect, and no route means the source cannot find a valid path.

### Symptoms
- Clients report timeout, refused, or no route with different timing patterns.
- Some probes may succeed while application requests fail.
- Routing or firewall changes may have occurred recently.
- One namespace or one source IP may fail while others work.
- Logs may lack server-side entries for timeout cases.

### Diagnosis commands
```bash
ip route get <target-ip>
ping -c 3 <target-ip>
nc -vz <target-ip> <port>
ss -tan state syn-sent,syn-recv,established
tcpdump -ni any host <target-ip> and port <port>
nft list ruleset 2>/dev/null | head -80
ip neigh show
```

### Decision table
| Client error | Usually means | Look at |
| --- | --- | --- |
| connection timed out | drop or no reply | route, firewall drop, server hang, packet loss |
| connection refused | RST from target or firewall reject | listener status and reject rules |
| no route to host | source routing or neighbor issue | ip route and ARP or ND |
| name resolves but connect fails | transport or policy issue | ss, route, firewall |

### Interpretation
- A timeout is compatible with the packet never arriving or the reply never returning.
- A refusal is often good news because it proves reachability to the target stack.
- No route can be a local route-table problem, a missing gateway, or a failed neighbor entry.
- Packet capture on the client quickly shows whether SYN left and whether anything came back.

### Fix
- Restore the missing route, gateway, or neighbor resolution path.
- Start the service or bind it to the correct address if refusal is the issue.
- Update host or network firewall rules when silent drops are blocking traffic.
- Correct namespace, policy routing, or source IP selection mismatches.

### Validation
- nc or the real client now completes quickly.
- Route lookup shows the expected next hop.
- tcpdump shows successful SYN, SYN-ACK, ACK if TCP is used.
- Application logs now record requests instead of silence.

### Prevention
- Monitor route table drift and failed neighbor entries on critical hosts.
- Alert on unexpected changes to firewall policies and service listeners.
- Use synthetic checks from the same source network as production clients.
- Document which errors map to which failure layers in runbooks.

## 4. DNS resolution failures

A DNS failure may live in the local stub, recursive resolver, delegation chain, or application cache. The visible symptom is often just a generic timeout or inability to connect.

### Symptoms
- Applications log getaddrinfo failures or generic connect timeouts.
- dig and getent disagree.
- Failures are hostname-specific, record-type-specific, or intermittent.
- Short names work differently from FQDNs.
- Kubernetes pods behave differently from nodes.

### Diagnosis commands
```bash
cat /etc/resolv.conf
getent hosts <name>
dig <name> A +short
dig <name> AAAA +short
dig @<resolver-ip> <name>
dig +trace <name>
resolvectl query <name> 2>/dev/null
```

### Decision table
| Observation | Likely cause | Action |
| --- | --- | --- |
| getent fails, dig works | stub resolver or NSS path issue | inspect local resolver and nsswitch |
| resolver returns SERVFAIL | upstream or DNSSEC issue | check recursive resolver logs |
| A works, AAAA fails | IPv6 path or policy problem | test dual-stack transport |
| short name only fails | search path or ndots issue | use FQDN and fix search domains |

### Interpretation
- Always test using the same path the application uses, not just dig to a public resolver.
- Negative or stale caching can extend the visible outage beyond the actual fault window.
- Different resolvers on node and pod explain many “works here, not there” incidents.
- Record TTL and response code because both affect future retries and caches.

### Fix
- Repair resolver configuration, search domains, or local stub service.
- Fix authoritative records or delegation when +trace shows the break.
- Flush or restart local caches when safe and necessary.
- Use a temporary FQDN or alternate resolver workaround only if policy allows.

### Validation
- getent and dig agree on the expected answer.
- Resolution latency returns to normal.
- The real application resolves and connects successfully.
- Caches no longer serve stale or negative answers.

### Prevention
- Monitor resolver latency, failure codes, and TTL anomalies.
- Document resolver paths for hosts, pods, and language runtimes.
- Keep CoreDNS or resolver capacity aligned with query bursts.
- Include DNS checks in synthetic monitoring for critical dependencies.

## 5. High TIME_WAIT socket count

TIME_WAIT sockets are a normal part of TCP active close, but very high counts can signal excessive connection churn, short-lived clients, or a lack of connection pooling.

### Symptoms
- ss summary shows a large TIME-WAIT count.
- Clients open many short-lived outbound connections.
- Ephemeral ports may become scarce under spikes.
- The application or proxy does not appear to reuse connections well.
- CPU may rise due to connection setup overhead rather than payload work.

### Diagnosis commands
```bash
ss -tan state time-wait | head -40
ss -s
sysctl net.ipv4.ip_local_port_range
sysctl net.ipv4.tcp_fin_timeout
grep -i keep-alive ./app.log 2>/dev/null | tail -20
lsof -iTCP -sTCP:TIME_WAIT 2>/dev/null | head -40
nstat -az | egrep "ActiveOpens|PassiveOpens|EstabResets"
```

### Decision table
| Pattern | Meaning | Action |
| --- | --- | --- |
| TIME_WAIT high on client | active close and churn | add pooling or keepalive |
| port exhaustion warnings | ephemeral range pressure | reuse connections or widen range carefully |
| many short HTTP requests | app or proxy defaults poor | tune keep-alive and pooling |
| RST or reset spikes too | abnormal teardown path | inspect transport errors |

### Interpretation
- TIME_WAIT itself is not a leak; it is a correctness state.
- The real question is why so many connections are being created and closed.
- Short-lived TLS connections multiply CPU and latency cost along with TIME_WAIT count.
- If ports are scarce, rate limiting or pooling is usually better than purely kernel-side tweaks.

### Fix
- Enable application or proxy connection pooling and keepalive.
- Reduce needless reconnect loops and health-check churn.
- Expand ephemeral port range only when connection reuse is already reasonable.
- Investigate resets or failed keepalives that force extra reconnects.

### Validation
- TIME_WAIT count falls under similar traffic.
- Connection rate falls while request rate remains healthy.
- Port exhaustion symptoms disappear.
- Latency and handshake CPU improve.

### Prevention
- Graph connection creation rate, reuse ratio, and TIME_WAIT count.
- Review keepalive defaults in every client and proxy tier.
- Stress test burst traffic to expose port-range pressure early.
- Document why any kernel TCP reuse tuning is safe in your environment.

## 6. Too many open files

File descriptor exhaustion can break network accepts, log writes, temporary files, and inter-process communication. The failure may be per-process or system-wide and is often caused by slow leaks rather than sudden spikes.

### Symptoms
- Applications log EMFILE or Too many open files.
- New client connections fail even though the process is still running.
- lsof output for one PID grows steadily.
- systemd service limits differ from shell ulimit expectations.
- Log rotation or watch services may stop working.

### Diagnosis commands
```bash
ulimit -n
cat /proc/sys/fs/file-max 2>/dev/null
cat /proc/<pid>/limits 2>/dev/null | grep files
ls /proc/<pid>/fd 2>/dev/null | wc -l
lsof -p <pid> 2>/dev/null | head -40
systemctl show <service> -p LimitNOFILE
ss -s
```

### Decision table
| Where limit hit | Typical symptom | Response |
| --- | --- | --- |
| process limit | single service errors | raise LimitNOFILE or fix leak |
| system-wide file-max | many services degrade | inspect global FD use |
| socket-heavy service | accept failures | check connection churn and leak |
| watcher leak | many inotify or file FDs | fix code path and recycle process |

### Interpretation
- First determine whether only one process is affected or the entire host is close to ENFILE.
- A higher limit is not a fix if the process leaks descriptors indefinitely.
- Sockets, eventfd, epoll, and deleted files all consume descriptors.
- systemd unit limits often explain why a manual shell test succeeds but the service fails.

### Fix
- Close or restart the leaking process if operationally safe.
- Raise per-service LimitNOFILE and any application internal limit together.
- Reduce connection churn or stale socket buildup if network heavy.
- Audit log, watcher, and file-handling code paths for leaks.

### Validation
- The FD count plateaus instead of growing.
- EMFILE or ENFILE errors stop.
- New connections or file opens succeed reliably.
- Service limits match documented expectations.

### Prevention
- Alert on FD count as a percentage of limit for critical processes.
- Review LimitNOFILE in systemd units during service onboarding.
- Add leak tests for sockets and files in CI where possible.
- Retain lsof or process metrics long enough to see slow leaks.

## 7. Zombie processes

Zombie processes have exited but were not reaped by their parent. They do not use CPU or significant memory, but large numbers can exhaust PIDs and signal broken parent process behavior, especially in containers where PID 1 is minimal.

### Symptoms
- ps shows defunct or Z-state processes.
- Parent PID remains alive and not reaping children.
- Process counts rise even though workload seems idle.
- Containers with poor init handling accumulate zombies under worker churn.
- Restarts may temporarily clear the issue.

### Diagnosis commands
```bash
ps -eo pid,ppid,stat,comm | awk "$3 ~ /Z/"
pstree -alp | head -60
cat /proc/<ppid>/status 2>/dev/null
strace -p <ppid> -e wait4,waitid,waitpid
systemctl status <service>
cat /proc/sys/kernel/pid_max
```

### Decision table
| Observation | Meaning | Action |
| --- | --- | --- |
| few transient zombies | usually harmless | monitor only |
| steady growth | parent not reaping | fix app or init handling |
| inside container only | PID 1 issue | use tini or proper init |
| PID exhaustion risk | large scale parent bug | restart parent carefully |

### Interpretation
- The zombie itself is not the problem; the parent behavior is.
- Signals and restart policies need to account for reaping, especially in containers.
- A child-heavy worker model makes reaping bugs visible sooner.
- If PID 1 in a container does not reap, every crash or short-lived child can accumulate.

### Fix
- Correct the parent to call wait or to use a subreaper pattern.
- Use a proper init process in containers that manage children.
- Restart the parent service if safe to clear accumulated zombies.
- Review signal handling and shutdown sequencing in the application.

### Validation
- Zombie count returns to zero or a low stable value.
- Parent process now reaps exited children during testing.
- PID space is no longer trending upward unnecessarily.
- The service shuts down cleanly without leaving defunct children.

### Prevention
- Use a minimal init such as tini when containers spawn children.
- Test child process churn in staging.
- Monitor zombie count and process count for worker-heavy services.
- Review library wrappers that fork external commands.

## 8. Disk full versus inode exhaustion

Both conditions block writes, but they have different causes and fixes. Byte exhaustion means capacity is consumed by large files, while inode exhaustion means the filesystem has too many files regardless of free space.

### Symptoms
- Applications report No space left on device.
- df -h may show free space while df -i is full, or vice versa.
- Small file creation fails even though large-file capacity remains.
- Log rotation, temp file creation, and package installs may all break.
- Deleted-open files can make df and du disagree.

### Diagnosis commands
```bash
df -h
df -i
du -sh ./* 2>/dev/null | sort -h | tail -20
find . -xdev -type f | wc -l
find . -xdev -type f | sed "s#/[^/]*$##" | sort | uniq -c | sort -nr | head -20
lsof +L1 2>/dev/null | head -40
find /var/log -type f -size +100M 2>/dev/null | head -40
```

### Decision table
| If | Then | Fix focus |
| --- | --- | --- |
| df -h high, df -i healthy | byte capacity issue | large files, retention, deleted-open files |
| df -i high, df -h healthy | inode issue | small-file explosion, cache dirs, mail queues |
| df and du disagree | deleted-open files or mount confusion | lsof +L1 and mount review |
| one directory dominates count | localized growth | cleanup and retention policy |

### Interpretation
- Inode exhaustion is common with cache directories, spools, and tiny rotated files.
- Byte exhaustion is often caused by large logs, dumps, backups, or deleted-open files.
- The same ENOSPC error text can hide both problems, so always check df -h and df -i together.
- Cleanup strategy should target the dominant directory rather than random deletion.

### Fix
- Delete or rotate large files when bytes are exhausted.
- Clear tiny-file spools or caches when inodes are exhausted.
- Restart or signal processes holding deleted-open files so space is reclaimed.
- Increase filesystem size or redesign retention if growth is legitimate.

### Validation
- df -h and df -i both return to safe headroom.
- Writes and package operations succeed again.
- No deleted-open files continue consuming hidden space.
- Growth rate after cleanup is understood and monitored.

### Prevention
- Alert separately on bytes used and inodes used.
- Review log retention and cache cleanup jobs regularly.
- Trend top directories by file count as well as size.
- Include lsof +L1 in disk-full runbooks.

## 9. Closing habits

- Prefer evidence that explains the queue or limit before changing settings.
- Save one or two representative command outputs with timestamps for every incident.
- Always validate the fix against the original symptom, not just against one metric.
- Add one prevention item to monitoring or runbooks before closing the incident.

