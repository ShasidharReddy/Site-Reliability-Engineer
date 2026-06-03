# SRE Full-Stack Incident Scenarios

Use these drills to practice production response across Kubernetes, monitoring, GCP, Linux, networking, and incident management.
Each scenario assumes realistic paging pressure, incomplete information, and the need to keep a timeline while debugging.

## Drill rules

- Assign an incident commander, driver, communications lead, and scribe before running the first command.
- Freeze additional deploys unless the scenario explicitly requires a forward fix.
- Confirm blast radius early: user segment, region, namespace, cluster, or shared dependency.
- Prefer reversible mitigations first: rollback, traffic shift, scale-out, or temporary feature disablement.
- Record every assumption that turns out wrong; scenario practice is as much about decision quality as commands.

## Scenario 1: The Monday Morning Cascade

A 9:00 AM deploy starts as a single service regression and turns into a multi-signal monitoring failure.

### Cross-module focus
- Kubernetes scheduling and memory limits
- Prometheus scrape health and alert blindness
- Incident command, rollback, and postmortem discipline

### Background
- The checkout API deploys a build with an accidental in-memory cache of full cart objects.
- Each new pod uses 2-3x more memory than the previous version during traffic spikes.
- HPA sees CPU climb from retry storms and starts requesting more replicas.
- Nodes fill faster than Cluster Autoscaler can add replacement capacity.

### Alert context
- Initial page: `CheckoutHighErrorRate` and `CheckoutPodsOOMKilled` at 09:04.
- Follow-up pages: `NodeMemoryPressure`, `PrometheusTargetMissing`, and `AlertmanagerNotificationsDropped`.
- Customer support reports cart failures and intermittent timeouts from the storefront.

### First 15 minutes
1. Declare one incident commander and one driver immediately because many alerts will be noisy or misleading.
2. Freeze further deploys to the affected namespace before the HPA multiplies bad pods.
3. Confirm whether old ReplicaSets are still healthy enough to serve rollback traffic.
4. Preserve observability capacity because losing Prometheus visibility will slow every later decision.

### Kubernetes investigation commands
```bash
kubectl get pods -n checkout -o wide
kubectl describe pod -n checkout <oom-pod>
kubectl get hpa -n checkout && kubectl describe hpa checkout-api -n checkout
kubectl top nodes && kubectl top pods -n checkout --sort-by=memory
```

### Monitoring and PromQL commands
```bash
curl -s "http://127.0.0.1:9090/api/v1/query?query=rate(container_oom_events_total{namespace=\"checkout\"}[5m])" | jq .
curl -s "http://127.0.0.1:9090/api/v1/query?query=up{job=\"kubernetes-pods\"}" | jq ".data.result[] | select(.value[1] != \"1\")"
curl -s "http://127.0.0.1:9090/api/v1/query?query=prometheus_target_scrape_pool_targets" | jq .
kubectl -n monitoring logs statefulset/prometheus-kube-prometheus-stack-prometheus --tail=200
```

### GCP, cloud, or shell commands
```bash
gcloud container clusters describe prod-cluster --region us-central1
gcloud compute instances list --filter="name~gke-prod-cluster"
kubectl get events -A --sort-by=.lastTimestamp | egrep "OOM|Evicted|FailedScheduling|Scrape" | tail -40
kubectl rollout history deploy/checkout-api -n checkout
```

### Evidence to collect
- OOMs start only after revision 2024.09.1 is created.
- HPA desired replicas climb while available replicas fall because most new pods never stabilize.
- Prometheus misses scrapes from kubelets and application pods because pressure removes node-exporter and app endpoints.
- Alertmanager is still running, but its notifications are degraded because upstream alerts become incomplete and grouping explodes.

### Root cause identification
- The deploy introduced a memory regression large enough to trigger pod-level OOM kills under real traffic.
- Autoscaling amplified the bad revision, increasing node memory pressure and reducing observability coverage.
- The monitoring stack depended on the same stressed nodes, so incident visibility degraded as the outage worsened.

### Mitigation plan
1. Rollback the checkout deployment to the previous ReplicaSet and cap HPA max replicas until memory returns to baseline.
2. Cordon and drain the most unstable nodes only after enough healthy capacity exists to absorb replacement pods.
3. Scale Prometheus or move it to protected nodes if scrape gaps persist after the rollback.
4. After user traffic stabilizes, review whether alert severity and runbook wording captured the cascade clearly enough.

### Postmortem fragment
```text
Impact: Checkout error rate peaked at 28% for 19 minutes; SREs lost partial telemetry for 11 minutes.
Trigger: Memory-heavy deploy at 09:00 with no canary memory guardrail.
Detection gap: The first page said application failure, but no automated rollback was tied to OOM rate.
Corrective actions: Add canary memory budgets, protect Prometheus on dedicated nodes, and cap HPA during unstable revisions.
```

### Lessons learned
- A healthy HPA can amplify a bad application build if the metric driving it is not the real bottleneck.
- Observability stacks need fault isolation from the workloads they are observing.
- Rollback authority should be explicit in the incident process; waiting for application approval costs minutes during a cascade.
- Postmortems should capture the systems interaction, not only the original code defect.

## Scenario 2: Silent SLO Burn

Error budget burns at 10x normal for three days, but the burn-rate alert never fires because the detector itself is wrong.

### Cross-module focus
- PromQL and recording rule audit
- Grafana dashboard provenance and SLI governance
- Release freeze decisions based on corrected math

### Background
- A backend service starts returning 502s for one mobile API route after a third-party auth dependency changes behavior.
- The route is low-volume relative to total traffic but high-value for premium users.
- The SLO dashboard shows healthy numbers because it excludes `route` labels created after a metrics refactor.
- The burn-rate alert depends on a recording rule that still references the old label set.

### Alert context
- No burn-rate page fired for 72 hours.
- On day three, the release gate calculates exhausted budget from a separate policy script and freezes deploys.
- Support tickets and partner complaints reveal premium-user impact far earlier than the dashboards did.

### First 15 minutes
1. Do not assume the release gate is wrong; prove which numerator and denominator each tool uses.
2. Pull the current alert expression, recording rule, dashboard JSON, and policy script into one timeline.
3. Separate customer-facing traffic from synthetic and batch traffic before recomputing the budget.
4. Assign one responder to math validation and one to the application fix so you do not block both tracks.

### Kubernetes investigation commands
```bash
kubectl -n monitoring get prometheusrule -o yaml | grep -n "burn" -n
kubectl -n monitoring get configmap -l grafana_dashboard=1 -o yaml | grep -n "availability" -n
kubectl logs deploy/mobile-api -n production --since=24h | egrep "502|auth" | tail -100
kubectl rollout history deploy/mobile-api -n production
```

### Monitoring and PromQL commands
```bash
curl -s "http://127.0.0.1:9090/api/v1/query?query=sum(rate(http_requests_total{job=\"mobile-api\",status=~\"5..\"}[5m])) by (route)" | jq .
curl -s "http://127.0.0.1:9090/api/v1/query?query=slo:availability:ratio_30d{service=\"mobile-api\"}" | jq .
curl -s "http://127.0.0.1:9090/api/v1/rules" | jq ".data.groups[]?.rules[] | select(.name|test(\"Burn\")) | {name:.name,query:.query}"
curl -s "http://127.0.0.1:9090/api/v1/query?query=sum(rate(http_requests_total{job=\"mobile-api\",route=\"/v2/premium/login\"}[30d]))" | jq .
```

### GCP, cloud, or shell commands
```bash
gcloud logging read "resource.type=k8s_container AND resource.labels.namespace_name=production AND textPayload:502" --limit 20 --freshness=7d
gcloud monitoring time-series list --filter="metric.type=\"custom.googleapis.com/mobile_api/error_rate\"" --limit=5
bash -lc "python3 scripts/recompute_budget.py --service mobile-api --days 30"
gh issue create --title "Audit mobile-api SLI label drift" --body "Burn alert missed premium route traffic after metrics refactor." --label reliability
```

### Evidence to collect
- The recording rule filters on `handler`, but the application now exports `route`.
- Grafana pulls from the stale recording rule, so the chart and alert agree with each other while both are wrong.
- The policy script uses raw request logs and sees the premium route failures correctly.
- Premium traffic is a small percentage of total volume, but its failures consume budget faster than the product team expected.

### Root cause identification
- A metrics schema refactor changed label names without updating the recording rule or the burn-rate alert.
- The dashboard and alert shared the same stale source, creating a false sense of correctness.
- Governance around SLI ownership was weak enough that no one audited the query after instrumentation changed.

### Mitigation plan
1. Patch the recording rule and alert to use the canonical route label, then backtest it against recent traffic.
2. Fix the premium login route and rerun the 30-day budget calculation with corrected data.
3. Temporarily keep the release freeze until leaders agree on whether retroactive budget spend applies operationally.
4. Document the SLI contract so future instrumentation refactors require query review before merge.

### Postmortem fragment
```text
Impact: Three days of premium-user degradation consumed the monthly budget before anyone was paged.
Trigger: Instrumentation label rename from `handler` to `route` without SLI rule update.
Detection gap: Dashboard and alert shared the same broken recording rule, so neither provided an independent check.
Corrective actions: Add SLI unit tests, quarterly query audits, and route-level traffic floors for premium endpoints.
```

### Lessons learned
- Two observability tools using the same bad source are not independent validation.
- High-value low-volume routes need explicit inclusion and often their own alert guards.
- Release freeze policy should define how to handle retroactive SLI corrections before the next incident.
- SLI ownership must be explicit whenever instrumentation schemas change.

## Scenario 3: 3 AM Multi-Region Latency Spike

EU and APAC users see slowness while US traffic looks normal, forcing a region-by-region investigation across GKE, Cloud Armor, storage, and node health.

### Cross-module focus
- Regional user-impact isolation
- Cloud Armor and GCLB behavior
- GCS-backed static asset diagnosis alongside Kubernetes service latency

### Background
- The application runs on a GKE regional cluster with traffic routed through a global external HTTP(S) load balancer and Cloud Armor.
- Static assets live in GCS behind CDN, while dynamic API traffic lands on Kubernetes services.
- Only EU and APAC complain; US synthetic checks remain green.
- The latency spike begins after a networking change intended to tighten Cloud Armor rules.

### Alert context
- Alerts: `ApiLatencyHigh` from EU probes, `CloudArmorDenyRateIncrease`, and `GCSAssetFetchSlow`.
- No global availability page fires because US traffic dominates aggregate dashboards.
- Support tickets mention CSS and image load failures more often than API timeouts.

### First 15 minutes
1. Break the problem into edge, static asset, and dynamic API paths; do not treat it as one homogeneous outage.
2. Compare region-specific SLIs and logs immediately because aggregate global charts are already hiding the issue.
3. Decide whether to shift traffic away from the degraded path before full root cause is proven.
4. Keep a note of which regions are affected by assets, APIs, or both, because that narrows the fault domain fast.

### Kubernetes investigation commands
```bash
kubectl get pods -n production -o wide
kubectl top pods -n production --sort-by=cpu
kubectl logs deploy/api-gateway -n production --since=30m | egrep "timeout|upstream" | tail -80
kubectl exec -n production <debug-pod> -- curl -sw "dns=%{time_namelookup} connect=%{time_connect} start=%{time_starttransfer}\n" https://app.example.com/health -o /dev/null
```

### Monitoring and PromQL commands
```bash
curl -s "http://127.0.0.1:9090/api/v1/query?query=histogram_quantile(0.95,sum(rate(http_request_duration_seconds_bucket{region=~\"europe-west1|asia-south1\"}[5m])) by (le,region))" | jq .
curl -s "http://127.0.0.1:9090/api/v1/query?query=sum(rate(cloudarmor_denied_requests_total[5m])) by (origin_region,rule_name)" | jq .
curl -s "http://127.0.0.1:9090/api/v1/query?query=sum(rate(gcs_request_duration_seconds_count[5m])) by (location)" | jq .
kubectl -n monitoring logs deploy/kube-prometheus-stack-grafana --tail=50
```

### GCP, cloud, or shell commands
```bash
gcloud compute security-policies rules list edge-policy
gcloud logging read "resource.type=http_load_balancer AND jsonPayload.enforcedSecurityPolicy.name=edge-policy" --limit 20 --freshness=30m
gcloud storage ls -L gs://prod-static-assets
gcloud compute backend-services get-health prod-api-backend --global
```

### Evidence to collect
- Cloud Armor denies increase sharply for EU and APAC CIDR blocks after the rule change.
- GCS asset latency is elevated only for one bucket region serving those geographies.
- US regional probes use a different CDN cache path and stay healthy, masking the issue in aggregate availability.
- Kubernetes pods remain healthy, but edge retries increase API latency by forcing extra round trips.

### Root cause identification
- A Cloud Armor rule change over-matched regional traffic, causing extra challenges and denials for EU/APAC users.
- At the same time, a cache miss pattern forced affected users to fetch more static assets directly from a slower GCS path.
- The cluster itself was largely healthy; the outage lived at the intersection of edge policy and asset serving.

### Mitigation plan
1. Rollback or narrow the offending Cloud Armor rule and confirm deny rates drop by region.
2. Warm or prefetch the impacted GCS-backed assets, or temporarily route them through a healthier cached path.
3. Keep region-specific dashboards visible during the incident so US health does not dominate the narrative.
4. After recovery, add synthetic probes from every major user geography to both asset and API paths.

### Postmortem fragment
```text
Impact: EU and APAC users saw 4-8x latency and partial asset failures for 47 minutes while US metrics remained healthy.
Trigger: Cloud Armor policy rollout combined with cold-cache fetches from a slower asset path.
Detection gap: Global dashboards hid regional pain because US traffic weighted the aggregates.
Corrective actions: Region-level SLOs, staged Cloud Armor rollout, and geo-distributed synthetic checks.
```

### Lessons learned
- Global green dashboards do not prove regional user health.
- Edge policy and object storage can create application symptoms even when Kubernetes is fine.
- Static and dynamic paths need separate telemetry during triage.
- Change reviews for security controls should include regional synthetic test results.

## Scenario 4: Database Credentials Rotated, Everything Breaks

A security rotation in Secret Manager invalidates credentials for 200 pods across 15 services, and no single team owns the whole blast radius.

### Cross-module focus
- Mass secret propagation and prioritization
- Kubernetes secret refresh behavior
- Cross-team incident coordination at service fleet scale

### Background
- Security rotates a shared production database password in Secret Manager during a routine maintenance window.
- External Secrets syncs to Kubernetes, but half the services consume credentials as env vars and never restart.
- Fifteen services, including queue workers and customer APIs, share the same database cluster.
- No single product team owns the shared secret dependency map.

### Alert context
- Pages: `DatabaseAuthFailuresHigh`, `ConnectionPoolTimeouts`, and several service-specific 5xx alerts.
- Support reports login, checkout, and background fulfillment delays simultaneously.
- DB itself is healthy; failures are concentrated around authentication.

### First 15 minutes
1. Classify services into customer-facing critical, async revenue-impacting, and deferrable internal workloads.
2. Find the shared secret name and which services consume it before restarting everything blindly.
3. Pause nonessential rollouts and batch jobs to protect the database during recovery.
4. Designate one lead for fleet inventory and one for the restart plan so teams do not overlap or miss services.

### Kubernetes investigation commands
```bash
kubectl get secret -A | grep database-credentials
kubectl get deploy,statefulset -A -o yaml | grep -n "database-credentials" -n
kubectl logs -A --since=20m | egrep "password authentication failed|permission denied" | head -200
kubectl rollout restart deploy -n <ns> <deploy>
```

### Monitoring and PromQL commands
```bash
curl -s "http://127.0.0.1:9090/api/v1/query?query=sum(rate(db_auth_failures_total[5m])) by (service)" | jq .
curl -s "http://127.0.0.1:9090/api/v1/query?query=sum(rate(http_requests_total{status=~\"5..\"}[5m])) by (service)" | jq .
curl -s "http://127.0.0.1:9090/api/v1/query?query=sum(rate(queue_depth_total[5m])) by (queue)" | jq .
kubectl -n monitoring get pods | grep reloader
```

### GCP, cloud, or shell commands
```bash
gcloud secrets versions list prod-db-password --project prod-platform
gcloud logging read "textPayload:\"password authentication failed\"" --limit 50 --freshness=30m
gcloud sql instances describe prod-main-db
gh issue create --title "Map shared DB credential consumers" --body "Created during auth outage." --label reliability
```

### Evidence to collect
- Services using mounted secrets recover automatically or after short refresh delay; env-var consumers do not.
- The same auth failure string appears across namespaces with different owners, proving a shared dependency issue.
- Queue workers can be deprioritized briefly while login and checkout are restarted first.
- No database CPU or replication alert fires, which helps separate auth propagation from database performance.

### Root cause identification
- Secret rotation was correct in Secret Manager but incomplete operationally because many workloads required restart to consume the new value.
- The platform lacked an authoritative inventory of which services shared the credential.
- Ownership fragmentation slowed prioritization and restart sequencing.

### Mitigation plan
1. Restart the highest-priority customer-facing services first, then revenue-impacting workers, then noncritical jobs.
2. If restart storm risk is high, batch by namespace and watch database connection counts between waves.
3. Deploy or verify a reloader controller so future secret rotations trigger controlled rollout for env-var consumers.
4. Build and store a living dependency map for shared credentials after the incident.

### Postmortem fragment
```text
Impact: Authentication-related failures hit 15 services; customer-facing errors lasted 32 minutes.
Trigger: Database password rotation without coordinated restart plan for env-var consumers.
Detection gap: No fleet-level alert existed for shared-secret auth failures across services.
Corrective actions: Shared-secret inventory, staggered restart automation, and rotation runbook that differentiates env vs volume consumers.
```

### Lessons learned
- Secret rotation is a distributed systems event, not just a security task.
- Shared dependencies need fleet inventory and blast-radius ranking ahead of time.
- Bulk restarts must protect downstream databases from reconnection storms.
- Incident command matters most when ownership is fragmented across many teams.

## Scenario 5: Grafana Shows 99.9% Uptime, Customers Say Site Was Down

Support has 500 tickets from an hour of real downtime, but the SLI recorded near-perfect availability because it measured the wrong thing.

### Cross-module focus
- SLI audit against user journey reality
- Retroactive SLO recalculation
- Separating transport success from business success

### Background
- The checkout frontend returned HTTP 200 for a maintenance-page shell while the API behind it failed every order submit.
- The official availability SLI counted only successful edge responses from the ingress controller.
- Support tickets and payment-partner logs show customers could not complete purchases for nearly an hour.
- Grafana remained green because the edge kept serving HTML successfully.

### Alert context
- Support escalation arrives before SRE paging because the chosen SLI never violated its threshold.
- Synthetic probe success remains high because probes only request the landing page.
- Business dashboards show order conversions falling to almost zero.

### First 15 minutes
1. Translate the customer complaint into a measurable user journey: browse, add to cart, submit order, receive confirmation.
2. Find where the current SLI sits in that journey and whether it can observe order-submit success at all.
3. Keep evidence from support, payments, and application logs together so the discussion does not become only theoretical.
4. Freeze claims about uptime until the SLI and business signals are reconciled.

### Kubernetes investigation commands
```bash
kubectl logs deploy/checkout-web -n production --since=2h | tail -100
kubectl logs deploy/checkout-api -n production --since=2h | egrep "500|payment|submit" | tail -100
kubectl get ingress -n production checkout -o yaml
kubectl rollout history deploy/checkout-api -n production
```

### Monitoring and PromQL commands
```bash
curl -s "http://127.0.0.1:9090/api/v1/query?query=sum(rate(nginx_ingress_controller_requests{status!~\"5..\"}[5m]))/sum(rate(nginx_ingress_controller_requests[5m]))" | jq .
curl -s "http://127.0.0.1:9090/api/v1/query?query=sum(rate(order_submit_total{result=\"success\"}[5m]))/sum(rate(order_submit_total[5m]))" | jq .
curl -s "http://127.0.0.1:9090/api/v1/query?query=sum(rate(payment_partner_callback_failures_total[5m]))" | jq .
curl -s "http://127.0.0.1:9090/api/v1/query_range?query=order_submit_total&start=<start>&end=<end>&step=60" | jq .
```

### GCP, cloud, or shell commands
```bash
gcloud logging read "resource.type=k8s_container AND textPayload:order-submit" --limit 50 --freshness=2h
gcloud monitoring time-series list --filter="metric.type=\"custom.googleapis.com/business/order_conversion\"" --limit=5
bash -lc "python3 scripts/recompute_slo.py --sli order-submit --start 2024-09-18T10:00:00Z --end 2024-09-18T11:00:00Z"
gh issue create --title "Replace ingress availability SLI for checkout" --body "Business success differed from transport success." --label slo
```

### Evidence to collect
- Ingress success stayed high because customers received a 200 response body, but order-submit success collapsed.
- Support tickets and payment-provider logs line up exactly with the missing business-success metric.
- The synthetic probe exercised only page load, not checkout completion.
- Retroactive order-submit data is available from application metrics and logs, allowing recalculation.

### Root cause identification
- The selected SLI measured edge availability rather than the user-critical transaction.
- Dashboards and alerts were optimized for transport success, not business success.
- Probe design did not include the end-to-end order path, so the outage remained invisible to the official uptime view.

### Mitigation plan
1. Adopt a transaction-success SLI for checkout and keep edge availability as a secondary supporting metric.
2. Recalculate the affected SLO window using order-submit success to determine real budget impact.
3. Expand synthetics to include authenticated or staged checkout flows that resemble real user behavior.
4. Update customer and leadership communication to explain why the old uptime figure was inaccurate.

### Postmortem fragment
```text
Impact: Customers experienced near-total checkout failure for 58 minutes despite a green uptime dashboard.
Trigger: API/payment failure hidden behind successful HTTP 200 landing-page responses.
Detection gap: Official SLI measured transport success instead of order completion.
Corrective actions: New transaction SLI, deeper synthetics, and mandatory SLI reviews with product owners.
```

### Lessons learned
- A valid HTTP response is not always a successful user outcome.
- Support tickets and business metrics are legitimate observability signals when SLIs are suspect.
- Retroactive SLO recalculation should be an established practice, not an improvisation.
- Every critical journey needs a named owner for its SLI definition.

## Scenario 6: A Node Pool Upgrade Causes 30% Pod Evictions

A GKE node pool upgrade begins normally, but restrictive PDBs and quorum-sensitive stateful sets turn maintenance into an availability incident.

### Cross-module focus
- Controlled GKE upgrade procedure
- PDB and StatefulSet recovery
- Capacity and quorum protection during maintenance

### Background
- Platform starts a routine GKE node pool upgrade during a low-traffic window.
- Several services have `minAvailable: 100%` PDBs copied from an old template.
- A stateful messaging cluster runs three replicas with no extra surge capacity.
- The upgrade drains nodes faster than the application teams expected.

### Alert context
- Alerts: `PodEvictionsHigh`, `PDBBlockingDrain`, and `StatefulSetQuorumRisk`.
- GKE marks the upgrade as stalled while workloads remain partially unavailable.
- User-facing impact starts when one stateful set loses quorum and dependent APIs back up.

### First 15 minutes
1. Stop the upgrade or reduce its concurrency before more nodes drain.
2. Find which PDBs and StatefulSets are blocking or losing quorum, not just which nodes are draining.
3. Decide whether capacity can be added before relaxing disruption budgets.
4. Create a clear record of which changes are temporary maintenance overrides so they can be reverted.

### Kubernetes investigation commands
```bash
kubectl get pdb -A
kubectl get pods -A | egrep "Evicted|Pending|Terminating"
kubectl describe pdb <pdb> -n <ns>
kubectl rollout status statefulset/<name> -n <ns>
```

### Monitoring and PromQL commands
```bash
curl -s "http://127.0.0.1:9090/api/v1/query?query=sum(rate(kube_pod_evict_total[5m])) by (namespace)" | jq .
curl -s "http://127.0.0.1:9090/api/v1/query?query=kube_poddisruptionbudget_status_current_healthy" | jq .
curl -s "http://127.0.0.1:9090/api/v1/query?query=sum(rate(statefulset_quorum_loss_total[5m])) by (statefulset)" | jq .
kubectl get events -A --sort-by=.lastTimestamp | grep -i disruption | tail -50
```

### GCP, cloud, or shell commands
```bash
gcloud container operations list --filter="TYPE:UPGRADE" --limit=5
gcloud container node-pools describe prod-general --cluster prod-cluster --region us-central1
gcloud compute instances list --filter="name~gke-prod-general"
gcloud container clusters update prod-cluster --region us-central1 --no-enable-autoupgrade
```

### Evidence to collect
- PDBs with 100% availability requirements leave no room for voluntary disruption.
- Stateless services recover once new nodes arrive, but stateful quorum loss persists until members rejoin safely.
- The upgrade controller is not broken; it is respecting budgets that no longer match reality.
- Node surge capacity was too small to host replacements before drains started.

### Root cause identification
- The upgrade collided with over-restrictive PDBs and underprovisioned maintenance capacity.
- Stateful workloads lacked an explicit upgrade playbook, so quorum-sensitive services were treated like stateless deployments.
- Automatic maintenance proceeded without validating disruption budgets against real topology.

### Mitigation plan
1. Pause the upgrade, add temporary surge capacity, and recover quorum-sensitive services first.
2. Relax the strictest PDBs only after confirming extra healthy replicas or application-safe failover steps.
3. Resume upgrades in smaller waves with explicit verification after each node drain.
4. Create a pre-upgrade checklist that includes PDB audit, stateful service approval, and rollback conditions.

### Postmortem fragment
```text
Impact: 30% of pods were evicted; one messaging cluster lost quorum and caused downstream API latency for 41 minutes.
Trigger: Routine node pool upgrade without sufficient surge capacity and with overly strict PDBs.
Detection gap: Maintenance readiness checks did not model voluntary disruption for stateful workloads.
Corrective actions: PDB standard review, maintenance canary upgrades, and stateful upgrade runbooks.
```

### Lessons learned
- PDBs protect availability only when they match real redundancy, not aspirational redundancy.
- Node upgrades are application events, not just infrastructure events.
- Stateful services need bespoke maintenance procedures and quorum-aware dashboards.
- Platform automation should fail fast when pre-checks detect impossible disruption budgets.

## Scenario 7: Log Volume Explodes, Loki Dies, Alerts Stop Working

A single noisy microservice floods Loki, fills disks, and indirectly breaks alert evaluation that depends on logs.

### Cross-module focus
- Log pipeline backpressure and retention safety
- Loki availability and alert dependencies
- Multi-system recovery sequencing under telemetry failure

### Background
- A new service deploys with debug logging enabled in a tight request loop.
- Log rate jumps to 10,000 lines per second from one namespace.
- Promtail agents back up, Loki ingesters fill disk, and compaction stalls.
- One operational alert depends on a Loki log query rather than Prometheus metrics.

### Alert context
- Alerts: `LokiDiskUsageHigh`, `PromtailDroppedEntries`, and then silence from the log-based alert that normally catches auth anomalies.
- Applications keep running, so user impact is initially indirect: missing logs and blind responders.
- Eventually, kubelet disk pressure starts on nodes hosting Loki components.

### First 15 minutes
1. Throttle the log source first; recovering the pipeline without reducing input usually fails.
2. Protect alerting by identifying which rules depend on Loki and whether a temporary Prometheus substitute exists.
3. Preserve a sample of the noisy logs before disabling them entirely so the source bug can still be debugged.
4. Treat observability loss as customer-risking even before application metrics fail.

### Kubernetes investigation commands
```bash
kubectl logs deploy/noisy-service -n production --since=5m | head -100
kubectl get pods -n monitoring -o wide | egrep "loki|promtail"
kubectl describe pod -n monitoring <loki-pod>
kubectl get events -A --sort-by=.lastTimestamp | egrep "DiskPressure|Evicted|loki|promtail" | tail -50
```

### Monitoring and PromQL commands
```bash
curl -s "http://127.0.0.1:9090/api/v1/query?query=sum(rate(loki_distributor_bytes_received_total[5m])) by (tenant)" | jq .
curl -s "http://127.0.0.1:9090/api/v1/query?query=sum(rate(promtail_dropped_entries_total[5m])) by (job)" | jq .
curl -s "http://127.0.0.1:9090/api/v1/query?query=loki_request_duration_seconds_count" | jq .
kubectl -n monitoring logs deploy/loki-read --tail=200
```

### GCP, cloud, or shell commands
```bash
gcloud logging read "resource.type=k8s_container AND resource.labels.namespace_name=production AND textPayload:DEBUG" --limit 20 --freshness=15m
gcloud compute disks list --filter="name~loki"
kubectl scale deploy/noisy-service -n production --replicas=0
kubectl -n monitoring exec <loki-pod> -- df -h
```

### Evidence to collect
- The noisy service alone accounts for the majority of bytes received by Loki.
- Promtail retries and dropped-entry counters increase before Loki becomes fully unavailable.
- The log-based alert stops evaluating because its datasource becomes unhealthy, not because the underlying auth issue disappeared.
- Node disk pressure begins on the monitoring nodes, threatening more than just logging.

### Root cause identification
- Debug logging at extreme volume overwhelmed the log ingestion and storage path.
- Alert design coupled a critical detector to Loki availability without a backup metrics-based signal.
- Monitoring workloads were not sufficiently isolated from disk exhaustion caused by log bursts.

### Mitigation plan
1. Disable or scale down the noisy service and verify log ingress drops immediately.
2. Free Loki disk safely by retaining required forensics, then restore compaction and ingestion health.
3. Replace or duplicate the critical log-based rule with a Prometheus-backed signal before closing the incident.
4. Add per-service log rate limits and debug-log feature flags that can be disabled remotely.

### Postmortem fragment
```text
Impact: Loki was degraded for 36 minutes and one auth anomaly alert was blind during the same window.
Trigger: Debug logging loop in newly deployed microservice.
Detection gap: Critical alerting depended on a single Loki datasource without fallback.
Corrective actions: Per-service log budgets, protected monitoring nodes, and dual-source alerting for critical risks.
```

### Lessons learned
- Logs are production traffic and need budgets like any other workload.
- Observability backends should have quotas and isolation from application spikes.
- Critical alerts should avoid single-datasource dependence when a fallback metric exists.
- Reducing input is often the fastest recovery lever for telemetry incidents.

## Scenario 8: The Runbook Doesn't Work at 2 AM

The alert is real, but the runbook fails midstream because tools are missing and access assumptions are wrong, extending downtime to 90 minutes.

### Cross-module focus
- Runbook usability under stress
- Access readiness and tooling parity
- Postmortem-driven hardening of operational docs

### Background
- A critical payment alert fires overnight and the on-call engineer opens the documented runbook.
- Step 4 requires a CLI utility not installed on the engineer laptop or jump host.
- Step 6 assumes production Grafana admin access, but the on-call role only has viewer permissions.
- The service remains down for 90 minutes while responders improvise around missing prerequisites.

### Alert context
- The original detector was correct; the process failure happened after detection.
- Slack fills with contradictory advice because responders are not using the same path or permissions.
- Leadership sees a long outage but the technical root cause is partly operational debt.

### First 15 minutes
1. Separate service mitigation from runbook repair; one responder should restore service while another documents each runbook failure.
2. Confirm what the on-call engineer can actually access from their current device and network path.
3. Switch to the minimal set of available tools that can still prove system health and apply the safe mitigation.
4. Capture screenshots or terminal transcripts of each broken step so the postmortem can be specific.

### Kubernetes investigation commands
```bash
kubectl get pods -n payments
kubectl logs deploy/payments-api -n payments --since=15m | tail -100
kubectl rollout undo deploy/payments-api -n payments
kubectl get events -n payments --sort-by=.lastTimestamp | tail -30
```

### Monitoring and PromQL commands
```bash
curl -s "http://127.0.0.1:9090/api/v1/query?query=sum(rate(http_requests_total{job=\"payments-api\",status=~\"5..\"}[5m]))" | jq .
curl -s "http://127.0.0.1:9090/api/v1/query?query=histogram_quantile(0.95,sum(rate(http_request_duration_seconds_bucket{job=\"payments-api\"}[5m])) by (le))" | jq .
kubectl -n monitoring port-forward svc/prometheus-operated 9090:9090
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

### GCP, cloud, or shell commands
```bash
gcloud auth list
gcloud container clusters get-credentials prod-cluster --region us-central1 --project prod-platform
bash -lc "command -v stern || echo stern-missing"
gh issue create --title "Runbook prerequisites broken for payments outage" --body "Missing CLI and insufficient access prolonged mitigation." --label postmortem
```

### Evidence to collect
- The rollback command available in the base runbook toolset restores the service, proving the detector and core mitigation were valid.
- The missing CLI was convenience tooling, not a hard requirement, but the runbook presented it as mandatory.
- Viewer-only Grafana access prevented inspection of a protected dashboard panel referenced by the runbook.
- The on-call checklist did not validate tool installation or access grants before rotation start.

### Root cause identification
- Runbook authors assumed a richer toolset and permission model than the actual on-call environment provided.
- No routine drill or access audit tested the runbook from the perspective of a fresh overnight responder.
- Operational documentation drifted away from real incident conditions.

### Mitigation plan
1. Short term: keep a minimal fallback path in the runbook using `kubectl`, `curl`, and `gcloud` only.
2. Medium term: standardize the on-call environment so required tooling is preinstalled on approved hosts.
3. Long term: rehearse runbooks during office hours with engineers who did not author them and fix every broken prerequisite.
4. Track access gaps as reliability issues, not personal setup mistakes.

### Postmortem fragment
```text
Impact: Payments were unavailable for 90 minutes; 54 of those minutes were extended by runbook/tooling/access failures.
Trigger: Valid production regression compounded by an unusable overnight runbook.
Detection gap: The team tested the detector but not the human execution path under realistic permissions.
Corrective actions: Minimal-tool runbooks, pre-rotation access audits, and quarterly game days using the exact on-call environment.
```

### Lessons learned
- A runbook is production code and needs testing in the same environment where it will be used.
- Every critical step should have a fallback path using the guaranteed base tools.
- On-call readiness includes permissions, device health, MFA, VPN, and context, not only pager ownership.
- Postmortems should record process debt with the same rigor as software defects.

