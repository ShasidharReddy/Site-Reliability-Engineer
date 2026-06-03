# Lab 02: Dashboard Provisioning and GitOps

## Lab goals

- Export a dashboard JSON model from the Grafana UI.
- Package the dashboard as a Kubernetes ConfigMap and load it with the Grafana sidecar.
- Provision a Prometheus datasource with YAML.
- Define a GitOps workflow so dashboard updates are reviewed and automatically applied.

## File map

| Artifact | Purpose | Suggested path |
| --- | --- | --- |
| Dashboard JSON | Serialized dashboard model | dashboards/service-reliability.json |
| ConfigMap YAML | Makes dashboard available to Grafana sidecar | k8s/grafana-dashboard-configmap.yaml |
| Helm values | Enables the sidecar or sets watch labels | monitoring/values-grafana.yaml |
| Datasource provisioning YAML | Creates stable datasource UIDs | provisioning/datasources/datasources.yaml |

## Prerequisites

- [ ] Grafana is running in Kubernetes or a similar environment with a writable dashboard directory.
- [ ] You can access the Grafana UI and export a dashboard JSON model.
- [ ] Your deployment method supports ConfigMaps and either a sidecar or file mount workflow.
- [ ] You have Git access to the repository that stores dashboard and provisioning manifests.

## Step 1: Export dashboard JSON from the Grafana UI

1. Open the golden signals dashboard created in Lab 01.
2. Choose Share or Dashboard settings -> JSON Model, then export the dashboard JSON.
3. Save the file locally as `dashboards/service-reliability.json`.
4. Review the JSON for stable `uid`, expected `title`, and datasource UIDs rather than local datasource names only.

### Command-line normalization

```bash
mkdir -p dashboards
jq '.title, .uid' dashboards/service-reliability.json
jq 'del(.version)' dashboards/service-reliability.json > dashboards/service-reliability.normalized.json
mv dashboards/service-reliability.normalized.json dashboards/service-reliability.json
```

### Verification

- [ ] The exported JSON contains a stable UID.
- [ ] Datasource references use the intended UID.
- [ ] The JSON loads in a text editor without truncation or binary characters.

## Step 2: Create a ConfigMap for the dashboard

Use either `kubectl create configmap` or commit a declarative YAML file.


### Imperative generation

```bash
kubectl create configmap grafana-dashboard-service-reliability   --namespace monitoring   --from-file=service-reliability.json=dashboards/service-reliability.json   --dry-run=client -o yaml > k8s/grafana-dashboard-configmap.yaml
```

### Declarative YAML

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-service-reliability
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
    app.kubernetes.io/part-of: observability
data:
  service-reliability.json: |
    {
      "title": "Service Reliability",
      "uid": "service-reliability",
      "schemaVersion": 39,
      "panels": []
    }
```

### Why labels matter

- The dashboard sidecar watches for a label such as `grafana_dashboard=1` and copies the JSON payload to a mounted directory.
- If the label does not match the sidecar configuration, Grafana never sees the file even though the ConfigMap exists.
- Keep one consistent label across the platform to simplify operations.

### Verification

- [ ] The ConfigMap exists in the correct namespace.
- [ ] The ConfigMap data key ends in `.json`.
- [ ] The label matches the sidecar watch configuration.

## Step 3: Configure the Grafana sidecar

| Setting | Meaning | Recommended value |
| --- | --- | --- |
| enabled | Turns on automatic dashboard loading | true |
| label | ConfigMap label to watch | grafana_dashboard |
| labelValue | Expected label value | 1 |
| folder | Where dashboard files are mounted | /var/lib/grafana/dashboards |
| searchNamespace | Namespaces to watch | monitoring or ALL |

### Helm values example

```yaml
grafana:
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
      labelValue: "1"
      folder: /var/lib/grafana/dashboards
      searchNamespace: ALL
      provider:
        allowUiUpdates: false
        foldersFromFilesStructure: true
```

### Sidecar log checks

```bash
kubectl logs -n monitoring deploy/grafana -c grafana-sc-dashboard --since=10m
kubectl exec -n monitoring deploy/grafana -c grafana -- ls -R /var/lib/grafana/dashboards
```

### Verification

- [ ] The sidecar container is running.
- [ ] Sidecar logs mention the ConfigMap name and copied dashboard file.
- [ ] The dashboard JSON appears in the Grafana dashboard directory.

## Step 4: Provision the datasource with YAML

- Provision datasources so dashboard JSON can rely on stable UIDs across environments.
- Treat datasource YAML as code alongside dashboard JSON so imports do not break after renaming.

### Datasource provisioning YAML

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    uid: prometheus-main
    type: prometheus
    access: proxy
    url: http://prometheus-operated.monitoring.svc:9090
    isDefault: true
    editable: false
    jsonData:
      timeInterval: 30s
      httpMethod: POST
  - name: Tempo
    uid: tempo-main
    type: tempo
    access: proxy
    url: http://tempo.monitoring.svc:3200
    editable: false
```

### ConfigMap for datasource provisioning

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
  namespace: monitoring
  labels:
    grafana_datasource: "1"
data:
  datasources.yaml: |
    apiVersion: 1
    datasources:
      - name: Prometheus
        uid: prometheus-main
        type: prometheus
        access: proxy
        url: http://prometheus-operated.monitoring.svc:9090
```

### Verification

- [ ] Grafana shows the datasource as provisioned and read-only if desired.
- [ ] The datasource UID matches the dashboard JSON references.
- [ ] A datasource test succeeds from the Grafana UI or API.

## Step 5: Build the GitOps workflow

| Stage | Action | Evidence |
| --- | --- | --- |
| Author | Export JSON and update YAML in a feature branch | Git diff shows only expected dashboard or datasource changes |
| Review | Peer reviews queries, thresholds, titles, and UIDs | Pull request comments and approvals |
| CI | Validate YAML syntax and optionally lint JSON | Pipeline result |
| CD | Apply ConfigMaps and restart or refresh sidecars if needed | kubectl apply output |
| Runtime | Grafana reloads files and displays the updated dashboard | UI and API verification |

### Example GitOps commands

```bash
git checkout -b feat/grafana-service-reliability
cp dashboards/service-reliability.json dashboards/archive/service-reliability.$(date +%Y%m%d).json
kubectl apply --dry-run=client -f k8s/grafana-dashboard-configmap.yaml
kubectl apply --dry-run=client -f provisioning/grafana-datasources-configmap.yaml
git add dashboards/service-reliability.json k8s/grafana-dashboard-configmap.yaml provisioning/grafana-datasources-configmap.yaml
git commit -m "feat(grafana): provision service reliability dashboard"
```

### Pull request checklist

- [ ] UIDs did not change unless a deliberate dashboard replacement is intended.
- [ ] Panel titles and folder names follow platform naming standards.
- [ ] Datasource UIDs exist in every target environment.
- [ ] Any dashboard UI-only edits were exported back to Git before merge.

## Step 6: End-to-end verification

1. Apply the dashboard and datasource ConfigMaps.
2. Watch the sidecar logs for file copy events.
3. Open Grafana and confirm the dashboard appears in the expected folder.
4. Use the API to fetch the dashboard by UID.
5. Change a visible title in Git, re-apply, and verify the UI updates automatically.

### Verification commands

```bash
kubectl apply -f k8s/grafana-dashboard-configmap.yaml
kubectl apply -f provisioning/grafana-datasources-configmap.yaml
kubectl logs -n monitoring deploy/grafana -c grafana-sc-dashboard --since=5m
curl -s -u admin:admin http://localhost:3000/api/dashboards/uid/service-reliability | jq '.dashboard.title'
```

### Final success criteria

- [ ] Dashboard JSON is stored in Git.
- [ ] ConfigMap and datasource provisioning are declarative.
- [ ] Grafana loads the dashboard without manual UI import.
- [ ] A new commit is enough to update the dashboard in the cluster.

## Step 7: Plan rollback and drift control

A GitOps workflow needs a clean rollback path and a way to detect UI drift.

### Rollback checklist

- [ ] Keep the last known good dashboard JSON in Git history or an `archive/` directory.
- [ ] Re-apply the previous ConfigMap manifest if a newly provisioned dashboard breaks rendering.
- [ ] Roll back datasource UID changes separately from dashboard content so you know which layer changed.
- [ ] Capture the failing dashboard UID, folder, and commit SHA before reverting.

### Rollback commands

```bash
git log -- dashboards/service-reliability.json
kubectl rollout status -n monitoring deploy/grafana
kubectl apply -f k8s/grafana-dashboard-configmap.yaml
curl -s -u admin:admin http://localhost:3000/api/dashboards/uid/service-reliability | jq '.dashboard.version'
```

### Drift-control table

| Drift source | Symptom | Control |
| --- | --- | --- |
| UI edits not exported | Grafana differs from Git | Disable UI updates or force export-after-edit |
| Datasource rename | Imported dashboard shows missing datasource | Reference stable datasource UIDs |
| Sidecar label drift | ConfigMap exists but no dashboard reload | Keep label values in a shared Helm value or policy |
| Folder mismatch | Dashboard appears in the wrong place | Standardize provider folder names and org IDs |

### Verification

- [ ] You can revert to a previous dashboard revision in one commit or one `kubectl apply`.
- [ ] The on-call engineer knows where to find the last good JSON artifact.
- [ ] Drift is reviewed during pull requests, not during an incident.

## Appendix: Fast reference

### Reference 1: Verification commands

- Use API calls to validate Grafana state.
- Use `kubectl logs` for sidecar and backend inspection.
- Use `jq` to validate dashboard JSON.

```bash
curl -s -u admin:admin http://localhost:3000/api/health | jq
kubectl logs -n monitoring deploy/grafana --since=5m
jq . dashboards/service-reliability.json > /dev/null
```

### Reference 2: Review checklist

- Titles are stable and descriptive.
- Thresholds and units are explicit.
- UIDs are stable across environments.

```yaml
review:
  dashboard_title: stable
  datasource_uid: prometheus-main
  alert_labels: normalized
```

### Reference 3: Hand-off notes

- Store exported JSON in Git.
- Capture screenshots for incident or change records.
- Record the final verification output.

```json
{
  "owner": "sre",
  "artifact": "dashboard-json",
  "verified": true
}
```
