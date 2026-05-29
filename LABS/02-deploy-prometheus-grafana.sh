#!/usr/bin/env bash
set -euo pipefail

# Deploy kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
NAMESPACE=monitoring
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --namespace ${NAMESPACE} --create-namespace --wait

# Port-forward Grafana (local access)
kubectl -n ${NAMESPACE} get deploy | grep grafana || true
echo "To access Grafana: kubectl -n ${NAMESPACE} port-forward svc/monitoring-grafana 3000:80"
