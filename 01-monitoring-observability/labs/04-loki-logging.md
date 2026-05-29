# Lab 04: Loki Log Aggregation

## Deploy Loki Stack
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm upgrade --install loki grafana/loki-stack \
  --namespace monitoring \
  --set grafana.enabled=false \
  --set promtail.enabled=true
```

## Verify Promtail
```bash
kubectl get pods -n monitoring | grep promtail
kubectl logs -n monitoring -l app=promtail | tail -20
```

## LogQL Queries (Grafana Explore)
```logql
{namespace="default", app="api"}
{namespace="default"} |= "ERROR"
{app="api"} | json | level="error"
rate({app="api"} |= "ERROR" [5m])
topk(5, sum(count_over_time({app="api"} |= "ERROR" [1h])) by (msg))
```

## Log-Based Alert
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: loki-log-alerts
  namespace: monitoring
spec:
  groups:
    - name: log-alerts
      rules:
        - alert: HighErrorLogRate
          expr: sum(rate({app="api"} |= "ERROR" [5m])) > 10
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "High error log rate for api"
```

## Verification
- [ ] Promtail DaemonSet running on all nodes
- [ ] Loki receiving logs in Grafana Explore
- [ ] LogQL rate query returns values
