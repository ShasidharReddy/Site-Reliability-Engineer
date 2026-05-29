#!/usr/bin/env bash
# bootstrap-lab.sh — Validate SRE lab prerequisites and cluster connectivity
# Targets: GKE (production), kind (local parity), or any CNCF-conformant cluster
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*"; }
info() { echo -e "${BLUE}[INFO]${NC}  $*"; }

echo ""
echo "╔══════════════════════════════════════╗"
echo "║     SRE Lab Environment Check        ║"
echo "╚══════════════════════════════════════╝"
echo ""

ERRORS=0

check_cmd() {
    local cmd=$1 min_ver=${2:-""} purpose=${3:-""}
    if command -v "$cmd" >/dev/null 2>&1; then
        local ver
        ver=$("$cmd" version --client --short 2>/dev/null \
            || "$cmd" version --short 2>/dev/null \
            || "$cmd" --version 2>/dev/null \
            || "$cmd" version 2>/dev/null | head -1 || echo "unknown")
        ok "$cmd $(echo "$ver" | head -1) — $purpose"
    else
        fail "$cmd not found — Install: $purpose"
        (( ERRORS++ )) || true
    fi
}

echo "── Required Tools ──────────────────────"
check_cmd kubectl "" "cluster management"
check_cmd helm "" "chart deployment"
check_cmd gcloud "" "GKE auth + GCP operations"

echo ""
echo "── Recommended Tools ───────────────────"
check_cmd kind "" "local multi-node K8s clusters (production parity)"
check_cmd terraform "" "infrastructure as code"
check_cmd jq "" "JSON processing in lab exercises"

echo ""
echo "── Kubernetes Cluster ──────────────────"

if kubectl cluster-info >/dev/null 2>&1; then
    CTX=$(kubectl config current-context 2>/dev/null || echo "unknown")
    SERVER=$(kubectl cluster-info 2>/dev/null | head -1 | grep -oE 'https?://[^ ]+' || echo "unknown")
    K8S_VER=$(kubectl version --short 2>/dev/null | grep Server | awk '{print $3}' || echo "unknown")

    ok "Connected to cluster"
    info "Context : $CTX"
    info "Server  : $SERVER"
    info "Version : $K8S_VER"
    echo ""
    echo "  Node Status:"
    kubectl get nodes --no-headers 2>/dev/null | \
        awk '{printf "  %-40s %-10s %-10s\n", $1, $2, $5}' || warn "Cannot list nodes"

    # Check node count
    NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if (( NODE_COUNT < 2 )); then
        warn "Only $NODE_COUNT node(s) — production requires multi-node for HA testing"
    else
        ok "$NODE_COUNT nodes — suitable for HA testing"
    fi

    # Check existing monitoring namespace
    if kubectl get namespace monitoring >/dev/null 2>&1; then
        info "Namespace 'monitoring' already exists"
        kubectl get pods -n monitoring --no-headers 2>/dev/null | \
            awk '{printf "  %-50s %s\n", $1, $3}' | head -10
    fi
else
    warn "No cluster connected."
    echo ""
    echo "  ── Connect to a cluster ──────────────────────────────"
    echo ""
    echo "  GKE (recommended for full lab coverage):"
    echo "    gcloud container clusters get-credentials CLUSTER --zone ZONE --project PROJECT"
    echo ""
    echo "  Create a local multi-node cluster with kind:"
    echo "    kind create cluster --config kind-sre-lab.yaml"
    echo ""
    echo "  kind-sre-lab.yaml:"
    echo "    kind: Cluster"
    echo "    apiVersion: kind.x-k8s.io/v1alpha4"
    echo "    name: sre-lab"
    echo "    nodes:"
    echo "      - role: control-plane"
    echo "      - role: worker"
    echo "      - role: worker"
    echo "      - role: worker"
    echo ""
    echo "  On-prem / other:"
    echo "    Any CNCF-conformant cluster (RKE2, K3s HA, OpenShift) works."
    echo "    minikube is NOT recommended — single-node, non-standard CNI/CSI."
fi

echo ""
echo "── Helm Repositories ───────────────────"
REPOS=$(helm repo list 2>/dev/null || echo "")

check_repo() {
    local name=$1 url=$2
    if echo "$REPOS" | grep -q "^$name"; then
        ok "helm repo: $name"
    else
        warn "helm repo '$name' not added — run: helm repo add $name $url"
    fi
}
check_repo prometheus-community https://prometheus-community.github.io/helm-charts
check_repo grafana              https://grafana.github.io/helm-charts
check_repo jetstack             https://charts.jetstack.io

echo ""
echo "── GCP / GKE Auth ──────────────────────"
if gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q "@"; then
    GCP_ACC=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1)
    GCP_PROJ=$(gcloud config get-value project 2>/dev/null || echo "none set")
    ok "GCP authenticated: $GCP_ACC"
    info "Project: $GCP_PROJ"
else
    warn "Not authenticated to GCP — run: gcloud auth application-default login"
fi

echo ""
if (( ERRORS > 0 )); then
    fail "$ERRORS required tool(s) missing. Install them before proceeding."
else
    ok "All required tools present."
    echo ""
    info "Next step: bash scripts/deploy-monitoring-stack.sh"
fi
echo ""
