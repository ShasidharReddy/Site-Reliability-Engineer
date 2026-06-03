# 04 — Automation and CI

## Local Automation Commands

| Command | Purpose |
|---|---|
| `make setup` | prerequisite check and script readiness |
| `make run-local` | create/reuse kind cluster and deploy stack |
| `make deploy` | deploy stack to current kubectl context |
| `make cleanup` | clean monitoring stack resources |
| `make build` | generate artifacts/course-index.md |
| `make validate` | structural + link + shell validation |
| `make ci` | CI-equivalent local execution |

## CI Automation

Workflow path: `.github/workflows/ci.yml`

Triggers:
- push to `main`
- pull requests to `main`

Primary job:
- checkout
- `make ci`

## Operations Automation Ideas

Use these scripts in cron or scheduled workflow jobs:
- `05-gcp-operations/scripts/gcp-health-check.sh`
- `06-linux-networking/scripts/system-health-check.sh`
- `06-linux-networking/scripts/network-diag.sh`

Recommended schedule:
- every 15m: cluster and alerting health checks
- hourly: node and pod drift checks
- daily: dependency and runbook verification

