Lab 03 — Define SLIs, SLOs and Alerts

1) Example SLI: request success rate over 5m
Prometheus: 
  expr: (sum(rate(http_requests_total{job="myapp",code!~"5.."}[5m]))
         / sum(rate(http_requests_total{job="myapp"}[5m]))) * 100

2) Create PrometheusRule (recording + alerting)
- Use kube-prometheus-stack: apply a PrometheusRule manifest under monitoring namespace
- Example alert: if success_rate < 99.5% for 10m -> fire

3) Error budget and SLO workflow
- Track burn rate via alerting rules
- Link alerts to runbooks and incident channels
