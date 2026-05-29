#!/usr/bin/env bash
# network-diag.sh — Network connectivity diagnostics
set -euo pipefail
RED='[0;31m'; GREEN='[0;32m'; YELLOW='[1;33m'; NC='[0m'
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; }

TARGET=${1:-8.8.8.8}

echo "=============================="
echo " Network Diagnostics"
echo " Target: $TARGET"
echo " $(date)"
echo "=============================="

# DNS
echo ""
echo "--- DNS Resolution ---"
if nslookup google.com >/dev/null 2>&1; then
    ok "DNS resolution working"
else
    fail "DNS resolution failed — check /etc/resolv.conf"
fi
cat /etc/resolv.conf | grep nameserver

# Ping
echo ""
echo "--- ICMP (Ping) ---"
if ping -c3 -W2 "$TARGET" >/dev/null 2>&1; then
    latency=$(ping -c3 "$TARGET" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
    ok "Ping to $TARGET OK (avg ${latency}ms)"
else
    fail "Ping to $TARGET failed"
fi

# Route
echo ""
echo "--- Route to Target ---"
ip route get "$TARGET" 2>/dev/null || route -n 2>/dev/null | head -10

# Connections
echo ""
echo "--- Connection Summary ---"
ss -s 2>/dev/null | grep -E "estab|time-wait|close-wait"

# Listening
echo ""
echo "--- Listening Ports ---"
ss -tlnp 2>/dev/null | awk 'NR>1 {print $4, $6}' | sort

# Interface stats
echo ""
echo "--- Interface Errors ---"
ip -s link 2>/dev/null | awk '/^[0-9]/{iface=$2} /errors/{print iface, $0}' | head -10

echo ""
echo "=============================="
