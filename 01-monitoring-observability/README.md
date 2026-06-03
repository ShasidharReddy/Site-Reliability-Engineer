# 01 — Monitoring & Observability

This module teaches the observability workflow that powers modern SRE practice: collect the right signals, visualize them clearly, alert on actionable failures, and use correlated evidence to troubleshoot faster. It is the best entry point after you finish the core Linux and SRE foundations.

## Prerequisites

- Basic Linux command line comfort
- Familiarity with HTTP, DNS, and ports
- Basic Kubernetes awareness is helpful but not required
- Ability to run repository commands such as `make run-local`

## What you'll learn

### Basic

- what metrics, logs, and traces are used for
- how Prometheus scrapes targets and stores time series
- how Grafana dashboards answer common operational questions
- how Alertmanager groups and routes alerts

### Intermediate

- how to write PromQL for rates, error percentages, and latency views
- how to build dashboards for golden signals and workload health
- how to create alert rules with clear thresholds and severities
- how to use Loki and tracing tools during investigations

### Advanced

- how to connect metrics, logs, and traces into one debugging workflow
- how to avoid noisy alerts and reduce blind spots
- how to reason about label usage, cardinality, and dashboard scalability
- how to design observability outputs that help on-call engineers act quickly

## File index

| File | Description |
|---|---|
| [theory.md](theory.md) | Core concepts for Prometheus, PromQL, Grafana, Alertmanager, Loki, and tracing |
| [labs/01-prometheus-setup.md](labs/01-prometheus-setup.md) | Step-by-step lab for deploying a production-style Prometheus stack |
| [labs/02-grafana-dashboards.md](labs/02-grafana-dashboards.md) | Dashboard-building lab focused on useful, operator-friendly visuals |
| [labs/03-alertmanager-rules.md](labs/03-alertmanager-rules.md) | Alerting lab for rule design, routing, and validation |
| [labs/04-loki-logging.md](labs/04-loki-logging.md) | Logging lab using Loki and LogQL for investigation workflows |
| [labs/05-distributed-tracing.md](labs/05-distributed-tracing.md) | Tracing lab that connects Tempo and Grafana Explore |
| [configs/prometheus.yml](configs/prometheus.yml) | Example Prometheus scrape and storage configuration |
| [configs/alertmanager.yml](configs/alertmanager.yml) | Example Alertmanager routing tree and receiver definitions |
| [configs/loki-config.yml](configs/loki-config.yml) | Loki server configuration for log ingestion and querying |
| [dashboards/kubernetes-overview.json](dashboards/kubernetes-overview.json) | Importable dashboard for Kubernetes cluster visibility |
| [dashboards/slo-dashboard.json](dashboards/slo-dashboard.json) | Importable dashboard for SLI, SLO, and error budget views |

## Key concepts covered

- metrics vs logs vs traces
- golden signals and service health indicators
- Prometheus scrape model and time-series thinking
- PromQL filtering, aggregation, and rate math
- dashboard structure and panel selection
- alert fatigue reduction and actionable alerting
- log and trace correlation during incidents

## Practice suggestions

- Run `make run-local` and confirm the monitoring stack becomes healthy.
- Build one dashboard for a workload you understand instead of only importing examples.
- Write at least five PromQL queries from memory and explain what each reveals.
- Create one warning alert and one critical alert for the same signal with different thresholds.
- During a lab failure, pivot from Grafana to logs and then to traces to practice multi-signal debugging.

## Continue with the learning path

After this module, move deeper into [03-kubernetes-reliability](../03-kubernetes-reliability/) or revisit the full progression in [10-learning-paths](../10-learning-paths/README.md).
