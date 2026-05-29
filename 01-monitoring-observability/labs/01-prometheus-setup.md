# Lab 01 — Deploy Prometheus Stack on Kubernetes

## Overview
Deploy the `kube-prometheus-stack` Helm chart on minikube and explore built-in dashboards.

## Prerequisites
- minikube ≥ 1.30, kubectl ≥ 1.27, helm ≥ 3.12
- 4 CPU, 8GB RAM available for minikube

## Steps

### 1. Start minikube cluster
```bash
minikube start --cpus=4 --memory=8192 --driver=docker
kubectl cluster-info
kubectl get nodes
```
Expected: 1 node in Ready state.

### 2. Add Helm repositories
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

### 3. Create monitoring namespace and deploy stack
```bash
kubectl create namespace monitoring

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set prometheus.prometheusSpec.retention=7d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=10Gi \
  --set grafana.adminPassword=admin123 \
  --set alertmanager.enabled=true \
  --wait --timeout=10m
```

### 4. Verify deployment
```bash
kubectl get pods -n monitoring
# Expected: prometheus, grafana, alertmanager, node-exporter, kube-state-metrics all Running

kubectl get svc -n monitoring
```

### 5. Access Prometheus UI
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
open http://localhost:9090
```

Try these queries in Prometheus UI:
```promql
# Node CPU usage
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Pod count by namespace
count(kube_pod_info) by (namespace)

# Container memory usage
sum(container_memory_working_set_bytes{container!=""}) by (pod) / 1024 / 1024
```

### 6. Access Grafana
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &
open http://localhost:3000
# Login: admin / admin123
```

Explore pre-built dashboards:
- "Kubernetes / Cluster" — overall cluster health
- "Kubernetes / Nodes" — per-node metrics  
- "Kubernetes / Pods" — per-pod CPU/memory

### 7. Deploy a sample app with /metrics endpoint
```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      containers:
      - name: app
        image: prom/prometheus:latest
        ports:
        - containerPort: 9090
EOF
```

### 8. Create a ServiceMonitor for the sample app
```bash
kubectl apply -f - <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: sample-app-monitor
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: sample-app
  namespaceSelector:
    matchNames:
      - default
  endpoints:
  - port: http
    interval: 15s
    path: /metrics
EOF
```

## Verification
```bash
# Check targets in Prometheus UI → Status → Targets
# Should see sample-app targets in UP state

# Query in Prometheus
curl -s 'http://localhost:9090/api/v1/query?query=up{job="sample-app"}' | python3 -m json.tool
```

## Cleanup
```bash
helm uninstall kube-prometheus-stack -n monitoring
minikube stop
```
