# Lab 03: ServiceNow Workflow

## Scenario
API intermittent 503 errors — practice proper ticket management.

## Step 1: Create Incident

```
Short description: [payment-api] Intermittent 503 from checkout — user reports
Description:
  User-reported: Checkout failing with "Service Unavailable"
  Time started: ~14:15 (user reports 30 min ago)
  Frequency: ~15% of checkout attempts
  Initial check: Grafana shows 15% error rate on /v2/checkout since 14:12
  No scheduled maintenance window
  Last deployment: 2 days ago

Business service: Payment Platform
Priority: P2
```

## Step 2: Work Notes Template
```
[14:23] Assigned. Beginning investigation.
[14:28] Confirmed: 14.8% error rate in Grafana on /v2/checkout. Other endpoints healthy.
[14:31] Pod logs: "upstream connect error" in nginx ingress. 5/8 payment-api pods affected.
[14:35] Found: 5 pods on nodes with 94% disk usage since 14:10.
[14:37] Hypothesis: disk pressure causing I/O throttling.
[14:45] SRE added new nodes. Pods rescheduling.
[14:58] Error rate: 0.0%. Service restored.
```

## Step 3: Resolution Notes
```
Root cause: Node pool disk pressure (94%) caused I/O throttling on 5/8 pods.
Fix: SRE scaled node pool, pods rescheduled to healthy nodes.
Prevention: Reduce disk alert threshold to 80%, update PDB for node spread.
Action items: SNOW-4821 (disk alert threshold), SNOW-4822 (PDB update)
```

## Step 4: Escalation Template
```
Escalating to: SRE Engineering
Issue: payment-api 15% 503 since 14:12
Found: 5/8 pods on high-disk nodes
Tried: Pod restart — rescheduled to same nodes
Need: Node pool access to cordon/scale nodes
Grafana: [link]
SNOW: INC0012345
```

## Verification
- [ ] Incident created with all fields
- [ ] Work notes document timeline
- [ ] Resolution explains root cause
- [ ] Action items created
- [ ] Closed after user confirms
