# GCP Operations Incident Scenarios

## How to use this file

These scenarios are written like mini runbooks.
Each one starts with the situation.
Then it moves into investigation, commands, execution, and resolution.
Use them for training, game days, and incident preparation.
The commands are examples and should be adjusted to your environment.

Common variables used below:

```bash
export PROJECT_ID="YOUR_PROJECT_ID"
export CLUSTER_NAME="prod-cluster"
export LOCATION="us-central1"
export NODE_POOL="primary-pool"
export NAMESPACE="payments"
```

---

## Scenario 1: GKE node pool needs emergency upgrade — plan and execute

### Situation

A critical CVE affects your current node image.
Security requires an emergency node pool upgrade within hours.
The service is production-facing and cannot tolerate broad downtime.

### Initial investigation

Questions to answer first:

- what node pools are affected
- what version is approved as the target
- do PDBs and replica counts support safe disruption
- do you have enough quota for surge nodes
- is there a maintenance freeze that must be overridden through approved process

### Commands

```bash
gcloud container node-pools list \
  --cluster="$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID"
```

```bash
gcloud container node-pools describe "$NODE_POOL" \
  --cluster="$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --format='yaml(version,management,upgradeSettings)'
```

```bash
gcloud container get-server-config \
  --location="$LOCATION" \
  --project="$PROJECT_ID"
```

```bash
kubectl get pdb -A
kubectl get deploy,statefulset -A
kubectl get nodes -L cloud.google.com/gke-nodepool
```

### Plan

1. confirm the approved target version
2. notify workload owners and on-call teams
3. set or verify surge upgrade settings
4. confirm node quota headroom
5. monitor node join and workload rescheduling in real time
6. pause if customer-impacting symptoms begin

### Execute

Configure a conservative surge profile:

```bash
gcloud container node-pools update "$NODE_POOL" \
  --cluster="$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --enable-surge-upgrade \
  --max-surge-upgrade=2 \
  --max-unavailable-upgrade=0
```

Start the upgrade:

```bash
gcloud container node-pools upgrade "$NODE_POOL" \
  --cluster="$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --cluster-version=TARGET_GKE_VERSION
```

Watch the rollout:

```bash
kubectl get nodes -L cloud.google.com/gke-nodepool
kubectl get pods -A -o wide
kubectl get events -A --sort-by=.lastTimestamp | tail -30
```

### Resolution criteria

- every node in the pool reaches the target version
- no customer-facing error rate regression remains
- no blocked drain events remain
- security confirms the vulnerable version is fully removed

### Post-incident review

Capture:

- how long the emergency upgrade took
- which workloads blocked progress
- whether PDBs were too strict
- whether quota slowed execution
- what should be automated before the next emergency

---

## Scenario 2: Service account key leaked — incident response

### Situation

A developer reports that a JSON service account key may have been exposed in a chat message or repository.
The service account belongs to a production automation identity.

### Initial investigation

Determine:

- which service account owns the key
- whether the key is still active
- where the key was exposed
- which systems use the key today
- what permissions the service account has

### Commands

```bash
gcloud iam service-accounts keys list \
  --iam-account="svc-automation@${PROJECT_ID}.iam.gserviceaccount.com"
```

```bash
gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten='bindings[].members' \
  --filter='bindings.members:serviceAccount:svc-automation@'"$PROJECT_ID"'.iam.gserviceaccount.com' \
  --format='table(bindings.role,bindings.members)'
```

```bash
gcloud logging read '
logName="projects/'"$PROJECT_ID"'/logs/cloudaudit.googleapis.com%2Factivity"
protoPayload.methodName="google.iam.admin.v1.CreateServiceAccountKey"
' \
  --project="$PROJECT_ID" \
  --limit=20
```

### Containment plan

1. identify consuming systems before revocation if possible
2. create a replacement identity path using impersonation or Workload Identity
3. revoke the exposed key
4. monitor for breakage and unauthorized use attempts
5. rotate any dependent secrets or configs

### Execute

Delete the exposed key:

```bash
gcloud iam service-accounts keys delete KEY_ID \
  --iam-account="svc-automation@${PROJECT_ID}.iam.gserviceaccount.com"
```

If the workload was on GKE, move it to Workload Identity.
If it was a CI job, move it to service account impersonation.

### Resolution criteria

- exposed key is revoked
- replacement auth path works
- no unexpected authentication failures remain
- incident scope and blast radius are documented

### Post-incident review

Ask:

- why did a JSON key exist at all
- why was it accessible outside the target runtime
- which detection controls failed or succeeded
- which service accounts can be migrated off keys next

---

## Scenario 3: Production GKE cluster running out of IP addresses

### Situation

Pods are starting to remain Pending during scale events.
Cluster autoscaler tries to add nodes, but capacity stalls.
Platform metrics suggest IP exhaustion in a VPC-native cluster.

### Initial investigation

Determine:

- whether the pressure is on node IPs, pod IPs, or service ranges
- whether the problem is regional growth or a one-time surge
- whether the subnet belongs to Shared VPC and needs host-project changes

### Commands

```bash
gcloud container clusters describe "$CLUSTER_NAME" \
  --location="$LOCATION" \
  --project="$PROJECT_ID" \
  --format='yaml(ipAllocationPolicy,subnetwork,networkConfig)'
```

```bash
kubectl get pods -A --field-selector=status.phase=Pending
kubectl get events -A --sort-by=.lastTimestamp | tail -30
```

```bash
gcloud compute networks subnets describe SUBNET_NAME \
  --region="$LOCATION" \
  --project=HOST_PROJECT_ID
```

### Resolution options

Depending on architecture:

- expand subnet secondary ranges
- add additional pod ranges if supported
- reduce unnecessary parallel scale-outs
- clean up unused workloads or zombie namespaces
- create a new cluster with larger ranges and migrate workloads if the current design is boxed in

### Tactical response

Short-term stabilizers may include:

- slowing deploy waves
- scaling down non-critical jobs
- moving batch workloads elsewhere
- reducing upgrade surge temporarily if safe

### Long-term resolution

The durable fix is better CIDR planning.
Document actual pod density, growth rate, and cluster-per-VPC strategy.
Do not leave the final outcome as “we got lucky after a cleanup.”

### Resolution criteria

- new pods schedule successfully
- autoscaler can add nodes again
- IP ranges have documented headroom
- future growth path is agreed and tracked

---

## Scenario 4: Audit finds over-privileged service accounts — remediation plan

### Situation

A routine access audit shows multiple service accounts with `roles/editor`, `roles/owner`, or broad admin permissions in production projects.
No incident is active yet, but the security risk is high.

### Initial investigation

Determine for each service account:

- which workloads use it
- what APIs it actually calls
- whether a predefined role can replace the broad grant
- whether a custom role is justified
- whether it still needs to exist at all

### Commands

```bash
gcloud projects get-iam-policy "$PROJECT_ID" \
  --flatten='bindings[].members' \
  --format='table(bindings.role,bindings.members)' | grep 'serviceAccount:'
```

```bash
gcloud iam service-accounts list --project="$PROJECT_ID"
```

```bash
gcloud logging read '
logName="projects/'"$PROJECT_ID"'/logs/cloudaudit.googleapis.com%2Factivity"
protoPayload.authenticationInfo.principalEmail:"gserviceaccount.com"
' \
  --project="$PROJECT_ID" \
  --limit=100
```

### Remediation plan

1. group service accounts by owning team and purpose
2. identify actual API usage from logs and application owners
3. map each account to the minimum required role set
4. create custom roles only when predefined roles are still too broad
5. apply replacement grants first
6. validate workload behavior
7. remove the broad role after validation

### Example command

```bash
gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:legacy-bot@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role='roles/editor'
```

Only run the removal after the replacement permissions are validated.

### Resolution criteria

- all audited service accounts have documented owners
- broad roles are removed or exception-approved
- replacement roles are validated in runtime
- keyless auth patterns are preferred where possible

### Post-review improvements

- add recurring IAM review cadence
- alert on new primitive role grants
- alert on service account key creation
- require justification for broad production roles

---

## Scenario 5: Cloud Monitoring bill increased 300% — investigate and optimize

### Situation

Finance alerts the platform team that the Monitoring and observability bill rose sharply this month.
No one intentionally changed retention policy or bought new infrastructure.

### Initial investigation

You need to understand whether the cost rise came from:

- higher metric ingestion
- high-cardinality custom metrics
- excessive log-based metrics
- duplicate exports and dashboards
- an environment that suddenly scaled far beyond normal

### Commands

Start with recent platform changes and observability object inventory.

```bash
gcloud monitoring dashboards list --project="$PROJECT_ID"
gcloud monitoring uptime list-configs --project="$PROJECT_ID"
gcloud logging metrics list --project="$PROJECT_ID"
gcloud logging sinks list --project="$PROJECT_ID"
```

Review deployments and scale changes around the cost jump.
Then inspect whether custom metrics or logs changed dramatically.

### Investigation workflow

1. identify what changed in the billing window
2. compare metric and log volume before and after
3. find high-cardinality labels in custom metrics and structured logs
4. review duplicate sinks or overly broad exports
5. review whether debug logging was enabled accidentally
6. identify dashboards or agents scraping far more than intended

### Optimization actions

Potential fixes include:

- remove unnecessary high-cardinality labels
- reduce verbose debug logs in production
- narrow log sink filters
- add safe exclusions for noisy low-value logs
- reduce unnecessary scrape intervals
- delete unused log-based metrics
- consolidate redundant dashboards and alert rules

### Example exclusion command

```bash
gcloud logging sinks update _Default \
  --project="$PROJECT_ID" \
  --add-exclusion=name=exclude-success-healthchecks,description='Reduce health check log noise',filter='resource.type="http_load_balancer" AND httpRequest.requestUrl:"/healthz" AND httpRequest.status=200'
```

### Resolution criteria

- a clear root cause is identified
- wasteful observability patterns are reduced without harming detection
- projected spend returns to an acceptable range
- guardrails are added to prevent repeat surprise costs

### Post-incident improvements

- define a cardinality review for custom metrics
- require owner and purpose for each sink and log-based metric
- add monthly observability cost review to platform operations
- document acceptable debug logging policy for production

---

## Closing note

These scenarios are intentionally operational.
They are not just about knowing commands.
They are about sequencing, risk management, and verification.
Practice them before the real incident, not during it.
