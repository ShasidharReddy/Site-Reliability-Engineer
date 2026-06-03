# GCP Operations — Theory

## How to Use This Document

This theory guide moves from fundamentals to advanced operations.
It is written for SREs who support GCP workloads with an emphasis on GKE.
Use it as a reference before running the labs in this directory.
The examples prefer least privilege, repeatability, and production-safe defaults.
When commands differ between console, API, and CLI support, the document calls that out.
The focus is operations, reliability, and recoverability rather than app development.

---

## 1. GCP Resource Hierarchy

### 1.1 Why the hierarchy matters

Every GCP deployment lives inside a hierarchy.
The hierarchy controls ownership, billing boundaries, organization policy, and IAM inheritance.
SREs care because outages and access mistakes often start with hierarchy mistakes.
A role granted at the wrong level can expose every production project.
A log sink created at the wrong level can miss or duplicate logs.
An org policy applied at the wrong node can block upgrades, image pulls, or service enablement.

### 1.2 Core hierarchy objects

GCP organizes resources like this:

```text
Organization
└── Folder
    └── Project
        └── Resources
            ├── GKE clusters
            ├── Cloud SQL instances
            ├── VPC networks
            ├── Pub/Sub topics
            ├── Cloud Storage buckets
            └── Logging / Monitoring objects
```

An organization is usually mapped to a Google Workspace or Cloud Identity domain.
Folders are optional but strongly recommended.
Projects are the primary isolation boundary for APIs, quotas, IAM, billing labels, and service enablement.
Resources live inside projects.
Some resources are global.
Some are regional or zonal.
Their IAM and org policy behavior still ties back to the project ancestor path.

### 1.3 Organization level

The organization node is the top management boundary.
It is the right place for global guardrails.
Examples include:

- organization policies
- audit log exports
- access reviews
- domain restricted sharing
- central security roles
- billing visibility
- centralized logging architecture

Bad practice:
Granting broad admin roles at organization scope for convenience.

Better practice:
Grant narrow org-level roles only to central platform, security, and billing teams.
Delegate service ownership at folders and projects.

### 1.4 Folder level

Folders let you group projects by environment, business unit, or compliance requirement.
Common folder patterns:

- `production`
- `non-production`
- `shared-services`
- `sandbox`
- `regulated-workloads`

Folder-level IAM is useful when many projects need the same access model.
Folder-level org policies are useful when production must be stricter than development.
Folder-level logging sinks are useful when a business unit wants its own analytics destination.

### 1.5 Project level

Projects are the operational unit most engineers touch every day.
A project defines:

- enabled APIs
- service identities
- quotas
- billing labels and budgets
- IAM policy bindings for the project and many child resources
- audit logs for activity in that project

Production reliability often improves when projects have a clear purpose.
Good patterns include separate projects for shared networking, shared CI/CD, and application workloads.
Poor patterns include a single giant project that mixes prod, dev, and experiments.

### 1.6 Example hierarchy for an SRE-managed platform

```text
Organization: example.com
├── Folder: production
│   ├── Project: prod-host-network
│   ├── Project: prod-gke-platform
│   ├── Project: prod-payments
│   └── Project: prod-observability
├── Folder: non-production
│   ├── Project: dev-gke-platform
│   ├── Project: staging-payments
│   └── Project: perf-testing
└── Folder: shared-services
    ├── Project: cicd-platform
    ├── Project: security-tooling
    └── Project: identity-services
```

This design makes ownership clear.
It also reduces blast radius.
If one project hits quota limits or has IAM drift, the whole company is not affected.

### 1.7 IAM inheritance basics

IAM policies inherit downward.
That means:

- bindings on the organization apply to folders, projects, and resources below it
- bindings on a folder apply to child folders, projects, and resources below it
- bindings on a project apply to resources inside that project
- resource-level IAM can add permissions but cannot cancel inherited allow bindings by itself

A useful mental model is:
Access granted high in the tree spreads down widely.
Therefore grant high only when necessary.

### 1.8 IAM inheritance example

```text
Organization
└── Folder: production
    └── Project: prod-payments
        └── GKE cluster: pay-prod-cluster
```

If `group:sre@example.com` has `roles/logging.viewer` on the production folder:

- they can view logs in every project under `production`
- they can see logs from the payments cluster without a project-specific grant

If `user:alice@example.com` has `roles/container.admin` on `prod-payments` only:

- Alice can administer clusters in that project
- Alice cannot administer clusters in sibling production projects

### 1.9 IAM inheritance risk patterns

Common risky patterns include:

- assigning `roles/editor` at folder scope
- assigning `roles/owner` to user accounts instead of break-glass groups
- giving CI/CD service accounts organization-wide write permissions
- using a shared human admin account instead of groups and audit-friendly identities
- forgetting inherited access when investigating who can reach a resource

### 1.10 Resource Manager commands for hierarchy visibility

```bash
# View organizations visible to the caller
gcloud organizations list

# View folders under an organization
gcloud resource-manager folders list \
  --organization=123456789012

# View projects under a folder
gcloud projects list \
  --filter='parent.type=folder parent.id=345678901234'

# Describe a project parent path
gcloud projects describe prod-payments \
  --format='yaml(projectId,parent,labels)'
```

### 1.11 Hierarchy design guidance for reliability

Use separate projects when you need separate quotas.
Use separate projects when you need separate IAM admin boundaries.
Use separate projects when a team should be able to fail independently.
Use separate folders when many projects need shared policy.
Keep shared networking and shared observability centralized, but not overloaded.
Document who owns each folder and project.
Treat hierarchy drift as an operational risk, not just a governance issue.

---

## 2. IAM Deep Dive

### 2.1 IAM building blocks

IAM answers three questions:

- who is making the request
- what resource is targeted
- which permission is required

The main objects are:

- principals
- roles
- permissions
- bindings
- conditions
- deny rules
- audit logs

### 2.2 Principals

A principal can be:

- a Google account
- a group
- a service account
- a workload identity principal
- a domain
- all authenticated users in some contexts
- all users in limited public contexts

For SRE operations, groups and service accounts are the preferred normal path.
Individual user bindings should be rare and justified.

### 2.3 Permissions and roles

Permissions are atomic operations such as:

- `container.clusters.get`
- `logging.logEntries.list`
- `monitoring.alertPolicies.create`
- `compute.instances.get`

Roles are bundles of permissions.
A binding connects a principal to a role on a resource.

### 2.4 Primitive roles

Primitive roles are the original project-wide roles:

| Role | Scope | Why SREs avoid it |
|---|---|---|
| `roles/owner` | Very broad | Includes IAM admin and destructive powers |
| `roles/editor` | Broad write access | Too much non-obvious privilege |
| `roles/viewer` | Read-only | Still broad, but less dangerous |

`owner` and `editor` are almost always too broad for modern operations.
They also hide exactly what the identity can do.
`viewer` is less risky but still wider than most least-privilege designs need.

### 2.5 Predefined roles

Predefined roles are Google-managed and service-specific.
Examples relevant to SREs include:

| Role | Use case |
|---|---|
| `roles/container.viewer` | Read GKE cluster state |
| `roles/container.developer` | Deploy and manage workloads without full cluster admin |
| `roles/container.admin` | Full GKE administration |
| `roles/logging.viewer` | Read logs |
| `roles/logging.configWriter` | Create sinks, exclusions, metrics |
| `roles/monitoring.viewer` | Read metrics, dashboards, alerting configs |
| `roles/monitoring.editor` | Change dashboards and alerting |
| `roles/iam.serviceAccountUser` | Let a principal act as a service account on resources |
| `roles/iam.serviceAccountTokenCreator` | Mint tokens or sign blobs on behalf of a service account |
| `roles/cloudsql.viewer` | Inspect Cloud SQL |
| `roles/pubsub.viewer` | Read Pub/Sub topology and metadata |

Advantages of predefined roles:

- narrower than primitive roles
- aligned with APIs
- automatically updated by Google as services evolve

Trade-off:
They can still contain more permissions than a tightly controlled team wants.

### 2.6 Custom roles

Custom roles let you define exactly which permissions are allowed.
Use them when predefined roles are too broad and permissions are stable enough to manage.
Examples:

- a log export operator role
- a GKE read-only audit role
- a Cloud SQL failover observer role

Custom roles are powerful but operationally expensive.
Someone must maintain them when APIs change.
A missing permission can break production procedures during an incident.
Too many custom roles create policy sprawl.

### 2.7 Custom role example

```yaml
title: SRELogExportOperator
description: Create and manage log sinks and log-based metrics.
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

```bash
gcloud iam roles create sreLogExportOperator \
  --project=my-project \
  --file=custom-role.yaml
```

### 2.8 Choosing role types

A practical decision tree:

- use predefined roles first
- use custom roles when a predefined role is clearly too broad
- avoid primitive roles except tightly controlled break-glass cases
- prefer group bindings over direct user bindings
- prefer project or folder scope over organization scope unless centralization is intentional

### 2.9 IAM conditions

IAM conditions make allow bindings context-aware.
A condition adds logic such as:

- only before a certain date
- only for specific resource name patterns
- only for a request time window
- only for specific resource types

Conditions reduce standing privilege.
They are useful for contractors, migrations, incident windows, and scoped admin actions.

### 2.10 Time-based condition example

```bash
gcloud projects add-iam-policy-binding my-project \
  --member='group:incident-admins@example.com' \
  --role='roles/container.admin' \
  --condition='expression=request.time < timestamp("2025-12-31T23:59:59Z"),title=TemporaryIncidentAccess,description=Expire elevated GKE access at year end'
```

This binding self-expires based on request time.
It is safer than granting the role and relying on memory to remove it later.

### 2.11 Resource-based condition example

```bash
gcloud projects add-iam-policy-binding my-project \
  --member='group:platform-readers@example.com' \
  --role='roles/storage.objectViewer' \
  --condition='expression=resource.name.startsWith("projects/_/buckets/prod-backups/objects/runbooks/"),title=RunbookPrefixOnly,description=Read only runbook objects'
```

This narrows access within a broader resource family.
Conditions are especially useful in storage and secret access patterns.

### 2.12 IAM condition cautions

Conditions are evaluated at request time.
They can be confusing during incident response if teams forget they exist.
Not every permission or service interaction behaves the same way.
Always test critical workflows.
Document all privileged conditional bindings.

### 2.13 Service accounts

A service account is a non-human identity for workloads and automation.
SREs should think about service accounts in three dimensions:

- where they are created
- what roles they hold
- how credentials are obtained

Best practices:

- one service account per workload or automation purpose
- no shared generic service accounts across unrelated systems
- no long-lived keys unless unavoidable
- rotate permissions as well as credentials
- alert on user-managed key creation

### 2.14 Service account usage patterns

Common patterns include:

- Cloud Build deploying to GKE
- GKE pods calling GCP APIs through Workload Identity
- scheduled backup jobs writing to Cloud Storage
- automation reading Monitoring and Logging APIs

The most important distinction is between impersonation and key usage.
Impersonation is preferred.
User-managed JSON keys are the risky legacy pattern.

### 2.15 Service account impersonation

Impersonation lets a human or workload act as a service account without exporting a static key.
This improves auditability and reduces credential sprawl.

```bash
# Run a command as a service account by impersonation
gcloud projects get-iam-policy my-project \
  --impersonate-service-account=sre-bot@my-project.iam.gserviceaccount.com
```

To impersonate, the caller usually needs `roles/iam.serviceAccountTokenCreator` on the target service account.
Grant this narrowly.

### 2.16 Service account keys

User-managed keys are files.
Files get copied.
Copied keys become incident tickets.
That is why modern designs avoid them.

Risks include:

- keys stored in Git repos
- keys copied into CI variables without expiration tracking
- keys on laptops outside corporate controls
- keys that outlive the project they were created for

If a key must exist temporarily, define:

- owner
- purpose
- expiry date
- detection rule
- rotation process
- revocation runbook

### 2.17 Listing service account keys

```bash
# List all user-managed keys in a project
for sa in $(gcloud iam service-accounts list --format='value(email)'); do
  gcloud iam service-accounts keys list \
    --iam-account="$sa" \
    --managed-by=user \
    --format='table(name,validAfterTime,validBeforeTime,keyType)'
done
```

### 2.18 Workload Identity for GKE

Workload Identity is the preferred way for pods to call GCP APIs.
It replaces node-wide scopes and static secrets with identity federation between Kubernetes and Google IAM.

The mapping is:

- Kubernetes Service Account
- GKE workload pool principal
- Google Service Account permissions

Operationally this means a pod can get a token for the mapped Google identity without storing a key file.

### 2.19 Workload Identity setup flow

```bash
# Enable Workload Identity on the cluster
gcloud container clusters update my-cluster \
  --location=us-central1 \
  --workload-pool=my-project.svc.id.goog

# Create the Google Service Account
gcloud iam service-accounts create payments-api \
  --display-name='Payments API runtime identity'

# Grant runtime permissions
gcloud projects add-iam-policy-binding my-project \
  --member='serviceAccount:payments-api@my-project.iam.gserviceaccount.com' \
  --role='roles/pubsub.publisher'

# Permit the Kubernetes Service Account to use the Google Service Account
gcloud iam service-accounts add-iam-policy-binding \
  payments-api@my-project.iam.gserviceaccount.com \
  --role='roles/iam.workloadIdentityUser' \
  --member='serviceAccount:my-project.svc.id.goog[payments/payments-api]'

# Annotate the Kubernetes Service Account
kubectl annotate serviceaccount payments-api \
  --namespace payments \
  iam.gke.io/gcp-service-account=payments-api@my-project.iam.gserviceaccount.com
```

### 2.20 Workload Identity debugging questions

When a pod cannot access a GCP API, ask:

- is the cluster workload pool enabled
- does the pod use the expected Kubernetes Service Account
- is the annotation correct
- does the Google Service Account trust the KSA principal
- does the Google Service Account actually have the needed role
- is the API enabled in the project
- is the workload calling the intended project or another one

### 2.21 IAM deny policies

Allow policies answer what is permitted.
Deny policies answer what must never happen.
A deny rule overrides allows except in a few special cases for exempt principals.
This is powerful for security guardrails.

Examples:

- deny service account key creation except for a break-glass group
- deny deletion of production log buckets
- deny disabling Security Command Center or audit-relevant services

### 2.22 Deny policy mental model

Use deny policies for controls that must not be bypassed accidentally.
Do not use them casually.
A mistaken deny can break emergency response.
Test in lower environments.
Document exemptions.
Keep scope as small as possible.

### 2.23 Deny policy example concept

```yaml
name: policies/denyServiceAccountKeyCreation
spec:
  rules:
    - denyRule:
        deniedPermissions:
          - iam.serviceAccountKeys.create
        deniedPrincipals:
          - principalSet://goog/public:all
        exceptionPrincipals:
          - principalSet://goog/group/security-admins@example.com
```

The exact API surface for deny policy management evolves.
Treat deny as a centrally managed control with change review and testing.

### 2.24 IAM audit strategy for SREs

At minimum, review:

- primitive role assignments
- service account key creation events
- impersonation grants
- folder and organization level bindings
- expired or temporary condition-based access that never got removed
- public access grants where not intended

### 2.25 Audit log queries for IAM changes

```bash
gcloud logging read '
logName="projects/my-project/logs/cloudaudit.googleapis.com%2Factivity"
protoPayload.serviceName="cloudresourcemanager.googleapis.com"
protoPayload.methodName:("SetIamPolicy" OR "google.iam.admin.v1.CreateServiceAccountKey")
' \
  --limit=50 \
  --format='table(timestamp,protoPayload.authenticationInfo.principalEmail,protoPayload.methodName,resource.labels.project_id)'
```

### 2.26 IAM operating principles

Prefer identity by group.
Prefer short-lived credentials.
Prefer impersonation over keys.
Prefer least privilege over convenience.
Prefer reviewable changes over ad hoc console edits.
Prefer project and folder scoping over org-wide grants.

---

## 3. GKE Architecture

### 3.1 Managed control plane model

GKE is a managed Kubernetes service.
Google operates the control plane.
You operate cluster configuration, workloads, node pools, networking, and workload-level reliability.
This shared responsibility model is central to GKE operations.

Google manages:

- API server lifecycle
- etcd operations
- control plane patching and availability targets
- many managed add-ons

You still own:

- workload resource requests and limits
- disruption budgets
- deployment strategy
- node pool design
- network policy and service exposure
- RBAC and IAM mapping
- cost controls

### 3.2 Standard mode vs Autopilot mode

| Capability | Standard | Autopilot |
|---|---|---|
| Node control | You manage node pools | Google manages nodes for you |
| DaemonSets | Broadly supported | Restricted to supported patterns |
| Privileged workloads | More flexible | More restricted |
| Cost model | Pay for nodes and attached resources | Pay for pod-requested resources and platform-managed overheads |
| Ops burden | Higher | Lower |
| Tuning freedom | Higher | Lower |

Standard is better when you need fine-grained node control.
Autopilot is better when you want stronger platform defaults and less fleet toil.

### 3.3 Standard mode operational profile

In Standard mode you choose:

- machine types
- disk sizes
- node images
- node pool layout
- taints and labels
- autoscaling settings
- upgrade strategy

That flexibility is useful for performance and special workloads.
It also means more opportunities for drift and misconfiguration.

### 3.4 Autopilot operational profile

Autopilot removes many node management decisions.
This improves baseline reliability for common workloads.
Teams give up some low-level control in exchange for guardrails.
Autopilot is especially attractive for service teams that do not want to run Kubernetes as a platform engineering discipline.

### 3.5 Zonal vs regional clusters

A zonal cluster runs a single control plane in one zone.
A regional cluster replicates the control plane across multiple zones in a region.
Node pools can also be distributed across zones.

Operational trade-off:

- zonal clusters cost less and are simpler
- regional clusters offer better availability and are preferred for production

### 3.6 Cluster topology comparison

| Design | Control plane | Node distribution | Typical use |
|---|---|---|---|
| Zonal Standard | One zone | One or more zones depending on node pool config | Dev, test, lower-tier workloads |
| Regional Standard | Multi-zone regional control plane | Multi-zone | Production services |
| Autopilot regional | Managed regional approach | Managed across zones | Production with low ops overhead |

### 3.7 Control plane SLA thinking

For production workloads, control plane availability matters but workload resiliency matters more.
A healthy control plane does not guarantee healthy applications.
A temporarily unavailable control plane usually affects management actions first.
Existing workloads may keep running.
Therefore SREs should design for:

- zone failure tolerance
- replica distribution
- readiness and liveness correctness
- graceful rollout behavior
- backlog absorption during API disruptions

### 3.8 Release channels

GKE release channels help teams consume versions predictably.
Typical channels include Rapid, Regular, and Stable.
Rapid gets features first and carries more change risk.
Stable emphasizes lower change frequency.
Most production fleets choose Regular or Stable depending on tolerance.

### 3.9 Node pools

Node pools are groups of nodes with shared configuration.
Use multiple node pools when workloads differ in:

- CPU to memory shape
- spot vs on-demand usage
- GPU needs
- taints and tolerations
- upgrade cadence
- security isolation needs

A single giant node pool is simple but often becomes operational debt.

### 3.10 Node pool design examples

- general services pool for web and API workloads
- system pool for critical add-ons
- stateful pool with larger disks
- batch pool with spot VMs
- isolated pool for privileged agents or specific compliance needs

### 3.11 Node auto-repair

Auto-repair replaces unhealthy nodes automatically.
This reduces toil.
It does not remove the need to understand why nodes became unhealthy.
If many nodes are repaired repeatedly, the platform is masking a bigger issue.

### 3.12 Node auto-upgrade

Auto-upgrade keeps node pools aligned with supported versions.
It reduces version drift.
It can still be disruptive if workloads are not disruption-tolerant.
Always combine auto-upgrade with:

- PodDisruptionBudgets
- multi-replica deployments
- readiness probes
- capacity headroom
- rollout observation

### 3.13 Surge upgrades

Surge upgrades create extra nodes temporarily during an upgrade.
This allows workloads to move before old nodes are removed.
It is one of the most important reliability features for production GKE upgrades.

Key controls:

- `max-surge-upgrade`
- `max-unavailable-upgrade`
- soak durations in more advanced rollout policies

### 3.14 Surge upgrade strategy guidance

Use small surge with zero unavailable for critical services.
Use more aggressive unavailable settings for dev or batch pools.
Verify quota exists for temporary surge nodes.
Remember that regional clusters multiply capacity math across zones.

### 3.15 Example node pool surge configuration

```bash
gcloud container node-pools update primary-pool \
  --cluster=prod-cluster \
  --location=us-central1 \
  --enable-surge-upgrade \
  --max-surge-upgrade=2 \
  --max-unavailable-upgrade=0
```

### 3.16 Blue-green vs surge thinking

Some environments prefer blue-green style upgrades for even more control.
Surge is often enough for stateless services.
Blue-green patterns matter more when workloads are highly sensitive or need long soak periods.
The choice depends on SLA, statefulness, and quota budget.

### 3.17 Maintenance windows and exclusions

Maintenance windows define when automatic changes may happen.
Maintenance exclusions block changes during freezes such as Black Friday or year-end close.
Use them deliberately.
Too many exclusions cause version drift and support risk.
Too few cause surprise changes during critical business periods.

### 3.18 Maintenance command examples

```bash
# Recurring maintenance window
gcloud container clusters update prod-cluster \
  --location=us-central1 \
  --maintenance-window-start=2025-01-05T02:00:00Z \
  --maintenance-window-end=2025-01-05T06:00:00Z \
  --maintenance-window-recurrence='FREQ=WEEKLY;BYDAY=SA,SU'

# Add a temporary exclusion
gcloud container clusters update prod-cluster \
  --location=us-central1 \
  --add-maintenance-exclusion-name=peak-season-freeze \
  --add-maintenance-exclusion-start=2025-11-20T00:00:00Z \
  --add-maintenance-exclusion-end=2025-12-02T23:59:59Z \
  --add-maintenance-exclusion-scope=no_upgrades
```

### 3.19 Standard cluster creation example

```bash
gcloud container clusters create prod-cluster \
  --location=us-central1 \
  --release-channel=regular \
  --num-nodes=3 \
  --enable-ip-alias \
  --workload-pool=my-project.svc.id.goog \
  --enable-private-nodes \
  --enable-master-authorized-networks \
  --enable-shielded-nodes
```

### 3.20 Autopilot cluster creation example

```bash
gcloud container clusters create-auto prod-auto \
  --location=us-central1 \
  --release-channel=regular \
  --workload-pool=my-project.svc.id.goog
```

### 3.21 GKE reliability design checklist

Ask these before production launch:

- is the cluster regional
- are workloads spread across zones
- do PDBs allow safe node operations
- do upgrades have quota headroom
- are node pools separated by workload class
- is Workload Identity used instead of keys
- are maintenance windows aligned with business risk
- are cluster add-ons monitored

---

## 4. GKE Networking

### 4.1 VPC-native clusters

Modern GKE clusters should be VPC-native.
In GKE this usually means IP aliasing with secondary ranges.
Pods and Services get IPs from dedicated ranges rather than overlay networking.
Benefits include better scaling, easier routing, and tighter Google Cloud integration.

### 4.2 Alias IP basics

With alias IPs:

- node primary IPs come from the subnet primary range
- pod IPs come from a subnet secondary range
- service ClusterIPs come from another secondary range

This separation matters for capacity planning.
It also matters for hybrid connectivity and Shared VPC operations.

### 4.3 CIDR planning principles

Bad CIDR planning causes painful outages.
The classic production failure is a cluster that runs out of pod IPs and cannot scale.
Plan ranges early.
Document assumptions.
Reserve space for future node pools and region growth.

### 4.4 Questions to ask during CIDR planning

- how many nodes may the cluster need at peak
- how many pods per node are expected
- will the cluster add more node pools later
- are multiple clusters sharing the same VPC
- is Shared VPC in use
- will VPC peering or on-prem routes overlap with pod/service ranges
- do you need room for additional pod ranges later

### 4.5 Simple capacity formula

A rough model is:

- expected nodes per cluster
- expected max pods per node
- growth factor for upgrades and autoscaling

If your design needs 500 nodes and 64 pods per node, the pod range must be much larger than a small test cluster range.
Running out of IPs is harder to fix later than to avoid during design.

### 4.6 Subnet and secondary range example

```bash
gcloud compute networks subnets create gke-prod-us-central1 \
  --project=prod-host-network \
  --region=us-central1 \
  --network=prod-shared-vpc \
  --range=10.20.0.0/20 \
  --secondary-range=gke-pods=10.24.0.0/14,gke-services=10.28.0.0/20
```

### 4.7 Shared VPC considerations for GKE networking

In Shared VPC, the network lives in a host project and the cluster often lives in a service project.
This is powerful for central control.
It also means cluster creation depends on cross-project IAM and subnet visibility.
Troubleshooting must include both the service and host project context.

### 4.8 Services in GKE

Kubernetes Service types matter operationally:

- ClusterIP for internal cluster communication
- NodePort for direct node-level exposure
- LoadBalancer for cloud load balancer integration
- Headless Services for service discovery without VIP abstraction

Most production user-facing traffic should avoid raw NodePort.
Prefer managed load balancers through Service or Ingress abstractions.

### 4.9 Internal load balancers

Internal load balancers are used for east-west or private north-south traffic.
Typical use cases:

- internal APIs
- databases behind private consumers
- back-office apps on private networks
- services consumed through Private Service Connect or internal clients

### 4.10 External load balancers

External load balancers expose public endpoints.
SRE concerns include:

- TLS termination strategy
- health checks
- backend capacity
- session behavior
- Cloud Armor protections
- global vs regional design

### 4.11 Internal LoadBalancer Service example

```yaml
apiVersion: v1
kind: Service
metadata:
  name: payments-api-internal
  namespace: payments
  annotations:
    networking.gke.io/load-balancer-type: "Internal"
spec:
  type: LoadBalancer
  selector:
    app: payments-api
  ports:
    - name: https
      port: 443
      targetPort: 8443
```

### 4.12 External LoadBalancer Service example

```yaml
apiVersion: v1
kind: Service
metadata:
  name: payments-api-public
  namespace: payments
spec:
  type: LoadBalancer
  selector:
    app: payments-api
  ports:
    - name: https
      port: 443
      targetPort: 8443
```

### 4.13 GKE Ingress

Ingress provides L7 routing for HTTP and HTTPS.
It integrates with Google Cloud load balancing.
It can support:

- host and path routing
- managed certificates depending on setup
- Cloud Armor policies
- backend configuration for timeouts and health checks
- multi-service routing

### 4.14 Ingress operational notes

Ingress is powerful but not magical.
Check:

- controller events
- NEG health if using container-native load balancing
- backend service health checks
- certificate provisioning state
- firewall rules and reachability
- Cloud Armor rules after policy changes

### 4.15 Ingress example

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web-ingress
  namespace: frontend
  annotations:
    kubernetes.io/ingress.class: "gce"
    networking.gke.io/managed-certificates: "frontend-cert"
    cloud.google.com/backend-config: '{"default": "frontend-backendconfig"}'
spec:
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend-service
                port:
                  number: 80
```

### 4.16 BackendConfig example for GKE Ingress

```yaml
apiVersion: cloud.google.com/v1
kind: BackendConfig
metadata:
  name: frontend-backendconfig
  namespace: frontend
spec:
  timeoutSec: 30
  connectionDraining:
    drainingTimeoutSec: 60
  healthCheck:
    requestPath: /healthz
    port: 8080
  logging:
    enable: true
    sampleRate: 1.0
  securityPolicy:
    name: prod-cloud-armor-policy
```

### 4.17 Cloud Armor basics

Cloud Armor protects HTTP(S) load balanced services.
It is relevant to SREs because availability incidents often begin as abusive traffic patterns.
Capabilities include:

- WAF rules
- rate limiting
- IP and geo filtering
- preconfigured threat signatures
- adaptive protection in some environments

### 4.18 Cloud Armor operational considerations

False positives can create self-inflicted outages.
Deploy rules in preview or log-only modes where possible.
Coordinate with application owners.
Monitor backend 4xx/5xx changes after policy rollout.
Keep emergency allowlists documented.

### 4.19 Cloud Armor example

```bash
gcloud compute security-policies create prod-edge-policy \
  --description='Protect internet-facing GKE services'

gcloud compute security-policies rules create 1000 \
  --security-policy=prod-edge-policy \
  --expression='evaluatePreconfiguredWaf("sqli-stable")' \
  --action=deny-403
```

### 4.20 Gateway API note

Many modern GKE environments are also adopting Gateway API.
It offers more expressive traffic management than legacy Ingress in some cases.
For an SRE, the operational lesson is the same:
Understand which controller owns the resource and how that maps to Google load balancer objects.

---

## 5. Cloud Monitoring

### 5.1 What Cloud Monitoring provides

Cloud Monitoring is the metrics, dashboards, alerting, uptime, and SLO system in the Operations Suite.
It receives platform metrics from Google services.
It can also ingest custom and Prometheus metrics.
For SREs it is the primary place to answer:

- is the service healthy now
- is it getting worse
- did a change cause a regression
- are we burning error budget
- who should be notified

### 5.2 Metrics Explorer

Metrics Explorer is the fastest way to inspect a metric interactively.
It is useful for:

- validating a metric exists
- checking cardinality and labels
- comparing dimensions such as cluster, namespace, or response code
- finding the right aggregation for an alert policy

### 5.3 Good metric exploration workflow

Start with a single metric.
Add filters to isolate the workload.
Choose the correct aligner.
Choose the correct reducer if multiple series exist.
Check whether spikes are expected or noise.
Only then turn the query into a dashboard or alert.

### 5.4 Example metric families SREs should know

| Area | Metric examples |
|---|---|
| GKE compute | `kubernetes.io/node/cpu/allocatable_utilization`, `kubernetes.io/container/restart_count` |
| Load balancing | `loadbalancing.googleapis.com/https/request_count`, `loadbalancing.googleapis.com/https/backend_latencies` |
| Cloud SQL | `cloudsql.googleapis.com/database/cpu/utilization`, `cloudsql.googleapis.com/database/disk/bytes_used` |
| Pub/Sub | `pubsub.googleapis.com/subscription/num_undelivered_messages`, `pubsub.googleapis.com/subscription/oldest_unacked_message_age` |
| Uptime | `monitoring.googleapis.com/uptime_check/check_passed` |

### 5.5 Uptime checks

Uptime checks simulate external or network-based availability tests.
Common protocols include HTTP, HTTPS, TCP, and SSL certificate monitoring.
Use them for black-box validation.
They complement white-box service metrics.

### 5.6 HTTP uptime checks

HTTP uptime checks answer whether a URL responds correctly.
Use content matching when appropriate.
Avoid checking only a shallow endpoint if the true user journey is more complex.
A shallow `/healthz` can be useful for infra issues but may miss dependency failures.

### 5.7 TCP uptime checks

TCP checks are useful for private services or non-HTTP endpoints.
They confirm network reachability and port acceptance.
They do not prove application correctness beyond handshake success.

### 5.8 SSL uptime checks

SSL certificate checks are useful for detecting impending expiration.
They are low effort and prevent embarrassing outages.
Certificate health is a classic SRE “easy win” signal.

### 5.9 Uptime check create example

```bash
gcloud monitoring uptime create prod-homepage-http \
  --resource-type=uptime-url \
  --resource-labels=host=app.example.com,project_id=my-project \
  --path=/healthz \
  --protocol=https \
  --port=443 \
  --period=60s \
  --timeout=10s \
  --validate-ssl \
  --regions=usa,eur
```

### 5.10 Alerting policies

Alerting policies turn symptoms into notifications.
A reliable alert has:

- a meaningful signal
- correct filtering
- sane aggregation
- an actionable threshold
- a response target
- low enough noise to be trusted

### 5.11 Common alert conditions

- high error rate
- high latency
- pod restart spikes
- node not ready
- disk nearly full
- Cloud SQL CPU saturation
- Pub/Sub backlog age rising
- SSL expiration window breached
- no data from critical workload

### 5.12 Multiple-condition alerts

Use multiple conditions when one symptom alone is too noisy.
Examples:

- high CPU and high latency
- high error rate and request volume above a floor
- node memory pressure and pod eviction events

Done well, multi-condition policies reduce false alarms.
Done poorly, they create logic nobody understands at 3 AM.

### 5.13 Notification channels

Notification channels define where alerts go.
Typical channels include:

- email
- SMS
- PagerDuty
- Pub/Sub
- webhook
- Slack via integrations depending on architecture

Always configure more than one path for critical services.
Human paging paths and machine-event paths can coexist.

### 5.14 Notification channel CLI example

```bash
gcloud beta monitoring channels create \
  --display-name='Primary SRE Email' \
  --description='Email fallback for production paging' \
  --type=email \
  --channel-labels=email_address=sre-oncall@example.com
```

### 5.15 Alert policy API pattern

The CLI support for some alerting objects can vary by release track.
In practice many teams manage alert policies through Terraform, the Monitoring API, or declarative JSON.
That is acceptable and often more repeatable than manual console editing.

### 5.16 Example alert policy JSON

```json
{
  "displayName": "GKE pod restarts high",
  "combiner": "OR",
  "conditions": [
    {
      "displayName": "Restart count above threshold",
      "conditionThreshold": {
        "filter": "resource.type=\"k8s_container\" AND metric.type=\"kubernetes.io/container/restart_count\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 5,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_DELTA"
          }
        ]
      }
    }
  ],
  "enabled": true,
  "alertStrategy": {
    "autoClose": "1800s"
  }
}
```

### 5.17 SLO monitoring

SLOs connect technical metrics to reliability promises.
The important pieces are:

- service definition
- SLI definition
- objective target
- rolling compliance window
- error budget burn alerts

Common SLI types:

- request-based availability
- request-based latency
- window-based uptime
- backlog or freshness approximations for async systems

### 5.18 SLO design guidance

Choose an SLI that users feel.
Do not choose an SLI because it is easy to measure but irrelevant.
For GKE apps, request success ratio and latency are common.
For batch or event-driven systems, delivery age or job completion latency may fit better.

### 5.19 Dashboard design principles

A useful dashboard should answer one of three questions:

- what is broken now
- what changed recently
- where is capacity risk building

Avoid dumping every metric on one page.
Group by audience.
Typical dashboards:

- executive service health
- on-call triage
- GKE platform capacity
- release monitoring
- dependency health

### 5.20 Dashboard snippet example

```yaml
displayName: GKE Service Overview
gridLayout:
  widgets:
    - title: Request Rate
      xyChart:
        dataSets:
          - timeSeriesQuery:
              timeSeriesFilter:
                filter: metric.type="loadbalancing.googleapis.com/https/request_count"
    - title: Container Restarts
      xyChart:
        dataSets:
          - timeSeriesQuery:
              timeSeriesFilter:
                filter: metric.type="kubernetes.io/container/restart_count"
```

### 5.21 Grafana integration

Grafana can read Cloud Monitoring as a data source.
This is useful when teams want a shared dashboard experience across clouds or custom observability stacks.
Make sure data source permissions are read-only unless write actions are required.

### 5.22 Monitoring anti-patterns

Avoid:

- alerting on every pod restart without context
- paging on CPU alone for autoscaled services
- dashboards with unlabeled graphs
- SLOs with no burn-rate alerts
- noisy alerts routed only to email for critical services
- relying on a single internal metric without black-box validation

---

## 6. Cloud Logging

### 6.1 Why logging still matters in a metrics-first world

Metrics tell you that something is wrong.
Logs tell you why, who, where, and often which request or change triggered it.
In GCP, Cloud Logging is also a control plane audit source.
That makes it critical for both debugging and security review.

### 6.2 Log Router

The Log Router receives logs and routes them to destinations.
Possible destinations include:

- default buckets
- user-defined log buckets
- BigQuery datasets
- Cloud Storage buckets
- Pub/Sub topics
- another project or centralized logging project

The router evaluates sinks and exclusions.
This is the foundation of cost control and centralization.

### 6.3 Log buckets and retention

Not all logs need the same retention.
Operational debug logs might need weeks.
Audit logs may need many months.
Compliance workloads may need even longer retention in BigQuery or GCS archives.
Retention choices are cost and risk decisions.

### 6.4 Platform log categories

Important categories include:

- Admin Activity audit logs
- Data Access audit logs
- System Event audit logs
- Access Transparency logs
- workload logs from GKE containers
- load balancer logs
- VPC flow logs
- Cloud SQL logs

### 6.5 Logging query language basics

A query usually combines:

- resource type
- labels
- severity
- payload field matching
- timestamp filters
- audit method names

This query style is a daily operational skill.

### 6.6 Query examples from basic to advanced

```text
severity>=ERROR
```

```text
resource.type="k8s_container"
resource.labels.cluster_name="prod-cluster"
resource.labels.namespace_name="payments"
severity>=WARNING
```

```text
resource.type="http_load_balancer"
httpRequest.status>=500
jsonPayload.statusDetails!="response_from_cache"
```

```text
logName="projects/my-project/logs/cloudaudit.googleapis.com%2Factivity"
protoPayload.methodName="io.k8s.core.v1.pods.create"
protoPayload.authenticationInfo.principalEmail:"deployer"
```

### 6.7 Structured vs unstructured logs

Structured JSON logs are better for operations.
They allow filtering on fields such as:

- trace ID
- request ID
- tenant ID
- operation name
- dependency target
- latency value

Free-text logs still have value, but they are harder to query and turn into metrics.

### 6.8 Log-based metrics

Log-based metrics turn log matches into metric streams.
They are useful when the application does not emit a native metric.
Examples:

- authentication failures
- panic or fatal events
- rate of specific error codes
- queue processing failures

### 6.9 Counter metric example

```bash
gcloud logging metrics create auth_failures \
  --description='Authentication failures from API logs' \
  --log-filter='resource.type="k8s_container" AND jsonPayload.event="auth_failure"'
```

### 6.10 Distribution metric example concept

If logs contain latency values, a distribution metric can extract them.
That enables percentiles and better alerting.
This is often easier than changing code immediately during a migration period.

### 6.11 Log exclusions

Log exclusions reduce cost and noise.
Typical candidates:

- verbose health check success logs
- debug logs from short-lived test namespaces
- duplicate access logs in lower environments

Never exclude logs blindly.
Make sure the logs are not needed for security, debugging, or compliance.

### 6.12 Sink examples

```bash
# Export errors to BigQuery
gcloud logging sinks create prod-errors-bq \
  bigquery.googleapis.com/projects/obs-project/datasets/prod_errors \
  --log-filter='severity>=ERROR'

# Archive audit logs to Cloud Storage
gcloud logging sinks create audit-archive \
  storage.googleapis.com/prod-audit-archive \
  --log-filter='logName:"cloudaudit.googleapis.com"'

# Forward critical logs to Pub/Sub
gcloud logging sinks create critical-events \
  pubsub.googleapis.com/projects/obs-project/topics/critical-events \
  --log-filter='severity>=CRITICAL'
```

### 6.13 BigQuery export patterns

BigQuery export is powerful for:

- incident forensics
- trend analysis
- IAM change audits
- cost analysis of noisy services
- joining logs with deployment data or ticket data

Be careful with schema drift and nested payloads.
Partitioned tables and retention controls help manage cost.

### 6.14 Logging reliability lessons

Logs can be delayed.
Routes can fail due to missing sink permissions.
Exclusions can hide the very event you need.
Centralized logging projects can become critical dependencies.
Therefore test sinks after changes.
Alert on export failures where possible.
Treat observability pipelines as production systems.

---

## 7. Cloud Operations Suite Beyond Metrics and Logs

### 7.1 Cloud Trace

Cloud Trace helps you understand request paths and latency across services.
It is useful for:

- pinpointing slow dependency calls
- separating frontend time from backend time
- validating whether latency is app, network, or database related

In microservice systems, traces are often the fastest way to identify a latency bottleneck.

### 7.2 Trace operational usage

Use Trace when:

- p95 latency rose but CPU did not
- one region is slow and you need to isolate a dependency
- a new release changed call patterns
- a database query fanout exploded

Metrics tell you the symptom.
Trace shows the path.

### 7.3 Cloud Profiler

Profiler samples application performance over time.
It helps answer:

- where CPU time is spent
- which code paths allocate the most memory
- whether a leak or hot loop is growing over time

This is especially useful for services that are stable enough to keep running but inefficient enough to threaten cost or saturation.

### 7.4 Profiler operational value

SREs should care because efficiency is reliability.
Wasteful CPU means less headroom.
Excess memory means more OOM risk.
A workload that is merely slow at 30% traffic might fail at 70% traffic.

### 7.5 Error Reporting

Error Reporting groups similar application errors.
It is useful for prioritization.
Instead of raw error log volume, you get grouped issues and frequency trends.
This helps distinguish a new regression from background noise.

### 7.6 Operations Suite integration model

The suite is strongest when signals are correlated:

- metrics reveal symptom scope
- logs reveal event detail
- traces reveal dependency path
- profiler reveals inefficiency
- Error Reporting reveals app regressions

An SRE workflow should move through these layers quickly.

---

## 8. Cloud SQL and Cloud Spanner Basics for SREs

### 8.1 Why SREs need database awareness

Many app outages blamed on Kubernetes are actually dependency failures.
Databases are frequent root causes.
You do not need to be a DBA to operate reliably, but you do need to understand service limits, failover behavior, and monitoring signals.

### 8.2 Cloud SQL basics

Cloud SQL is a managed relational database service.
Common engines are MySQL, PostgreSQL, and SQL Server.
Operationally relevant topics include:

- high availability configuration
- CPU and memory saturation
- storage growth
- connection limits
- backup success
- replication lag for replicas

### 8.3 Cloud SQL signals SREs should watch

- CPU utilization
- memory utilization
- disk bytes used
- disk write/read ops
- connection count
- replication lag
- backup status
- maintenance activity

### 8.4 Cloud SQL failover thinking

HA improves resilience but not application correctness.
Applications still need:

- sane connection pooling
- retries with backoff
- idempotency for repeated writes where possible
- readiness behavior during failover windows

### 8.5 Cloud Spanner basics

Cloud Spanner is globally distributed and horizontally scalable.
For SREs, the important concepts are:

- instance sizing by compute capacity
- regional vs multi-region configuration
- latency and locality expectations
- schema change planning
- backup and restore strategy

### 8.6 Cloud SQL vs Spanner mental model

| Service | Best for | SRE concern |
|---|---|---|
| Cloud SQL | traditional relational workloads | instance limits, failover, connection management |
| Cloud Spanner | high scale, strong consistency, horizontal scale | regional placement, capacity planning, query behavior |

### 8.7 Database reliability patterns

For either service:

- alert on saturation before users feel it
- test restore procedures, not just backup creation
- monitor maintenance windows
- know where credentials and IAM auth live
- model dependency failure in SLOs and capacity plans

---

## 9. Cloud Storage for Backup and Disaster Recovery

### 9.1 Why Cloud Storage matters to SREs

Cloud Storage is not just object storage.
It is often the destination for:

- database backups
- logs archives
- release artifacts
- DR snapshots metadata
- configuration exports
- incident evidence bundles

### 9.2 Bucket design decisions

Important choices include:

- region or multi-region
- retention policy
- object versioning
- lifecycle rules
- CMEK requirements
- access model

### 9.3 Backup patterns

Common SRE backup uses:

- exporting Cloud SQL backups
- storing Velero or backup manifests for GKE workloads
- archiving logs for compliance
- keeping build artifacts for rollback

### 9.4 DR considerations

A backup is not recovery until restore is tested.
For DR, document:

- RPO target
- RTO target
- backup frequency
- bucket region strategy
- object retention rules
- who can restore
- how secrets and IAM are restored

### 9.5 Example lifecycle policy concept

```json
{
  "rule": [
    {
      "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
      "condition": {"age": 30}
    },
    {
      "action": {"type": "Delete"},
      "condition": {"age": 365}
    }
  ]
}
```

### 9.6 Storage operational lessons

Protect backup buckets from accidental deletion.
Use retention locks where required.
Keep restore documentation close to the backup job definition.
Test IAM access during recovery exercises.

---

## 10. Cloud Pub/Sub for Event-Driven Architectures

### 10.1 Why SREs care about Pub/Sub

Event-driven systems fail differently from request-response systems.
Instead of 500 errors, you may see backlog age, redelivery spikes, or consumer lag.
Pub/Sub is reliable, but workloads around it can still misbehave badly.

### 10.2 Core concepts

The building blocks are:

- topics
- subscriptions
- publishers
- subscribers
- acknowledgement deadlines
- dead-letter topics
- retention

### 10.3 SRE metrics for Pub/Sub

Useful signals include:

- `num_undelivered_messages`
- `oldest_unacked_message_age`
- delivery latency
- dead-letter volume
- subscriber throughput

### 10.4 Reliability questions for Pub/Sub systems

Ask:

- can consumers catch up after an outage
- what happens during message duplication
- are messages idempotent
- when does backlog age become user-visible harm
- where do poison messages go

### 10.5 Operational patterns

Good patterns include:

- backlog alerts by age, not only count
- dead-letter routing
- replay plans
- autoscaling subscribers on backlog or CPU
- per-subscription dashboards

### 10.6 Pub/Sub and GKE

GKE workloads commonly publish or consume Pub/Sub messages.
Use Workload Identity for authentication.
Keep request/limit sizing realistic for consumers.
Remember that autoscaling on CPU alone may not track backlog fast enough.

---

## 11. Cloud NAT, VPC Peering, Shared VPC, and Private Service Connect

### 11.1 Cloud NAT

Cloud NAT provides outbound internet access for private resources without public IPs.
This is common for private GKE nodes.
It does not provide inbound reachability.
SREs care because failed image pulls or failed external API calls often trace back to NAT capacity or routing design.

### 11.2 Cloud NAT operational concerns

Check:

- whether the subnet is covered
- port allocation and exhaustion
- route and firewall interactions
- regional placement
- whether Private Google Access is needed instead of internet egress for Google APIs

### 11.3 VPC peering

VPC peering connects two VPCs privately.
Important rule:
It is not transitive.
That catches teams often.
Peering is useful but can become hard to reason about at scale.
Overlap in CIDR ranges blocks peering.
That is another reason good GKE CIDR planning matters.

### 11.4 Shared VPC

Shared VPC centralizes networking in a host project.
Service projects attach resources to the shared network.
Benefits:

- centralized firewall and subnet management
- cleaner network governance
- easier large-scale IP planning

Costs:

- cross-project IAM complexity
- troubleshooting across project boundaries
- dependency on central networking team practices

### 11.5 Private Service Connect

Private Service Connect exposes services privately over internal IPs.
It is increasingly important for consuming managed services without public endpoints.
From an SRE perspective it improves security posture and can simplify controlled connectivity.
It also adds more moving parts to debugging.

### 11.6 Connectivity troubleshooting checklist

When a GKE workload cannot reach a service, check:

- DNS resolution
- NetworkPolicy rules
- VPC firewall rules
- NAT coverage
- Private Google Access
- peering route overlap
- PSC endpoint health and permissions

---

## 12. Cloud Build and Artifact Registry for CI/CD

### 12.1 CI/CD relevance to reliability

Deploy systems are production systems.
If the pipeline is unreliable, rollback and recovery are unreliable too.
Cloud Build and Artifact Registry are common GCP-native building blocks.

### 12.2 Cloud Build basics

Cloud Build executes build steps in managed infrastructure.
SREs should understand:

- service account permissions used by builds
- image provenance and signing practices
- deployment triggers
- log visibility
- failure notification paths

### 12.3 Artifact Registry basics

Artifact Registry stores:

- container images
- language packages
- Helm charts in supported patterns

Reliability topics include:

- regional placement near clusters
- retention and cleanup policies
- pull permissions for runtime identities
- image immutability strategy

### 12.4 CI/CD security and reliability controls

Recommended patterns:

- use dedicated Cloud Build service accounts
- grant only push/pull permissions needed
- store deployable artifacts in Artifact Registry, not random buckets
- enable Binary Authorization where appropriate
- preserve previous good versions for rollback

### 12.5 Cloud Build example

```yaml
steps:
  - name: gcr.io/cloud-builders/docker
    args: ['build', '-t', 'us-central1-docker.pkg.dev/my-project/apps/payments:${SHORT_SHA}', '.']
  - name: gcr.io/cloud-builders/docker
    args: ['push', 'us-central1-docker.pkg.dev/my-project/apps/payments:${SHORT_SHA}']
images:
  - us-central1-docker.pkg.dev/my-project/apps/payments:${SHORT_SHA}
```

### 12.6 Artifact Registry operational lessons

Monitor image pull errors from nodes.
Keep repository permissions tight.
Align cleanup policies with rollback windows.
Ensure private clusters can reach the registry path they need.

---

## 13. Binary Authorization and Supply Chain Controls

### 13.1 Why Binary Authorization matters

Binary Authorization helps ensure only trusted images run in clusters.
For SREs this is both a security and reliability control.
It reduces the chance of unknown or manually built images entering production.

### 13.2 Policy concepts

Binary Authorization policies can require attestations.
A trusted build system or signer attests that an image passed required checks.
Cluster admission then enforces that policy.

### 13.3 Operational caution

If policy is stricter than the build pipeline supports, deployment stops.
That is good from a security standpoint but disruptive if rolled out carelessly.
Start with dry-run or controlled scope.
Test rollback images too.

---

## 14. GCP SRE for GKE Workloads

### 14.1 Shared responsibility in managed Kubernetes

Managed control plane does not mean managed reliability.
Google reduces control plane toil.
Your team still owns service reliability.
Many incidents in GKE are caused by workload design, not the cluster control plane.

### 14.2 Reliability pillars for GKE workloads

Key pillars include:

- multi-zone replica spread
- correct probes
- sane resource requests and limits
- disruption tolerance
- workload identity instead of secrets
- versioned and reversible deployments
- dependency-aware alerts
- tested backups and recovery

### 14.3 Probe design

Liveness probes restart dead workloads.
Readiness probes protect traffic from not-ready instances.
Startup probes protect slow-starting containers from premature restarts.
Misconfigured probes cause self-inflicted outages.
Probe tuning is an SRE responsibility even in Autopilot.

### 14.4 Resource requests and limits

Right-sizing matters.
Too low means noisy throttling or OOM kills.
Too high wastes money and reduces bin-packing efficiency.
Autopilot particularly depends on accurate requests because pricing and scheduling are request-driven.

### 14.5 PDB and rollout coordination

PodDisruptionBudgets help protect availability during node maintenance and upgrades.
But an overly strict PDB can block critical upgrades.
The goal is graceful change, not zero movement forever.
Test whether PDBs allow at least one pod to move when needed.

### 14.6 Horizontal and vertical autoscaling

Autoscaling is not a substitute for capacity planning.
HPA reacts after signals move.
VPA can help right-size but may require careful rollout strategy.
Cluster autoscaling needs spare IPs, quotas, and correct node pool ranges.

### 14.7 Control plane events vs workload events

An important SRE skill is separating platform from application failure.
Questions to ask:

- are workloads failing because nodes are unhealthy
- or are nodes fine and only one deployment is broken
- did a control plane action happen at incident start
- or did a bad rollout happen at the same time

### 14.8 Observability for GKE workloads

At minimum, instrument:

- request rate
- success ratio
- latency percentiles
- pod restarts
- container OOMs
- HPA behavior
- queue depth or backlog age for async workers
- dependency status where possible

### 14.9 Autopilot reliability perspective

Autopilot often improves baseline reliability by reducing node-level misconfiguration.
It enforces safer defaults.
It also restricts some patterns.
Teams that truly need low-level kernel, privileged, or niche daemon behavior may prefer Standard.
For many service teams, Autopilot reduces toil and therefore improves reliability outcomes.

### 14.10 Managed control plane reality check

Because the control plane is managed, do not waste time designing custom masters.
Spend that energy on:

- resilient app architecture
- observability
- deployment safety
- dependency management
- incident response maturity

### 14.11 GKE production checklist

Before production launch, verify:

- regional cluster or clear zonal risk acceptance
- Workload Identity enabled
- private nodes and controlled ingress where appropriate
- upgrade strategy documented
- maintenance windows set
- dashboards and alerts tested
- log sinks verified
- backup and restore rehearsed
- runbooks written for node, network, and IAM issues

---

## 15. Practical Tables for Fast Recall

### 15.1 IAM role selection cheat sheet

| Need | Preferred choice |
|---|---|
| Read cluster state | `roles/container.viewer` |
| Deploy workloads | `roles/container.developer` plus namespace RBAC |
| View logs | `roles/logging.viewer` |
| Manage log sinks and metrics | `roles/logging.configWriter` or a custom role |
| View metrics and dashboards | `roles/monitoring.viewer` |
| Act as a service account on compute resources | `roles/iam.serviceAccountUser` |
| Mint tokens for impersonation workflows | `roles/iam.serviceAccountTokenCreator` |

### 15.2 GKE mode selection cheat sheet

| Requirement | Better fit |
|---|---|
| Need custom node tuning | Standard |
| Want minimum node ops overhead | Autopilot |
| Run many privileged or custom daemon workloads | Standard |
| Want opinionated safety defaults | Autopilot |
| Small platform team with many app teams | Autopilot often wins |

### 15.3 Networking decision cheatsheet

| Requirement | Common answer |
|---|---|
| Private nodes needing internet egress | Cloud NAT |
| Cross-project centralized networking | Shared VPC |
| Private managed service consumption | Private Service Connect |
| Cross-VPC private connectivity without transitivity | VPC peering |
| L7 HTTP routing for GKE | Ingress or Gateway API |

### 15.4 Observability signal cheatsheet

| Question | Primary tool | Secondary tool |
|---|---|---|
| Is the service up for users | Uptime checks / SLO | Logs |
| Is latency isolated to one dependency | Trace | Metrics |
| Are errors grouped by stack signature | Error Reporting | Logs |
| Is the workload resource-starved | Metrics | Profiler |
| Did someone change IAM | Audit logs | Cloud Asset / policy review |

---

## 16. Failure Patterns SREs See Repeatedly

### 16.1 Over-privileged identities

The team grants `editor` during an outage.
The role is never removed.
Months later a routine script makes a destructive change.
The true fix is access process design, not blame.

### 16.2 Pod IP exhaustion

The cluster worked for months.
Autoscaling increased node count.
Suddenly new pods stay Pending.
The root cause is CIDR planning done for day one, not year two.

### 16.3 Noisy alerting

Teams page on CPU for every service.
Autoscaling handles it.
On-call ignores pages.
Then a real saturation incident arrives and trust is already gone.

### 16.4 Sink misconfiguration

A log sink is created but writer permissions are missing.
The team thinks logs are being archived.
During an investigation, the export dataset is empty.
Always verify sinks after creation.

### 16.5 Upgrade deadlock

Auto-upgrade starts.
PDBs are too strict.
Quota headroom is insufficient for surge.
The node pool stalls mid-upgrade.
This is not a GKE mystery.
It is a workload disruption-planning failure.

### 16.6 Service account key leakage

A JSON key lands in CI variables or a repo.
The key is copied to multiple systems.
Revocation takes days because nobody knows what uses it.
This is why Workload Identity and impersonation matter.

---

## 17. Closing Guidance

Design hierarchy before scale arrives.
Use IAM with intent, not convenience.
Prefer Workload Identity over keys.
Prefer regional GKE for production unless a conscious exception exists.
Plan pod and service CIDRs like durable infrastructure.
Treat Monitoring and Logging as production dependencies.
Use Cloud Build and Artifact Registry as part of your reliability story, not just delivery tooling.
Remember that managed Kubernetes reduces toil but does not remove the need for SRE discipline.
If you master these topics, the labs in this repository will feel practical rather than abstract.
