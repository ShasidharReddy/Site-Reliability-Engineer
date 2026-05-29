# Postmortem: [Incident Title]

**Incident ID**: INC-XXXX  
**Severity**: SEV[1/2/3]  
**Date**: YYYY-MM-DD  
**Duration**: X hours Y minutes  
**Status**: [Draft / In Review / Final]  
**Author(s)**: @name  
**Reviewers**: @name1, @name2

---

## Incident Summary

> 3 sentences: what happened, what was the user impact, how was it resolved.

On [date] at [time UTC], [brief description of what broke]. This resulted in [user impact — X% of users affected, specific features broken]. The issue was resolved at [time] by [brief mitigation — rollback, fix deployed, etc.].

---

## Impact

| Metric | Value |
|--------|-------|
| Duration | Xh Ym |
| Users affected | ~X,XXX |
| Requests failed | ~X% (X,XXX requests) |
| Services impacted | service-a, service-b |
| SLO impact | X% budget consumed (was at Y% before incident) |
| Revenue impact | $X (if known) |

---

## Timeline

All times in UTC.

| Time | Event |
|------|-------|
| HH:MM | First alert fired: [alert name] |
| HH:MM | On-call engineer acknowledged |
| HH:MM | Incident declared SEV[X] |
| HH:MM | [Action taken / discovery made] |
| HH:MM | [Action taken / discovery made] |
| HH:MM | Mitigation deployed (rollback / feature flag off / etc.) |
| HH:MM | Error rate returned to normal — incident resolved |
| HH:MM | Post-incident monitoring period ended, all-clear declared |

---

## Root Cause

> What single fundamental change or condition caused this incident?

[Describe the root cause in 2-4 sentences. Be specific — name the exact failure mode.]

---

## Contributing Factors

> What other factors made this incident worse, harder to detect, or harder to mitigate?

1. **Detection delay**: Alert threshold was set at X% error rate; actual impact started at Y% but took Z minutes to fire.
2. **Runbook gap**: The runbook for [alert] did not include steps for [specific scenario].
3. **Deployment process**: No automated rollback was in place, requiring manual intervention.
4. **Knowledge gap**: Only one engineer knew how to [specific action]; that person was not on-call.

---

## What Went Well

- Detection was fast: alert fired within X minutes of first errors
- On-call rotation worked: escalation reached secondary within Y minutes
- Rollback was clean: no data loss, service restored within Z minutes
- Communication was clear: stakeholders updated on schedule

---

## What Could Be Improved

- Alert threshold was too high — impact began before alert fired
- Status page was updated X minutes late
- Root cause took too long to identify — need better dashboard for [component]
- Runbook for [alert] was outdated and referenced deprecated tooling

---

## Action Items

| # | Action | Owner | Priority | Due Date | Status |
|---|--------|-------|----------|----------|--------|
| 1 | Lower alert threshold for [metric] from X to Y | @alice | P1 | YYYY-MM-DD | Open |
| 2 | Update runbook for [alert] with [specific steps] | @bob | P1 | YYYY-MM-DD | Open |
| 3 | Add automated rollback for [component] | @carol | P2 | YYYY-MM-DD | Open |
| 4 | Add index on [table.column] to prevent slow queries | @dave | P1 | YYYY-MM-DD | Open |
| 5 | Document [knowledge] in wiki | @eve | P3 | YYYY-MM-DD | Open |

**Priority Key**: P1 = fix within 1 week | P2 = fix within 1 month | P3 = fix within quarter

---

## Lessons Learned

> 2-3 key takeaways for the broader team.

1. 
2. 
3. 

---

## Appendix

### Graphs During Incident
[Attach relevant Grafana screenshots with time range set to incident window]

### Log Excerpts
```
[relevant log lines that helped diagnose the issue]
```

### Relevant Dashboards
- [Link to Grafana dashboard]
- [Link to ServiceNow ticket]
