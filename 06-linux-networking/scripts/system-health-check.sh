#!/usr/bin/env bash
# system-health-check.sh - portable SRE-oriented host health summary
set -u
set -o pipefail

PROGRAM=${0##*/}
LOAD_WARN=""
LOAD_CRIT=""
MEM_WARN=75
MEM_CRIT=90
DISK_WARN=80
DISK_CRIT=90
TOP_N=5
SHOW_TOP=1
SHOW_NETWORK=1
SHOW_SYSCTLS=1
NO_COLOR=0
EXIT_CODE=0

usage() {
  cat <<USAGE
Usage: $PROGRAM [options]

Portable host health summary for Linux-centric diagnostics.
The script degrades gracefully when commands or Linux files are unavailable.

Options:
  --load-warn N        Warn threshold for 1m load average (default: CPU count)
  --load-crit N        Critical threshold for 1m load average (default: CPU count * 1.5)
  --mem-warn N         Warn threshold for memory used percent (default: 75)
  --mem-crit N         Critical threshold for memory used percent (default: 90)
  --disk-warn N        Warn threshold for filesystem use percent (default: 80)
  --disk-crit N        Critical threshold for filesystem use percent (default: 90)
  --top N              Show top N CPU and memory processes (default: 5)
  --quick              Skip top processes, network summary, and sysctl checks
  --no-network         Skip socket summary
  --no-sysctls         Skip sysctl overview
  --no-color           Disable ANSI colors
  -h, --help           Show this help
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --load-warn) LOAD_WARN=$2; shift 2 ;;
    --load-crit) LOAD_CRIT=$2; shift 2 ;;
    --mem-warn) MEM_WARN=$2; shift 2 ;;
    --mem-crit) MEM_CRIT=$2; shift 2 ;;
    --disk-warn) DISK_WARN=$2; shift 2 ;;
    --disk-crit) DISK_CRIT=$2; shift 2 ;;
    --top) TOP_N=$2; shift 2 ;;
    --quick) SHOW_TOP=0; SHOW_NETWORK=0; SHOW_SYSCTLS=0; shift ;;
    --no-network) SHOW_NETWORK=0; shift ;;
    --no-sysctls) SHOW_SYSCTLS=0; shift ;;
    --no-color) NO_COLOR=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

if [ "$NO_COLOR" -eq 1 ]; then
  RED=""; GREEN=""; YELLOW=""; BLUE=""; BOLD=""; RESET=""
else
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'
fi

have_cmd() { command -v "$1" >/dev/null 2>&1; }
section() { printf '\n%s== %s ==%s\n' "$BLUE" "$1" "$RESET"; }
info() { printf '%s[INFO]%s %s\n' "$BLUE" "$RESET" "$*"; }
ok() { printf '%s[OK]%s   %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$YELLOW" "$RESET" "$*"; [ "$EXIT_CODE" -lt 1 ] && EXIT_CODE=1; }
crit() { printf '%s[CRIT]%s %s\n' "$RED" "$RESET" "$*"; EXIT_CODE=2; }
float_ge() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a >= b) }'; }
int_ge() { [ "$1" -ge "$2" ] 2>/dev/null; }

get_cpu_count() {
  if have_cmd getconf; then
    getconf _NPROCESSORS_ONLN 2>/dev/null && return 0
  fi
  if have_cmd nproc; then
    nproc 2>/dev/null && return 0
  fi
  if have_cmd sysctl; then
    sysctl -n hw.ncpu 2>/dev/null && return 0
  fi
  echo 1
}

get_load_triplet() {
  if [ -r /proc/loadavg ]; then
    awk '{print $1, $2, $3}' /proc/loadavg
    return 0
  fi
  if have_cmd sysctl; then
    sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1, $2, $3}'
    return 0
  fi
  echo "0 0 0"
}

mem_linux() {
  local total avail used pct
  total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
  avail=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
  [ -n "$total" ] && [ -n "$avail" ] || return 1
  used=$((total - avail))
  pct=$(( used * 100 / total ))
  echo "$total $avail $pct"
}

mem_darwin() {
  local total pagesize free inactive speculative available used pct
  total=$(sysctl -n hw.memsize 2>/dev/null) || return 1
  pagesize=$(sysctl -n hw.pagesize 2>/dev/null) || pagesize=4096
  free=$(vm_stat 2>/dev/null | awk -F: '/Pages free/ {gsub("\\.","",$2); gsub(/ /,"",$2); print $2+0}')
  inactive=$(vm_stat 2>/dev/null | awk -F: '/Pages inactive/ {gsub("\\.","",$2); gsub(/ /,"",$2); print $2+0}')
  speculative=$(vm_stat 2>/dev/null | awk -F: '/Pages speculative/ {gsub("\\.","",$2); gsub(/ /,"",$2); print $2+0}')
  available=$(( (free + inactive + speculative) * pagesize / 1024 ))
  used=$(( total / 1024 - available ))
  pct=$(( used * 100 / (total / 1024) ))
  echo "$(( total / 1024 )) $available $pct"
}

show_top_processes_linux() {
  if have_cmd ps; then
    printf 'CPU:\n'
    ps -eo pid,ppid,%cpu,%mem,stat,comm --sort=-%cpu 2>/dev/null | head -n $((TOP_N + 1))
    printf '\nMemory:\n'
    ps -eo pid,ppid,%cpu,%mem,rss,stat,comm --sort=-%mem 2>/dev/null | head -n $((TOP_N + 1))
  fi
}

show_top_processes_portable() {
  if have_cmd ps; then
    printf 'CPU:\n'
    ps -Ao pid,ppid,%cpu,%mem,stat,comm 2>/dev/null | { IFS= read -r header && printf '%s\n' "$header" && sort -k3,3nr; } | head -n $((TOP_N + 1))
    printf '\nMemory:\n'
    ps -Ao pid,ppid,%cpu,%mem,comm 2>/dev/null | { IFS= read -r header && printf '%s\n' "$header" && sort -k4,4nr; } | head -n $((TOP_N + 1))
  fi
}

printf '%s%s%s\n' "$BOLD" "System Health Check" "$RESET"
printf 'Host: %s\n' "$(hostname 2>/dev/null || echo unknown)"
printf 'Time: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
printf 'Kernel: %s\n' "$(uname -sr 2>/dev/null || echo unknown)"

CPU_COUNT=$(get_cpu_count)
set -- $(get_load_triplet)
LOAD1=${1:-0}; LOAD5=${2:-0}; LOAD15=${3:-0}
[ -n "$LOAD_WARN" ] || LOAD_WARN=$CPU_COUNT
[ -n "$LOAD_CRIT" ] || LOAD_CRIT=$(awk -v c="$CPU_COUNT" 'BEGIN { printf "%.1f", c * 1.5 }')

section "CPU and load"
printf 'CPUs: %s\n' "$CPU_COUNT"
printf 'Load average: %s %s %s\n' "$LOAD1" "$LOAD5" "$LOAD15"
if float_ge "$LOAD1" "$LOAD_CRIT"; then
  crit "1-minute load ($LOAD1) exceeds critical threshold ($LOAD_CRIT)"
elif float_ge "$LOAD1" "$LOAD_WARN"; then
  warn "1-minute load ($LOAD1) exceeds warning threshold ($LOAD_WARN)"
else
  ok "1-minute load is within threshold"
fi
if have_cmd uptime; then
  info "$(uptime 2>/dev/null)"
fi
if have_cmd vmstat; then
  info "vmstat snapshot"
  vmstat 1 2 2>/dev/null | tail -n 2
fi
if have_cmd mpstat; then
  info "mpstat summary"
  mpstat -P ALL 1 1 2>/dev/null | tail -n +3
fi

section "Memory"
if [ -r /proc/meminfo ]; then
  set -- $(mem_linux)
  MEM_TOTAL=${1:-0}; MEM_AVAIL=${2:-0}; MEM_PCT=${3:-0}
  printf 'MemTotal: %s MiB\n' $((MEM_TOTAL / 1024))
  printf 'MemAvailable: %s MiB\n' $((MEM_AVAIL / 1024))
  printf 'Memory used estimate: %s%%\n' "$MEM_PCT"
elif have_cmd sysctl && have_cmd vm_stat; then
  set -- $(mem_darwin)
  MEM_TOTAL=${1:-0}; MEM_AVAIL=${2:-0}; MEM_PCT=${3:-0}
  printf 'MemTotal: %s MiB\n' $((MEM_TOTAL / 1024))
  printf 'Approx available: %s MiB\n' $((MEM_AVAIL / 1024))
  printf 'Memory used estimate: %s%%\n' "$MEM_PCT"
else
  MEM_PCT=0
  warn "Memory detail unavailable on this platform"
fi
if int_ge "$MEM_PCT" "$MEM_CRIT"; then
  crit "Memory usage estimate exceeds critical threshold"
elif int_ge "$MEM_PCT" "$MEM_WARN"; then
  warn "Memory usage estimate exceeds warning threshold"
else
  ok "Memory usage estimate is within threshold"
fi
if have_cmd free; then
  free -h 2>/dev/null | sed 's/^/[DATA] /'
fi
if [ -r /proc/pressure/memory ]; then
  info "memory PSI"
  sed 's/^/[DATA] /' /proc/pressure/memory
fi

section "Disk capacity"
printf 'Thresholds: warn=%s%% crit=%s%%\n' "$DISK_WARN" "$DISK_CRIT"
if have_cmd df; then
  df -Pk 2>/dev/null | awk -v warn_t="$DISK_WARN" -v crit_t="$DISK_CRIT" '
    NR==1 {print; next}
    ($1 ~ /^\/dev\// || $1 == "overlay") && $5 ~ /%/ {
      pct=$5; gsub(/%/, "", pct); status="OK"
      if (pct+0 >= crit_t) status="CRIT"
      else if (pct+0 >= warn_t) status="WARN"
      printf "[%s] %s\n", status, $0
    }
  '
else
  warn "df command unavailable"
fi
if df -Pi >/dev/null 2>&1; then
  info "inode usage"
  df -Pi 2>/dev/null | awk 'NR==1 || $1 ~ /^\/dev\// || $1 == "overlay" {print}'
fi
if have_cmd lsof; then
  info "deleted-open files (top 10 if any)"
  lsof +L1 2>/dev/null | head -10 || true
fi

if [ "$SHOW_TOP" -eq 1 ]; then
  section "Top processes"
  if [ -d /proc ]; then
    show_top_processes_linux
  else
    show_top_processes_portable
  fi
fi

if [ "$SHOW_NETWORK" -eq 1 ]; then
  section "Socket and network summary"
  if have_cmd ss; then
    ss -s 2>/dev/null || warn "ss summary unavailable"
    info "top listening sockets"
    ss -lntup 2>/dev/null | head -20 || true
  elif have_cmd netstat; then
    netstat -an 2>/dev/null | head -40 || warn "netstat unavailable"
  else
    warn "Neither ss nor netstat is available"
  fi
  if have_cmd ip; then
    info "interface counters"
    ip -s link 2>/dev/null | head -40
  elif have_cmd netstat; then
    info "interface counters"
    netstat -ib 2>/dev/null | head -20
  fi
fi

section "Kernel signals"
if [ -d /proc ]; then
  if have_cmd dmesg; then
    info "recent OOM or IO related kernel messages"
    dmesg 2>/dev/null | egrep -i 'oom|out of memory|reset|error|ext4|xfs|blk|nvme' | tail -10 || true
  fi
  if [ -r /proc/sys/fs/file-max ]; then
    printf 'fs.file-max: %s\n' "$(cat /proc/sys/fs/file-max 2>/dev/null)"
  fi
  if [ -r /proc/sys/vm/max_map_count ]; then
    printf 'vm.max_map_count: %s\n' "$(cat /proc/sys/vm/max_map_count 2>/dev/null)"
  fi
fi

if [ "$SHOW_SYSCTLS" -eq 1 ] && have_cmd sysctl; then
  section "Selected sysctls"
  for key in net.core.somaxconn net.ipv4.tcp_max_syn_backlog net.ipv4.tcp_fin_timeout vm.swappiness kernel.pid_max; do
    value=$(sysctl -n "$key" 2>/dev/null || true)
    if [ -n "$value" ]; then
      printf '%s=%s\n' "$key" "$value"
    fi
  done
fi

printf '\nResult code: %s\n' "$EXIT_CODE"
exit "$EXIT_CODE"
