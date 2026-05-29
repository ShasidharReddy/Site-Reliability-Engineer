#!/bin/bash
# GCP Infrastructure Health Check Script
# Usage: ./gcp-health-check.sh [PROJECT_ID] [CLUSTER_NAME] [ZONE]
set -euo pipefail

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; }
info() { echo -e "      $*"; }

PROJECT="${1:-$(gcloud config get-value project 2>/dev/null)}"
CLUSTER="${2:-}"
ZONE="${3:-us-central1-a}"

echo "=============================================="
echo " GCP Health Check — $(date)"
echo " Project: $PROJECT"
echo "=============================================="

# 1. Auth check
echo ""
echo "--- Authentication ---"
ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1)
if [[ -n "$ACCOUNT" ]]; then
  ok "Authenticated as: $ACCOUNT"
else
  fail "Not authenticated — run: gcloud auth login"
  exit 1
fi

# 2. GKE cluster check
echo ""
echo "--- GKE Clusters ---"
if [[ -n "$CLUSTER" ]]; then
  STATUS=$(gcloud container clusters describe "$CLUSTER" --zone "$ZONE" --project "$PROJECT" \
    --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
  if [[ "$STATUS" == "RUNNING" ]]; then
    ok "Cluster $CLUSTER is RUNNING"
    VERSION=$(gcloud container clusters describe "$CLUSTER" --zone "$ZONE" --project "$PROJECT" \
      --format="value(currentMasterVersion)" 2>/dev/null)
    info "Master version: $VERSION"
  else
    fail "Cluster $CLUSTER status: $STATUS"
  fi
else
  # List all clusters
  gcloud container clusters list --project "$PROJECT" \
    --format="table(name,status,currentMasterVersion,location)" 2>/dev/null || warn "No clusters found"
fi

# 3. Node status
echo ""
echo "--- Node Status ---"
if command -v kubectl &>/dev/null; then
  NOT_READY=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready" | wc -l)
  TOTAL=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
  if [[ "$NOT_READY" -eq 0 ]]; then
    ok "All $TOTAL nodes are Ready"
  else
    fail "$NOT_READY/$TOTAL nodes not Ready"
    kubectl get nodes --no-headers | grep -v " Ready" || true
  fi

  # 4. Failed/Pending pods
  echo ""
  echo "--- Pod Health ---"
  PROBLEM_PODS=$(kubectl get pods -A --no-headers 2>/dev/null | grep -v -E "Running|Completed|Succeeded" | wc -l)
  if [[ "$PROBLEM_PODS" -eq 0 ]]; then
    ok "All pods healthy"
  else
    warn "$PROBLEM_PODS pods not Running/Completed:"
    kubectl get pods -A --no-headers | grep -v -E "Running|Completed|Succeeded" | head -20
  fi

  # 5. Recent warning events
  echo ""
  echo "--- Recent Warnings ---"
  WARNINGS=$(kubectl get events -A --field-selector type=Warning --no-headers 2>/dev/null | wc -l)
  if [[ "$WARNINGS" -eq 0 ]]; then
    ok "No warning events"
  else
    warn "$WARNINGS warning events in cluster:"
    kubectl get events -A --field-selector type=Warning --sort-by='.lastTimestamp' 2>/dev/null | tail -10
  fi
fi

# 5. Cloud Monitoring — active alerts
echo ""
echo "--- Cloud Monitoring Alerts ---"
ACTIVE_INCIDENTS=$(gcloud alpha monitoring policies list --project "$PROJECT" \
  --format="value(name)" 2>/dev/null | wc -l || echo "0")
info "Alerting policies configured: $ACTIVE_INCIDENTS"
info "Check active incidents: https://console.cloud.google.com/monitoring/alerting?project=$PROJECT"

echo ""
echo "=============================================="
echo " Health check complete — $(date)"
echo "=============================================="
