# Linux & Networking — Theory

## 1. Linux Kernel Fundamentals

### 1.1 Process Model
- Every running program is a **process** (unique PID)
- **Threads** share memory within a process (Linux: threads are lightweight processes)
- **fork()**: create child process (copy-on-write memory until written)
- **exec()**: replace current process image with new program
- **File descriptors**: everything is a file — sockets, pipes, devices all use FDs

### 1.2 Linux Namespaces (basis of containers)
| Namespace | Isolates |
|-----------|---------|
| **pid** | Process IDs — container sees PID 1 for its init |
| **net** | Network interfaces, routing tables, iptables |
| **mnt** | Mount points — container's own filesystem view |
| **uts** | Hostname and domain name |
| **ipc** | System V IPC, POSIX message queues |
| **user** | User/group IDs — root in container ≠ root on host (with user ns) |
| **cgroup** | cgroup root — isolates resource limit visibility |

### 1.3 cgroups v1 vs v2
```bash
# Check which cgroup version is active
stat -fc %T /sys/fs/cgroup/  # "cgroup2fs" = v2, "tmpfs" = v1

# v2: unified hierarchy at /sys/fs/cgroup/
# v1: per-controller hierarchies at /sys/fs/cgroup/cpu/, /sys/fs/cgroup/memory/, etc.

# Container CPU quota (v2)
cat /sys/fs/cgroup/cpu.max
# "250000 1000000" = 25% of one CPU (250ms per 1000ms period)

# Container memory limit (v2)
cat /sys/fs/cgroup/memory.max
```

---

## 2. Memory Management

### 2.1 Virtual Memory Concepts
- Each process gets a virtual address space (128TB on 64-bit Linux)
- **Page tables** translate virtual → physical addresses
- **Page fault**: accessing unmapped page → kernel allocates physical page
- **Copy-on-write (CoW)**: fork() shares pages until one process writes — then copies
- **Memory-mapped files**: files mapped into address space (shared libraries use this)

### 2.2 Key Memory Metrics
```bash
free -h
#               total    used    free    shared  buff/cache   available
# Mem:           15Gi    3.2Gi   1.1Gi   456Mi    11Gi        11Gi
# Swap:           2Gi      0B    2Gi

# "available" is the most useful metric — includes reclaimable cache
# "buff/cache" = disk cache — Linux uses free RAM for disk caching

# Detailed memory info
cat /proc/meminfo
# MemTotal:        → Physical RAM
# MemAvailable:    → Best "how much can apps use" metric
# Cached:          → Disk cache (reclaimable)
# SwapUsed:        → If > 0, memory pressure is occurring
# Dirty:           → Data written to disk cache but not yet flushed
```

### 2.3 OOM Killer
```bash
# Detect OOM kills
dmesg | grep -iE "oom|killed process|out of memory" | tail -10

# OOM score: process with highest score is killed first
cat /proc/<PID>/oom_score
cat /proc/<PID>/oom_score_adj  # -1000 = never kill, 1000 = always kill first

# Recent OOM in K8s
kubectl describe pod <pod> | grep -i "oom\|killed\|137"
# Exit code 137 = killed by signal 9 (often OOMKill)
```

### 2.4 Memory Pressure Indicators
```bash
# Swap activity (si/so columns) — if non-zero, under memory pressure
vmstat 1 5
# r=runqueue, b=blocked, si=swap-in, so=swap-out, us/sy/wa/id = cpu

# Page reclaim rate
grep "pgscan_kswapd\|pgsteal" /proc/vmstat

# Huge pages (can cause latency spikes if transparent huge pages collapse)
cat /sys/kernel/mm/transparent_hugepage/enabled
# Recommended for most workloads: [madvise] or [never]
```

---

## 3. CPU Performance

### 3.1 Load Average Interpretation
```
load average: 1.5, 2.0, 1.8
               1m   5m   15m

Rule: compare to number of CPUs (nproc)
- load < ncpus: capacity available
- load == ncpus: fully utilized
- load > ncpus: work is queuing

⚠️ Load includes I/O wait! A load of 4.0 on 4 CPUs might be 
   entirely I/O-bound, not CPU-bound. Check 'wa' in top.
```

### 3.2 CPU Analysis Tools
```bash
# Interactive CPU view (press '1' for per-core)
top -1

# Column meanings:
# us: user space code    sy: system/kernel     ni: nice'd processes
# id: idle               wa: I/O wait          st: steal (hypervisor)
# hi: hardware IRQ       si: software IRQ

# Per-core CPU stats (1-second intervals, 5 samples)
mpstat -P ALL 1 5

# CPU usage by process over time
sar -u 1 10

# CPU profiling — find hot functions
perf top                           # Live (requires root or paranoid=0)
perf record -g -p <PID> -- sleep 30
perf report --stdio | head -40
```

### 3.3 CPU Throttling in Containers
```bash
# Check throttling in K8s container
CGROUP="/sys/fs/cgroup/cpu,cpuacct/kubepods/pod<UID>/<container-ID>"
cat "$CGROUP/cpu.stat"
# throttled_time: ns spend throttled — if high, CPU limit too low

# Prometheus metric for throttling
rate(container_cpu_cfs_throttled_seconds_total{container="my-app"}[5m])
# Non-zero means the container is hitting its CPU limit
```

---

## 4. Storage & I/O

### 4.1 iostat Analysis
```bash
iostat -x 1 5

# Key columns:
# %util:    How busy the disk is (100% = saturated, work is queuing)
# await:    Avg I/O wait time in ms (includes queue + service time)
# r_await:  Read wait time
# w_await:  Write wait time
# aqu-sz:   Average queue size (> 1 = saturation)
# rkB/s:    Read throughput
# wkB/s:    Write throughput

# General guidance:
# SSD: await < 1ms normal, > 10ms problematic
# HDD: await < 10ms normal, > 100ms problematic
```

### 4.2 Disk Full / Inode Exhaustion
```bash
# Space check (excluding virtual filesystems)
df -h --exclude-type=tmpfs --exclude-type=devtmpfs

# Inode check (separate limit from space!)
df -i
# If inodes 100% but space available: too many tiny files

# Find large files
find / -xdev -type f -size +100M 2>/dev/null | sort -k5 -rn | head -20

# Find directory with most files (inode hog)
find /var/log -type d | while read d; do
  echo "$(find "$d" -maxdepth 1 | wc -l) $d"
done | sort -rn | head -10

# Common causes of inode exhaustion:
# - /tmp filled with session files
# - /var/log filled with tiny log files
# - Node modules, pip cache, Maven repo
```

---

## 5. Networking Deep Dive

### 5.1 TCP State Machine
```
CLIENT                               SERVER
  │                                    │
  │──────── SYN ───────────────────→  │  LISTEN
  │          (seq=x)                   │
  │  ←──── SYN-ACK ──────────────────│  SYN_RCVD
  │          (seq=y, ack=x+1)          │
  │──────── ACK ───────────────────→  │  ESTABLISHED
  │          (ack=y+1)                 │
  │◄══════ DATA EXCHANGE ═══════════► │
  │                                    │
  │──────── FIN ───────────────────→  │  FIN_WAIT_1
  │  ←──── ACK ──────────────────────│  CLOSE_WAIT
  │  ←──── FIN ──────────────────────│
  │──────── ACK ───────────────────→  │  CLOSED
  │  (waits 2×MSL in TIME_WAIT)        │
```

### 5.2 TIME_WAIT vs CLOSE_WAIT
```bash
# High TIME_WAIT: normal for HTTP servers with many short connections
# Fix: enable SO_REUSEADDR, use connection pooling, HTTP/2
echo 30 > /proc/sys/net/ipv4/tcp_fin_timeout  # Reduce TIME_WAIT duration

# High CLOSE_WAIT: BUG — app not calling close() on socket
# Fix: find the application code that's not closing connections
ss -tanp state CLOSE_WAIT  # Which process has CLOSE_WAIT sockets?
```

### 5.3 DNS Resolution Flow
```
App calls getaddrinfo("api.example.com")
    │
    ▼
Check /etc/nsswitch.conf → "files dns"
    │
    ├─ Check /etc/hosts first
    │
    └─ Query nameserver from /etc/resolv.conf
            │
            ├─ Kubernetes pod: CoreDNS at 10.96.0.10
            │       │
            │       ├─ "api.example.com" has < 5 dots (ndots=5)
            │       ├─ Try: api.example.com.default.svc.cluster.local
            │       ├─ Try: api.example.com.svc.cluster.local  
            │       ├─ Try: api.example.com.cluster.local
            │       └─ Finally: api.example.com. (external DNS)
            │
            └─ External: upstream DNS (8.8.8.8 or corporate DNS)
```

**Slow DNS in K8s**: ndots:5 causes 3-4 failed local lookups before external resolution.
Fix: set `ndots: 2` in pod spec, or use FQDNs with trailing dot.

### 5.4 tcpdump Quick Reference
```bash
# Capture all traffic on interface
tcpdump -i eth0 -w /tmp/cap.pcap

# Filter by host and port
tcpdump -i any -n 'host 10.0.0.1 and port 8080'

# HTTP requests only
tcpdump -i any -A -s 0 'port 80' | grep -E "GET|POST|HTTP"

# DNS queries
tcpdump -i any -n 'port 53' -l | grep -v '^$'

# Connections to a specific IP
tcpdump -i any "src 10.0.0.1 or dst 10.0.0.1"

# -n: don't resolve hostnames  -A: ASCII output  -l: line-buffered
# -s 0: capture full packet    -w: write to file  -r: read from file
```

### 5.5 HTTP & TLS Debugging
```bash
# Full HTTP response headers
curl -I -v https://api.example.com/health

# Check TLS certificate
openssl s_client -connect api.example.com:443 -servername api.example.com < /dev/null 2>/dev/null \
  | openssl x509 -text -noout | grep -E "Subject:|Not After:|SAN:|DNS:"

# Certificate expiry in days
echo | openssl s_client -connect api.example.com:443 2>/dev/null \
  | openssl x509 -noout -enddate \
  | cut -d= -f2 | xargs -I{} date -d {} +%s \
  | xargs -I{} echo "Expires in $(( ({} - $(date +%s)) / 86400 )) days"

# Test specific TLS version
openssl s_client -connect host:443 -tls1_2 -brief
openssl s_client -connect host:443 -tls1_3 -brief
```

---

## 6. Performance Tools Reference

| Tool | What It Shows | Common Usage |
|------|--------------|-------------|
| `top` / `htop` | CPU, memory by process | `top -b -n1` for snapshot |
| `vmstat` | CPU, memory, I/O summary | `vmstat 1 10` |
| `iostat` | Disk I/O per device | `iostat -x 1 5` |
| `sar` | Historical system stats | `sar -u 1 10`, `sar -r` (memory) |
| `ss` | Network sockets | `ss -tlnp`, `ss -tan` |
| `netstat` | Legacy network stats | `netstat -s | grep retransmit` |
| `lsof` | Open files by process | `lsof -p <PID>`, `lsof -i :8080` |
| `strace` | System call trace | `strace -p <PID> -e trace=network` |
| `tcpdump` | Packet capture | `tcpdump -i any -n port 80` |
| `perf` | CPU profiling | `perf top`, `perf record` |
| `dmesg` | Kernel messages | `dmesg -T | tail -20` |
| `iotop` | I/O by process | `iotop -ao -P` |
