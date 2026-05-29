#!/usr/bin/env bash
# system-health-check.sh — Quick Linux system health check
set -euo pipefail
RED='[0;31m'; GREEN='[0;32m'; YELLOW='[1;33m'; NC='[0m'
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
crit() { echo -e "${RED}[CRIT]${NC}  $*"; }

echo "=============================="
echo " System Health Check"
echo " $(hostname) — $(date)"
echo "=============================="

# Load average
read -r one five fifteen _ < /proc/loadavg
ncpus=$(nproc)
echo ""
echo "Load Average: $one (1m) $five (5m) $fifteen (15m) | CPUs: $ncpus"
if (( $(echo "$one > $ncpus" | bc -l) )); then
    crit "Load average exceeds CPU count"
else
    ok "Load average normal"
fi

# Memory
memtotal=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
memavail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
mempct=$(( (memtotal - memavail) * 100 / memtotal ))
echo ""
echo "Memory: ${mempct}% used ($(( memavail / 1024 ))MB available of $(( memtotal / 1024 ))MB)"
if (( mempct > 90 )); then
    crit "Memory critically high: ${mempct}%"
elif (( mempct > 75 )); then
    warn "Memory high: ${mempct}%"
else
    ok "Memory OK: ${mempct}%"
fi

# Disk
echo ""
echo "Disk Usage:"
df -h | awk 'NR==1 || /^\/dev/ {
    if (NR > 1) {
        pct = substr($5, 1, length($5)-1)
        if (pct+0 > 90) print "  [CRIT] " $0
        else if (pct+0 > 75) print "  [WARN] " $0
        else print "  [OK]   " $0
    } else print "  " $0
}'

# Top CPU processes
echo ""
echo "Top 5 CPU Consumers:"
ps aux --sort=-%cpu | awk 'NR==2,NR==6 {printf "  %5s %5s  %s\n", $3, $4, $11}'

# Top Memory processes
echo ""
echo "Top 5 Memory Consumers:"
ps aux --sort=-%mem | awk 'NR==2,NR==6 {printf "  %5s %5s  %s\n", $3, $4, $11}'

# OOM check
oom_count=$(dmesg 2>/dev/null | grep -c "Out of memory" || true)
echo ""
if (( oom_count > 0 )); then
    crit "OOM events in dmesg: $oom_count"
    dmesg 2>/dev/null | grep "Out of memory" | tail -3
else
    ok "No OOM events in dmesg"
fi

echo ""
echo "=============================="
