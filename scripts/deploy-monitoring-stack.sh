#!/usr/bin/env bash
# deploy-monitoring-stack.sh — Install kube-prometheus-stack + Loki + Tempo
set -euo pipefail
RED='[0;31m'; GREEN='[0;32m'; YELLOW='[1;33m'; NC='[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

NAMESPACE=${MONITORING_NAMESPACE:-monitoring}
CLUSTER=${KUBECTL_CONTEXT:-$(kubectl config current-context 2>/dev/null || echo "default")}

info "Deploying monitoring stack to namespace: $NAMESPACE (cluster: $CLUSTER)"

# Verify prerequisites
command -v kubectl >/dev/null 2>&1 || error "kubectl not found"
command -v helm >/dev/null 2>&1 || error "helm not found"

kubectl cluster-info >/dev/null 2>&1 || error "Cannot connect to Kubernetes cluster"

# Create namespace
kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"
info "Namespace $NAMESPACE ready"

# Add Helm repos
info "Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update

# Deploy kube-prometheus-stack (Prometheus + Grafana + AlertManager)
info "Installing kube-prometheus-stack..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace "$NAMESPACE" \
  --set grafana.adminPassword=admin123 \
  --set grafana.sidecar.dashboards.enabled=true \
  --set grafana.sidecar.dashboards.label=grafana_dashboard \
  --set prometheus.prometheusSpec.retention=7d \
  --set prometheus.prometheusSpec.retentionSize=10GB \
  --set alertmanager.alertmanagerSpec.retention=120h \
  --wait --timeout=10m

info "kube-prometheus-stack installed"

# Deploy Loki
info "Installing Loki stack..."
helm upgrade --install loki grafana/loki-stack \
  --namespace "$NAMESPACE" \
  --set grafana.enabled=false \
  --set promtail.enabled=true \
  --wait --timeout=5m

info "Loki stack installed"

# Deploy Tempo
info "Installing Grafana Tempo..."
helm upgrade --install tempo grafana/tempo \
  --namespace "$NAMESPACE" \
  --set tempo.storage.trace.backend=local \
  --set tempo.storage.trace.local.path=/var/tempo/traces \
  --wait --timeout=5m

info "Tempo installed"

# Show access info
echo ""
info "====== Deployment Complete ======"
GRAFANA_PORT=3000
echo ""
echo "Access Grafana:"
echo "  kubectl port-forward -n $NAMESPACE svc/kube-prometheus-stack-grafana $GRAFANA_PORT:80"
echo "  URL: http://localhost:$GRAFANA_PORT"
echo "  User: admin / Pass: admin123"
echo ""
echo "Access Prometheus:"
echo "  kubectl port-forward -n $NAMESPACE svc/kube-prometheus-stack-prometheus 9090:9090"
echo ""
echo "Access AlertManager:"
echo "  kubectl port-forward -n $NAMESPACE svc/kube-prometheus-stack-alertmanager 9093:9093"
