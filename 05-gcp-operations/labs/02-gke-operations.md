# Lab 02: GKE Operations

## Cluster Health Check
```bash
gcloud container clusters list --project=$PROJECT_ID
gcloud container clusters describe <cluster> --zone=<zone>

# Node pool status
gcloud container node-pools list --cluster=<cluster> --zone=<zone>
```

## Node Upgrades
```bash
# Check current version
gcloud container clusters describe <cluster> --format='value(currentMasterVersion,currentNodeVersion)'

# List available versions
gcloud container get-server-config --zone=<zone> | grep validMasterVersions

# Upgrade master
gcloud container clusters upgrade <cluster> --master --cluster-version=1.29

# Upgrade node pool (surge upgrade)
gcloud container node-pools update <pool> \
  --cluster=<cluster> \
  --zone=<zone> \
  --max-surge-upgrade=1 \
  --max-unavailable-upgrade=0
```

## Workload Identity Setup
```bash
# Enable on existing cluster
gcloud container clusters update <cluster> \
  --workload-pool=$PROJECT_ID.svc.id.goog

# Create K8s SA
kubectl create serviceaccount my-app-sa -n default

# Bind to GCP SA
gcloud iam service-accounts add-iam-policy-binding \
  my-app@$PROJECT_ID.iam.gserviceaccount.com \
  --role=roles/iam.workloadIdentityUser \
  --member="serviceAccount:$PROJECT_ID.svc.id.goog[default/my-app-sa]"

# Annotate K8s SA
kubectl annotate serviceaccount my-app-sa \
  iam.gke.io/gcp-service-account=my-app@$PROJECT_ID.iam.gserviceaccount.com
```

## Node Drain for Maintenance
```bash
# Get nodes
kubectl get nodes

# Cordon (stop new pods)
kubectl cordon <node>

# Drain (evict existing pods, respect PDB)
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data

# After maintenance: uncordon
kubectl uncordon <node>
```

## Verification
- [ ] Cluster health checked via gcloud
- [ ] Node pool upgrade completed without pod downtime
- [ ] Workload Identity configured for a service
