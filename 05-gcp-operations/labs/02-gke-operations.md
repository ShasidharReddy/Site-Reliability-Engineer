# Lab 02: Advanced GKE Operations

## Lab goals

This lab focuses on day-2 GKE operations.
You will connect `kubectl` to a cluster.
You will inspect cluster health and node pool status.
You will configure upgrade strategy with surge settings.
You will enable Workload Identity and validate a pod-to-GCP access path.
You will review maintenance windows.
You will enable node auto-repair and auto-upgrade.
You will export and update a Binary Authorization policy.

## Outcomes

By the end of the lab you should be able to:

- connect to a GKE cluster safely
- assess control plane and node pool state
- plan a node pool upgrade with minimal disruption
- implement Workload Identity for a workload
- configure maintenance windows and exclusions
- understand Binary Authorization rollout basics
- confirm auto-repair and auto-upgrade posture

## Prerequisites

- a GCP project with GKE API enabled
- a Standard or Autopilot cluster for exploration
- `gcloud`, `kubectl`, and `curl` installed locally
- IAM permissions for GKE, IAM, and Binary Authorization
- a namespace where you can deploy a test workload

## Environment variables

```bash
export PROJECT_ID="YOUR_PROJECT_ID"
export CLUSTER_NAME="prod-cluster"
export LOCATION="us-central1"
export NODE_POOL="primary-pool"
export NAMESPACE="payments"
export KSA_NAME="payments-api"
export GSA_NAME="payments-api"
```

## Step 1: set the project and verify APIs

```bash
gcloud config set project "$PROJECT_ID"

gcloud services enable \
  container.googleapis.com \
  containeranalysis.googleapis.com \
  binaryauthorization.googleapis.com \
  iam.googleapis.com
```

## Step 2: inspect available clusters

```bash
gcloud container clusters list \
  --project="$PROJECT_ID" \
  --format='table(name,location,status,currentMasterVersion,releaseChannel.channel)'
```

Look for:

- cluster status is `RUNNING`
- cluster location matches what you expect
- release channel is documented
- master version is within your support policy

## Step 3: connect `kubectl` to the cluster

For a regional cluster:

```bash
gcloud container clusters get-credentials "$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID"
```

For a zonal cluster, use `--zone` instead.
If the cluster is private and you need the internal endpoint, use `--internal-ip` where appropriate.

## Step 4: confirm current Kubernetes context

```bash
kubectl config current-context
kubectl cluster-info
kubectl get ns
```

A surprising number of production mistakes happen because the operator is pointed at the wrong cluster.
Always verify context before any upgrade or drain operation.

## Step 5: inspect cluster health from GKE control plane metadata

```bash
gcloud container clusters describe "$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --format='yaml(name,location,status,releaseChannel,currentMasterVersion,currentNodeVersion,autoscaling,networkConfig,workloadIdentityConfig,maintenancePolicy)'
```

Review:

- release channel
- current master version
- current node version
- Workload Identity setting
- maintenance policy
- whether the cluster is VPC-native

## Step 6: inspect cluster health from Kubernetes itself

```bash
kubectl get nodes -o wide
kubectl get pods -n kube-system
kubectl get events -A --sort-by=.lastTimestamp | tail -20
```

Healthy clusters usually show:

- nodes in `Ready`
- core system pods running
- no flood of warning events

## Step 7: inspect node pool state

```bash
gcloud container node-pools list \
  --cluster="$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --format='table(name,status,version,config.machineType,autoscaling.enabled,management.autoRepair,management.autoUpgrade)'
```

If you run multiple pools, document which workloads live on which pool.
That mapping is essential during upgrades and incidents.

## Step 8: describe a single node pool in detail

```bash
gcloud container node-pools describe "$NODE_POOL" \
  --cluster="$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --format='yaml(name,status,version,config.machineType,config.diskSizeGb,management,upgradeSettings,autoscaling,locations)'
```

Review:

- node version
- machine type
- auto-repair and auto-upgrade settings
- surge upgrade settings
- autoscaling bounds

## Step 9: check version skew and available upgrades

```bash
gcloud container get-server-config \
  --location="$LOCATION" \
  --project="$PROJECT_ID"
```

Before upgrading:

- compare current master and node versions
- confirm target version is valid in the chosen channel
- avoid skipping too many versions without a test plan

## Step 10: inspect workload disruption posture

Before any node upgrade, inspect the workloads that will be moved.

```bash
kubectl get deploy,statefulset,daemonset -A
kubectl get pdb -A
kubectl get hpa -A
```

You care about:

- single-replica workloads
- strict PodDisruptionBudgets
- workloads without readiness probes
- workloads pinned to one zone or one node pool

## Step 11: document node pool upgrade strategy

Use surge upgrades for production pools whenever possible.
They reduce disruption by creating temporary replacement capacity.
A common safe pattern is:

- `max-surge-upgrade=1` or `2`
- `max-unavailable-upgrade=0`

This costs temporary capacity during the rollout.
Plan quota and budget accordingly.

## Step 12: configure surge upgrade settings

```bash
gcloud container node-pools update "$NODE_POOL" \
  --cluster="$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --enable-surge-upgrade \
  --max-surge-upgrade=2 \
  --max-unavailable-upgrade=0
```

## Step 13: enable auto-repair and auto-upgrade on the node pool

```bash
gcloud container node-pools update "$NODE_POOL" \
  --cluster="$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --enable-autorepair

gcloud container node-pools update "$NODE_POOL" \
  --cluster="$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --enable-autoupgrade
```

## Step 14: verify management settings

```bash
gcloud container node-pools describe "$NODE_POOL" \
  --cluster="$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --format='yaml(management,upgradeSettings)'
```

If these fields do not reflect your changes, re-check the target pool and project.
Operators often update the wrong node pool during busy maintenance windows.

## Step 15: plan a controlled node pool upgrade

A good upgrade plan includes:

- target version
- business impact window
- surge settings
- rollback or halt criteria
- workload owner notification
- success metrics
- watch commands during rollout

Useful watch commands:

```bash
watch -n 20 'kubectl get nodes -o wide'
```

```bash
watch -n 20 'kubectl get pods -A --field-selector=status.phase!=Running'
```

## Step 16: initiate a node pool upgrade

```bash
gcloud container node-pools upgrade "$NODE_POOL" \
  --cluster="$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --cluster-version=TARGET_GKE_VERSION
```

Replace `TARGET_GKE_VERSION` with a valid version from `get-server-config`.
During the upgrade, keep one terminal on `kubectl get nodes` and another on workload health metrics.

## Step 17: validate node pool upgrade progress

```bash
gcloud container operations list \
  --project="$PROJECT_ID" \
  --filter="TARGET:${CLUSTER_NAME}"

kubectl get nodes -L cloud.google.com/gke-nodepool
kubectl get pods -A -o wide
```

Confirm:

- new nodes join successfully
- workloads reschedule cleanly
- no unexpected CrashLoopBackOff events appear
- PDBs are not blocking progress indefinitely

## Step 18: inspect maintenance window settings

```bash
gcloud container clusters describe "$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --format='yaml(maintenancePolicy)'
```

Maintenance windows matter because auto-upgrades and other managed changes should happen when risk is lowest.
They are not a substitute for safe workload design.

## Step 19: set a recurring maintenance window

```bash
gcloud container clusters update "$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --maintenance-window-start=2025-01-05T02:00:00Z \
  --maintenance-window-end=2025-01-05T06:00:00Z \
  --maintenance-window-recurrence='FREQ=WEEKLY;BYDAY=SA,SU'
```

## Step 20: set a temporary maintenance exclusion

Use this during freeze periods such as a large release or major holiday.

```bash
gcloud container clusters update "$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --add-maintenance-exclusion-name=peak-season-freeze \
  --add-maintenance-exclusion-start=2025-11-20T00:00:00Z \
  --add-maintenance-exclusion-end=2025-12-02T23:59:59Z \
  --add-maintenance-exclusion-scope=no_upgrades
```

Do not overuse exclusions.
Too many freeze windows create version drift and increase future risk.

## Step 21: enable Workload Identity on the cluster

If the cluster already has Workload Identity enabled, this command is idempotent for your planning purposes.

```bash
gcloud container clusters update "$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --workload-pool="${PROJECT_ID}.svc.id.goog"
```

## Step 22: create the Kubernetes namespace and service account

```bash
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create serviceaccount "$KSA_NAME" -n "$NAMESPACE"
```

## Step 23: create the Google service account

```bash
gcloud iam service-accounts create "$GSA_NAME" \
  --project="$PROJECT_ID" \
  --display-name='Payments API GSA'
```

## Step 24: grant a sample permission to the GSA

For this lab, Pub/Sub publisher is a simple example.
Use only the permissions your workload actually needs.

```bash
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role='roles/pubsub.publisher'
```

## Step 25: allow the KSA to impersonate the GSA

```bash
gcloud iam service-accounts add-iam-policy-binding \
  "${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="$PROJECT_ID" \
  --role='roles/iam.workloadIdentityUser' \
  --member="serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${KSA_NAME}]"
```

## Step 26: annotate the Kubernetes service account

```bash
kubectl annotate serviceaccount "$KSA_NAME" \
  -n "$NAMESPACE" \
  iam.gke.io/gcp-service-account="${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --overwrite
```

## Step 27: deploy a test workload that uses the KSA

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: wi-test
  namespace: payments
spec:
  serviceAccountName: payments-api
  containers:
    - name: test
      image: google/cloud-sdk:slim
      command: ["/bin/sh", "-c"]
      args:
        - "gcloud auth list && sleep 3600"
```

Apply it:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: wi-test
  namespace: payments
spec:
  serviceAccountName: payments-api
  containers:
    - name: test
      image: google/cloud-sdk:slim
      command: ["/bin/sh", "-c"]
      args:
        - "gcloud auth list && sleep 3600"
EOF
```

## Step 28: validate Workload Identity from inside the pod

```bash
kubectl exec -n "$NAMESPACE" wi-test -- gcloud auth list
kubectl exec -n "$NAMESPACE" wi-test -- gcloud pubsub topics list --project="$PROJECT_ID"
```

If the second command succeeds, the identity path is working.
If it fails, check cluster workload pool, KSA annotation, IAM binding, and API enablement.

## Step 29: inspect Binary Authorization policy

Before changing policy, export the current state.
That gives you a baseline and a rollback artifact.

```bash
gcloud container binauthz policy export > binauthz-policy.yaml
cat binauthz-policy.yaml
```

## Step 30: understand a simple Binary Authorization policy structure

A typical policy includes:

- global evaluation mode
- default admission rule
- allowlist patterns if any
- attestor requirements for trusted images

A gradual rollout pattern is:

- start in observation or permissive mode where appropriate
- validate image provenance from the build pipeline
- enforce on production namespaces or projects only after tests pass

## Step 31: example Binary Authorization policy snippet

```yaml
defaultAdmissionRule:
  evaluationMode: REQUIRE_ATTESTATION
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
  requireAttestationsBy:
    - projects/YOUR_PROJECT_ID/attestors/prod-build-attestor
globalPolicyEvaluationMode: ENABLE
name: projects/YOUR_PROJECT_ID/policy
```

## Step 32: import an updated Binary Authorization policy

```bash
gcloud container binauthz policy import binauthz-policy.yaml --strict-validation
```

Do this only after your build system can produce the required attestations.
Otherwise you may block deployments unexpectedly.

## Step 33: confirm cluster posture after policy work

```bash
gcloud container clusters describe "$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --format='yaml(name,binaryAuthorization,workloadIdentityConfig,maintenancePolicy)'
```

## Step 34: inspect cluster and workload events one more time

```bash
kubectl get events -A --sort-by=.lastTimestamp | tail -30
kubectl get pods -A
kubectl get nodes
```

This closes the loop between control-plane configuration and runtime health.
The best GKE operators always re-check workload state after platform changes.

## Operational review prompts

Use these questions during the lab review:

- was the correct cluster targeted from the start
- do node pools have a documented purpose
- are upgrade settings aligned with workload criticality
- do workloads have PDBs and readiness probes
- is Workload Identity enabled and keyless
- is Binary Authorization rolled out with a safe adoption plan
- do maintenance windows match business risk windows

## Verification checklist

- [ ] `kubectl` connected to the intended GKE cluster
- [ ] cluster health inspected with `gcloud` and `kubectl`
- [ ] node pool health and management settings reviewed
- [ ] surge upgrade strategy configured
- [ ] node auto-repair enabled
- [ ] node auto-upgrade enabled
- [ ] maintenance window configured or reviewed
- [ ] maintenance exclusion understood and tested in plan form
- [ ] Workload Identity configured for a sample workload
- [ ] Binary Authorization policy exported and reviewed

## Cleanup

If this was a test environment, remove the sample pod and optional namespace after validation.

```bash
kubectl delete pod wi-test -n "$NAMESPACE" --ignore-not-found
kubectl delete serviceaccount "$KSA_NAME" -n "$NAMESPACE" --ignore-not-found
```

Do not delete the namespace or service account in production unless you have confirmed nothing depends on them.
