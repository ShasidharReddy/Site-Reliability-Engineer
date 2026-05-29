#!/bin/bash
# Safe GKE Node Drain with Pre-Checks
# Usage: ./gke-node-drain.sh <node-name>
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

NODE="${1:-}"
[[ -z "$NODE" ]] && fail "Usage: $0 <node-name>"

echo "=== GKE Node Drain Pre-Flight Check ==="
echo "Node: $NODE"
echo ""

# 1. Verify node exists
kubectl get node "$NODE" &>/dev/null || fail "Node $NODE not found"
ok "Node $NODE exists"

# 2. Check pods on node
POD_COUNT=$(kubectl get pods -A --field-selector spec.nodeName="$NODE" --no-headers | wc -l)
echo ""
echo "Pods on node: $POD_COUNT"
kubectl get pods -A --field-selector spec.nodeName="$NODE" -o wide 2>/dev/null | head -30

# 3. Check PDBs — will drain be blocked?
echo ""
echo "--- Checking Pod Disruption Budgets ---"
NAMESPACES=$(kubectl get pods -A --field-selector spec.nodeName="$NODE" -o jsonpath='{.items[*].metadata.namespace}' | tr ' ' '\n' | sort -u)
PDB_ISSUES=0
for NS in $NAMESPACES; do
  while IFS= read -r line; do
    NAME=$(echo "$line" | awk '{print $1}')
    MIN_AVAIL=$(echo "$line" | awk '{print $2}')
    CURRENT=$(echo "$line" | awk '{print $5}')
    if [[ "$CURRENT" == "$MIN_AVAIL" ]] 2>/dev/null; then
      warn "PDB $NS/$NAME: currently at minAvailable ($CURRENT) — drain may block!"
      PDB_ISSUES=$((PDB_ISSUES + 1))
    fi
  done < <(kubectl get pdb -n "$NS" --no-headers 2>/dev/null | awk '{print $1, $2, $3, $4, $5}')
done
[[ "$PDB_ISSUES" -eq 0 ]] && ok "No PDB violations expected"

# 4. Check available nodes
echo ""
echo "--- Available Node Capacity ---"
kubectl get nodes --no-headers | grep -v "$NODE" | grep " Ready"

# 5. Confirm
echo ""
echo "Ready to drain node: $NODE"
read -rp "Proceed with drain? [y/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# 6. Cordon first (prevent new pods scheduling)
echo ""
echo "Cordoning node $NODE..."
kubectl cordon "$NODE"
ok "Node cordoned"

# 7. Drain
echo "Draining node $NODE (timeout 5 minutes)..."
kubectl drain "$NODE" \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --force \
  --timeout=300s
ok "Node drained successfully"

echo ""
echo "=== Post-Drain Verification ==="
kubectl get pods -A --field-selector spec.nodeName="$NODE" --no-headers | wc -l | xargs -I{} echo "Remaining pods on node: {}"
echo ""
echo "To uncordon after maintenance:"
echo "  kubectl uncordon $NODE"
