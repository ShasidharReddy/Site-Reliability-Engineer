# 04 — Incident Management

This module covers the human and procedural side of reliability engineering: how teams detect incidents, coordinate response, communicate under pressure, and turn failures into lasting improvement. It is where technical troubleshooting becomes operational leadership.

## Prerequisites

- Basic familiarity with service monitoring and alerts
- Comfort with Linux, Kubernetes, or application troubleshooting basics
- Recommended completion of [02-sre-principles](../02-sre-principles/) and [03-kubernetes-reliability](../03-kubernetes-reliability/)

## What you'll learn

### Basic

- what severity levels mean and how to assign them
- the stages of an incident from detection to closure
- why runbooks reduce confusion and response time
- what a blameless postmortem should accomplish

### Intermediate

- how incident commander, communications, and subject matter expert roles differ
- how escalation paths and stakeholder updates should work
- how to structure timelines, evidence, and mitigation notes
- how to write reusable runbooks and postmortem documents

### Advanced

- how to keep incident coordination calm and focused during ambiguity
- how to separate symptoms, impact, root causes, and contributing factors
- how to turn postmortem actions into reliability improvements that actually get finished
- how to improve alerting, ownership, and preparedness based on recurring incident patterns

## File index

| File | Description |
|---|---|
| [theory.md](theory.md) | Guide to severity models, incident lifecycle, runbooks, RCA, postmortems, and common tooling |
| [labs/01-incident-simulation.md](labs/01-incident-simulation.md) | Simulation lab for responding to a Kubernetes-style production incident |
| [labs/02-runbook-creation.md](labs/02-runbook-creation.md) | Lab for drafting clear, actionable operational runbooks |
| [labs/03-postmortem-practice.md](labs/03-postmortem-practice.md) | Lab for writing a blameless postmortem with concrete follow-ups |
| [troubleshooting.md](troubleshooting.md) | Troubleshooting guide for broken response processes, paging failures, and postmortem quality gaps |
| [scenarios.md](scenarios.md) | Scenario catalog with detailed tabletop exercises for common and high-stress incidents |
| [templates/sev-incident-runbook.md](templates/sev-incident-runbook.md) | Runbook template for severe incidents with response structure and examples |
| [templates/postmortem-template.md](templates/postmortem-template.md) | Full postmortem template for timeline, impact, causes, and actions |
| [templates/escalation-matrix.md](templates/escalation-matrix.md) | Escalation matrix template for routing issues to the right owners |

## Key concepts covered

- severity and impact classification
- incident roles and communication flow
- mitigation vs diagnosis vs prevention
- runbooks and decision support under pressure
- escalation criteria and handoff quality
- blameless learning and corrective action tracking

## Practice suggestions

- Run one tabletop exercise with a fake outage and assign explicit roles.
- Write a short runbook for a service you know, even if it is only a lab app.
- During every practice incident, keep a timestamped timeline instead of relying on memory.
- Review one public postmortem and map it to the structure used in this module.

## Continue with the learning path

Use this module alongside [05-gcp-operations](../05-gcp-operations/) and [08-application-support-l2l3](../08-application-support-l2l3/), and keep the overall progression in [10-learning-paths](../10-learning-paths/README.md).
