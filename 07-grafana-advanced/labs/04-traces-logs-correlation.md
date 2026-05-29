# Lab 04: Traces and Logs Correlation

## Overview
Configure Grafana to correlate metrics → traces → logs for full observability.

## Architecture
```
Metrics (Prometheus) ─── exemplars ──▶ Traces (Tempo)
Logs (Loki) ─────────── traceId field ─▶ Traces (Tempo)
Grafana Explore ──────── unified view ──▶ All three
```

## Part 1: Configure Datasource Links

In datasources.yaml:
```yaml
- name: Prometheus
  jsonData:
    exemplarTraceIdDestinations:
      - name: traceID
        datasourceUid: tempo-uid  # Clicks on metric exemplars open Tempo

- name: Loki
  jsonData:
    derivedFields:
      - name: TraceID
        matcherRegex: 'traceId=(\w+)'
        url: '$${__value.raw}'
        datasourceUid: tempo-uid  # traceId in log line becomes link
```

## Part 2: Use Explore for Correlation

1. Grafana → Explore → Select Prometheus
2. Query: `http_request_duration_seconds_bucket{job="api"}[5m]`
3. See exemplars as dots on chart
4. Click an exemplar → "Open in Tempo"
5. See full trace for that high-latency request

## Part 3: Logs Correlation

1. Grafana → Explore → Select Loki
2. Query: `{app="api"} |= "ERROR"`
3. Expand a log line → see traceId field highlighted as link
4. Click → Opens Tempo trace for that request

## Part 4: Split View

1. Explore → Split (two datasources side-by-side)
2. Left: Prometheus metrics for service
3. Right: Loki logs filtered to same time range
4. When you zoom in on left, right syncs to same time window

## Part 5: Create Correlation Dashboard

Panel with Data Links:
```json
{
  "fieldConfig": {
    "defaults": {
      "links": [
        {
          "title": "View logs",
          "url": "/explore?orgId=1&left={"datasource":"loki-uid","queries":[{"expr":"{job=\"${__field.labels.job}\"}"}],"range":{"from":"${__from}","to":"${__to}"}}",
          "targetBlank": false
        }
      ]
    }
  }
}
```

## Verification
- [ ] Click exemplar → opens Tempo trace
- [ ] Log line with traceId shows link to Tempo
- [ ] Explore split view works
- [ ] Data links navigate correctly
