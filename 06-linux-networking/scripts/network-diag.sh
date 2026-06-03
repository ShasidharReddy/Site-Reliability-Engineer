#!/usr/bin/env bash
# network-diag.sh - portable network diagnostics for SRE workflows
set -u
set -o pipefail

PROGRAM=${0##*/}
TARGET="localhost"
PORT=""
RESOLVER=""
COUNT=3
TIMEOUT=3
HTTP_PATH="/"
SKIP_DNS=0
SKIP_PING=0
SKIP_TRACE=0
NO_COLOR=0
EXIT_CODE=0

usage() {
  cat <<USAGE
Usage: $PROGRAM [options]

Portable network diagnostics that prefer safe, read-only checks.
The script degrades gracefully when commands or privileges are unavailable.

Options:
  --target HOST        Target host or IP (default: localhost)
  --port PORT          Optional TCP port to test
  --resolver IP        Resolver to query when DNS checks run
  --count N            Ping count (default: 3)
  --timeout SEC        Connect or curl timeout (default: 3)
  --http-path PATH     HTTP path for curl checks (default: /)
  --skip-dns           Skip DNS checks
  --skip-ping          Skip ICMP checks
  --skip-trace         Skip tracepath or traceroute checks
  --no-color           Disable ANSI colors
  -h, --help           Show this help
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET=$2; shift 2 ;;
    --port) PORT=$2; shift 2 ;;
    --resolver) RESOLVER=$2; shift 2 ;;
    --count) COUNT=$2; shift 2 ;;
    --timeout) TIMEOUT=$2; shift 2 ;;
    --http-path) HTTP_PATH=$2; shift 2 ;;
    --skip-dns) SKIP_DNS=1; shift ;;
    --skip-ping) SKIP_PING=1; shift ;;
    --skip-trace) SKIP_TRACE=1; shift ;;
    --no-color) NO_COLOR=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

if [ "$NO_COLOR" -eq 1 ]; then
  RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
else
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RESET='\033[0m'
fi

have_cmd() { command -v "$1" >/dev/null 2>&1; }
section() { printf '\n%s== %s ==%s\n' "$BLUE" "$1" "$RESET"; }
ok() { printf '%s[OK]%s   %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$YELLOW" "$RESET" "$*"; [ "$EXIT_CODE" -lt 1 ] && EXIT_CODE=1; }
fail() { printf '%s[FAIL]%s %s\n' "$RED" "$RESET" "$*"; EXIT_CODE=2; }

is_ip() {
  case "$1" in
    *:*|*.*.*.*) return 0 ;;
    *) return 1 ;;
  esac
}

section "Session"
printf 'Target: %s\n' "$TARGET"
[ -n "$PORT" ] && printf 'Port: %s\n' "$PORT"
printf 'Time: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"

if [ "$SKIP_DNS" -eq 0 ] && ! is_ip "$TARGET"; then
  section "DNS"
  if [ -r /etc/resolv.conf ]; then
    printf 'Resolvers from /etc/resolv.conf:\n'
    grep '^nameserver' /etc/resolv.conf 2>/dev/null || true
  fi
  if have_cmd getent; then
    getent hosts "$TARGET" 2>/dev/null && ok "getent resolved $TARGET" || warn "getent failed for $TARGET"
  elif have_cmd dscacheutil; then
    dscacheutil -q host -a name "$TARGET" 2>/dev/null && ok "dscacheutil resolved $TARGET" || warn "dscacheutil failed for $TARGET"
  else
    warn "No getent or dscacheutil available for local resolver test"
  fi
  if have_cmd dig; then
    if [ -n "$RESOLVER" ]; then
      dig +time="$TIMEOUT" +short @"$RESOLVER" "$TARGET" 2>/dev/null || warn "dig via resolver $RESOLVER failed"
    else
      dig +time="$TIMEOUT" +short "$TARGET" 2>/dev/null || warn "dig failed for $TARGET"
    fi
  elif have_cmd nslookup; then
    nslookup "$TARGET" ${RESOLVER:+$RESOLVER} 2>/dev/null || warn "nslookup failed for $TARGET"
  else
    warn "No dig or nslookup available"
  fi
fi

section "Routing"
if have_cmd ip; then
  ip route get "$TARGET" 2>/dev/null || warn "ip route get failed for $TARGET"
elif have_cmd route; then
  route -n get "$TARGET" 2>/dev/null || warn "route lookup failed for $TARGET"
else
  warn "No route inspection command available"
fi

if [ "$SKIP_PING" -eq 0 ] && have_cmd ping; then
  section "ICMP"
  if ping -c "$COUNT" "$TARGET" >/dev/null 2>&1; then
    ok "Ping to $TARGET succeeded"
    ping -c "$COUNT" "$TARGET" 2>/dev/null | tail -n 2
  else
    warn "Ping to $TARGET failed or is filtered"
  fi
fi

if [ "$SKIP_TRACE" -eq 0 ]; then
  section "Path trace"
  if have_cmd tracepath; then
    tracepath "$TARGET" 2>/dev/null | head -20 || warn "tracepath failed"
  elif have_cmd traceroute; then
    traceroute "$TARGET" 2>/dev/null | head -20 || warn "traceroute failed"
  else
    warn "No tracepath or traceroute available"
  fi
fi

section "Socket summary"
if have_cmd ss; then
  ss -s 2>/dev/null || warn "ss summary unavailable"
  [ -n "$PORT" ] && ss -tan 2>/dev/null | awk -v p=":$PORT" '$4 ~ p || $5 ~ p {print}' | head -20
elif have_cmd netstat; then
  netstat -an 2>/dev/null | awk 'NR<=40 {print}'
else
  warn "Neither ss nor netstat is available"
fi

if [ -n "$PORT" ]; then
  section "TCP connect"
  if have_cmd nc; then
    if nc -z -w "$TIMEOUT" "$TARGET" "$PORT" >/dev/null 2>&1; then
      ok "TCP connect to $TARGET:$PORT succeeded"
    else
      fail "TCP connect to $TARGET:$PORT failed"
    fi
  else
    warn "nc is not available for TCP connect testing"
  fi
fi

if [ -n "$PORT" ] && have_cmd curl && { [ "$PORT" = "80" ] || [ "$PORT" = "443" ]; }; then
  section "HTTP or HTTPS"
  if [ "$PORT" = "443" ]; then
    URL="https://$TARGET$HTTP_PATH"
  else
    URL="http://$TARGET:$PORT$HTTP_PATH"
  fi
  curl -k -sS -o /dev/null -D - --max-time "$TIMEOUT" "$URL" 2>/dev/null | head -20 || warn "curl failed for $URL"
fi

if [ -n "$PORT" ] && [ "$PORT" = "443" ] && have_cmd openssl; then
  section "TLS"
  printf '' | openssl s_client -connect "$TARGET:$PORT" -servername "$TARGET" 2>/dev/null | awk '/subject=|issuer=|Verify return code|Protocol|Cipher/' || warn "openssl handshake failed"
fi

section "Interface counters"
if have_cmd ip; then
  ip -s link 2>/dev/null | awk 'NR<=40 {print}'
elif have_cmd netstat; then
  netstat -ib 2>/dev/null | awk 'NR<=20 {print}'
else
  warn "No interface counter command available"
fi

section "Policy overview"
if have_cmd nft; then
  nft list ruleset 2>/dev/null | awk 'NR<=80 {print}' || warn "Unable to read nftables ruleset"
elif have_cmd iptables; then
  iptables -L -n -v --line-numbers 2>/dev/null | awk 'NR<=80 {print}' || warn "Unable to read iptables rules"
elif have_cmd pfctl; then
  pfctl -sr 2>/dev/null | awk 'NR<=80 {print}' || warn "Unable to read pf rules"
else
  warn "No firewall inspection command available"
fi

printf '\nResult code: %s\n' "$EXIT_CODE"
exit "$EXIT_CODE"
