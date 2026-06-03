# Incident Management — Theory

> **Level progression:** Basic (SEV levels, lifecycle) → Intermediate (roles, runbooks, PagerDuty) → Advanced (war room, postmortems, on-call health, MTTR engineering)

---

## 1. Severity Levels

### SEV Definitions

| Level | Description | Examples | Response SLA | Comms Cadence |
|-------|-------------|----------|-------------|---------------|
| **SEV1** | Complete outage or data loss/corruption | Site down, payment broken, data breach | Page immediately, ACK in 15 min | Every 30 min to stakeholders |
| **SEV2** | Major functionality broken, significant user impact | Login broken for 20% users, latency 10× normal | Page, respond in 30 min | Every 1 hour |
| **SEV3** | Minor degradation, partial functionality | Dashboard slow, non-critical feature broken | Respond in 4 hours | Daily update |
| **SEV4** | No user impact, potential future risk | Alert threshold needs tuning, deprecation warning | Next business day | Weekly |

### Declaring Severity — Decision Tree

```
Is user-facing functionality impacted?
  ├── YES: What fraction of users?
  │         ├── >10%  → SEV1 or SEV2
  │         ├── 1-10% → SEV2 or SEV3
  │         └── <1%   → SEV3
  └── NO: Is there risk of escalation?
            ├── Imminent risk → SEV3
            └── Long-term risk → SEV4
```

**Golden rule:** When in doubt, **declare higher**. Downgrading is cheap; under-responding to a SEV1 has real business cost.

---

## 2. Incident Lifecycle

```
DETECTION     TRIAGE        MITIGATION      RESOLUTION     REVIEW
    │             │               │               │            │
    ▼             ▼               ▼               ▼            ▼
Alert fires → Confirm real? → Stop bleeding → Fix root → Postmortem
(or report)   How many?      Rollback/FF     cause      within 72h
              Declare SEV    Communicate     (may take
              Open channel   every 30m       days)
```

### Phase: Detection
Sources of incident detection:
- **Alertmanager → PagerDuty** — primary automated detection
- **Synthetic/uptime checks** — Cloud Monitoring, Blackbox Exporter
- **Customer reports** — support tickets, social media, #customer-reports Slack
- **Canary deployments** — automated rollback on error rate increase
- **SLO burn rate alerts** — fast/slow burn multi-window

Mean Time to Detect (MTTD) target: < 5 minutes for SEV1/SEV2.

### Phase: Triage

**5-Question triage protocol** (complete within first 5 min):
1. Is this real or false positive? (check dashboard)
2. What is the blast radius? (users, regions, services)
3. When did it start? (first bad data point)
4. Is there a recent change? (deploy, config, schema migration)
5. Does a runbook exist for this alert?

### Phase: Mitigation (Stop the Bleeding)
Priority: **reduce user impact first**, root cause second.

Common mitigation actions:
```bash
# Rollback last deployment (Kubernetes)
kubectl rollout undo deployment/<service> -n production
kubectl rollout status deployment/<service> -n production

# Feature flag off (if using LaunchDarkly/Unleash/Flipt)
ldctl variation off --flag checkout-v2 --env production

# Scale up replicas to handle load spike
kubectl scale deployment/<service> --replicas=20 -n production

# Redirect traffic to backup region
gcloud compute backend-services update <backend> \
  --global \
  --connection-draining-timeout=30

# Restart stuck pods
kubectl rollout restart deployment/<service> -n production
```

### Phase: Resolution
Root cause addressed. May take hours to days after mitigation. Checklist before closing:
- [ ] Error rate back to baseline for 15+ minutes
- [ ] All runbook steps completed
- [ ] Monitoring dashboards green
- [ ] Status page updated to "resolved"
- [ ] Stakeholder communication sent

### Phase: Review (Postmortem)
Schedule within 48-72 hours. Required for all SEV1, recommended for SEV2.

---

## 3. Incident Roles

### Role: Incident Commander (IC)
**Single decision-maker during an incident.** Does NOT do technical work — coordinates.

Responsibilities:
- Declare SEV level and own it
- Assign technical lead and comms lead
- Drive toward mitigation
- Prevent "too many cooks" — control who speaks in war room
- Make go/no-go calls (failover, rollback, scale)
- Communicate status every 30 min (SEV1) or 1 hr (SEV2)
- Close the incident and initiate postmortem

### Role: Technical Lead (TL)
Owns the investigation. Reports to IC.

Responsibilities:
- Form and test hypotheses
- Direct SMEs to specific investigation threads
- Report findings to IC every 10-15 min
- Recommend mitigation options with risk assessment
- Not responsible for stakeholder comms

### Role: Communications Lead (Comms)
Owns all external-facing communication.

Responsibilities:
- Status page updates (use templates — never improvise under pressure)
- Customer and stakeholder notifications
- Internal #incident channel narrator
- Escalation to management when required
- Tracks timeline for postmortem

### Role: Subject Matter Expert (SME)
Domain expert called in as needed (DB team, infra, payments, etc.).

IC → TL → SMEs (always route through TL, not directly to SMEs)

---

## 4. Communication Protocols

### Incident Channel Setup (Slack)
```
Channel naming: #inc-YYYYMMDD-<service>-<short-description>
Example:        #inc-20241215-checkout-503-errors

Pin at top:
  IC: @alice
  TL: @bob
  Comms: @charlie
  SEV: 1
  Impact: ~15% checkout failures
  Bridge: https://meet.google.com/xyz
  Status: https://status.company.com
  Runbook: <link>
```

### Status Page Update Templates

**Initial** (within 5 minutes of detection):
```
[Investigating] We are investigating reports of [brief description].
Our team has been notified and is actively investigating.
Next update in 30 minutes.
```

**Progress** (every 30 min for SEV1):
```
[Identified] We have identified the cause of [description].
We are implementing a fix. Affected users may experience [symptom].
Next update in 30 minutes.
```

**Resolved**:
```
[Resolved] This incident has been resolved as of [time UTC].
The issue causing [symptom] has been fixed.
We will share a postmortem within 72 hours.
```

### Escalation Path
```
Alert → On-Call Engineer (L1)
     → Senior On-Call / TL (if not resolved in 15 min)
     → Engineering Manager (SEV1 > 30 min)
     → VP Engineering (SEV1 > 1 hour)
     → Customer Success (if enterprise customers affected)
     → CEO (data breach, complete outage > 2 hours)
```

---

## 5. Runbook Design

### Anatomy of a Production Runbook

```
# Runbook: [Service] — [Alert Name]
## Metadata
  Owner: team-platform
  Last tested: 2024-11-01
  Alert: HighErrorRate on checkout-api

## Trigger
  When: error_rate > 1% for 5 minutes
  Severity: SEV2 (escalates to SEV1 if > 5%)

## Scope & Impact
  Who is affected: users completing checkout
  Estimated impact: X% of orders failing

## Quick Diagnosis (< 5 minutes)
  1. kubectl get pods -n production | grep checkout
  2. kubectl logs <pod> -n production --tail=50
  3. Check Grafana SLO dashboard: <link>

## Root Cause Candidates
  1. Recent deployment? → rollback
  2. DB connection pool? → check metrics
  3. Downstream API timeout? → check dependency health

## Mitigation Steps
  Step A: Rollback if deploy-related
    kubectl rollout undo deployment/checkout-api -n production
  Step B: Scale up if resource-constrained
    kubectl scale deployment/checkout-api --replicas=10 -n production

## Verification
  - Error rate drops below 0.1% within 5 min
  - kubectl rollout status shows complete

## Escalation
  If not resolved in 30 min: page @checkout-team-lead

## Post-Incident
  Create postmortem ticket, tag: checkout, reliability
```

### Runbook Quality Criteria
- [ ] Can a sleepy engineer follow this at 3am?
- [ ] No ambiguous steps ("check the logs" vs "run command X, look for pattern Y")
- [ ] Includes verification step (how do you know it worked?)
- [ ] Has clear escalation path
- [ ] Tested in last 90 days
- [ ] Covers top 3 root causes for this alert

---

## 6. Postmortem Methodology

### Blameless Culture
> "The goal is not to find who broke something, but to understand *how* the system allowed it to break."

Blameless does NOT mean:
- No accountability
- No process improvement
- Ignoring human error as a factor

Blameless DOES mean:
- Systems caused the failure, not individuals
- Individuals operated within the constraints of the system
- Fix the system, not the person

### Timeline Construction

```bash
# Pull PagerDuty alert timestamps
# Pull Grafana annotation history
# Pull Slack channel log export
# Pull kubectl events
kubectl get events -n production --sort-by='.lastTimestamp' > events.txt

# Pull deployment history
kubectl rollout history deployment/<service> -n production

# Pull Cloud Logging timeline
gcloud logging read "resource.type=k8s_container" \
  --freshness=24h \
  --format="table(timestamp,jsonPayload.message)" \
  --project=$PROJECT_ID
```

### Root Cause Analysis Techniques

**5 Whys:**
```
Problem: Checkout API returning 503s
Why 1: DB connection pool exhausted
Why 2: New code opened extra connections per request
Why 3: Code review missed the connection leak
Why 4: No integration test for connection usage
Why 5: Test coverage policy doesn't mandate resource tests
Root Cause: Missing policy for resource usage testing
```

**Fishbone (Ishikawa):**
```
                    PEOPLE          PROCESS
                       \              /
  Fishbone ─────────────────────────────── EFFECT (outage)
                       /              \
                  TOOLS            ENVIRONMENT
```

Categories: People, Process, Technology, Environment, Materials, Measurement

### Postmortem Document Structure

1. **Executive Summary** — 3 sentences max, non-technical
2. **Impact** — duration, % users, revenue/SLA impact
3. **Timeline** — UTC timestamps, who did what
4. **Root Cause** — systemic, not individual
5. **Contributing Factors** — what made it worse
6. **What Went Well** — (don't skip this)
7. **What Went Poorly** — honest assessment
8. **Action Items** — owner, due date, priority (P1/P2/P3)
9. **Lessons Learned**

---

## 7. PagerDuty Configuration

### Service Structure
```
PagerDuty Service = one logical system (checkout-api, auth-service, data-pipeline)

Service → Integrations (Prometheus Alertmanager, Grafana, Cloud Monitoring)
       → Escalation Policy → Schedule → On-Call User
```

### Escalation Policy Best Practices
```yaml
# Escalation Policy: checkout-api
Level 1:  Primary on-call engineer
          Notify: 5 min → page, SMS, push
Level 2:  Secondary on-call engineer
          Activate: if level 1 not acknowledged in 15 min
Level 3:  Engineering Manager
          Activate: if level 2 not acknowledged in 30 min
Repeat: 3 times total before "No One On Call" alert
```

### Reducing Alert Fatigue

| Problem | Solution |
|---|---|
| Too many low-priority pages | Route SEV3/4 to email/ticket only |
| Duplicate alerts | Alertmanager grouping + dedup |
| Flapping alerts | Add `for: 5m` duration to all rules |
| Wrong team paged | Review service ownership in PD |
| Noisy overnight pages | Mute timings for known maintenance |

Alert fatigue metric: **pages per engineer per week** — target < 2 actionable pages/night.

---

## 8. ServiceNow Integration

### Record Types
| Record | Purpose | Created By |
|--------|---------|------------|
| Incident | Active production issue | IC or auto-create from PD |
| Problem | Recurring issue root cause investigation | SRE after postmortem |
| Change | Planned modification to production | Engineer pre-deploy |
| Known Error | Documented workaround while fix pending | Problem Manager |

### Priority Matrix (Impact × Urgency)

```
             High Urgency    Medium Urgency    Low Urgency
High Impact  → P1 (Critical)  P2 (High)         P3 (Medium)
Med Impact   → P2 (High)      P3 (Medium)        P4 (Low)
Low Impact   → P3 (Medium)    P4 (Low)           P5 (Planning)
```

### SLA Targets (align with SEV levels)
| Priority | Response | Resolution |
|----------|----------|------------|
| P1 | 15 min | 4 hours |
| P2 | 30 min | 8 hours |
| P3 | 4 hours | 24 hours |
| P4 | 1 business day | 5 business days |

---

## 9. On-Call Health

### Sustainable On-Call Principles
1. **Pages must be actionable** — every page requires a decision and action
2. **Runbooks must exist** — no page without a runbook
3. **MTTR must be tracked** — if it takes > 30 min to resolve, fix the runbook
4. **Rotation health metrics**: pages/week, sleep-interrupts/week, MTTR, false positives
5. **After-action rotation review** — weekly 15-min on-call review meeting

### On-Call Schedule Design
```
Primary rotation:   7-day shifts, 1 engineer
Secondary backup:   parallel rotation, escalated if primary doesn't ACK
Shadow rotation:    new engineers shadow for 2 weeks before primary

Handoff checklist:
  - Open incidents
  - Ongoing investigations
  - Planned changes during your week
  - Known flapping alerts and context
```

### Alert Quality Scoring

Score each alert 1-5:
- **5**: Always actionable, clear runbook, right SEV, resolves quickly
- **3**: Sometimes actionable, runbook exists but incomplete
- **1**: Usually noise, no runbook, wakes engineer for nothing

Target: eliminate all score-1 and score-2 alerts monthly.

---

## 10. Key Metrics

| Metric | Definition | Good Target |
|--------|-----------|-------------|
| MTTD | Mean Time to Detect | < 5 min (SEV1) |
| MTTA | Mean Time to Acknowledge | < 15 min (SEV1) |
| MTTM | Mean Time to Mitigate | < 30 min (SEV1) |
| MTTR | Mean Time to Resolve | < 2 hours (SEV1) |
| MTBF | Mean Time Between Failures | Maximize → reliability |
| Alert volume | Pages per engineer per week | < 5 actionable |
| Postmortem rate | % SEV1+2 with postmortem | 100% |
| Action item close rate | % completed by due date | > 80% |

---

