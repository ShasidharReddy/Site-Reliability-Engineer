# 02 — SRE Principles

This module introduces the decision-making framework behind SRE work. It focuses on how reliability is measured, how trade-offs are made, and how teams reduce operational pain without losing sight of customer impact.

## Prerequisites

- Basic Linux and networking familiarity
- Comfort reading Markdown and YAML files
- Interest in service ownership, operations, and reliability trade-offs

## What you'll learn

### Basic

- what SLI, SLO, and SLA each mean
- how error budgets connect reliability to delivery speed
- what toil is and why SRE teams try to automate it
- how on-call differs from general support work

### Intermediate

- how to define service indicators that reflect user experience
- how to draft SLO policies and escalation expectations
- how to measure and visualize budget burn over time
- how to identify low-value repetitive work for automation

### Advanced

- how to challenge weak or vanity SLIs
- how to reason about reliability risk during releases or incidents
- how to connect postmortem actions back to SLO health and toil reduction
- how SRE principles influence platform and product decisions

## File index

| File | Description |
|---|---|
| [theory.md](theory.md) | Concept guide for SLIs, SLOs, error budgets, toil, and reliability culture |
| [troubleshooting.md](troubleshooting.md) | Production troubleshooting guide for SLO drift, budget policy conflicts, toil, capacity, and reliability testing |
| [scenarios.md](scenarios.md) | Scenario drills for launching services, handling budget freezes, reducing alert toil, and redesigning SLOs |
| [labs/01-define-slis-slos.md](labs/01-define-slis-slos.md) | Practice lab for turning service behavior into measurable indicators and objectives |
| [labs/02-error-budget-tracking.md](labs/02-error-budget-tracking.md) | Lab for monitoring error budget consumption and communicating risk |
| [labs/03-toil-reduction.md](labs/03-toil-reduction.md) | Lab for spotting repetitive work and planning automation improvements |
| [templates/slo-definition.yaml](templates/slo-definition.yaml) | Template for documenting an SLO with indicators, targets, and alert expectations |
| [templates/error-budget-policy.md](templates/error-budget-policy.md) | Template for defining how teams respond when budgets burn too quickly |
| [templates/toil-log-template.md](templates/toil-log-template.md) | Template for tracking repetitive manual work and automation candidates |

## Key concepts covered

- user-centric reliability measurement
- service indicators and objectives
- internal vs external reliability commitments
- error budget policy and release discipline
- toil accounting and automation priorities
- reliability ownership and on-call expectations

## Practice suggestions

- Define one SLI and one SLO for a service you know, even if it is only a sample app.
- Use the error budget template to decide when feature work should pause for reliability work.
- Keep a one-week toil log for your own repeated tasks and rank them by automation value.
- Pair this module with Linux troubleshooting practice so the theory stays grounded in operational reality.

## Continue with the learning path

This module is the foundation for every later topic. Continue with [01-monitoring-observability](../01-monitoring-observability/), [06-linux-networking](../06-linux-networking/), or review the full roadmap in [10-learning-paths](../10-learning-paths/README.md).
