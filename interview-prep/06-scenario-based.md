# Scenario-Based Questions

**Scenario 1: 3am — 15% 503 errors on payment API for 10 minutes.**
(1) Ack PD, create #inc-channel, declare SEV1. (2) Update status page. (3) Check deploy history — any deploy in last 30 min? (4) If yes: rollback immediately (mitigation before diagnosis). (5) Verify error rate drops. (6) If not deploy-related: check DB connectivity from app pod, check external payment gateway status page, check pod health. (7) Communicate every 30 min. Key: rollback first if recent deploy suspected.

**Scenario 2: All pods in production namespace are Pending.**
kubectl get events -n production | sort-by lastTimestamp. Describe one pending pod → Events. Check nodes: kubectl get nodes (all Ready?). Check node resources: kubectl describe nodes | grep Allocated. Check ResourceQuota: kubectl describe quota -n production. Check taints: kubectl describe nodes | grep Taint. Most common: nodes out of resources (scale up node pool), namespace quota hit, or accidental cordon/taint.

**Scenario 3: SLO burn rate alert — 80% budget consumed in 1 hour.**
Declare SEV1 — will breach SLO in ~1.5 more hours. Check SLO dashboard — which SLI burning (availability or latency)? Identify erroring endpoints: sum(rate(http_errors[5m])) by (path). Check for recent deploy. Implement mitigation (rollback, feature flag). Verify burn rate drops. Post-incident: why was 80% burned so fast — was threshold too loose? Add lower-burn-rate warning alert.

**Scenario 4: Simultaneous pod restarts across 20 services.**
Look for shared dependency failure. Check events: kubectl get events -A. Find common thread: same node pool? Same ConfigMap/Secret? Same DB? Check cluster-level: did a node fail? GKE maintenance event? Check shared infra: database connection count, Redis availability, shared NFS. Check autoscaler: did it drain a node with many pods? Use: kubectl get events -A --field-selector type=Warning --sort-by=lastTimestamp.

**Scenario 5: Customer reports intermittent 503s but your dashboards show <0.1% errors.**
(1) Trust the customer — get exact time range and client version. (2) Check load balancer logs directly (GCP: Cloud Logging, query httpRequest.status=503). (3) Check if error is from specific backend pod: error rate by (pod). (4) Check if specific region/CDN PoP affected. (5) Check health check logs — intermittent readiness probe failures? (6) Check for connection draining race on deploys. Add tracing to capture next occurrence.

**Scenario 6: Team wants to add 50 new Prometheus metrics.**
Raise: (1) Cardinality review — any unbounded labels (user_id, request_id)? (2) Estimate total series: 50 metrics × N label combos × M pods. (3) Do they need recording rules to pre-aggregate? (4) What will they alert on and dashboard? (5) Naming conventions. (6) Long-term storage needs. Propose: design doc for top 10 highest-value metrics first, review cardinality before each batch.

**Scenario 7: 30 pages per week but mostly noise — how to fix.**
(1) Export PD history: categorize actionable vs no-action-taken. (2) Top 5 noisy alerts: raise threshold, add for: duration, or delete if no value. (3) Add Alertmanager inhibition for alert storms. (4) Mandate runbook for every alert — no runbook = poorly defined alert. (5) Set repeat_interval >= 4h for warnings. (6) Target: <5 actionable pages/week. Track alert precision rate monthly.

**Scenario 8: Onboard a new service to monitoring.**
Checklist: (1) Service exposes /metrics with Golden Signals. (2) ServiceMonitor created for Prometheus scraping. (3) SLI/SLO defined in slo-definition.yaml. (4) Grafana dashboard with Golden Signals + SLO panel provisioned via Git. (5) PrometheusRule for error rate, latency, availability alerts. (6) Runbook linked in every alert annotation. (7) Added to on-call rotation if Tier 1. (8) Status page entry if customer-facing. (9) Tested: trigger error, verify alert fires and routes correctly.

**Scenario 9: GKE cluster upgrade — ensure zero downtime.**
(1) Verify all Deployments have PDBs (minAvailable >= 1 or maxUnavailable < total). (2) Verify all Deployments have >= 2 replicas. (3) Set maxSurge: 1, maxUnavailable: 0 on Deployments. (4) Check for DaemonSets with PDBs. (5) Test drain on non-prod: kubectl drain <node> --ignore-daemonsets --dry-run. (6) Configure surge upgrade on node pool: --max-surge-upgrade 1 --max-unavailable-upgrade 0. (7) Monitor during upgrade: watch kubectl get nodes and pod error rate.

**Scenario 10: Grafana shows memory leak in production pod — how to handle.**
(1) Is it impacting SLO now? If yes: restart pod (mitigation) while investigating. (2) Get memory growth rate from Grafana: container_memory_working_set_bytes over 24h. (3) Check OOM history: kubectl describe pod → Last State. (4) Temporarily increase memory limit to buy time. (5) Get heap dump: kubectl exec <pod> -- jmap -dump:format=b,file=/tmp/heap.hprof <pid> (Java), or pprof (Go). (6) Copy dump for analysis: kubectl cp. (7) Work with dev team to identify leak: unbounded cache, connection pool not closing, large in-memory dataset.
