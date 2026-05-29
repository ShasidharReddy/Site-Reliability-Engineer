# GCP Operations — Theory

## 1. GCP Resource Hierarchy

```
Organization (company.com)
└── Folders (optional grouping)
    ├── Production
    │   └── Projects
    │       ├── prod-api-123
    │       └── prod-data-456
    └── Development
        └── Projects
            └── dev-api-789
```

**IAM inherits down**: permissions granted at Org level apply to all projects.
**Best practice**: grant minimum permissions at the lowest level needed.

---

## 2. GCP IAM

### 2.1 Service Accounts
```bash
# Create a service account
gcloud iam service-accounts create my-sre-sa \
  --display-name="SRE Service Account" \
  --project=my-project

# Grant roles
gcloud projects add-iam-policy-binding my-project \
  --member="serviceAccount:my-sre-sa@my-project.iam.gserviceaccount.com" \
  --role="roles/monitoring.viewer"

# List service accounts
gcloud iam service-accounts list --project=my-project
```

### 2.2 Workload Identity (Secure K8s → GCP Auth)
- **Why**: Avoid mounting service account JSON keys into pods (security risk)
- **How**: K8s Service Account → GCP Service Account binding via IAM

```bash
# Enable Workload Identity on GKE cluster
gcloud container clusters update my-cluster \
  --workload-pool=my-project.svc.id.goog \
  --zone us-central1-a

# Bind K8s SA to GCP SA
gcloud iam service-accounts add-iam-policy-binding \
  my-gcp-sa@my-project.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:my-project.svc.id.goog[namespace/k8s-sa-name]"
```

### 2.3 Key Roles for SRE
| Role | Description |
|------|-------------|
| `roles/monitoring.admin` | Full Cloud Monitoring access |
| `roles/monitoring.viewer` | Read-only metrics and dashboards |
| `roles/logging.viewer` | Read-only log access |
| `roles/logging.admin` | Create log sinks, metrics |
| `roles/container.viewer` | Read-only GKE access |
| `roles/container.developer` | Deploy to GKE clusters |
| `roles/container.admin` | Full GKE admin |
| `roles/compute.viewer` | View Compute Engine resources |

---

## 3. GCP Networking

### 3.1 VPC Architecture
```
VPC (global)
├── Subnet us-central1 (10.0.0.0/24)
├── Subnet us-east1 (10.0.1.0/24)
└── Subnet europe-west1 (10.0.2.0/24)
```

Key concepts:
- VPCs are **global** (unlike AWS, subnets can be in any region within one VPC)
- **Private Google Access**: allows VMs without public IPs to reach Google APIs
- **Cloud NAT**: outbound internet for private VMs (no inbound)
- **VPC Peering**: connect two VPCs (not transitive — A↔B and B↔C does NOT mean A↔C)
- **Shared VPC**: one host project's VPC shared with service projects

### 3.2 Firewall Rules
```bash
# Allow HTTPS inbound to web tier
gcloud compute firewall-rules create allow-https \
  --network=my-vpc \
  --allow=tcp:443 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=web

# Allow internal traffic
gcloud compute firewall-rules create allow-internal \
  --network=my-vpc \
  --allow=tcp:0-65535,udp:0-65535,icmp \
  --source-ranges=10.0.0.0/8

# List firewall rules
gcloud compute firewall-rules list --filter="network=my-vpc"
```

---

## 4. Cloud Monitoring

### 4.1 Alerting Policies
```bash
# Create an uptime check
gcloud monitoring uptime-checks create http my-api-check \
  --display-name="API Health Check" \
  --http-check-path="/health" \
  --hostname=api.example.com \
  --port=443 \
  --use-ssl

# Create alerting policy (via YAML)
gcloud monitoring policies create --policy-from-file=alert-policy.json
```

**Alert Policy JSON example**:
```json
{
  "displayName": "High Error Rate",
  "conditions": [{
    "displayName": "HTTP 5xx rate > 1%",
    "conditionThreshold": {
      "filter": "metric.type="loadbalancing.googleapis.com/https/request_count" AND metric.labels.response_code_class="500"",
      "comparison": "COMPARISON_GT",
      "thresholdValue": 0.01,
      "duration": "300s",
      "aggregations": [{
        "alignmentPeriod": "60s",
        "crossSeriesReducer": "REDUCE_MEAN",
        "perSeriesAligner": "ALIGN_RATE"
      }]
    }
  }],
  "alertStrategy": {
    "autoClose": "1800s"
  }
}
```

### 4.2 Key GCP Metrics for SRE
```
# GKE
kubernetes.io/container/cpu/core_usage_time
kubernetes.io/container/memory/used_bytes
kubernetes.io/node/cpu/allocatable_utilization
kubernetes.io/pod/volume/used_bytes

# Cloud Load Balancing
loadbalancing.googleapis.com/https/request_count
loadbalancing.googleapis.com/https/backend_latencies
loadbalancing.googleapis.com/https/total_latencies

# Cloud SQL
cloudsql.googleapis.com/database/cpu/utilization
cloudsql.googleapis.com/database/memory/utilization
cloudsql.googleapis.com/database/disk/bytes_used

# Pub/Sub (for data pipeline SLOs)
pubsub.googleapis.com/subscription/num_undelivered_messages
pubsub.googleapis.com/subscription/oldest_unacked_message_age
```

---

## 5. Cloud Logging

### 5.1 Log Types
| Log Type | Source | Retention |
|----------|--------|-----------|
| Admin Activity | GCP API calls (create/delete) | 400 days (free) |
| Data Access | GCP API read/write operations | 30 days (configurable) |
| System Event | Google-generated events | 400 days (free) |
| Access Transparency | Google staff access | 400 days |
| Platform logs | GKE, GCE, etc. | Configurable |

### 5.2 Log Explorer Queries (Logging Query Language)
```
# All errors in last hour
severity>=ERROR

# Specific service errors
resource.type="k8s_container"
resource.labels.namespace_name="production"
severity=ERROR

# HTTP 5xx errors
httpRequest.status>=500

# Specific error message
textPayload:"connection refused"

# JSON log field
jsonPayload.level="error"
jsonPayload.service="api-gateway"

# Time range
timestamp>="2024-01-01T00:00:00Z" AND timestamp<="2024-01-01T01:00:00Z"
```

### 5.3 Log-Based Metrics
```bash
# Create a counter metric for 5xx errors
gcloud logging metrics create http_5xx_errors \
  --description="Count of HTTP 5xx errors" \
  --log-filter='resource.type="gce_instance" httpRequest.status>=500'

# Then alert on this metric in Cloud Monitoring
```

### 5.4 Log Sinks (Export)
```bash
# Export logs to BigQuery for analysis
gcloud logging sinks create bq-error-logs \
  bigquery.googleapis.com/projects/my-project/datasets/logs \
  --log-filter='severity>=ERROR'

# Export to GCS for archival
gcloud logging sinks create gcs-audit-logs \
  storage.googleapis.com/my-audit-logs-bucket \
  --log-filter='logName:"cloudaudit.googleapis.com"'
```

---

## 6. GKE Operations

### 6.1 Cluster Health Checks
```bash
# Check cluster status
gcloud container clusters describe my-cluster --zone us-central1-a \
  --format="table(name,status,currentMasterVersion,currentNodeVersion)"

# List node pools
gcloud container node-pools list --cluster my-cluster --zone us-central1-a

# Check node status
kubectl get nodes -o wide
kubectl describe nodes | grep -E "Conditions:|Ready|MemoryPressure|DiskPressure"

# Check system pods
kubectl get pods -n kube-system
```

### 6.2 GKE Logging (managed)
```bash
# GKE automatically ships logs to Cloud Logging
# View container logs
gcloud logging read \
  'resource.type="k8s_container" resource.labels.namespace_name="production"' \
  --limit=50 \
  --format="table(timestamp,jsonPayload.message)"
```

### 6.3 GKE Managed Prometheus
```bash
# Enable managed collection
gcloud container clusters update my-cluster \
  --enable-managed-prometheus \
  --zone us-central1-a

# Deploy a PodMonitoring resource
kubectl apply -f - <<'EOF'
apiVersion: monitoring.googleapis.com/v1
kind: PodMonitoring
metadata:
  name: my-app-monitoring
  namespace: production
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
  - port: metrics
    interval: 30s
EOF
```
