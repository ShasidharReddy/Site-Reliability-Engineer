#!/usr/bin/env bash
# run-local-lab.sh — Create kind cluster and deploy monitoring stack
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-sre-lab}"
KIND_CONFIG="${KIND_CONFIG:-$ROOT_DIR/configs/kind-sre-lab.yaml}"
KIND_CONTEXT="kind-${KIND_CLUSTER_NAME}"

command -v kind >/dev/null 2>&1 || error "kind not found"
command -v kubectl >/dev/null 2>&1 || error "kubectl not found"
command -v helm >/dev/null 2>&1 || error "helm not found"

if ! kind get clusters | grep -q "^${KIND_CLUSTER_NAME}$"; then
  info "Creating kind cluster: $KIND_CLUSTER_NAME"
  kind create cluster --name "$KIND_CLUSTER_NAME" --config "$KIND_CONFIG"
  ok "Created kind cluster"
else
  info "kind cluster already exists: $KIND_CLUSTER_NAME"
fi

kubectl config use-context "$KIND_CONTEXT" >/dev/null
ok "Using context: $KIND_CONTEXT"

info "Deploying monitoring stack..."
bash "$ROOT_DIR/scripts/deploy-monitoring-stack.sh"

echo ""
ok "Local lab is ready"
echo "Grafana:"
echo "  kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
echo "  kubectl get secret grafana-admin-credentials -n monitoring \\"
echo "    -o jsonpath='{.data.admin-password}' | base64 --decode; echo"

