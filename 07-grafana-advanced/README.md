# 07 — Grafana Advanced

This module builds on the observability basics and focuses on using Grafana as a production operations surface. The emphasis is on maintainable dashboards, provisioning, unified alerting, and faster investigation through signal correlation.

## Prerequisites

- Completion of [01-monitoring-observability](../01-monitoring-observability/) is strongly recommended
- Basic PromQL familiarity
- Comfort accessing Grafana and reading dashboards

## What you'll learn

### Basic

- how to structure Grafana dashboards around operator workflows
- how dashboard variables, repeating panels, and folders improve usability
- how Grafana alerting differs from raw metric collection

### Intermediate

- how to provision dashboards, data sources, and alert rules as code
- how to build golden-signal dashboards for services and clusters
- how to use Grafana to move between metrics, logs, and traces during debugging

### Advanced

- how to design dashboards that scale across teams and environments
- how to reduce dashboard clutter and emphasize decision-making panels
- how to use advanced Grafana features to support on-call engineers and support teams
- how to connect visualization, alerting, and incident workflow into one operating model

## File index

| File | Description |
|---|---|
| [theory.md](theory.md) | Advanced Grafana concepts for design, alerting, provisioning, and signal correlation |
| [labs/01-golden-signals-dashboard.md](labs/01-golden-signals-dashboard.md) | Lab for building a dashboard around latency, traffic, errors, and saturation |
| [labs/02-dashboard-provisioning.md](labs/02-dashboard-provisioning.md) | Lab for managing dashboards declaratively instead of only through the UI |
| [labs/03-grafana-alerting.md](labs/03-grafana-alerting.md) | Lab for configuring and understanding Grafana unified alerting |
| [labs/04-traces-logs-correlation.md](labs/04-traces-logs-correlation.md) | Lab for linking Tempo, Loki, and dashboards during investigations |
| [configs/alert-rules.yml](configs/alert-rules.yml) | Provisioned alert-rule examples for Grafana-managed alerting |
| [configs/datasources.yml](configs/datasources.yml) | Datasource provisioning example for repeatable environments |
| [configs/dashboards-provision.yml](configs/dashboards-provision.yml) | Dashboard folder and provisioning configuration example |

## Key concepts covered

- dashboard-as-code workflows
- golden signals and panel design discipline
- variables, folders, and reusable dashboard structure
- unified alerting in Grafana
- metrics, logs, and traces correlation
- operational UX for on-call and support teams

## Practice suggestions

- Rebuild one dashboard from the basic observability module using provisioning instead of manual clicks.
- Trim an overloaded dashboard until every panel answers a real troubleshooting question.
- Create a drill where you start with a Grafana alert, inspect the panel, then pivot to logs and traces.
- Export your dashboard JSON and review it as code with the same discipline you use for configuration files.

## Continue with the learning path

Use this module in the advanced stage together with [08-application-support-l2l3](../08-application-support-l2l3/), [09-production-readiness](../09-production-readiness/), and the broader roadmap in [10-learning-paths](../10-learning-paths/README.md).
