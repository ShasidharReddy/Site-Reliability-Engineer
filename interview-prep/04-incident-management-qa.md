# Incident Management Q&A

**Q1: Walk through a 3am SEV1 (database unresponsive).**
(1) Acknowledge PD alert. (2) Verify impact: check app error rate in Grafana. (3) Create #inc-channel, declare SEV1. (4) Update status page (5 min max). (5) Check if it's slow vs down: run simple query from app pod. (6) Check DB logs for error. (7) Any recent change? Deployment, config, schema migration? (8) Cloud managed DB? Check console for instance health + failover status. (9) If stuck: initiate failover. (10) Update stakeholders every 30 min. Key: mitigation first (failover), root cause after.

**Q2: Mitigation vs resolution.**
Mitigation: fastest path to stopping user impact. Rollback, feature flag off, failover, increase replicas. May not fix root cause. Resolution: permanent fix — code fix deployed, infrastructure corrected, root cause addressed. An incident can be "mitigated" (error rate normal) while root cause investigation continues. SLO clock stops at mitigation. Root cause fix may take days. Always distinguish: "we've mitigated the incident" from "we've resolved the root cause."

**Q3: How do you run a blameless postmortem?**
Schedule within 48-72h. Attendees: responders + relevant engineers. Build timeline from Slack, PD, monitoring. No blame: "the deploy caused X" not "Alice's code caused X." Find systemic root causes (process gap, missing test, missing alert). List what went well + what to improve. Generate concrete action items: specific, owned, time-bound. Track completion monthly. Share broadly as a learning document. Postmortems without follow-through on action items are theater.

**Q4: Grafana alerts firing but service looks healthy — false positive debugging.**
(1) Check alert condition and threshold — is it set correctly? (2) Check time window — brief spike during rolling restart? (3) Check query: is aggregation correct? Missing by() clause? (4) Check if metric reflects actual user experience or is an internal metric. (5) Check Alertmanager: is alert actually reaching users or silenced? Fix: add for: 5m for sustained condition, tune threshold, use SLO-based alerting on real user signals rather than internal metrics.

**Q5: Alert storm — 50+ alerts firing simultaneously.**
Don't try to address each alert individually. (1) Find the common root cause: what do they share? (same node, same namespace, same deploy time). (2) Identify the root cause alert — address that first. (3) Silence the noise for 2 hours while you work. (4) After resolution: add Alertmanager inhibition rules to prevent the pattern recurring. Alert storms = missing inhibition rules. Example: NodeDown should inhibit all PodCrashLooping alerts on that node.

**Q6: On-call health metrics.**
Pages per shift (target <5 actionable/week), MTTA (<5min for SEV1), alert precision rate (actionable/total, target >80%), toil time per shift, MTTR trend (quarter-over-quarter), escalation rate, postmortem action item completion rate. If pages >10/week: immediate alert audit. If precision <50%: emergency alert review. These metrics should be reviewed monthly in an SRE team meeting.

**Q7: How do you reduce alert fatigue?**
(1) Audit all alerts: categorize as actionable vs noise. (2) For noisy alerts: raise threshold, add for: duration, or delete. (3) Add for: duration to every alert (min 5m for non-critical). (4) Add Alertmanager inhibition rules. (5) Add runbooks to every actionable alert — if you can't write a runbook, the alert is poorly defined. (6) Set repeat_interval to 4h+ for warnings (don't re-page every 15min). (7) Use SLO burn rate alerts (fewer, higher signal) instead of many threshold alerts.

**Q8: What is the Incident Commander role?**
IC coordinates the response — NOT the person debugging. IC: assigns investigation tasks with time-boxes ("Alice, check DB connections, 10 min max"), controls communication (one voice in incident channel), updates stakeholders on cadence, makes decisions with incomplete information (avoids analysis paralysis), calls all-clear when resolved. IC failure modes: trying to debug AND coordinate, no time-boxing, letting too many people talk simultaneously, forgetting status page updates.

**Q9: ServiceNow incident lifecycle.**
New → In Progress → Resolved → Closed. Key fields: short description (1-line searchable summary), description (full context), assignment group (route correctly, don't leave as default), business service (CI in CMDB for trend analysis), work notes (internal, not visible to requester), resolution notes (what fixed it). Escalation: L2 creates → works → can't resolve → reassigns to L3 with full notes → L3 fixes → L2 verifies → resolves. Never close without verifying with affected user.

**Q10: SEV levels — definitions and response SLAs.**
SEV1: complete outage or data loss, all users affected. Page immediately, ack in 15min, updates every 30min. SEV2: major functionality broken, significant user impact. Page, ack in 30min, updates hourly. SEV3: minor degradation, partial functionality, workaround available. Ack in 4h, daily updates. SEV4: no current user impact, potential future risk. Next business day. When in doubt: declare higher, easier to downgrade than escalate too late.
