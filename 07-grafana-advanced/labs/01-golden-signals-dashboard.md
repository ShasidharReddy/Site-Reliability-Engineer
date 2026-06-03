# Lab 01: Build a Golden Signals Dashboard from Scratch

## Lab goals

- Build a complete golden signals dashboard from a blank Grafana dashboard.
- Implement chained variables for environment, service, and pod selection.
- Add traffic, errors, latency, and saturation panels with thresholds and annotations.
- Add data links so operators can jump from panels into Explore, logs, and traces.
- Export the final dashboard JSON for later provisioning.

## Time budget

| Phase | Target time | Primary output |
| --- | --- | --- |
| Scoping | 5 minutes | Folder, datasource choice, naming standard |
| Variables | 5 minutes | Environment/service/pod chain |
| Panels | 15 minutes | Golden signals rows complete |
| Annotations and links | 3 minutes | Deployments and incidents visible |
| Export and verify | 2 minutes | Reusable JSON |

## Prerequisites

- [ ] Grafana can reach Prometheus and the Prometheus datasource UID is known.
- [ ] Metrics exist for `http_requests_total`, `http_request_duration_seconds_bucket`, CPU, and memory.
- [ ] Deployment or incident annotation sources are available through Grafana annotations or Loki.
- [ ] You know at least one service name and one cluster/environment label to test with.

## Naming and layout standard

| Dashboard element | Convention | Example |
| --- | --- | --- |
| Dashboard title | Subject first | Checkout Service Reliability |
| Top row stats | Signal and unit | Request Rate (req/s) |
| Rows | Golden signal names | Traffic, Errors, Latency, Saturation |
| Variables | Lowercase nouns | environment, service, pod |

## Step 1: Create the folder and dashboard shell

1. Open Grafana and create or choose a folder named `SRE Services`.
2. Create a new dashboard and save immediately so it gets a stable UID.
3. Name it `Service Reliability - $service` if you want the title to reflect the selected service, or use a fixed title for provisioning stability.
4. Set the default time range to the last 1 hour and refresh to 30 seconds.

### API alternative

```bash
GRAFANA_URL=http://localhost:3000
GRAFANA_USER=admin
GRAFANA_PASS=admin

curl -s -u ${GRAFANA_USER}:${GRAFANA_PASS}   -H 'Content-Type: application/json'   -X POST ${GRAFANA_URL}/api/folders   -d '{"title":"SRE Services","uid":"sre-services"}' | jq
```

### Verification

- [ ] The folder exists and is visible in the left navigation.
- [ ] The new dashboard has a UID and saves without errors.
- [ ] The chosen Prometheus datasource is selected as default for new panels.

## Step 2: Create chained variables

Create variables in Dashboard settings -> Variables in the following order.

| Variable | Type | Query | Notes |
| --- | --- | --- | --- |
| environment | Query | label_values(kube_pod_info, cluster) | Use your cluster or environment label |
| service | Query | label_values(http_requests_total{cluster="$environment"}, job) | Depends on environment |
| pod | Query | label_values(kube_pod_info{cluster="$environment", pod=~"$service-.*"}, pod) | Depends on service |

### Variable options

- Enable multi-value for `pod` only if you sometimes compare a subset of pods.
- Disable `Include All` on `pod` unless your PromQL explicitly handles large pod sets.
- Set `Refresh` to `On Dashboard Load` for `environment` and `service`, and `On Time Range Change` for `pod` if pod churn is high.

### Variable JSON reference

```json
{
  "templating": {
    "list": [
      {
        "name": "environment",
        "type": "query",
        "query": "label_values(kube_pod_info, cluster)"
      },
      {
        "name": "service",
        "type": "query",
        "query": "label_values(http_requests_total{cluster="$environment"}, job)"
      },
      {
        "name": "pod",
        "type": "query",
        "query": "label_values(kube_pod_info{cluster="$environment", pod=~"$service-.*"}, pod)"
      }
    ]
  }
}
```

### Verification

- [ ] Changing environment changes the service dropdown options.
- [ ] Changing service changes the pod dropdown options.
- [ ] No variable query takes longer than a few seconds.

## Step 3: Build the Traffic row

### Panel: Request Rate (req/s)

- Visualization: timeseries
- Question answered: What is happening to traffic right now for the selected service?
- Keep the panel title stable so alert screenshots and incident notes match the dashboard.

Query

```promql
sum(rate(http_requests_total{cluster="$environment",job="$service",pod=~"$pod"}[5m]))
```

Configuration checklist

- [ ] Unit: req/s
- [ ] Legend: hidden for single series
- [ ] Thresholds: none for base throughput
- [ ] Link: Explore in Prometheus

Verification

- [ ] The Request Rate (req/s) panel renders without PromQL errors.
- [ ] Units are correct and thresholds display as expected.
- [ ] Changing variables updates only the intended data.
### Panel: Requests by Status Class

- Visualization: barchart
- Question answered: What is happening to traffic right now for the selected service?
- Keep the panel title stable so alert screenshots and incident notes match the dashboard.

Query

```promql
sum(rate(http_requests_total{cluster="$environment",job="$service",status_code=~"2..|3..|4..|5.."}[5m])) by (status_code)
```

Configuration checklist

- [ ] Display as bars
- [ ] Sort by value descending
- [ ] Use consistent colors for 2xx/4xx/5xx
- [ ] Link to route breakdown dashboard

Verification

- [ ] The Requests by Status Class panel renders without PromQL errors.
- [ ] Units are correct and thresholds display as expected.
- [ ] Changing variables updates only the intended data.

## Step 3: Build the Errors row

### Panel: Error Rate (%)

- Visualization: stat
- Question answered: What is happening to errors right now for the selected service?
- Keep the panel title stable so alert screenshots and incident notes match the dashboard.

Query

```promql
100 * sum(rate(http_requests_total{cluster="$environment",job="$service",status_code=~"5.."}[5m])) / sum(rate(http_requests_total{cluster="$environment",job="$service"}[5m]))
```

Configuration checklist

- [ ] Unit: percent
- [ ] Thresholds: 1 warning, 5 critical
- [ ] Sparkline: enabled
- [ ] Color mode: background

Verification

- [ ] The Error Rate (%) panel renders without PromQL errors.
- [ ] Units are correct and thresholds display as expected.
- [ ] Changing variables updates only the intended data.
### Panel: Error Volume Heatmap

- Visualization: heatmap
- Question answered: What is happening to errors right now for the selected service?
- Keep the panel title stable so alert screenshots and incident notes match the dashboard.

Query

```promql
sum(increase(http_requests_total{cluster="$environment",job="$service",status_code=~"5.."}[$__interval])) by (status_code)
```

Configuration checklist

- [ ] Bucket by status code or route
- [ ] Use yellow->red palette
- [ ] Keep panel height large enough
- [ ] Add data link to logs

Alternative query for route heatmap

```promql
topk(20, sum(rate(http_requests_total{cluster="$environment",job="$service",status_code=~"5.."}[5m])) by (route))
```

Verification

- [ ] The Error Volume Heatmap panel renders without PromQL errors.
- [ ] Units are correct and thresholds display as expected.
- [ ] Changing variables updates only the intended data.

## Step 3: Build the Latency row

### Panel: Latency Percentiles

- Visualization: timeseries
- Question answered: What is happening to latency right now for the selected service?
- Keep the panel title stable so alert screenshots and incident notes match the dashboard.

Query

```promql
histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket{cluster="$environment",job="$service"}[5m])) by (le))
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{cluster="$environment",job="$service"}[5m])) by (le))
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{cluster="$environment",job="$service"}[5m])) by (le))
```

Configuration checklist

- [ ] Unit: ms or s depending on metric
- [ ] Show p50, p95, p99 with distinct colors
- [ ] Legend includes percentile name
- [ ] Link to Tempo traces if exemplars exist

Legend suggestion

| Series | Color | Reason |
| --- | --- | --- |
| p50 | blue | Baseline median |
| p95 | orange | Common SLO signal |
| p99 | red | Tail latency and incident focus |

Verification

- [ ] The Latency Percentiles panel renders without PromQL errors.
- [ ] Units are correct and thresholds display as expected.
- [ ] Changing variables updates only the intended data.
### Panel: Latency Heatmap

- Visualization: heatmap
- Question answered: What is happening to latency right now for the selected service?
- Keep the panel title stable so alert screenshots and incident notes match the dashboard.

Query

```promql
sum(rate(http_request_duration_seconds_bucket{cluster="$environment",job="$service"}[5m])) by (le)
```

Configuration checklist

- [ ] Use histogram buckets
- [ ] Enable exemplars if available
- [ ] Y-axis unit follows bucket boundaries
- [ ] Link to Explore with same time range

Verification

- [ ] The Latency Heatmap panel renders without PromQL errors.
- [ ] Units are correct and thresholds display as expected.
- [ ] Changing variables updates only the intended data.

## Step 3: Build the Saturation row

### Panel: CPU Saturation (%)

- Visualization: gauge
- Question answered: What is happening to saturation right now for the selected service?
- Keep the panel title stable so alert screenshots and incident notes match the dashboard.

Query

```promql
100 * sum(rate(container_cpu_usage_seconds_total{cluster="$environment",pod=~"$pod"}[5m])) / sum(kube_pod_container_resource_limits{cluster="$environment",resource="cpu",pod=~"$pod"})
```

Configuration checklist

- [ ] Gauge max 100
- [ ] Thresholds: 70/85
- [ ] Show last value
- [ ] Link to pod drilldown

Common pitfall
- CPU limits may be absent for some workloads; if so, replace the denominator with CPU requests or show raw CPU usage.


Verification

- [ ] The CPU Saturation (%) panel renders without PromQL errors.
- [ ] Units are correct and thresholds display as expected.
- [ ] Changing variables updates only the intended data.
### Panel: Memory Saturation (%)

- Visualization: timeseries
- Question answered: What is happening to saturation right now for the selected service?
- Keep the panel title stable so alert screenshots and incident notes match the dashboard.

Query

```promql
100 * sum(container_memory_working_set_bytes{cluster="$environment",pod=~"$pod"}) / sum(kube_pod_container_resource_limits{cluster="$environment",resource="memory",pod=~"$pod"})
```

Configuration checklist

- [ ] Unit: percent
- [ ] Thresholds: 75/90
- [ ] Break down by pod if needed
- [ ] Link to Kubernetes dashboard

Verification

- [ ] The Memory Saturation (%) panel renders without PromQL errors.
- [ ] Units are correct and thresholds display as expected.
- [ ] Changing variables updates only the intended data.

## Step 4: Add annotations

- Create a deployment annotation so application changes are visible on the time series panels.
- Create an incident annotation to mark high-severity events or manual bookmarks.
- Tag annotations consistently so operators can filter by `deployment` or `incident`.

### Deployment annotation example

```json
{
  "name": "Deployments",
  "datasource": {"type": "grafana", "uid": "-- Grafana --"},
  "enable": true,
  "iconColor": "rgba(0, 211, 255, 1)",
  "tags": ["deployment"],
  "type": "tags"
}
```

### Incident annotation API example

```bash
curl -s -u admin:admin   -H 'Content-Type: application/json'   -X POST http://localhost:3000/api/annotations   -d '{
    "dashboardUID":"service-reliability",
    "time":1710000000000,
    "tags":["incident","sev2"],
    "text":"Checkout incident declared"
  }' | jq
```

### Verification

- [ ] Deployment markers appear on traffic, error, and latency panels.
- [ ] Incident annotations are visible and clickable.
- [ ] Annotation tags are useful for filtering.

## Step 5: Add thresholds and data links

| Panel | Threshold suggestion | Data link |
| --- | --- | --- |
| Error Rate (%) | 1 warning, 5 critical | Explore logs for selected service |
| Latency Percentiles | Match service SLO, for example p95 > 300ms | Tempo trace search or Explore |
| CPU Saturation (%) | 70 warning, 85 critical | Kubernetes pod detail dashboard |
| Memory Saturation (%) | 75 warning, 90 critical | Container restart or OOM dashboard |

### Example data link JSON

```json
{
  "fieldConfig": {
    "defaults": {
      "links": [
        {
          "title": "Open logs in Explore",
          "url": "/explore?left={"datasource":"loki-main","queries":[{"expr":"{app=\"$service\"}"}],"range":{"from":"${__from}","to":"${__to}"}}"
        }
      ]
    }
  }
}
```

## Step 6: Export the dashboard JSON

1. Open Dashboard settings -> JSON Model and copy the dashboard JSON, or use Share -> Export.
2. Save the file as `dashboards/service-reliability.json` in your Git repository.
3. Remove transient values such as local plugin version metadata if your review process prefers normalized JSON.

### API export example

```bash
curl -s -u admin:admin   http://localhost:3000/api/dashboards/uid/service-reliability   | jq '.dashboard' > dashboards/service-reliability.json
```

### Final verification checklist

- [ ] The dashboard shows all four golden signals for the selected service.
- [ ] Variables, annotations, thresholds, and data links all work.
- [ ] The exported JSON can be committed and reviewed in Git.
- [ ] At least one operator other than the author can understand the layout quickly.
