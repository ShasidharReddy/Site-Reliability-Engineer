#!/usr/bin/env bash
# bootstrap-lab.sh — Set up local K8s lab environment
set -euo pipefail
RED='[0;31m'; GREEN='[0;32m'; YELLOW='[1;33m'; NC='[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

info "Checking prerequisites..."

check_cmd() {
    command -v "$1" >/dev/null 2>&1 && info "  $1: OK" || warn "  $1: NOT FOUND"
}

check_cmd kubectl
check_cmd helm
check_cmd docker
check_cmd gcloud
check_cmd terraform

echo ""
info "Checking Kubernetes cluster..."
if kubectl cluster-info >/dev/null 2>&1; then
    info "Cluster: $(kubectl config current-context)"
    info "Server: $(kubectl cluster-info | head -1 | awk '{print $NF}')"
    info "Nodes:"
    kubectl get nodes -o wide 2>/dev/null || warn "Cannot list nodes"
else
    warn "No Kubernetes cluster found."
    echo ""
    echo "Options to create a local cluster:"
    echo "  minikube start --memory=4096 --cpus=2"
    echo "  kind create cluster --name sre-lab"
    echo "  k3d cluster create sre-lab"
fi

echo ""
info "Checking Helm repos..."
helm repo list 2>/dev/null | grep -E "prometheus|grafana" || {
    warn "Monitoring repos not added. Run:"
    echo "  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts"
    echo "  helm repo add grafana https://grafana.github.io/helm-charts"
}

echo ""
info "Environment summary:"
echo "  OS:         $(uname -s) $(uname -m)"
echo "  kubectl:    $(kubectl version --client --short 2>/dev/null || echo 'not found')"
echo "  helm:       $(helm version --short 2>/dev/null || echo 'not found')"
echo "  gcloud:     $(gcloud version 2>/dev/null | head -1 || echo 'not found')"
echo ""
info "Ready to start! Run: ./scripts/deploy-monitoring-stack.sh"
