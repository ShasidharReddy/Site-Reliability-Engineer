Lab 04 — Grafana dashboards

1) Import dashboards:
- Open Grafana (port-forward or ingress)
- Dashboards -> Import -> paste JSON or use Grafana dashboard ID

2) Recommended dashboards:
- Cluster overview: node CPU/mem, kube-system pods
- App overview: request rate, error rate, latency p50/p95
- SLO status panel: current error budget burn

3) Best practices:
- Single-purpose dashboards per audience
- Use templating variables for service/cluster
- Link each alert to a runbook URL
