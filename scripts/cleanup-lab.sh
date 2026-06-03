#!/usr/bin/env bash
# cleanup-lab.sh — Remove monitoring stack from cluster
set -euo pipefail
RED='[0;31m'; GREEN='[0;32m'; YELLOW='[1;33m'; NC='[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }

NAMESPACE=${MONITORING_NAMESPACE:-monitoring}
AUTO_APPROVE=false

if [[ "${1:-}" == "--yes" ]]; then
  AUTO_APPROVE=true
fi

warn "This will remove the monitoring stack from namespace: $NAMESPACE"
if [[ "$AUTO_APPROVE" != "true" ]]; then
  read -r -p "Continue? [y/N] " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

info "Removing Helm releases..."
helm uninstall tempo -n "$NAMESPACE" 2>/dev/null && info "Tempo removed" || warn "Tempo not found"
helm uninstall loki -n "$NAMESPACE" 2>/dev/null && info "Loki removed" || warn "Loki not found"
helm uninstall kube-prometheus-stack -n "$NAMESPACE" 2>/dev/null && info "kube-prometheus-stack removed" || warn "Not found"

info "Removing CRDs..."
kubectl get crd | grep -E "prometheus|alertmanager|servicemonitor|podmonitor|prometheusrule" | \
  awk '{print $1}' | xargs -r kubectl delete crd 2>/dev/null || true

info "Removing namespace..."
kubectl delete namespace "$NAMESPACE" --ignore-not-found

info "Cleanup complete."
