# Lab 01 — Deploy Production-Grade Prometheus Stack on Kubernetes

## Overview
Deploy `kube-prometheus-stack` with production-aligned configuration on a real Kubernetes cluster
(GKE, on-prem, or a multi-node `kind` cluster for local lab parity).
This lab uses a proper `values.yaml`, persistent storage, RBAC, and secure credential management
— the same patterns used in production SRE environments.

## Prerequisites

| Tool | Min Version | Purpose |
|------|-------------|---------|
| kubectl | 1.27+ | Cluster API |
| helm | 3.12+ | Chart deployment |
| gcloud | latest | GKE auth / credential management |
| kind (optional) | 0.20+ | Local multi-node cluster |

### Option A: GKE cluster (recommended)
```bash
# Authenticate
gcloud auth login
gcloud config set project <PROJECT_ID>
gcloud container clusters get-credentials <CLUSTER_NAME> --zone <ZONE>
kubectl get nodes   # Verify connectivity
```

### Option B: Local lab with kind (production-parity, multi-node)
```bash
# kind mirrors production: multi-node, real CNI, real StorageClass
cat > /tmp/kind-sre-lab.yaml << 'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: sre-lab
nodes:
  - role: control-plane
  - role: worker
  - role: worker
  - role: worker
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
EOF
kind create cluster --config /tmp/kind-sre-lab.yaml
kubectl get nodes   # Expect 1 control-plane + 3 workers
```

---

## Step 1: Prepare Namespace and Secrets

### Create namespace
```bash
kubectl create namespace monitoring
kubectl label namespace monitoring   monitoring=enabled   environment=production
```

### Store Grafana admin password in a Kubernetes Secret — never hardcode in Helm args
```bash
# Generate a strong password
GRAFANA_PASS=$(openssl rand -base64 24)

kubectl create secret generic grafana-admin-credentials   --from-literal=admin-user=admin   --from-literal=admin-password="$GRAFANA_PASS"   --namespace monitoring

echo "Grafana password (save this): $GRAFANA_PASS"
```

### Store Alertmanager credentials (PagerDuty, Slack) as Secrets
```bash
# Replace with real values from your PagerDuty / Slack integrations
kubectl create secret generic alertmanager-secrets   --from-literal=PAGERDUTY_INTEGRATION_KEY="<your-pd-key>"   --from-literal=SLACK_WEBHOOK_URL="https://hooks.slack.com/services/..."   --namespace monitoring
```

---

## Step 2: Create Production Helm Values

Save as `monitoring-values.yaml`:

```yaml
# monitoring-values.yaml — Production-grade kube-prometheus-stack config

## ── Prometheus ────────────────────────────────────────────────────────────
prometheus:
  prometheusSpec:
    ## Retention and storage
    retention: 15d
    retentionSize: 40GB

    ## Persistent storage (requires a StorageClass in your cluster)
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: standard    # Use: gp3 on AWS, pd-ssd on GCP
          resources:
            requests:
              storage: 50Gi

    ## High availability — 2 replicas with anti-affinity
    replicas: 2
    podAntiAffinity: hard

    ## Resource limits (right-size for your load)
    resources:
      requests:
        cpu: 500m
        memory: 2Gi
      limits:
        cpu: 2
        memory: 4Gi

    ## Remote write to long-term storage (Thanos/Mimir)
    # remoteWrite:
    #   - url: https://mimir.company.com/api/v1/push
    #     basicAuth:
    #       username:
    #         name: mimir-credentials
    #         key: username
    #       password:
    #         name: mimir-credentials
    #         key: password

    ## ServiceMonitor selector — scrape all namespaces
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false

## ── Alertmanager ──────────────────────────────────────────────────────────
alertmanager:
  alertmanagerSpec:
    retention: 120h
    replicas: 2
    podAntiAffinity: hard
    resources:
      requests:
        cpu: 100m
        memory: 128Mi

  config:
    global:
      resolve_timeout: 5m
      slack_api_url_file: /etc/alertmanager/secrets/alertmanager-secrets/SLACK_WEBHOOK_URL

    route:
      group_by: [alertname, job, namespace]
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      receiver: slack-sre

      routes:
        - matchers:
            - severity=critical
          receiver: pagerduty-critical
          continue: false

    receivers:
      - name: slack-sre
        slack_configs:
          - channel: '#sre-alerts'
            send_resolved: true
            title: '{{ .GroupLabels.alertname }}'
            text: >-
              {{ range .Alerts }}*{{ .Annotations.summary }}*{{ end }}

      - name: pagerduty-critical
        pagerduty_configs:
          - routing_key_file: /etc/alertmanager/secrets/alertmanager-secrets/PAGERDUTY_INTEGRATION_KEY
            severity: critical
            description: '{{ .GroupLabels.alertname }} — {{ .GroupLabels.namespace }}'

    inhibit_rules:
      - source_matchers: [severity=critical]
        target_matchers: [severity=warning]
        equal: [alertname, namespace]

  ## Mount the credentials secret into Alertmanager
  alertmanagerSpec:
    secrets:
      - alertmanager-secrets

## ── Grafana ────────────────────────────────────────────────────────────────
grafana:
  ## Pull credentials from Secret (not inline values)
  admin:
    existingSecret: grafana-admin-credentials
    userKey: admin-user
    passwordKey: admin-password

  ## Persistence — store dashboards DB on a PVC
  persistence:
    enabled: true
    storageClassName: standard
    size: 10Gi

  ## Resource limits
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

  ## Sidecar — auto-pick up ConfigMap dashboards (GitOps pattern)
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
      labelValue: "1"
      searchNamespace: ALL
    datasources:
      enabled: true
      label: grafana_datasource

  ## Production: expose via Ingress with TLS, not port-forward
  ## Uncomment and set host when deploying to a real cluster with cert-manager:
  # ingress:
  #   enabled: true
  #   ingressClassName: nginx
  #   annotations:
  #     cert-manager.io/cluster-issuer: letsencrypt-prod
  #     nginx.ingress.kubernetes.io/auth-type: basic
  #   hosts:
  #     - grafana.company.com
  #   tls:
  #     - secretName: grafana-tls
  #       hosts:
  #         - grafana.company.com

## ── Node Exporter ──────────────────────────────────────────────────────────
nodeExporter:
  enabled: true

## ── kube-state-metrics ─────────────────────────────────────────────────────
kubeStateMetrics:
  enabled: true

## ── PodDisruptionBudgets — ensure HA during node upgrades ─────────────────
prometheusOperator:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
```

---

## Step 3: Deploy

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values monitoring-values.yaml \
  --wait --timeout=15m

# Verify all pods are Running
kubectl get pods -n monitoring
kubectl get pvc -n monitoring      # Verify PVCs Bound
kubectl get svc -n monitoring
```

Expected output:
```
NAME                                                      READY   STATUS
kube-prometheus-stack-grafana-...                         3/3     Running
kube-prometheus-stack-kube-state-metrics-...              1/1     Running
kube-prometheus-stack-operator-...                        1/1     Running
kube-prometheus-stack-prometheus-node-exporter-...        1/1     Running (per node)
prometheus-kube-prometheus-stack-prometheus-0             2/2     Running
prometheus-kube-prometheus-stack-prometheus-1             2/2     Running  ← HA replica
alertmanager-kube-prometheus-stack-alertmanager-0         2/2     Running
alertmanager-kube-prometheus-stack-alertmanager-1         2/2     Running  ← HA replica
```

---

## Step 4: Access UI

### Production access (Ingress — enable after cert-manager is set up)
```bash
# Check Ingress
kubectl get ingress -n monitoring
# Access: https://grafana.company.com
```

### Local/debugging access (port-forward — temporary only, not production)
```bash
# Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Grafana — retrieve auto-generated password
kubectl get secret -n monitoring kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode; echo
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Alertmanager
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
```

---

## Step 5: Verify Prometheus Scraping

```bash
# Check all scrape targets are UP
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
PF_PID=$!

# Query via API (no UI needed)
curl -sG 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=up' | \
  python3 -m json.tool | grep -E '"job"|"value"' | head -40

# Check node-exporter targets
curl -s 'http://localhost:9090/api/v1/targets' | \
  python3 -m json.tool | grep -E '"job"|"health"' | head -40
```

Key PromQL queries to verify health:
```promql
# All scrape targets — should be 1 (UP)
up

# Node CPU (should show data for all nodes)
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Pod count by namespace
count(kube_pod_info) by (namespace)

# Container memory working set
sum(container_memory_working_set_bytes{container!=""}) by (pod, namespace)
  / 1024 / 1024
```

---

## Step 6: Deploy a Sample App with Custom Metrics

```bash
kubectl apply -f - <<'EOF'
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-metrics-app
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sample-metrics-app
  template:
    metadata:
      labels:
        app: sample-metrics-app
    spec:
      containers:
      - name: app
        image: ghcr.io/prometheus/prometheus:v2.50.1   # exposes /metrics natively
        ports:
        - name: metrics
          containerPort: 9090
        resources:
          requests:
            cpu: 50m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
        readinessProbe:
          httpGet:
            path: /-/ready
            port: 9090
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /-/healthy
            port: 9090
          initialDelaySeconds: 15
          periodSeconds: 30
---
apiVersion: v1
kind: Service
metadata:
  name: sample-metrics-app
  namespace: default
  labels:
    app: sample-metrics-app
spec:
  selector:
    app: sample-metrics-app
  ports:
  - name: metrics
    port: 9090
    targetPort: 9090
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: sample-metrics-app
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  namespaceSelector:
    matchNames: [default]
  selector:
    matchLabels:
      app: sample-metrics-app
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
    honorLabels: true
EOF
```

Verify scraping:
```bash
# Wait ~30s for Prometheus to pick up the ServiceMonitor
kubectl get servicemonitor -n monitoring

# Check target is UP in Prometheus
curl -sG 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=up{job="sample-metrics-app"}' | python3 -m json.tool
```

---

## Step 7: Create a PrometheusRule (Alert)

```bash
kubectl apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: sample-app-alerts
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
  - name: sample-app
    rules:
    - alert: SampleAppDown
      expr: up{job="sample-metrics-app"} == 0
      for: 2m
      labels:
        severity: critical
        team: sre
      annotations:
        summary: "Sample app instance {{ $labels.instance }} is down"
        runbook_url: "https://wiki.company.com/runbooks/sample-app-down"
    - alert: SampleAppHighMemory
      expr: |
        container_memory_working_set_bytes{
          namespace="default",
          pod=~"sample-metrics-app-.*"
        } / 1024 / 1024 > 200
      for: 5m
      labels:
        severity: warning
        team: sre
      annotations:
        summary: "Sample app memory high on {{ $labels.pod }}: {{ $value | printf "%.0f" }}MB"
EOF
```

```bash
# Verify rule is loaded
curl -s 'http://localhost:9090/api/v1/rules' | python3 -m json.tool | grep "SampleApp"
```

---

## Verification Checklist
- [ ] All pods in `monitoring` namespace are Running with 2/2 or 3/3 containers
- [ ] PVCs are `Bound` (persistent storage working)
- [ ] 2 Prometheus replicas, 2 Alertmanager replicas (HA)
- [ ] No hardcoded passwords (credentials are in K8s Secrets)
- [ ] `up` metric shows all node-exporter instances UP
- [ ] ServiceMonitor created and sample-app target is UP in Prometheus
- [ ] PrometheusRule loaded and visible in Prometheus UI → Alerts
- [ ] Grafana pre-built K8s dashboards show real data
