# Incident Management Q&A

## Basic

**Q: [Basic] What are SEV levels?**
SEV levels classify incidents by user impact, urgency, and business risk. A SEV1 usually means a major outage or data risk with immediate paging and tight communication expectations, while lower severities allow slower response and lighter coordination. The exact definitions vary by company, but the rules should be written and practiced before a real incident.

**Q: [Basic] What are the common roles in an incident?**
The most common roles are Incident Commander, communications lead, and one or more technical leads or subject-matter investigators. The Incident Commander coordinates the response, assigns work, and keeps the timeline moving rather than debugging everything personally. Clear roles reduce chaos, duplicated work, and missed stakeholder updates.

**Q: [Basic] What is a postmortem?**
A postmortem is the structured review that happens after an incident to understand what happened and how to prevent a repeat. It should cover impact, timeline, contributing factors, mitigation, root causes, and follow-up actions. The purpose is organizational learning, not assigning blame.

**Q: [Basic] What is the difference between mitigation and resolution?**
Mitigation is the fastest safe action that reduces or stops customer impact, such as a rollback, failover, or feature disablement. Resolution is the permanent fix that removes the underlying cause or reduces the risk long term. Teams should communicate clearly when an incident is mitigated but not fully resolved.

**Q: [Basic] Why are runbooks important during incidents?**
Runbooks turn institutional knowledge into repeatable response steps that any on-call engineer can follow under pressure. They reduce time spent guessing, make escalation cleaner, and improve consistency across responders. Good runbooks are short, current, and linked directly from alerts.

## Intermediate

**Q: [Intermediate] What are good on-call practices?**
Healthy on-call programs have clear ownership, sustainable schedules, actionable alerts, and enough documentation for responders to succeed at 3 a.m. Teams should review page load, escalation rates, and false positives regularly so on-call stays humane. Shadow shifts, incident drills, and post-incident learning are also part of good practice.

**Q: [Intermediate] How should escalation procedures work?**
Escalation procedures should define when to page the next level, when to involve another team, and when leadership or customer support must be informed. The trigger should be based on impact and blocked progress, not on responder pride or uncertainty. Strong procedures reduce delay by making escalation a normal control, not a sign of failure.

**Q: [Intermediate] What should a good PagerDuty configuration include?**
A solid PagerDuty setup includes well-defined services, severity-based escalation policies, schedule coverage, and noise controls such as event grouping or maintenance windows. Alerts should include enough context to let the responder decide the first action without hunting through multiple tools. Ownership labels and clear runbook links make the setup much more effective.

**Q: [Intermediate] What does a blameless culture mean in incident management?**
Blameless culture means focusing on the system conditions and process gaps that allowed the incident, rather than on shaming an individual. People still own actions and follow-ups, but the analysis asks why the system allowed a mistake to become customer impact. This approach improves reporting, trust, and long-term learning.

**Q: [Intermediate] How should status page communication be handled?**
Status page updates should be timely, plain-language, and focused on customer impact rather than internal jargon. The first update should arrive early, even if the root cause is not yet known, and later updates should explain scope, mitigation, and recovery progress. Consistency matters more than perfect detail during the first phase of the incident.

**Q: [Intermediate] Why is an incident timeline valuable?**
A timeline reconstructs who saw what, when decisions were made, and how the response evolved. It helps teams distinguish root cause from later symptoms and spot where escalation, communication, or tooling slowed the recovery. A precise timeline is the backbone of a useful postmortem.

**Q: [Intermediate] How do you handle long incidents that span shifts or regions?**
Long incidents need formal handoffs with current status, hypotheses, actions taken, open risks, and next checkpoints. The handoff should be written, not just verbal, so nothing important disappears during fatigue or timezone changes. Good responders keep the incident context portable instead of locked in one person’s head.

**Q: [Intermediate] How do you communicate with executives or customer-facing teams during an incident?**
Executives and support teams usually need impact, current mitigation status, expected next update, and business risk more than low-level technical detail. Communication should be concise, credible, and regular, especially when the incident is visible externally. A dedicated communication owner prevents engineers from splitting attention between debugging and stakeholder management.

## Advanced

**Q: [Advanced] How do you run an effective war room?**
An effective war room has a clear Incident Commander, a small number of active speakers, and explicit time-boxed tasks for investigators. The goal is to create shared situational awareness without turning the call into an unstructured brainstorm. Good war rooms focus on mitigation first and keep a written log of major decisions.

**Q: [Advanced] What are practical ways to reduce MTTR?**
MTTR usually drops when teams invest in fast diagnosis, fast mitigation, and fewer coordination bottlenecks. Examples include prebuilt dashboards, tested rollback paths, dependency maps, known-good configuration baselines, and clearer incident roles. Practicing realistic scenarios is just as important as adding more tooling.

**Q: [Advanced] Which incident metrics matter most?**
Useful incident metrics include MTTD, MTTA, MTTR, recurrence rate, severity mix, and action-item completion rate. These tell you whether the program has problems with detection, acknowledgement, restoration, or learning follow-through. The best teams review trends over time instead of treating each incident as an isolated event.

**Q: [Advanced] How do you build on-call health metrics?**
On-call health metrics measure the human cost of the support model, not just technical uptime. Typical examples are pages per shift, percentage of actionable alerts, overnight interruption rate, escalation load, and after-hours toil. These metrics help leaders see burnout risk before attrition or reliability quality makes it obvious.

**Q: [Advanced] How should postmortem action items be tracked?**
Action items need an owner, a due date, a concrete outcome, and a status that survives past the meeting itself. They should be reviewed in a recurring forum so important prevention work does not disappear under feature pressure. Strong programs also separate tactical fixes from strategic improvements so both get attention.

**Q: [Advanced] How do you reduce alert fatigue?**
Start by measuring which alerts are actionable, which are informational, and which never lead to meaningful work. Remove or retune noisy alerts, add `for` durations where appropriate, and use inhibition so child alerts do not storm when a parent dependency fails. The goal is not fewer alerts at any cost, but fewer alerts that waste human attention.

**Q: [Advanced] How do you handle a false positive page?**
Treat false positives as a reliability problem in the monitoring system, not as harmless background noise. The responder should confirm user impact quickly, document why the alert misfired, and ensure it gets tuned or removed instead of accepted forever. If engineers stop trusting pages, real incidents will take longer to detect.

**Q: [Advanced] What should you do during an alert storm?**
An alert storm usually means one underlying failure is triggering many dependent symptoms. Focus on identifying the common root condition, suppress the secondary noise if policy allows it, and keep responders centered on the few alerts that matter most. Afterward, improve routing and inhibition so the same storm cannot page dozens of times again.

**Q: [Advanced] How do you train new incident responders?**
New responders learn fastest through shadow rotations, guided simulations, and gradually increasing responsibility with backup support. Training should include tools, escalation rules, communication expectations, and common failure modes for the services they support. Teams should assess readiness based on repeated performance, not just completion of onboarding slides.

**Q: [Advanced] When is incident response automation appropriate?**
Automation is appropriate when the remediation is safe, frequent, and well understood, such as restarting a failed job or triggering a controlled rollback. It is less appropriate when the failure mode is ambiguous or the action could make the outage worse. Strong teams automate the boring first steps while keeping humans in control of high-risk decisions.

**Q: [Advanced] How do you measure incident management maturity?**
Maturity shows up in consistent severity handling, low-noise paging, fast coordination, strong postmortem follow-through, and fewer repeat incidents from the same causes. It is not measured by having more documents or more tools alone. A mature program makes good response behavior the default even under stress.

**Q: [Advanced] What do you do when the same incident pattern keeps returning?**
Recurring incidents mean the organization is treating symptoms instead of risk. Teams should group those events, quantify cumulative impact, and prioritize structural fixes such as redesign, automation, or stronger deployment controls. Repetition is often the strongest argument for investing in reliability work.

**Q: [Advanced] When should you raise or lower incident severity?**
Severity should change when user impact, business risk, or expected duration changes, not because a call feels calmer or louder. Raising severity early is usually safer than waiting too long and losing response time. Lowering severity is appropriate only when evidence shows impact is contained and the response model can safely scale down.
