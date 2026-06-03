# Error Budget Policy Template

Use this template to document how a team will respond to SLO performance over time.
The template is intentionally detailed so it can support real governance instead of becoming a decorative document.
Replace placeholder values before approval.

---

## 1. Policy metadata

**Service name**: `_______________________`

**Service tier**: `tier-0 / tier-1 / tier-2 / internal / batch / data`

**Primary team**: `_______________________`

**SRE or reliability partner**: `_______________________`

**Product owner**: `_______________________`

**Primary SLO used for policy**: `_______________________`

**Target**: `_____ %`

**Measurement window**: `_____ days`

**Error budget fraction**: `_______________________`

**Approved by**: `_______________________`

**Approval date**: `_______________________`

**Last reviewed**: `_______________________`

**Next review due**: `_______________________`

---

## 2. Scope of this policy

This policy applies to:

- services and user journeys covered by the primary policy-driving SLO,
- changes that affect the critical path for those journeys,
- incident response and release decisions when budget burn or depletion occurs.

This policy does not automatically apply to:

- unrelated internal tools,
- maintenance work outside the SLO scope,
- emergency security changes approved through the exception process.

---

## 3. Service context

### 3.1 User journey protected by this policy

Describe the user journey in one or two sentences.

Example:

`Customers submit checkout requests and receive a success or failure response within 500 ms.`

### 3.2 Why this SLO matters

Document the operational and business consequences of missing the target.

Examples:

- direct revenue loss,
- customer trust impact,
- delayed downstream processing,
- compliance or reporting risks,
- support load increase.

### 3.3 Measurement source

Specify the telemetry source used for policy decisions.

- Prometheus recording rule name:
- Dashboard link:
- Query owner:
- Validation method:

### 3.4 Exclusions

List traffic or events excluded from the SLO.
Examples:

- health checks,
- labeled synthetic traffic,
- non-production environments,
- planned maintenance windows if formally approved,
- manually triggered backfills for data pipelines.

---

## 4. Core definitions

### 4.1 Error budget formula

```text
error_budget_fraction = 1 - slo_target
allowed_bad_events = total_eligible_events * error_budget_fraction
budget_used_percent = (observed_bad_events / allowed_bad_events) * 100
budget_remaining_percent = 100 - budget_used_percent
burn_rate = observed_error_rate / error_budget_fraction
```

### 4.2 Example interpretation

For a `99.9%` SLO over `30d`:

- error budget fraction = `0.001`
- allowed failure budget = `0.1%` of eligible events
- a burn rate of `1x` means budget is being consumed at the planned pace
- a burn rate of `6x` means budget is being consumed six times too fast

### 4.3 Reference table

| SLO | 30-day time budget |
|---|---|
| 99.0% | 432 minutes |
| 99.5% | 216 minutes |
| 99.9% | 43.2 minutes |
| 99.95% | 21.6 minutes |
| 99.99% | 4.32 minutes |

---

## 5. Policy thresholds and required actions

### 5.1 Budget healthy — greater than 50% remaining

**Operational posture**: normal

Required actions:

- feature development proceeds normally,
- standard deployment controls apply,
- experiments can proceed with normal review,
- weekly SLO review is sufficient.

Recommended actions:

- keep reliability backlog groomed,
- address low-effort recurring issues,
- review slow-burn trends even if total budget looks healthy.

### 5.2 Budget watch — 25% to 50% remaining

**Operational posture**: caution

Required actions:

- weekly error budget review becomes mandatory,
- recent incident causes are reviewed for recurrence risk,
- risky changes to the critical path require senior engineer or SRE review,
- release notes must call out reliability-impacting changes.

Recommended actions:

- add extra canary time for risky deploys,
- prioritize top reliability debt items in sprint planning,
- validate rollback paths before launches.

### 5.3 Budget guarded — 10% to 25% remaining

**Operational posture**: guarded

Required actions:

- daily budget review with service owner,
- reduce scope of releases touching critical paths,
- prioritize bug fixes and reliability work over new feature work,
- require engineering manager sign-off for significant deploys,
- review on-call load and recurring alerts.

Recommended actions:

- increase observability on critical paths,
- delay migrations, dependency upgrades, or schema changes unless low risk,
- accelerate top postmortem actions.

### 5.4 Budget critical — 0% to 10% remaining

**Operational posture**: emergency caution

Required actions:

- freeze risky feature launches,
- allow only reliability improvements, rollback work, urgent bug fixes, and explicitly approved exceptions,
- hold daily reliability stand-up,
- provide leadership visibility on current posture,
- document recovery plan with owners and dates.

Recommended actions:

- assign an incident or reliability coordinator,
- review paging load and temporary mitigations,
- pause non-essential infrastructure changes.

### 5.5 Budget exhausted — 0% or less remaining

**Operational posture**: breached

Required actions:

- declare SLO breach,
- freeze risky changes until recovery criteria are met,
- complete a breach-level postmortem or review,
- track recovery plan at engineering leadership level,
- require exception approval for any non-reliability release,
- review whether current SLI and SLO definitions still reflect user experience.

Recommended actions:

- publish short stakeholder updates on recovery progress,
- re-rank roadmap items around reliability needs,
- review staffing, on-call, and platform constraints that delayed recovery.

---

## 6. Burn-rate alert mapping

Document which burn-rate alerts feed this policy.

| Alert name | Window | Threshold | Intended meaning | Expected action |
|---|---|---:|---|---|
| `SLOBurnFast` | 1h | 14.4x | acute active issue | page on-call and triage immediately |
| `SLOBurnHigh` | 6h | 6x | sustained elevated burn | investigate and reduce risk |
| `SLOBurnDay` | 24h | 3x | meaningful daily degradation | prioritize reliability work |
| `SLOBurnTrend` | 72h | 1x | chronic erosion | review debt and recurring causes |

### 6.1 Notes on burn-rate usage

- Burn rate triggers rapid response.
- Budget remaining drives broader policy posture.
- Both matter.
- A service can have plenty of total budget left and still need urgent action if the current burn rate is extremely high.

---

## 7. Release policy by budget state

| Budget state | Normal deploys | Risky changes | Feature launches | Reliability fixes |
|---|---|---|---|---|
| Healthy | allowed | allowed with standard review | allowed | allowed |
| Watch | allowed | extra review | allowed with caution | prioritized |
| Guarded | limited | approval required | discouraged | prioritized |
| Critical | only low-risk | mostly blocked | frozen | required |
| Breached | exception only | blocked unless emergency | frozen | mandatory focus |

Define what counts as a risky change for this service:

- `____________________________________________________________`
- `____________________________________________________________`
- `____________________________________________________________`

---

## 8. Exception process

Sometimes the organization must ship despite a low or exhausted budget.
Use this section to make those decisions explicit.

### 8.1 Valid reasons for exception consideration

Examples:

- critical security patch,
- legal or compliance requirement,
- customer-facing outage fix,
- urgent financial or business continuity need.

### 8.2 Exception requirements

Every exception must include:

- a written risk summary,
- current budget state,
- rollback or disable plan,
- owner for live monitoring,
- approvals from named leaders,
- post-change review date.

### 8.3 Exception request template

```yaml
service: _______________________
change_summary: _______________________
reason_for_exception: _______________________
current_budget_remaining_percent: ______
risk_summary:
  - _______________________
mitigations:
  - _______________________
rollback_plan: _______________________
approvals:
  engineering: _______________________
  sre: _______________________
  product: _______________________
review_date: _______________________
```

---

## 9. Roles and responsibilities

| Activity | Service owner | Engineering manager | SRE | Product | Leadership |
|---|---|---|---|---|---|
| Maintain telemetry | A | C | C | I | I |
| Review budget weekly | R | A | C | C | I |
| Trigger freeze actions | R | A | C | C | I |
| Approve exceptions | C | A | A | A | I |
| Own recovery plan | R | A | C | C | I |
| Review quarterly policy fitness | C | A | C | C | I |

Legend:

- `R` = responsible
- `A` = accountable
- `C` = consulted
- `I` = informed

---

## 10. Decision tree

```text
Start
 |
 +-- Is the budget metric trustworthy?
 |     |
 |     +-- No --> Fix telemetry, annotate reports, do not overreact to bad data
 |     |
 |     +-- Yes
 |
 +-- Is burn rate above emergency threshold?
 |     |
 |     +-- Yes --> Page on-call, start triage, review recent changes immediately
 |     |
 |     +-- No
 |
 +-- Is budget remaining > 50%?
 |     |
 |     +-- Yes --> Normal delivery posture
 |     |
 |     +-- No
 |
 +-- Is budget remaining between 25% and 50%?
 |     |
 |     +-- Yes --> Weekly review and extra deployment scrutiny
 |     |
 |     +-- No
 |
 +-- Is budget remaining between 10% and 25%?
 |     |
 |     +-- Yes --> Daily review and reduced change scope
 |     |
 |     +-- No
 |
 +-- Is budget remaining between 0% and 10%?
 |     |
 |     +-- Yes --> Freeze risky work and focus on recovery
 |     |
 |     +-- No
 |
 +-- Budget exhausted
       |
       +-- Trigger breach workflow, freeze risky changes, approve exceptions formally
```

---

## 11. Breach workflow

When the budget is exhausted, complete the following:

1. confirm the SLI calculation and blast radius,
2. announce breach state in the agreed communication channel,
3. pause risky changes,
4. open or update recovery work items,
5. assign owner for daily progress review,
6. complete postmortem or reliability review,
7. define exit criteria for returning to normal posture.

### 11.1 Suggested exit criteria

- acute incident resolved,
- burn rate below long-window caution thresholds,
- recovery actions for top recurrence risks assigned,
- leadership agrees normal delivery can resume.

---

## 12. Reporting cadence

### Weekly

- current budget remaining,
- current burn-rate summary,
- incidents that materially consumed budget,
- upcoming risky launches.

### Monthly

- trend against previous month,
- policy actions taken,
- open recovery items,
- stakeholder review of whether SLI still matches user experience.

### Quarterly

- validate target appropriateness,
- review exclusions,
- review exception frequency,
- review whether the policy drove useful behavior.

---

## 13. Policy review checklist

- [ ] Target and window still make sense.
- [ ] SLI matches user experience.
- [ ] Exclusions are still justified.
- [ ] Burn-rate alerts are tuned correctly.
- [ ] Freeze thresholds are understood by all stakeholders.
- [ ] Exception process is being used sparingly.
- [ ] Recovery actions from prior breaches were completed.

---

## 14. Approval sign-off

**Engineering manager**: `_______________________`

**SRE manager or delegate**: `_______________________`

**Product owner**: `_______________________`

**Date**: `_______________________`
