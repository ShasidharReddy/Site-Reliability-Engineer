# 08 — Application Support L2/L3

This module explains how SRE overlaps with support engineering when incidents, escalations, and production debugging reach deeper application layers. It focuses on disciplined triage, evidence-based escalation, and clean handoffs between operational roles.

## Prerequisites

- Basic incident-response awareness
- Familiarity with logs, metrics, and common debugging signals
- Recommended completion of [04-incident-management](../04-incident-management/) and [07-grafana-advanced](../07-grafana-advanced/)

## What you'll learn

### Basic

- what L2 and L3 support typically mean in production environments
- how to triage incoming issues consistently
- what information should be collected before escalation

### Intermediate

- how to use dashboards, logs, and application evidence together during support work
- how to create escalation notes that save time for the next responder
- how ticketing or workflow systems fit into incident and support operations

### Advanced

- how to avoid noisy escalations by improving first-pass diagnosis quality
- how to separate platform, application, dependency, and user-impact symptoms
- how to communicate support findings clearly across operations, development, and management teams
- how support patterns can reveal deeper reliability problems that deserve permanent fixes

## File index

| File | Description |
|---|---|
| [theory.md](theory.md) | Overview of L2 and L3 support responsibilities, triage flow, and escalation quality |
| [labs/01-l2-triage.md](labs/01-l2-triage.md) | Lab for structured L2 triage and initial evidence gathering |
| [labs/02-app-debugging.md](labs/02-app-debugging.md) | Lab for application-level debugging and support-oriented investigation |
| [labs/03-servicenow-workflow.md](labs/03-servicenow-workflow.md) | Lab for support-ticket flow and operational handoff thinking |
| [templates/l2-triage-checklist.md](templates/l2-triage-checklist.md) | Checklist template for repeatable first-response triage |
| [templates/escalation-to-l3.md](templates/escalation-to-l3.md) | Template for clean escalation notes from L2 to L3 or engineering teams |

## Key concepts covered

- support-level boundaries and ownership
- structured triage and evidence capture
- escalation quality and handoff discipline
- dashboard, log, and application-symptom correlation
- ticket workflow and stakeholder communication
- feeding recurring support pain back into reliability improvements

## Practice suggestions

- Use the triage checklist during a simulated incident instead of improvising your first response.
- Practice writing one escalation note that an engineer could act on without asking follow-up questions.
- Compare a platform issue and an application issue to learn what evidence separates them.
- Review repeated support patterns and decide which ones should become runbooks, alerts, or automation.

## Continue with the learning path

This module pairs well with [04-incident-management](../04-incident-management/) and [09-production-readiness](../09-production-readiness/). For the full sequence, see [10-learning-paths](../10-learning-paths/README.md).
