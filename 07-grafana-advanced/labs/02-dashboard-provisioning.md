# Lab 02: Provision Dashboards via Code

## Overview
Provision a Grafana dashboard as a ConfigMap in Kubernetes. This is the GitOps approach.

## Step 1: Export Dashboard JSON
1. Open your Golden Signals dashboard
2. Dashboard Settings → JSON Model → Copy All
3. Save to file: `dashboards/golden-signals.json`

## Step 2: Create ConfigMap
```bash
kubectl create configmap golden-signals-dashboard \
  --from-file=golden-signals.json=dashboards/golden-signals.json \
  -n monitoring \
  --dry-run=client -o yaml | kubectl apply -f -
```

Or create YAML file:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: golden-signals-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"      # Grafana sidecar watches this label
data:
  golden-signals.json: |
    {
      "__inputs": [],
      "__requires": [],
      "annotations": {"list": []},
      "title": "Service Golden Signals",
      "uid": "golden-signals",
      "panels": []
    }
```

## Step 3: Configure Grafana Sidecar (if using kube-prometheus-stack)
```yaml
# values.yaml for kube-prometheus-stack helm chart
grafana:
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
      labelValue: "1"
      folder: /var/lib/grafana/dashboards
      searchNamespace: ALL      # Watch all namespaces
```

## Step 4: Verify Provisioning
```bash
# Check sidecar picked up the configmap
kubectl logs -n monitoring deploy/grafana -c grafana-sc-dashboard | tail -20

# Verify dashboard exists in Grafana
curl -s http://admin:admin@localhost:3000/api/dashboards/uid/golden-signals | jq .meta.title
```

## Step 5: Update via Git
```bash
# Edit dashboard in Grafana UI → Export → replace JSON in file
git diff dashboards/golden-signals.json   # See what changed
git add dashboards/golden-signals.json
git commit -m "feat(dashboard): add latency heatmap panel"
git push  # CI/CD applies ConfigMap → Grafana auto-reloads
```

## Verification
- [ ] ConfigMap created with grafana_dashboard label
- [ ] Dashboard appears in Grafana within 30s
- [ ] Dashboard title matches ConfigMap data
- [ ] Updating ConfigMap reflects in Grafana
