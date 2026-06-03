# Lab 01 — Production-Grade Prometheus Setup on Kubernetes

## Overview

In this lab you will deploy `kube-prometheus-stack`, validate Prometheus internals, add a custom `ServiceMonitor`, configure `remote_write`, and intentionally create a high-cardinality failure so you can recognize and fix it.

By the end of the lab you should be able to:

- verify cluster prerequisites before installation
- deploy `kube-prometheus-stack` with production-oriented values
- inspect scrape targets, TSDB health, WAL behavior, and scrape intervals
- onboard a custom application with `ServiceMonitor`
- configure `remote_write` to Thanos backed by GCS
- identify and reduce high-cardinality damage
- validate the full monitoring stack with CLI commands

---

## Lab Topology

```text
Kubernetes cluster
   │
   ├── kube-prometheus-stack
   │    ├── Prometheus Operator
   │    ├── Prometheus (2 replicas)
   │    ├── Alertmanager (2 replicas)
   │    ├── Grafana
   │    ├── node-exporter
   │    └── kube-state-metrics
   │
   ├── custom demo app
   │    └── /metrics
   │
   └── Thanos Receive
        └── GCS bucket for long-term metrics
```

---

## Prerequisites

| Requirement | Recommended Version | Why It Matters |
|---|---|---|
| Kubernetes | 1.27+ | Modern CRDs and API compatibility |
| `kubectl` | 1.27+ | Cluster access |
| `helm` | 3.12+ | Chart deployment |
| `promtool` | latest Prometheus release | Rule and config validation |
| `jq` | latest | API output parsing |
| `gcloud` | latest if using GKE/GCS | Auth and bucket access |

### Prerequisites Check

Run these checks before changing anything:

```bash
kubectl version --short
helm version
promtool --version
kubectl cluster-info
kubectl get nodes -o wide
kubectl get storageclass
kubectl auth can-i create namespaces
kubectl auth can-i create customresourcedefinitions.apiextensions.k8s.io
```

Expected outcomes:

- cluster is reachable
- at least one default `StorageClass` exists
- you have enough permissions to deploy CRDs and StatefulSets
- worker nodes have enough spare CPU and memory

### Capacity Guidance

For a realistic lab, aim for at least:

- 3 worker nodes or equivalent capacity
- 4 vCPU total available for monitoring components
- 10-20 GiB free storage for Prometheus PVCs

---

## Step 1 — Prepare Namespace and Secrets

```bash
kubectl create namespace monitoring
kubectl label namespace monitoring monitoring=enabled environment=lab --overwrite
```

Create Grafana admin credentials:

```bash
GRAFANA_PASS=$(openssl rand -base64 24)

kubectl create secret generic grafana-admin-credentials \
  --namespace monitoring \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$GRAFANA_PASS"
```

Create secrets for Alertmanager and Thanos remote write:

```bash
kubectl create secret generic alertmanager-secrets \
  --namespace monitoring \
  --from-literal=SLACK_WEBHOOK_URL='https://hooks.slack.com/services/REPLACE/ME' \
  --from-literal=PAGERDUTY_INTEGRATION_KEY='replace-with-real-key'

kubectl create secret generic thanos-remote-write \
  --namespace monitoring \
  --from-literal=username='thanos-user' \
  --from-literal=password='replace-with-real-password'
```

Verify:

```bash
kubectl get secrets -n monitoring
```

---

## Step 2 — Create Production Values

Save the following as `./kube-prometheus-stack-values.yaml` in this module directory when running the lab.

```yaml
prometheus:
  service:
    type: ClusterIP

  prometheusSpec:
    replicas: 2
    retention: 15d
    retentionSize: 80GB
    scrapeInterval: 30s
    evaluationInterval: 30s
    walCompression: true
    enableAdminAPI: false
    externalLabels:
      cluster: sre-lab
      environment: training

    resources:
      requests:
        cpu: 1000m
        memory: 4Gi
      limits:
        cpu: 2
        memory: 8Gi

    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: standard
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 100Gi

    podAntiAffinity: hard
    ruleSelectorNilUsesHelmValues: false
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    probeSelectorNilUsesHelmValues: false

    remoteWrite:
      - url: https://thanos-receive.example.com/api/v1/receive
        name: thanos-primary
        remoteTimeout: 30s
        basicAuth:
          username:
            name: thanos-remote-write
            key: username
          password:
            name: thanos-remote-write
            key: password
        queueConfig:
          capacity: 25000
          minShards: 4
          maxShards: 32
          maxSamplesPerSend: 5000
          batchSendDeadline: 5s
          minBackoff: 100ms
          maxBackoff: 5s
        metadataConfig:
          send: true
          sendInterval: 1m
        writeRelabelConfigs:
          - sourceLabels: [__name__]
            regex: 'go_.+|process_.+'
            action: keep

    additionalScrapeConfigs:
      - job_name: blackbox-http
        metrics_path: /probe
        params:
          module: [http_2xx]
        static_configs:
          - targets:
              - https://example.com/health
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - source_labels: [__param_target]
            target_label: instance
          - target_label: __address__
            replacement: blackbox-exporter.monitoring.svc:9115

alertmanager:
  alertmanagerSpec:
    replicas: 2
    retention: 120h
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: standard
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 10Gi
    podAntiAffinity: hard
    secrets:
      - alertmanager-secrets

  config:
    global:
      resolve_timeout: 5m
      slack_api_url_file: /etc/alertmanager/secrets/alertmanager-secrets/SLACK_WEBHOOK_URL

    route:
      receiver: slack-general
      group_by: [alertname, cluster, namespace, service]
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      routes:
        - matchers:
            - severity="critical"
          receiver: pagerduty-critical
          continue: true
        - matchers:
            - severity="critical"
          receiver: slack-critical
        - matchers:
            - team="platform"
          receiver: slack-platform

    receivers:
      - name: slack-general
        slack_configs:
          - channel: '#sre-alerts'
            send_resolved: true
            title: '{{ .GroupLabels.alertname }}'
            text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'

      - name: slack-critical
        slack_configs:
          - channel: '#sre-critical'
            send_resolved: true
            color: danger
            title: 'CRITICAL: {{ .GroupLabels.alertname }}'
            text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'

      - name: slack-platform
        slack_configs:
          - channel: '#platform-alerts'
            send_resolved: true
            title: '{{ .GroupLabels.alertname }}'
            text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'

      - name: pagerduty-critical
        pagerduty_configs:
          - routing_key_file: /etc/alertmanager/secrets/alertmanager-secrets/PAGERDUTY_INTEGRATION_KEY
            send_resolved: true
            severity: critical
            description: '{{ .GroupLabels.alertname }} in {{ .CommonLabels.cluster }}'

    inhibit_rules:
      - source_matchers: [severity="critical"]
        target_matchers: [severity="warning"]
        equal: [alertname, cluster, namespace]

grafana:
  admin:
    existingSecret: grafana-admin-credentials
    userKey: admin-user
    passwordKey: admin-password

  persistence:
    enabled: true
    storageClassName: standard
    size: 20Gi

  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 1
      memory: 1Gi

  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
      labelValue: "1"
      searchNamespace: ALL
    datasources:
      enabled: true
      label: grafana_datasource

prometheusOperator:
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 1
      memory: 1Gi

kubeStateMetrics:
  enabled: true

nodeExporter:
  enabled: true
```

### Why These Values Matter

- `replicas: 2` improves availability
- `walCompression: true` reduces disk usage
- `retention` and `retentionSize` bound local TSDB growth
- `remoteWrite` sends long-term data to Thanos
- `podAntiAffinity` prevents both replicas landing on one node
- `externalLabels` make cross-cluster queries easier

---

## Step 3 — Install `kube-prometheus-stack`

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values ./kube-prometheus-stack-values.yaml \
  --wait \
  --timeout 20m
```

Watch the rollout:

```bash
kubectl get pods -n monitoring -w
```

Base validation:

```bash
kubectl get all -n monitoring
kubectl get pvc -n monitoring
kubectl get prometheus,alertmanager -n monitoring
kubectl get servicemonitors,podmonitors,prometheusrules -n monitoring | head
```

Expected components:

- Prometheus Operator
- Prometheus StatefulSet with two pods
- Alertmanager StatefulSet with two pods
- Grafana Deployment
- node-exporter on every node
- kube-state-metrics

---

## Step 4 — Access Prometheus and Grafana

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

In another terminal:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Fetch Grafana password if needed:

```bash
kubectl get secret grafana-admin-credentials -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 --decode && echo
```

---

## Step 5 — Verify Targets and Scrape Health

### Check Target Status from the API

```bash
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health, lastScrape: .lastScrape}'
```

### Check `up`

```bash
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=up' | jq '.data.result[] | {job: .metric.job, instance: .metric.instance, value: .value[1]}'
```

### Useful Validation Queries

```promql
up
count(up == 0) by (job)
prometheus_target_scrape_pool_targets
scrape_duration_seconds{job="kubernetes-service-endpoints"}
scrape_samples_post_metric_relabeling
```

### Verify Scrape Interval and Timeout Behavior

```promql
prometheus_target_interval_length_seconds{quantile="0.99"}
prometheus_target_scrape_pool_sync_total
prometheus_target_scrapes_exceeded_sample_limit_total
```

Interpretation:

- interval distribution should match your configured `scrapeInterval`
- scrape duration must stay well below timeout
- sample limit or body-size errors indicate bad targets or too much telemetry

---

## Step 6 — Verify TSDB Health, WAL, and Retention

Prometheus must be monitored like any other production service.

### TSDB Health Queries

```promql
prometheus_tsdb_head_series
prometheus_tsdb_head_chunks
prometheus_tsdb_symbol_table_size_bytes
prometheus_tsdb_compactions_total
prometheus_tsdb_compaction_duration_seconds_bucket
```

### WAL Queries

```promql
prometheus_tsdb_wal_segment_current
prometheus_tsdb_wal_fsync_duration_seconds_bucket
prometheus_tsdb_wal_completed_pages_total
prometheus_tsdb_wal_truncations_failed_total
```

### Query Retention-Related Metrics

```promql
prometheus_tsdb_storage_blocks_bytes
prometheus_tsdb_retention_limit_bytes
prometheus_tsdb_lowest_timestamp_seconds
```

### Prometheus Runtime Checks

```bash
kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  sh -c 'wget -qO- http://localhost:9090/api/v1/status/runtimeinfo'

kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- \
  sh -c 'wget -qO- http://localhost:9090/api/v1/status/config'
```

What to look for:

- WAL segment count should grow steadily, not explosively
- compactions should happen without repeated failures
- `head_series` should remain within planned capacity
- retention values should match your Helm settings

---

## Step 7 — Add a Custom App with `ServiceMonitor`

Deploy a demo application that exposes Prometheus metrics.

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-metrics-app
  namespace: observability-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo-metrics-app
  template:
    metadata:
      labels:
        app: demo-metrics-app
    spec:
      containers:
        - name: demo
          image: quay.io/brancz/prometheus-example-app:v0.5.0
          ports:
            - name: web
              containerPort: 8080
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
---
apiVersion: v1
kind: Namespace
metadata:
  name: observability-demo
---
apiVersion: v1
kind: Service
metadata:
  name: demo-metrics-app
  namespace: observability-demo
  labels:
    app: demo-metrics-app
spec:
  selector:
    app: demo-metrics-app
  ports:
    - name: web
      port: 8080
      targetPort: web
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: demo-metrics-app
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  namespaceSelector:
    matchNames: [observability-demo]
  selector:
    matchLabels:
      app: demo-metrics-app
  endpoints:
    - port: web
      path: /metrics
      interval: 15s
      scrapeTimeout: 10s
      honorLabels: false
      metricRelabelings:
        - sourceLabels: [instance]
          regex: '(.+):8080'
          targetLabel: instance
          replacement: '$1'
EOF
```

Validation:

```bash
kubectl get ns observability-demo
kubectl get pods,svc -n observability-demo
kubectl get servicemonitor -n monitoring demo-metrics-app -o yaml
```

Prometheus checks:

```promql
up{job=~".*demo-metrics-app.*"}
sum(rate(http_requests_total{job=~".*demo-metrics-app.*"}[5m]))
```

API validation:

```bash
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=up{job=~".*demo-metrics-app.*"}' | jq
```

---

## Step 8 — Configure `remote_write` to Thanos with GCS Backing

Prometheus does **not** write directly to GCS.
The usual production path is:

```text
Prometheus -> remote_write -> Thanos Receive -> object storage (GCS)
```

### Thanos/GCS Architecture Reminder

- Prometheus sends remote-write traffic to **Thanos Receive**
- Thanos stores blocks in **GCS**
- Thanos Query exposes a global read path

### Optional Secret for GCS in Thanos

The GCS credential is typically mounted in the Thanos side, not Prometheus.
Example for Thanos components:

```yaml
type: GCS
config:
  bucket: sre-observability-metrics
  service_account: |
    {
      "type": "service_account",
      "project_id": "example-project",
      "private_key_id": "replace-me",
      "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
      "client_email": "thanos-sa@example-project.iam.gserviceaccount.com"
    }
```

### Validate `remote_write`

PromQL queries:

```promql
prometheus_remote_storage_samples_pending
prometheus_remote_storage_samples_total
prometheus_remote_storage_failed_samples_total
prometheus_remote_storage_shards{remote_name="thanos-primary"}
prometheus_remote_storage_highest_timestamp_in_seconds
```

Expected behavior:

- pending samples remain low and stable
- failed samples stay at zero
- shard count scales up during burst traffic and then settles

### CLI Checks

```bash
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=prometheus_remote_storage_failed_samples_total' | jq

curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=prometheus_remote_storage_samples_pending' | jq
```

---

## Step 9 — Test a High-Cardinality Failure

This step is intentionally destructive from a telemetry perspective.
Do it in a lab only.

### Example Bad Metric Pattern

Imagine an app exposes this metric:

```text
checkout_requests_total{request_id="ab12cd34ef56",user_id="998877",path="/users/998877/orders/123"}
```

That label set creates a new series for nearly every request.

### What to Observe

Watch these metrics before and after generating bad traffic:

```promql
prometheus_tsdb_head_series
prometheus_tsdb_head_chunks
prometheus_tsdb_symbol_table_size_bytes
prometheus_tsdb_head_samples_appended_total
```

### Demo Query for Noisy Labels

```promql
topk(20, count by (__name__)({__name__=~".+"}))
count by (path) (http_requests_total)
count by (request_id) (checkout_requests_total)
```

### Remediation Options

1. fix instrumentation so labels are bounded
2. normalize paths to route templates
3. drop dynamic labels with `metricRelabelings`
4. aggregate with recording rules before exporting remotely

Example `metricRelabelings` fix:

```yaml
endpoints:
  - port: web
    path: /metrics
    metricRelabelings:
      - sourceLabels: [request_id]
        regex: '.+'
        action: labeldrop
      - sourceLabels: [user_id]
        regex: '.+'
        action: labeldrop
```

### Validate the Fix

After dropping the labels, re-check:

```promql
prometheus_tsdb_head_series
count by (request_id) (checkout_requests_total)
```

You should see:

- head series growth flattening out
- dynamic labels no longer queryable because they were removed
- query latency returning to normal

---

## Step 10 — Validation Commands Checklist

Use these commands as your final operational checklist.

### Kubernetes Validation

```bash
kubectl get pods -n monitoring
kubectl get pvc -n monitoring
kubectl get prometheus,alertmanager -n monitoring -o wide
kubectl top pods -n monitoring
```

### Prometheus API Validation

```bash
curl -s http://localhost:9090/api/v1/targets | jq '.status'
curl -s http://localhost:9090/api/v1/rules | jq '.status'
curl -s http://localhost:9090/api/v1/status/runtimeinfo | jq '.status'
curl -s http://localhost:9090/api/v1/alerts | jq '.status'
```

### PromQL Validation Set

```promql
up
prometheus_tsdb_head_series
prometheus_tsdb_wal_segment_current
prometheus_engine_query_duration_seconds_count
prometheus_remote_storage_failed_samples_total
sum(rate(http_requests_total[5m])) by (job)
```

### Rule Validation

```bash
promtool check rules ./example-rules.yaml
```

---

## Common Errors

### Error: Prometheus pod stays `Pending`

Possible causes:

- no default `StorageClass`
- requested PVC size too large
- anti-affinity cannot be satisfied

Diagnosis:

```bash
kubectl describe pod -n monitoring prometheus-kube-prometheus-stack-prometheus-0
kubectl get events -n monitoring --sort-by=.lastTimestamp | tail -20
```

### Error: Targets stay `DOWN`

Possible causes:

- wrong port name in `ServiceMonitor`
- app not exposing `/metrics`
- namespace selector mismatch
- TLS or auth issue

Diagnosis:

```bash
kubectl get servicemonitor -A
kubectl describe servicemonitor demo-metrics-app -n monitoring
kubectl get endpoints -n observability-demo demo-metrics-app -o yaml
```

### Error: WAL or compaction metrics spike

Possible causes:

- very high sample ingestion
- disk IO bottleneck
- label explosion

Diagnosis:

```promql
prometheus_tsdb_wal_fsync_duration_seconds_bucket
prometheus_tsdb_compaction_duration_seconds_bucket
prometheus_tsdb_head_series
```

### Error: `remote_write` backlog grows forever

Possible causes:

- Thanos Receive unavailable
- auth failure
- queue too small
- too much outbound volume

Diagnosis:

```promql
prometheus_remote_storage_samples_pending
prometheus_remote_storage_failed_samples_total
prometheus_remote_storage_retried_samples_total
```

### Error: Prometheus memory keeps rising

Possible causes:

- high cardinality
- too many active targets
- too-short scrape intervals

Diagnosis:

```promql
prometheus_tsdb_head_series
count(up) by (job)
prometheus_target_scrape_pool_targets
```

---

## Final Validation

You have completed this lab successfully when all of the following are true:

- [ ] `kube-prometheus-stack` components are healthy
- [ ] Prometheus targets are mostly `UP`
- [ ] TSDB and WAL metrics are readable and make sense
- [ ] a custom `ServiceMonitor` is scraping a demo app
- [ ] `remote_write` metrics show successful export behavior
- [ ] you can detect and explain a high-cardinality problem
- [ ] you know which Prometheus self-metrics to watch in production
