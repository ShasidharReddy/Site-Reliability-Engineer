# Lab 03: Advanced IAM and Access Operations

## Lab goals

This lab focuses on identity hygiene for SRE environments.
You will audit project IAM.
You will identify over-privileged principals.
You will create a minimal custom role.
You will compare service account keys to Workload Identity.
You will configure Workload Identity for a GKE workload.
You will create IAM conditions.
You will review audit logs for IAM-related changes.

## Target outcomes

By the end of the lab you should be able to:

- read and reason about project IAM policies
- detect risky `owner`, `editor`, and broad admin grants
- define a minimal custom role for a specific operational purpose
- understand why static service account keys are risky
- implement Workload Identity instead of keys for GKE
- create time-based and resource-based IAM conditions
- query Cloud Audit Logs for IAM events

## Prerequisites

- a GCP project with IAM and Logging APIs enabled
- a GKE cluster for the Workload Identity section
- `gcloud`, `kubectl`, and `jq` installed locally
- enough permissions to read and update IAM policies

## Environment variables

```bash
export PROJECT_ID="YOUR_PROJECT_ID"
export CLUSTER_NAME="prod-cluster"
export LOCATION="us-central1"
export NAMESPACE="payments"
export KSA_NAME="payments-api"
export GSA_NAME="payments-runtime"
export TEMP_GROUP="incident-admins@example.com"
```

## Step 1: set the project and enable APIs

```bash
gcloud config set project "$PROJECT_ID"

gcloud services enable \
  iam.googleapis.com \
  cloudresourcemanager.googleapis.com \
  logging.googleapis.com \
  container.googleapis.com
```

## Step 2: capture the full project IAM policy

```bash
gcloud projects get-iam-policy "$PROJECT_ID" \
  --format=json > project-iam-policy.json

jq '.bindings | length' project-iam-policy.json
```

Always take a baseline before cleanup work.
This gives you a rollback artifact and a reviewable snapshot.

## Step 3: view IAM policy in a table

```bash
gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten='bindings[].members' \
  --format='table(bindings.role,bindings.members)'
```

Look for:

- roles granted directly to users instead of groups
- service accounts with broad admin access
- production roles assigned to personal accounts
- unexpected external identities

## Step 4: specifically search for primitive roles

```bash
gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten='bindings[].members' \
  --format='table(bindings.role,bindings.members)' | grep -E 'roles/owner|roles/editor|roles/viewer' || true
```

Interpret carefully:

- `viewer` may be acceptable in some cases
- `editor` is usually too broad
- `owner` should be rare and tightly controlled

## Step 5: identify service accounts with broad roles

```bash
gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten='bindings[].members' \
  --format='table(bindings.role,bindings.members)' | grep 'serviceAccount:' || true
```

Then ask:

- does the service account still exist
- does it still serve an active workload
- is the role aligned to the workload purpose
- can the role be narrowed to a predefined or custom role

## Step 6: list all service accounts in the project

```bash
gcloud iam service-accounts list \
  --project="$PROJECT_ID" \
  --format='table(email,displayName,disabled)'
```

This inventory is the starting point for access cleanup.
It also helps map service accounts to runtime systems and owners.

## Step 7: detect user-managed service account keys

```bash
for sa in $(gcloud iam service-accounts list --project="$PROJECT_ID" --format='value(email)'); do
  gcloud iam service-accounts keys list \
    --iam-account="$sa" \
    --managed-by=user \
    --format='table(name,validAfterTime,validBeforeTime,keyType)'
done
```

If any user-managed keys appear, document:

- owner
- purpose
- consuming system
- rotation status
- decommission plan

## Step 8: compare service account keys vs Workload Identity

Use this table during the review.

| Attribute | Service account key | Workload Identity |
|---|---|---|
| Credential type | long-lived file | short-lived federated token |
| Rotation burden | high | low |
| Leak risk | high | much lower |
| Audit clarity | weaker | stronger |
| Best use in GKE | avoid | preferred |
| Revocation model | revoke key and redeploy dependents | adjust IAM binding or KSA mapping |

For GKE workloads, prefer Workload Identity unless a specific unsupported edge case exists.

## Step 9: create a custom role definition for log export operators

This example grants only the permissions needed to manage log sinks and log-based metrics.

```yaml
title: LogExportOperator
description: Manage log sinks and log metrics without broad project admin rights.
stage: GA
includedPermissions:
  - logging.sinks.create
  - logging.sinks.get
  - logging.sinks.list
  - logging.sinks.update
  - logging.metrics.create
  - logging.metrics.get
  - logging.metrics.list
  - logging.metrics.update
  - resourcemanager.projects.get
```

## Step 10: create the custom role file

```bash
cat > custom-role.yaml <<'EOF'
title: LogExportOperator
description: Manage log sinks and log metrics without broad project admin rights.
stage: GA
includedPermissions:
  - logging.sinks.create
  - logging.sinks.get
  - logging.sinks.list
  - logging.sinks.update
  - logging.metrics.create
  - logging.metrics.get
  - logging.metrics.list
  - logging.metrics.update
  - resourcemanager.projects.get
EOF
```

## Step 11: create the custom role

```bash
gcloud iam roles create logExportOperator \
  --project="$PROJECT_ID" \
  --file=custom-role.yaml
```

## Step 12: inspect the custom role

```bash
gcloud iam roles describe logExportOperator \
  --project="$PROJECT_ID"
```

Review whether the role is too broad or too narrow.
Custom roles should be specific enough to matter but stable enough to maintain.

## Step 13: create a limited service account for the custom role

```bash
gcloud iam service-accounts create log-exporter \
  --project="$PROJECT_ID" \
  --display-name='Log Export Operator Identity'
```

## Step 14: grant the custom role to the service account

```bash
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:log-exporter@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="projects/${PROJECT_ID}/roles/logExportOperator"
```

## Step 15: remove an over-privileged binding example

Do this only after confirming the principal has an approved replacement path.

```bash
gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
  --member='user:someone@company.com' \
  --role='roles/editor'
```

A safe cleanup sequence is:

- identify the broad role
- define the minimal replacement
- apply the new grant
- validate required access still works
- remove the broad role

## Step 16: create a time-based IAM condition

Time-based conditions are useful for temporary incident access.

```bash
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="group:${TEMP_GROUP}" \
  --role='roles/container.admin' \
  --condition='expression=request.time < timestamp("2025-12-31T23:59:59Z"),title=TemporaryIncidentAccess,description=Expires elevated access automatically'
```

This is much safer than granting permanent elevated rights and hoping someone removes them later.

## Step 17: review conditional bindings in the policy JSON

```bash
jq '.bindings[] | select(.condition != null)' project-iam-policy.json
```

If the file was captured before you added the condition, recapture the policy and re-run the command.
Always verify that the condition exists in the final stored policy.

## Step 18: resource-based IAM condition example

A resource-scoped condition can narrow access to part of a storage namespace.

```bash
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member='group:platform-readers@example.com' \
  --role='roles/storage.objectViewer' \
  --condition='expression=resource.name.startsWith("projects/_/buckets/prod-backups/objects/runbooks/"),title=RunbookObjectsOnly,description=View only runbook objects'
```

This pattern is useful for shared buckets that contain multiple classes of data.

## Step 19: enable Workload Identity on the GKE cluster

```bash
gcloud container clusters update "$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --workload-pool="${PROJECT_ID}.svc.id.goog"
```

If the cluster already uses Workload Identity, keep the command in the runbook anyway.
It serves as explicit documentation.

## Step 20: create a namespace and Kubernetes service account

```bash
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create serviceaccount "$KSA_NAME" -n "$NAMESPACE"
```

## Step 21: create the Google service account for the workload

```bash
gcloud iam service-accounts create "$GSA_NAME" \
  --project="$PROJECT_ID" \
  --display-name='Payments workload runtime identity'
```

## Step 22: grant the minimum required role to the GSA

For demonstration, grant read-only Monitoring access.
Adjust the role to the workload’s real purpose.

```bash
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role='roles/monitoring.viewer'
```

## Step 23: bind the KSA to the GSA

```bash
gcloud iam service-accounts add-iam-policy-binding \
  "${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="$PROJECT_ID" \
  --role='roles/iam.workloadIdentityUser' \
  --member="serviceAccount:${PROJECT_ID}.svc.id.goog[${NAMESPACE}/${KSA_NAME}]"
```

## Step 24: annotate the Kubernetes service account

```bash
kubectl annotate serviceaccount "$KSA_NAME" \
  -n "$NAMESPACE" \
  iam.gke.io/gcp-service-account="${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --overwrite
```

## Step 25: deploy a test pod for Workload Identity validation

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: iam-wi-test
  namespace: payments
spec:
  serviceAccountName: payments-api
  containers:
    - name: test
      image: google/cloud-sdk:slim
      command: ["/bin/sh", "-c"]
      args:
        - "gcloud auth list && gcloud monitoring dashboards list --project=${PROJECT_ID} || true && sleep 3600"
EOF
```

## Step 26: validate access from the pod

```bash
kubectl exec -n "$NAMESPACE" iam-wi-test -- gcloud auth list
kubectl exec -n "$NAMESPACE" iam-wi-test -- gcloud monitoring dashboards list --project="$PROJECT_ID"
```

If access works, you have a keyless runtime identity path.
That is the preferred end state for GKE workloads.

## Step 27: discuss why JSON keys should be avoided in this case

Do not run this in production unless you have a strong exception case.
This example is here to show the contrast.

```bash
# Not recommended for GKE workloads
gcloud iam service-accounts keys create key.json \
  --iam-account="${GSA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
```

Risk review:

- the key is a file
- files get copied
- copies are hard to inventory
- revoking the key can break unknown consumers
- audit trails show key use, but lifecycle control is still weaker than federation

## Step 28: query audit logs for IAM changes

Admin Activity logs are the first place to look when investigating IAM drift.

```bash
gcloud logging read '
logName="projects/'"$PROJECT_ID"'/logs/cloudaudit.googleapis.com%2Factivity"
(protoPayload.serviceName="cloudresourcemanager.googleapis.com" OR protoPayload.serviceName="iam.googleapis.com")
(protoPayload.methodName:"SetIamPolicy" OR protoPayload.methodName:"CreateServiceAccountKey" OR protoPayload.methodName:"DeleteServiceAccountKey")
' \
  --project="$PROJECT_ID" \
  --limit=50 \
  --format='table(timestamp,protoPayload.authenticationInfo.principalEmail,protoPayload.serviceName,protoPayload.methodName)'
```

## Step 29: search specifically for service account key creation events

```bash
gcloud logging read '
logName="projects/'"$PROJECT_ID"'/logs/cloudaudit.googleapis.com%2Factivity"
protoPayload.methodName="google.iam.admin.v1.CreateServiceAccountKey"
' \
  --project="$PROJECT_ID" \
  --limit=20 \
  --format='table(timestamp,protoPayload.authenticationInfo.principalEmail,resource.labels.service_account_id)'
```

This query is a strong candidate for an always-on alert in mature environments.
Key creation should be rare and reviewable.

## Step 30: search for policy changes on the project

```bash
gcloud logging read '
logName="projects/'"$PROJECT_ID"'/logs/cloudaudit.googleapis.com%2Factivity"
protoPayload.methodName="SetIamPolicy"
' \
  --project="$PROJECT_ID" \
  --limit=20 \
  --format=json | jq '.[].protoPayload | {methodName, principalEmail: .authenticationInfo.principalEmail, serviceName}'
```

## Step 31: identify stale or suspicious principals

After you gather the current policy and recent logs, review for:

- unknown service accounts
- direct user grants to production write roles
- former employee accounts
- third-party identities without owners
- expired temporary access that was never removed

This human review step is where many important findings emerge.
Automation helps, but context still matters.

## Step 32: build a remediation plan for over-privileged access

A strong remediation plan includes:

- the risky principal
- the risky role and scope
- the replacement minimal role
- owner approval
- validation steps
- rollback steps
- audit evidence after the change

## Step 33: re-capture the final IAM policy

```bash
gcloud projects get-iam-policy "$PROJECT_ID" \
  --format=json > project-iam-policy-final.json

jq '.bindings | length' project-iam-policy-final.json
```

Keep both the before and after files when the lab is run in a real environment under change control.
They become part of the audit trail.

## Operational review questions

- which principals still have primitive roles
- which service accounts still use user-managed keys
- which custom roles are worth keeping versus replacing with predefined roles
- which temporary conditions need an expiry review process
- which workloads can migrate from keys to Workload Identity immediately
- which IAM changes should page security or platform teams

## Verification checklist

- [ ] project IAM policy captured before changes
- [ ] primitive roles reviewed
- [ ] service accounts inventoried
- [ ] user-managed keys identified or confirmed absent
- [ ] custom role created and inspected
- [ ] minimal service account created for the custom role
- [ ] time-based IAM condition created
- [ ] resource-based IAM condition understood or tested
- [ ] Workload Identity configured for a GKE workload
- [ ] IAM audit log queries return meaningful events

## Cleanup

If you created a test pod or lab-only service accounts, remove them when finished.

```bash
kubectl delete pod iam-wi-test -n "$NAMESPACE" --ignore-not-found
kubectl delete serviceaccount "$KSA_NAME" -n "$NAMESPACE" --ignore-not-found
```

Do not delete real production identities or roles unless the change is approved and validated.
