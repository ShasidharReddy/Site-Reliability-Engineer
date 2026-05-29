#!/usr/bin/env bash
# deploy-monitoring-stack.sh
# Deploy production-aligned monitoring stack: kube-prometheus-stack + Loki + Tempo
# Target: GKE, on-prem, or multi-node kind cluster
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

NAMESPACE=${MONITORING_NAMESPACE:-monitoring}
CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
CHART_VERSION_PROM=${PROM_STACK_VERSION:-"65.1.1"}   # kube-prometheus-stack
CHART_VERSION_LOKI=${LOKI_VERSION:-"6.6.2"}
CHART_VERSION_TEMPO=${TEMPO_VERSION:-"1.7.2"}

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║      SRE Monitoring Stack Deployment             ║"
echo "╚══════════════════════════════════════════════════╝"
info "Cluster context : $CONTEXT"
info "Namespace       : $NAMESPACE"
info "kube-prom-stack : v${CHART_VERSION_PROM}"
echo ""

# ── Pre-flight checks ──────────────────────────────────────────────────────
command -v kubectl >/dev/null 2>&1 || error "kubectl not found"
command -v helm    >/dev/null 2>&1 || error "helm not found"
kubectl cluster-info >/dev/null 2>&1 || error "Cannot connect to cluster. Run bootstrap-lab.sh first."

NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
info "Cluster nodes: $NODE_COUNT"
if (( NODE_COUNT < 2 )); then
    warn "Single-node cluster detected."
    warn "For production labs (HA Prometheus/Alertmanager), use 3+ nodes."
    warn "Continuing with single-replica overrides..."
    HA=false
else
    HA=true
fi

# ── Namespace and secrets ──────────────────────────────────────────────────
kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 \
    || kubectl create namespace "$NAMESPACE"
kubectl label namespace "$NAMESPACE" monitoring=enabled --overwrite

# Generate Grafana admin password and store in Secret (not in Helm values)
if ! kubectl get secret grafana-admin-credentials -n "$NAMESPACE" >/dev/null 2>&1; then
    GRAFANA_PASS=$(openssl rand -base64 24 | tr -d '/=+')
    kubectl create secret generic grafana-admin-credentials \
        --from-literal=admin-user=admin \
        --from-literal=admin-password="$GRAFANA_PASS" \
        -n "$NAMESPACE"
    ok "Created Grafana admin credentials (Secret: grafana-admin-credentials)"
    echo ""
    warn "▶  Save this password — you won't see it again:"
    echo "   Username: admin"
    echo "   Password: $GRAFANA_PASS"
    echo ""
else
    info "Grafana secret already exists — skipping creation"
fi

# Create Alertmanager placeholder secret if not present
if ! kubectl get secret alertmanager-secrets -n "$NAMESPACE" >/dev/null 2>&1; then
    kubectl create secret generic alertmanager-secrets \
        --from-literal=PAGERDUTY_INTEGRATION_KEY="REPLACE_WITH_REAL_KEY" \
        --from-literal=SLACK_WEBHOOK_URL="REPLACE_WITH_REAL_URL" \
        -n "$NAMESPACE"
    warn "Created placeholder alertmanager-secrets — update with real PD/Slack keys:"
    warn "  kubectl edit secret alertmanager-secrets -n $NAMESPACE"
fi

# ── Helm repos ─────────────────────────────────────────────────────────────
info "Updating Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add grafana              https://grafana.github.io/helm-charts              2>/dev/null || true
helm repo update >/dev/null

# ── Build Helm values ──────────────────────────────────────────────────────
PROM_REPLICAS=2
AM_REPLICAS=2
PROM_ANTI_AFFINITY=hard
if [ "$HA" = false ]; then
    PROM_REPLICAS=1
    AM_REPLICAS=1
    PROM_ANTI_AFFINITY=soft
    warn "Single-node: setting replicas=1, podAntiAffinity=soft"
fi

VALUES_FILE=$(mktemp /tmp/prom-stack-values-XXXX.yaml)
cat > "$VALUES_FILE" << HELMVALUES
prometheus:
  prometheusSpec:
    retention: 15d
    retentionSize: 40GB
    replicas: ${PROM_REPLICAS}
    podAntiAffinity: "${PROM_ANTI_AFFINITY}"
    storageSpec:
      volumeClaimTemplate:
        spec:
          resources:
            requests:
              storage: 50Gi
    resources:
      requests:
        cpu: 500m
        memory: 2Gi
      limits:
        cpu: "2"
        memory: 4Gi
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false

alertmanager:
  alertmanagerSpec:
    retention: 120h
    replicas: ${AM_REPLICAS}
    podAntiAffinity: "${PROM_ANTI_AFFINITY}"
    secrets:
      - alertmanager-secrets
    resources:
      requests:
        cpu: 100m
        memory: 128Mi

grafana:
  admin:
    existingSecret: grafana-admin-credentials
    userKey: admin-user
    passwordKey: admin-password
  persistence:
    enabled: true
    size: 10Gi
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
      labelValue: "1"
      searchNamespace: ALL
    datasources:
      enabled: true
      label: grafana_datasource

nodeExporter:
  enabled: true

kubeStateMetrics:
  enabled: true
HELMVALUES

# ── Deploy kube-prometheus-stack ───────────────────────────────────────────
info "Deploying kube-prometheus-stack v${CHART_VERSION_PROM}..."
helm upgrade --install kube-prometheus-stack \
    prometheus-community/kube-prometheus-stack \
    --version "$CHART_VERSION_PROM" \
    --namespace "$NAMESPACE" \
    --values "$VALUES_FILE" \
    --wait --timeout=15m

ok "kube-prometheus-stack deployed"
rm -f "$VALUES_FILE"

# ── Deploy Loki stack ──────────────────────────────────────────────────────
info "Deploying Loki + Promtail v${CHART_VERSION_LOKI}..."
helm upgrade --install loki grafana/loki-stack \
    --version "$CHART_VERSION_LOKI" \
    --namespace "$NAMESPACE" \
    --set grafana.enabled=false \
    --set promtail.enabled=true \
    --set loki.persistence.enabled=true \
    --set loki.persistence.size=10Gi \
    --wait --timeout=10m

ok "Loki stack deployed"

# ── Deploy Tempo ───────────────────────────────────────────────────────────
info "Deploying Grafana Tempo v${CHART_VERSION_TEMPO}..."
helm upgrade --install tempo grafana/tempo \
    --version "$CHART_VERSION_TEMPO" \
    --namespace "$NAMESPACE" \
    --set tempo.storage.trace.backend=local \
    --set tempo.storage.trace.local.path=/var/tempo/traces \
    --wait --timeout=5m

ok "Tempo deployed"

# ── Final status ───────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║            Deployment Complete                   ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
kubectl get pods -n "$NAMESPACE" --no-headers | \
    awk '{printf "  %-55s %s\n", $1, $3}'

echo ""
echo "── Access ──────────────────────────────────────────"
echo ""
echo "  Production (Ingress): configure ingress.enabled=true in Helm values"
echo "  after installing cert-manager and an Ingress controller."
echo ""
echo "  Local debug (port-forward — temporary access only):"
echo ""
echo "  Grafana:"
echo "    kubectl port-forward -n $NAMESPACE svc/kube-prometheus-stack-grafana 3000:80"
echo "    # Password:"
echo "    kubectl get secret grafana-admin-credentials -n $NAMESPACE \\"
echo "      -o jsonpath='{.data.admin-password}' | base64 --decode; echo"
echo ""
echo "  Prometheus:"
echo "    kubectl port-forward -n $NAMESPACE svc/kube-prometheus-stack-prometheus 9090:9090"
echo ""
echo "  Alertmanager:"
echo "    kubectl port-forward -n $NAMESPACE svc/kube-prometheus-stack-alertmanager 9093:9093"
echo ""
echo "  Tempo:"
echo "    kubectl port-forward -n $NAMESPACE svc/tempo 3200:3200"
echo ""
warn "Update alertmanager-secrets with real PagerDuty/Slack credentials:"
echo "  kubectl edit secret alertmanager-secrets -n $NAMESPACE"
echo ""
