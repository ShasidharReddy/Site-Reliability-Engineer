# GCP Operations Troubleshooting Guide

## How to use this guide

This guide is written for active incident response.
Each section starts with observable symptoms.
Then it lists high-signal commands.
Then it ends with the most likely fixes and verification steps.
The emphasis is on GKE, IAM, Monitoring, and Logging issues that SREs see repeatedly.

## Quick triage rules

Before deep-diving any issue:

- confirm the correct project, cluster, and region
- confirm the time window of the incident
- capture current state before making changes
- prefer reversible changes first
- verify the fix with metrics or workload behavior after remediation

Useful baseline variables:

```bash
export PROJECT_ID="YOUR_PROJECT_ID"
export CLUSTER_NAME="prod-cluster"
export LOCATION="us-central1"
export NODE_POOL="primary-pool"
export NAMESPACE="payments"
export POD_NAME="payments-api-abc123"
```

---

## 1. GKE node not joining cluster

### Symptoms

- a new node is expected during scale-up or upgrade but never appears as Ready
- `gcloud container operations list` shows a long-running node pool operation
- workloads remain Pending because capacity is not increasing
- the node count in the Managed Instance Group does not match Kubernetes node count

### First commands to run

```bash
gcloud container node-pools describe "$NODE_POOL" \
  --cluster="$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID"
```

```bash
gcloud container operations list \
  --project="$PROJECT_ID" \
  --filter="TARGET:${CLUSTER_NAME}"
```

```bash
kubectl get nodes -o wide
kubectl get events -A --sort-by=.lastTimestamp | tail -30
```

```bash
gcloud compute instance-groups managed list --filter="name~gke-${CLUSTER_NAME}"
```

### Likely causes

- subnet or pod IP range exhaustion
- quota exhaustion for CPUs, addresses, or disks
- image pull or bootstrap failure on the new node
- firewall or network path issue preventing node registration
- node service account or metadata access problem
- cluster upgrade or auto-repair operation blocked mid-flight

### Detailed checks

Check the cluster network configuration:

```bash
gcloud container clusters describe "$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --format='yaml(networkConfig,subnetwork,ipAllocationPolicy)'
```

Check project quota pressure:

```bash
gcloud compute project-info describe --project="$PROJECT_ID"
```

Check recent warning logs:

```bash
gcloud logging read 'resource.type="gke_nodepool" OR resource.type="gce_instance"' \
  --project="$PROJECT_ID" \
  --limit=50 \
  --freshness=2h
```

### Fixes

If the pod or node IP range is exhausted:

- expand secondary ranges where architecture allows
- add additional pod ranges if supported for the cluster
- reduce unnecessary node or pod density temporarily

If quota is exhausted:

- request quota increase
- lower surge settings temporarily if safe
- stop non-critical scale-outs in the same region

If firewall rules are blocking bootstrap:

- verify required egress to Google APIs and registry endpoints
- verify private cluster and NAT design

If one broken node instance is stuck:

- review the instance serial logs
- recreate the affected node or allow the node pool to replace it

### Verification

```bash
kubectl get nodes -o wide
kubectl get pods -A --field-selector=status.phase=Pending
```

The incident is resolved when:

- the new node joins as `Ready`
- Pending workloads start scheduling
- node pool operation completes successfully

---

## 2. GKE pods can't access GCP APIs

### Symptoms

- application logs show `403`, `permission denied`, or token errors against Google APIs
- pods can run and serve traffic internally but fail on GCP-dependent actions
- Pub/Sub publish, Cloud Storage access, or Secret Manager reads fail only from inside GKE

### First commands to run

```bash
kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o yaml | grep serviceAccountName -n
kubectl get serviceaccount -n "$NAMESPACE"
```

```bash
gcloud container clusters describe "$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --format='value(workloadIdentityConfig.workloadPool)'
```

```bash
kubectl describe serviceaccount "$KSA_NAME" -n "$NAMESPACE"
```

```bash
gcloud iam service-accounts get-iam-policy "${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
```

### Likely causes

- Workload Identity is not enabled on the cluster
- the pod is running under the wrong Kubernetes Service Account
- the KSA annotation points to the wrong Google Service Account
- the GSA lacks the required IAM role
- the IAM binding for `roles/iam.workloadIdentityUser` is missing or malformed
- the target API is not enabled in the project

### Detailed checks

Verify the annotation:

```bash
kubectl get serviceaccount "$KSA_NAME" -n "$NAMESPACE" -o yaml
```

Verify the binding member syntax:

```bash
gcloud iam service-accounts get-iam-policy \
  "${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --format=json
```

Verify the workload identity token path from inside the pod:

```bash
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- gcloud auth list
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- curl -H 'Metadata-Flavor: Google' http://metadata.google.internal
```

### Fixes

If Workload Identity is disabled:

```bash
gcloud container clusters update "$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --workload-pool="${PROJECT_ID}.svc.id.goog"
```

If the GSA trust binding is missing:

```bash
gcloud iam service-accounts add-iam-policy-binding \
  "${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role='roles/iam.workloadIdentityUser' \
  --member="serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${KSA_NAME}]"
```

If the KSA annotation is wrong:

```bash
kubectl annotate serviceaccount "$KSA_NAME" \
  -n "$NAMESPACE" \
  iam.gke.io/gcp-service-account="${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --overwrite
```

If the GSA lacks permissions:

```bash
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role='roles/pubsub.publisher'
```

### Verification

```bash
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- gcloud pubsub topics list --project="$PROJECT_ID"
```

The incident is resolved when the pod can call the required API successfully without a mounted JSON key.

---

## 3. Cloud Monitoring alert not firing

### Symptoms

- dashboard shows degradation but no alert incident opens
- uptime check fails in charts but no notification arrives
- alert exists but never leaves `OK` state
- notifications work for other policies but not this one

### First commands to run

Review the policy definition in the console or API.
Then validate the metric and filter independently.

```bash
gcloud monitoring uptime list-configs --project="$PROJECT_ID"
```

```bash
gcloud beta monitoring channels list --project="$PROJECT_ID"
```

```bash
gcloud logging read 'severity>=ERROR' --project="$PROJECT_ID" --limit=10
```

### Likely causes

- the alert condition filter does not match the intended resource labels
- the aligner or reducer is wrong for the metric type
- the threshold is unrealistic for the current data shape
- the policy has no valid notification channel IDs attached
- the metric has no data in the selected time window
- the alert duration or trigger count is too strict

### Detailed checks

Use Metrics Explorer or dashboard queries to verify the exact metric name.
Compare:

- resource type
- metric type
- label filters
- alignment period
- threshold direction

For uptime-based alerts, confirm the uptime check itself exists and is returning data.
For log-based metrics, confirm the underlying log filter matches current log shape.

### Fixes

If the filter is wrong:

- remove over-specific labels first
- confirm data appears
- add labels back one by one

If alignment is wrong:

- use `ALIGN_DELTA` for counters where appropriate
- use `ALIGN_RATE` for rate views
- use `ALIGN_MEAN` or `ALIGN_MAX` based on the symptom you want to detect

If channels are missing or disabled:

```bash
gcloud beta monitoring channels list \
  --project="$PROJECT_ID" \
  --format='table(name,displayName,type,enabled)'
```

Recreate or reattach the correct channel IDs to the policy.

If the problem is simply that the condition never becomes true:

- lower the threshold in a test project
- deliberately trigger the symptom in a safe environment
- confirm incident creation end to end

### Verification

The issue is resolved when:

- the policy condition matches real metric data
- a controlled test opens an incident
- notifications arrive on every intended channel

---

## 4. Log sink not forwarding logs

### Symptoms

- the sink exists, but BigQuery tables remain empty
- the Pub/Sub subscription sees no messages
- the GCS archive bucket receives no new objects
- Log Explorer shows matching logs, but the export destination is empty

### First commands to run

```bash
gcloud logging sinks list --project="$PROJECT_ID"
```

```bash
gcloud logging sinks describe sre-errors-bq --project="$PROJECT_ID"
```

```bash
gcloud logging read 'severity>=ERROR' --project="$PROJECT_ID" --limit=20
```

### Likely causes

- the sink filter does not match the logs you expect
- the destination path is wrong
- the sink writer identity lacks permission on the destination
- the sink is disabled
- the verification window is too short and no matching logs have been emitted yet

### Detailed checks

Inspect the filter carefully.
A single bad resource type or typo in `logName` is enough to export nothing.

Check the sink state:

```bash
gcloud logging sinks describe sre-errors-bq \
  --project="$PROJECT_ID" \
  --format='yaml(name,destination,filter,disabled,writerIdentity)'
```

For BigQuery, verify dataset permissions.
For Cloud Storage, verify the sink SA can create objects.
For Pub/Sub, verify the sink SA has publisher rights.

### Fixes

If the writer identity is missing permissions:

- BigQuery: grant `roles/bigquery.dataEditor` on the dataset
- GCS: grant `roles/storage.objectCreator` on the bucket
- Pub/Sub: grant `roles/pubsub.publisher` on the topic

If the filter is too narrow:

- test with `severity>=ERROR`
- verify data appears
- then refine the filter safely

If the sink is disabled:

```bash
gcloud logging sinks update sre-errors-bq \
  --project="$PROJECT_ID" \
  --no-disabled
```

### Verification

The issue is resolved when:

- newly generated matching logs appear at the destination
- the sink remains enabled
- writer IAM is documented and reproducible

---

## 5. Workload Identity permission denied

### Symptoms

- pod authentication works, but API calls still fail with `permission denied`
- `gcloud auth list` inside the pod shows the expected identity
- the workload can reach Google APIs but lacks authorization to perform the action

### First commands to run

```bash
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- gcloud auth list
```

```bash
gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten='bindings[].members' \
  --filter="bindings.members:serviceAccount:${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --format='table(bindings.role,bindings.members)'
```

### Likely causes

- the GSA does not have the required role
- the application is calling a different project than expected
- the role exists, but the permission needed is not in that role
- an IAM condition blocks the request context
- an org policy or deny policy prevents the action

### Detailed checks

Confirm which project the workload targets.
A surprising number of failures happen because the identity is correct but the API call is sent to a different project.

Review recent IAM changes:

```bash
gcloud logging read '
logName="projects/'"$PROJECT_ID"'/logs/cloudaudit.googleapis.com%2Factivity"
protoPayload.methodName="SetIamPolicy"
' \
  --project="$PROJECT_ID" \
  --limit=20
```

Check if a conditional binding exists on the relevant role.

### Fixes

Grant the exact missing role or permission.
If a predefined role is too broad, create a minimal custom role.
If the request targets the wrong project, correct the application configuration rather than broadening IAM.
If a deny policy is blocking the action, involve the central security or platform owner before changing it.

### Verification

Re-run the exact failing API call from the pod.
The issue is resolved when the action succeeds with the intended least-privilege identity and without broadening access unnecessarily.

---

## 6. GKE node pool upgrade stuck

### Symptoms

- node pool upgrade starts but does not complete
- some nodes are upgraded while others remain old
- workloads stay Pending or drain operations stall
- maintenance operation runs much longer than expected

### First commands to run

```bash
gcloud container operations list \
  --project="$PROJECT_ID" \
  --filter="TARGET:${CLUSTER_NAME}"
```

```bash
gcloud container node-pools describe "$NODE_POOL" \
  --cluster="$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --format='yaml(version,management,upgradeSettings,statusMessage)'
```

```bash
kubectl get pdb -A
kubectl get nodes -L cloud.google.com/gke-nodepool
kubectl get pods -A -o wide
```

### Likely causes

- PodDisruptionBudgets are too strict
- surge settings require quota that is unavailable
- workloads have no spare replicas
- a node cannot drain because of unmanaged or unhealthy pods
- zonal capacity is constrained
- autoscaler or node health issues are interfering with progress

### Detailed checks

Look for evictions blocked by PDBs.
Look for single-replica stateful workloads.
Look for insufficient quota to create surge nodes.
Look for nodes stuck `SchedulingDisabled` with remaining critical pods.

### Fixes

If PDBs are too strict:

- temporarily relax the PDB if the service owner agrees
- increase replica count first
- retry drain or upgrade

If surge capacity is missing:

- raise regional quota
- lower `max-surge-upgrade` if business risk allows
- reduce competing scale-outs in the same region

If unmanaged pods block drain:

- identify the owning controller
- replace singleton or static workloads with managed replicas where possible
- use careful manual eviction only after impact review

If the node pool is unhealthy:

- pause further risky changes
- review node and cluster events
- consider opening a vendor support case if the managed operation itself is stuck after workload blockers are removed

### Verification

```bash
gcloud container operations list --project="$PROJECT_ID"
kubectl get nodes -L cloud.google.com/gke-nodepool
```

The issue is resolved when:

- all nodes in the pool reach the target version
- workloads stay healthy during and after the upgrade
- no blocked drain events remain

---

## Closing guidance

Most GCP operations incidents are not caused by one broken command.
They are caused by a mismatch between design assumptions and runtime reality.
Use these sections as a triage starting point.
Then update your runbooks with environment-specific details after every real incident.
