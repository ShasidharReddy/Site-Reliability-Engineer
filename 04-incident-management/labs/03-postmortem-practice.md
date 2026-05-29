# Lab 03: Postmortem Practice

## Overview
Write a postmortem from a simulated incident.

## Simulated Incident
- Service: checkout-api
- Duration: 14:12 to 14:58 (46 min)
- Impact: ~15% of checkout attempts failed
- Root cause: Node disk pressure caused IO throttling
- Detection: User report (monitoring gap — no disk alert!)

## Timeline to Build
```
14:12 — Disk usage on 3 nodes crossed 90% (undetected)
14:12 — checkout-api pods on those nodes start experiencing IO throttling
14:22 — First user reports intermittent checkout failures
14:23 — L2 support opens SNOW ticket INC0012345
14:28 — L2 confirms error rate in Grafana (14.8%)
14:35 — L2 identifies 5/8 pods on high-disk nodes
14:37 — L2 escalates to SRE with full context
14:42 — SRE scales node pool (adds 3 new nodes)
14:52 — Pods reschedule to new nodes. Error rate dropping.
14:58 — Error rate 0.0%. Incident resolved.
```

## Write the Postmortem

Fill in the postmortem template (see templates/postmortem-template.md):

1. **Summary**: 2-3 sentence summary with impact, duration, root cause
2. **Impact**: quantify — users affected, revenue estimate, SLO impact
3. **Timeline**: detailed minute-by-minute with sources
4. **Root cause**: technical and systemic
5. **Detection gap**: why monitoring didn't catch it
6. **Action items**: SMART format

## 5 Whys Analysis
Apply to this incident:
- Why did checkout fail? (IO throttling on pods)
- Why was there IO throttling? (disk at >90% on nodes)
- Why did disk fill up? (log rotation not configured)
- Why was log rotation not configured? (not in deployment checklist)
- Why isn't disk monitored? (alert threshold too conservative / missing)

## Verification
- [ ] Timeline accurate with sources (Grafana, SNOW, Slack)
- [ ] Root cause is systemic (not "person made mistake")
- [ ] Action items are SMART (specific, measurable, assigned, time-bound)
- [ ] Detection gap explicitly addressed
- [ ] Postmortem shared with team
