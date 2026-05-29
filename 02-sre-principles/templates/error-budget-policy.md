# Error Budget Policy

**Service**: _______________
**SLO**: _____% over ___ days
**Team**: _______________
**Approved by**: _______________
**Last reviewed**: _______________

---

## Policy

### When Budget is > 50% Remaining ✅
- Feature development proceeds at normal pace
- Risky infrastructure changes are allowed with standard review
- No additional approvals required for deploys

### When Budget is 25–50% Remaining 🟡
- Increase code review standards for infrastructure changes
- Require SRE approval for changes touching critical paths
- Add integration/load tests before shipping new features
- Weekly error budget review in team sync

### When Budget is 10–25% Remaining 🔴
- Partial feature freeze: only bug fixes and reliability improvements
- All deploys require SRE + Engineering Lead sign-off
- Daily error budget review
- Begin work on most impactful reliability improvements from backlog

### When Budget is < 10% Remaining ⛔
- Full feature freeze until budget recovers to 25%
- Emergency reliability sprint
- Daily leadership update
- Postmortem required for every incident during this period

### When Budget is Exhausted (SLO Breached) 🚨
- No new features shipped
- On-call rotation doubled for duration of breach
- Mandatory postmortem to be completed within 48 hours
- Root cause and action items reviewed by engineering leadership
- Budget recovery plan required before feature work resumes

---

## Budget Calculation

Monthly budget (minutes) = (1 - SLO_target) × 30 × 24 × 60

| SLO | Monthly budget |
|-----|---------------|
| 99.9% | 43.8 minutes |
| 99.95% | 21.9 minutes |
| 99.99% | 4.4 minutes |

## Review Cadence
- Weekly: SRE reviews budget consumption in weekly sync
- Monthly: Full SLO review with engineering and product stakeholders
- Quarterly: SLO target review — tighten if consistently met, loosen if consistently breached
