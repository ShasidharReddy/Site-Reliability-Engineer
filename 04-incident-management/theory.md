# Incident Management — Theory

## 1. Severity Levels

### SEV Definitions
| Level | Description | Examples | Response SLA | Comms Cadence |
|-------|-------------|----------|-------------|---------------|
| **SEV1** | Complete service outage or data loss/corruption | Site down, payment processing broken, data breach | Page immediately, respond in 15 min | Every 30 min to stakeholders |
| **SEV2** | Major functionality broken, significant user impact | Login broken for 20% of users, latency 10× normal | Page, respond in 30 min | Every 1 hour |
| **SEV3** | Minor degradation, partial functionality broken | Dashboard loading slowly, non-critical feature broken | Respond in 4 hours | Daily update |
| **SEV4** | No user impact, potential future risk | Alert threshold tuning needed, deprecation warning | Next business day | Weekly update |

### Declaring Severity
When in doubt, **declare higher**. It's easier to downgrade a SEV1 to SEV2 than to escalate too late.

---

## 2. Incident Lifecycle

```
DETECTION       TRIAGE          MITIGATION       RESOLUTION        REVIEW
    │               │               │                 │               │
    ▼               ▼               ▼                 ▼               ▼
Alert fires → Confirm scope → Stop the bleeding → Fix root cause → Postmortem
(or user     Is it real?    Rollback / disable  (may take days)  within 48-72h
 reports)    How bad?       feature / failover
             Declare SEV    Communicate status
```

### Detection Sources
- Alerting (Prometheus → Alertmanager → PagerDuty)
- Customer reports (via support tickets, social media)
- Internal monitoring dashboards
- Synthetic monitoring / uptime checks
- Canary deployment failures

### Triage Checklist
1. **Confirm** — is this real or a false positive? Check dashboards.
2. **Scope** — how many users affected? Which regions? Which services?
3. **Declare** — set SEV level. Create incident in ServiceNow.
4. **Assign IC** — designate Incident Commander (not always most senior person)
5. **Create channel** — `#inc-YYYYMMDD-description` in Slack
6. **Status page** — update public status page within 5 minutes of SEV1 confirmation

---

## 3. Incident Commander (IC) Role

The IC is NOT the person doing the debugging. The IC:
- **Coordinates** the response team
- **Controls** communication (who says what, to whom)
- **Delegates** investigation tasks clearly: "Alice, check DB connections. Bob, look at load balancer logs"
- **Time-boxes** investigation: "Let's try X for 10 minutes. If no result, we try Y"
- **Prevents** analysis paralysis — makes decisions with incomplete info
- **Updates** stakeholders on cadence
- **Calls** all-clear when resolved

### IC Failure Modes to Avoid
- ❌ Trying to debug AND coordinate simultaneously
- ❌ No clear time-boxes for investigation threads
- ❌ Too many people talking in the incident channel
- ❌ Forgetting to update status page
- ❌ Declaring resolution before verifying metrics recovered

---

## 4. Runbooks

### Anatomy of a Good Runbook
```
Title: <Alert Name> — Brief Description
---
1. OVERVIEW
   - What this alert means
   - Typical causes

2. IMPACT ASSESSMENT
   - How to check user impact
   - Key metrics to look at first

3. TRIAGE STEPS
   - Step-by-step commands to diagnose
   - Decision tree: "If you see X, do Y"

4. MITIGATION OPTIONS
   - Quick mitigation (rollback, disable feature flag)
   - Escalation if mitigation not working

5. RESOLUTION STEPS
   - Full fix procedure

6. ESCALATION
   - When to escalate
   - Who to escalate to (name + contact)

7. VERIFICATION
   - How to confirm the issue is resolved
   - What metrics to watch post-resolution
```

### Runbook Anti-Patterns
- ❌ "Check if there's a problem" — too vague
- ❌ Requires tribal knowledge: "Talk to Dave about the config"
- ❌ Outdated: references old hostnames, deprecated tools
- ❌ Too long to read during an incident — use collapsible sections
- ✅ Every alert has exactly one linked runbook

---

## 5. Root Cause Analysis (RCA)

### 5 Whys Example
```
Problem: API response times increased 10× for 45 minutes

Why 1: Why were response times high?
→ Database queries were slow (evidence: slow query log)

Why 2: Why were DB queries slow?
→ Full table scan on orders table

Why 3: Why was a full table scan happening?
→ A new query was added without an index

Why 4: Why was it added without an index?
→ No performance review was done before deploy

Why 5: Why was there no performance review?
→ No process requires SQL review for new queries

ROOT CAUSE: Process gap — no mandatory SQL query review before production deploy
ACTION ITEM: Add SQL review step to CI pipeline (query plan analysis)
```

### Contributing Factors vs Root Cause
- **Root cause**: The fundamental systemic reason. Fixing it prevents recurrence.
- **Contributing factors**: Things that made the incident worse or harder to detect.
  - Example: "We detected this 20 minutes late because our alert threshold was too high"

---

## 6. Blameless Postmortems

### Why Blameless?
- People make mistakes. Blame → fear → hiding problems → worse future incidents
- Systems should be designed so single human error doesn't cause outage
- Goal: improve the system, not punish individuals

### Postmortem Structure
1. **Incident Summary** — 3-sentence what/when/impact
2. **Timeline** — chronological events (times, actions, discoveries)
3. **Root Cause** — what fundamentally caused this
4. **Contributing Factors** — what made it worse or delayed detection
5. **Impact** — users affected, downtime, revenue impact
6. **What Went Well** — detection was fast, rollback worked, team communication
7. **What Went Poorly** — alert was too noisy, runbook was outdated
8. **Action Items** — table with: action, owner, priority (P1/P2/P3), due date

### Action Item Quality
| Bad | Good |
|-----|------|
| "Fix the monitoring" | "Add alerting for DB connection pool exhaustion (owner: @alice, due: 2024-02-15)" |
| "Be more careful" | "Add index review step to PR template (owner: @bob, due: 2024-02-01)" |
| "Improve logging" | "Add structured log for all 5xx responses including request ID (owner: @carol)" |

---

## 7. On-Call Best Practices

### Healthy On-Call Metrics
- Pages per on-call shift: < 2-3 actionable pages (more = alert fatigue)
- Actionable alert ratio: > 80% (alerts that require human action)
- MTTA (Mean Time to Acknowledge): < 5 min for SEV1
- MTTR (Mean Time to Resolve): track trend, aim to reduce 10% per quarter

### On-Call Health
If on-call is frequently interrupted (> 2 interruptions/hour):
1. Reduce noise first — audit alert thresholds
2. Review false positives — eliminate non-actionable alerts
3. Add more runbooks for top-paging alerts
4. Rotate on-call more frequently (every 1 week, not 2)

### PagerDuty Setup Best Practices
```
Escalation Policy:
  Level 1: Primary on-call (page immediately)
  Level 2: Secondary (if no ack in 5 min for SEV1)
  Level 3: Engineering manager (if no ack in 10 min for SEV1)

Schedules:
  - 1-week rotations
  - Follow-the-sun for global teams
  - Shadowing rotations for new team members

Alert Deduplication:
  - Event Rules: group related alerts
  - Time windows: suppress during maintenance
```

---

## 8. Mean Time Metrics

| Metric | Definition | Formula | How to Improve |
|--------|-----------|---------|----------------|
| **MTTA** | Mean Time To Acknowledge | avg(ack_time - alert_time) | Better on-call tooling, clearer escalation |
| **MTTD** | Mean Time To Detect | avg(detect_time - failure_time) | Better monitoring coverage |
| **MTTR** | Mean Time To Resolve | avg(resolve_time - detect_time) | Better runbooks, automation, postmortems |
| **MTBF** | Mean Time Between Failures | total_uptime / num_failures | Reliability engineering, chaos testing |
| **MTTF** | Mean Time To Failure | same as MTBF for non-repairable | Design for redundancy |

---

## 9. ServiceNow for Incidents

### Incident Lifecycle in SNOW
```
New → In Progress → Resolved → Closed
```

### Key Fields to Fill
- **Short Description**: 1-line summary (shown in lists/reports)
- **Description**: Full symptoms, timeline, impact
- **Category/Subcategory**: Maps to CMDB service
- **Priority**: Derived from Impact × Urgency
- **Assignment Group**: Team responsible
- **Work Notes**: Internal updates (not visible to requester)
- **Resolution Notes**: What fixed it

### CMDB Integration
- Link incident to the affected Configuration Item (CI)
- This enables trend analysis: "How many incidents hit payment-service this quarter?"
- Required for Problem Management process (finding patterns)

### Change Management
- After major incident: file an RFC (Request for Change) for the fix
- Change types: Normal (reviewed), Standard (pre-approved), Emergency
- Emergency Change: bypass normal review for critical production fixes
