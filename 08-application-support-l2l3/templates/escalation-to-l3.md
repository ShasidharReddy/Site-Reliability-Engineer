# Escalation Template: L2 -> L3

Fill completely before escalating.

## Incident Summary
SNOW Ticket: INC-XXXXXXX
Service: [service name]
Severity: SEV[1/2/3]
Impact: [X users / X% error rate since HH:MM]

## User-Reported Symptom
[What the user sees — not what you see in monitoring]

## What I Observed
| Check | Finding |
|-------|---------|
| Grafana error rate | X% since [time] |
| Affected pods | X of Y pods |
| Recent deploys | [date/time or none in 48h] |
| K8s events | [any warnings] |
| Logs | [key error message] |
| Resources | [CPU/mem/disk] |

## What I Tried
1. [Action 1] -> [Result]
2. [Action 2] -> [Result]

## Current Hypothesis
[Best guess at root cause]

## Why I Cannot Resolve
[Specific gap: access needed / expertise needed / code change]

## What I Need From L3
[ ] Node pool access
[ ] Database access
[ ] Code-level investigation
[ ] Cloud provider console
[ ] Other: ___

## Evidence
- Grafana: [URL with time range]
- Loki: [URL]
- SNOW: [URL]
