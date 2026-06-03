# Grafana Advanced Theory

## How to read this module

- Use the architecture sections first so later labs have the right mental model of how Grafana moves queries, credentials, and rendered data.
- Read dashboard design and panel sections before building dashboards so layout choices support fast incident response instead of visual clutter.
- Use the provisioning and Grafana-as-code sections together when you want repeatable dashboards across development, staging, and production.
- Return to the performance and multi-tenancy sections when the Grafana footprint grows from a single team tool into a shared observability platform.

## Learning outcomes

| Area | You should be able to explain | Why it matters |
| --- | --- | --- |
| Architecture | How browser requests move through the frontend, backend, database, and proxy layers | You can debug authentication, plugin, and data source issues faster |
| Dashboards | How to design dashboards around information hierarchy and golden signals | Operators can answer health questions in seconds |
| PromQL in Grafana | How variables, regex, repeated panels, and template chains work together | One dashboard can safely scale across many services |
| Panels and transforms | Which visualization and transformation to choose for a given question | Raw metrics become readable operational signals |
| Alerting and OnCall | How routing, schedules, silences, and escalation chains interact | Alerts reach the correct human at the correct time |
| Provisioning and code | How YAML, ConfigMaps, Jsonnet, and Terraform make Grafana reproducible | You reduce drift and improve reviewability |
| Performance and tenancy | How to scale dashboards and permissions safely | Shared platforms stay fast and secure |

## 1. Grafana architecture at a glance

- Grafana has a browser-based frontend, a Go backend, a plugin framework, and a persistent database for configuration and state.
- The browser never talks directly to most protected data sources in production; instead the Grafana backend usually proxies requests.
- Dashboards, folders, users, teams, alert rules, and data source configuration live in Grafana storage even when time-series data does not.
- Each query path includes identity, authorization, query translation, optional caching, response shaping, and rendering.

```
Browser UI
  |
  | 1. dashboard JSON, panel settings, variable selections
  v
Grafana frontend (React)
  |
  | 2. authenticated API calls
  v
Grafana backend (Go)
  |-- plugin manager
  |-- data source proxy
  |-- alerting engine
  |-- provisioning loader
  |-- RBAC / auth / org context
  |
  | 3a. reads and writes metadata
  +------> Grafana database (SQLite or Postgres)
  |
  | 3b. executes queries using plugins or built-in clients
  +------> Prometheus / Loki / Tempo / Elasticsearch / cloud APIs
```

### Architecture responsibilities

| Layer | Primary duties | Common failure mode | Typical fix |
| --- | --- | --- | --- |
| Frontend | Dashboard editing, variable rendering, panel layout, Explore UX | Panel loads but spinner never ends | Inspect browser network requests and backend logs |
| Backend | Auth, proxying, plugin execution, API surface, alert evaluation | Datasource health check fails | Validate credentials, network reachability, and backend config |
| Plugin system | Extends panels, data sources, and apps | Unsigned or incompatible plugin | Upgrade Grafana or sign/allow the plugin |
| Database | Stores config, users, sessions, alert definitions, annotations | SQLite lock or migration issue | Move to Postgres or repair migrations |
| Proxy | Hides credentials and enforces server-side access path | CORS or 502 errors | Correct proxy mode URL and outbound network policy |

## 2. Frontend internals

- Grafana frontend is primarily a React application that renders dashboards from JSON models returned by the backend API.
- Variable state is maintained in the browser and injected into panel queries before requests are sent to the backend.
- Panel plugins define editors, option schemas, and rendering logic, so the same dashboard JSON can drive multiple visualization types.
- Explore, Alerting, Dashboards, and OnCall screens all consume backend APIs but present different workflows to the operator.
- A slow frontend is often caused by too many panels, too many repeated panels, or queries that return far more series than the panel can reasonably render.

### Frontend design notes

- Use dashboard links and drilldowns to split overview and deep-dive use cases instead of putting every question on one page.
- Use collapsed rows for lower-priority detail to reduce initial render cost.
- Use library panels when the same visualization pattern must remain identical across services.
- When a panel feels crowded, the problem is usually scope, not font size.

### Browser-side verification

- [ ] Open developer tools and confirm panel query requests return 200 responses.
- [ ] Confirm variable dropdown API requests finish quickly and return expected label values.
- [ ] Check panel JSON for stale datasource UIDs after dashboard import or migration.
- [ ] Verify time range and refresh interval are reasonable for the dashboard purpose.

## 3. Backend internals

- Grafana backend is written in Go and exposes REST APIs for dashboards, folders, alerting, annotations, user management, and data source health.
- The backend evaluates permissions before returning dashboard JSON, alert configuration, or query results.
- For most data sources Grafana backend holds credentials and performs server-side queries, keeping secrets out of the browser.
- Background workers load provisioned files, process alerts, execute reporting jobs, and manage plugin lifecycle tasks.
- When unified alerting is enabled, the backend also hosts rule evaluation, notification orchestration, silence handling, and policy routing.

### Backend request flow

1. The frontend calls an API such as `/api/ds/query` or `/api/search`.
2. Grafana resolves the active organization and user identity.
3. RBAC and folder permissions are checked before resource access.
4. The backend loads the target data source configuration from the Grafana database or provisioning state.
5. Proxy logic injects secrets, headers, cookies, and TLS options as configured.
6. The plugin SDK or built-in client executes the request.
7. Results are normalized into data frames and returned to the frontend for rendering or transformation.

### Backend operational commands

```bash
# Check Grafana health endpoint
curl -s http://localhost:3000/api/health | jq

# Inspect configured data sources through the API
curl -s -u admin:admin http://localhost:3000/api/datasources | jq '.[].name'

# View recent Grafana logs in Kubernetes
kubectl logs -n monitoring deploy/grafana --since=10m
```

## 4. Plugin system

- Grafana supports data source plugins, panel plugins, and app plugins.
- Data source plugins know how to query an external system and translate results into Grafana data frames.
- Panel plugins focus on rendering and editor experience, often consuming any compatible data frame.
- App plugins package broader workflows, navigation items, pages, and resource APIs.
- Plugins can be core, signed marketplace plugins, or private plugins built in-house.

### Plugin types and responsibilities

| Plugin type | Extends | Typical examples | Operator concern |
| --- | --- | --- | --- |
| Data source | Query editors, health checks, proxy routes | Prometheus, Loki, Tempo, CloudWatch | Credential storage and query semantics |
| Panel | Visualization renderers and editors | Time series, heatmap, canvas, geomap | Version compatibility with dashboard JSON |
| App | Navigation pages and integrations | OnCall, incident workflows | App permissions and lifecycle |

### Plugin lifecycle guidance

- Pin plugin versions in production so dashboards do not silently change behavior after container image updates.
- Use signed plugins where possible; unsigned plugins require explicit allow-listing and increase supply-chain risk.
- Validate plugin support against your Grafana major version before a platform upgrade.
- Keep custom plugins under source control and test them in a staging Grafana instance before rollout.

### Example plugin allow list

```yaml
apiVersion: 1
plugins:
  - name: grafana-oncall-app
    version: 1.9.0
  - name: grafana-polystat-panel
    version: 2.1.13
```

## 5. Database options: SQLite and Postgres

- Grafana database stores dashboards, folders, users, API keys, data source definitions, team membership, alerting metadata, and annotations.
- SQLite is the default lightweight option and works well for small labs, demos, and single-instance setups.
- Postgres is the preferred production backend when multiple operators, HA Grafana instances, or heavy concurrent writes exist.
- MySQL is also supported, but this module focuses on SQLite and Postgres because they are common in SRE platform deployments.

### Storage comparison

| Backend | Best fit | Strengths | Trade-offs |
| --- | --- | --- | --- |
| SQLite | Single-pod labs, workshops, small teams | Simple, zero external dependency, quick startup | File locking, harder HA story, less concurrency |
| Postgres | Production, HA, larger teams | Concurrency, backups, replicas, operational maturity | Requires external service and credentials |

### SQLite considerations

- SQLite stores state in a local file, so persistent volumes matter if the Grafana pod is recreated.
- Do not expect multiple Grafana replicas to share one SQLite file safely.
- Provisioning can reduce dependency on mutable UI changes, but the SQLite database still stores runtime state such as users and alert history.

### Postgres considerations

- Use Postgres when you need backup tooling, replication, and predictable concurrency under heavier write load.
- Validate database connection pool settings when dashboards, alerting, and provisioning all scale at once.
- Keep schema migrations aligned with the Grafana version during upgrades.

### Postgres configuration example

```ini
[database]
type = postgres
host = postgres.monitoring.svc.cluster.local:5432
name = grafana
user = grafana
password = $__file{/etc/secrets/grafana-db-password}
ssl_mode = require
max_open_conn = 50
max_idle_conn = 10
conn_max_lifetime = 14400
```

### Verification checklist

- [ ] Back up the Grafana database before major upgrades.
- [ ] Confirm alerting history survives pod reschedules.
- [ ] Measure database latency if dashboard save operations feel slow.
- [ ] Inspect migration logs during version changes.

## 6. Data source proxy and access modes

- In proxy mode the browser talks to Grafana, and Grafana talks to the data source on behalf of the user.
- Proxy mode protects secrets, simplifies CORS, and centralizes outbound network policy.
- Browser or direct mode can be useful in limited cases, but it often exposes CORS problems and pushes credentials to the client.
- Proxy routes can also be customized by plugins for authentication handshakes or proprietary APIs.

### Why proxy mode is usually preferred

- Credentials remain on the server side instead of being sent to every browser session.
- Service names like `http://prometheus.monitoring.svc:9090` stay resolvable from Grafana even when a browser cannot reach them.
- Audit and rate limiting can be centralized.
- TLS, custom headers, cookies, and OAuth forwarding are easier to standardize.

### Datasource provisioning example using proxy mode

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    uid: prometheus-main
    type: prometheus
    access: proxy
    url: http://prometheus-operated.monitoring.svc:9090
    isDefault: true
    jsonData:
      httpMethod: POST
      prometheusType: Prometheus
      cacheLevel: High
      timeInterval: 30s
    editable: false
```

### Troubleshooting proxy path

| Symptom | Likely layer | Check first |
| --- | --- | --- |
| 401 from datasource test | Credentials or OAuth forwarding | Datasource secureJsonData and auth headers |
| 502 Bad Gateway | Network or backend route | Grafana pod reachability to datasource URL |
| CORS error in browser | Wrong access mode | Switch datasource from browser to proxy |
| Query works with curl but not Grafana | Header mismatch or org context | Backend logs and datasource plugin config |

## 7. Dashboard design principles

- Good dashboards answer a small number of questions quickly; they do not try to replace ad hoc exploration.
- Information hierarchy means the highest-value indicators appear first, with drilldown detail below or behind links.
- A service reliability dashboard should prioritize traffic, errors, latency, and saturation because they map directly to user experience and resource stress.
- Each panel should justify its screen real estate by supporting a diagnosis or a decision.

### Information hierarchy pattern

| Zone | What belongs here | Operator question |
| --- | --- | --- |
| Top row | Status summary, current SLO, key alerts, active annotations | Is something wrong right now? |
| Middle rows | Golden signal trends and breakdowns | Which signal changed and when? |
| Lower rows | Dependency, pod, route, or shard details | Where exactly is the problem? |
| External links | Runbooks, Explore links, traces, logs | What is the next investigation step? |

### Golden signals layout

1. Row 1: service summary, current error rate, p95 latency, CPU/memory headroom, active incidents.
2. Row 2: traffic trends and request breakdowns by environment, route, or status code.
3. Row 3: error rate, error budget burn, and error volume distribution.
4. Row 4: latency percentiles, histogram heatmap, and traces or exemplars for jump-to-root-cause.
5. Row 5: saturation metrics such as CPU, memory, queue depth, connection pool usage, and pod restarts.
6. Row 6: optional dependency or infrastructure rows for database, cache, ingress, or queue backlogs.

### Naming conventions

- Start dashboard titles with the subject, not the environment: `Checkout Service Reliability` is better than `Prod Checkout Metrics`.
- Use stable panel titles that describe the signal and unit, for example `Request Rate (req/s)` or `Latency p95 (ms)`.
- Avoid team-specific shorthand unless every operator understands it on-call.
- Reserve emojis for curated exec dashboards if your organization intentionally uses them; avoid them on operational dashboards.

### Consistent coloring

| Signal | Recommended color bias | Reason |
| --- | --- | --- |
| Traffic | Blue/green | Neutral throughput is not itself failure |
| Errors | Yellow to red | Matches incident severity mental model |
| Latency | Purple/orange with percentile distinction | Easier to separate p50, p95, and p99 |
| Saturation | Green to amber to red thresholds | Capacity headroom is visually intuitive |

### Annotation strategy

- Use deployment annotations so traffic, error, or latency changes can be tied to releases quickly.
- Use incident annotations or bookmarks to mark major events during retrospective reviews.
- Keep annotation tags predictable such as `deployment`, `rollback`, `incident`, `maintenance`.
- Do not overload dashboards with noisy annotation sources; high-value events only.

### Dashboard review checklist

- [ ] The first screen answers whether the service is healthy for users.
- [ ] Threshold colors are consistent with platform conventions.
- [ ] The dashboard has links to runbooks, logs, and traces.
- [ ] Units are set on every panel and do not rely on operator guesswork.

## 8. PromQL in Grafana: variables, regex, and repeated panels

- Grafana template variables make one dashboard reusable across environments, clusters, services, pods, and routes.
- PromQL variables should be fast, predictable, and chained from broader scope to narrower scope.
- Regex in variable queries and panel queries can simplify filtering, but broad regexes can also create hidden cardinality explosions.
- Repeated panels and repeated rows help you stamp out a pattern per service, pod, zone, or route, but only when the variable cardinality is controlled.

### Template variable chain

```yaml
variables:
  - name: environment
    type: query
    query: label_values(kube_pod_info, cluster)
    includeAll: false
  - name: service
    type: query
    query: label_values(http_requests_total{cluster="$environment"}, job)
    refresh: onDashboardLoad
  - name: pod
    type: query
    query: label_values(kube_pod_info{cluster="$environment", namespace=~"prod|staging", pod=~"$service-.*"}, pod)
    refresh: onTimeRangeChanged
```

### Variable design rules

- Order variables from least to most cardinal: environment, region, namespace, service, pod, route.
- Use `label_values(metric, label)` for simple cases and query expressions only when the label relationship demands it.
- Avoid `includeAll` on very high-cardinality dimensions unless the dashboard is explicitly designed for aggregated views.
- Prefer `${var:regex}` or `${var:pipe}` formatting when building regular expressions from multi-select variables.

### Query examples with variables

```promql
# Traffic by selected service
sum(rate(http_requests_total{cluster="$environment", job="$service"}[5m]))

# Error rate using a chained pod variable
sum(rate(http_requests_total{cluster="$environment", job="$service", pod=~"$pod", status_code=~"5.."}[5m]))
/
sum(rate(http_requests_total{cluster="$environment", job="$service", pod=~"$pod"}[5m]))

# Regex against routes selected by a custom variable
sum(rate(http_requests_total{job="$service", route=~"${route:regex}"}[5m])) by (route)
```

### Repeated panels and rows

- Repeat a pod saturation row when each pod needs the same CPU and memory layout.
- Repeat a panel only when the repeated unit can still be scanned quickly on one screen.
- Cap `maxPerRow` so the layout stays readable on standard laptop displays.
- Use a top-level summary panel before repeated detail panels so operators can decide whether to expand further.

### Repeated panel JSON fragment

```json
{
  "title": "Pod CPU Usage",
  "type": "timeseries",
  "repeat": "pod",
  "repeatDirection": "h",
  "maxPerRow": 3,
  "targets": [
    {
      "expr": "sum(rate(container_cpu_usage_seconds_total{pod=~"$pod"}[5m])) by (pod)"
    }
  ]
}
```

### Verification checklist

- [ ] Changing the environment variable changes the service variable choices.
- [ ] Selecting multiple services does not produce invalid PromQL syntax.
- [ ] Repeated panels stay below a manageable panel count.
- [ ] The dashboard still loads quickly when default variable values are used.

## 9. Panel types deep dive

### Time series

- Primary purpose: Trend analysis over time for rates, percentiles, and saturation.
- Good uses: Requests per second, CPU usage, latency percentiles.
- Anti-pattern: Too many series in one panel hides meaning.
- Operator tip: Set unit, legend, thresholds, and null handling deliberately.

Example query

```promql
sum(rate(http_requests_total{job="$service"}[5m])) by (status_code)
```

Review question
- What decision should this panel help an on-call engineer make within 30 seconds?

### Stat

- Primary purpose: Single-value or compact sparkline view for current state.
- Good uses: Current error rate, latest p95 latency, active alert count.
- Anti-pattern: A stat without context can hide volatility.
- Operator tip: Pair stats with a trend panel when operators need historical context.

Example JSON options

```json
{
  "type": "stat",
  "options": {
    "orientation": "horizontal",
    "textMode": "value_and_name",
    "reduceOptions": {
      "calcs": ["lastNotNull"]
    }
  }
}
```

Review question
- What decision should this panel help an on-call engineer make within 30 seconds?

### Table

- Primary purpose: Structured comparison across labels, routes, pods, or teams.
- Good uses: Top failing routes, noisy pods, alert inventory.
- Anti-pattern: Huge tables become unreadable on a dashboard.
- Operator tip: Use sorting, value mappings, and links.

Example transformation pairing

```json
{
  "transformations": [
    {"id": "reduce", "options": {"reducers": ["lastNotNull"]}},
    {"id": "sortBy", "options": {"fields": {}, "sort": [{"field": "Value", "desc": true}]}}
  ]
}
```

Review question
- What decision should this panel help an on-call engineer make within 30 seconds?

### Heatmap

- Primary purpose: Distribution changes over time, especially latency buckets.
- Good uses: Histogram buckets for request duration or queue delay.
- Anti-pattern: Heatmaps are poor for simple two-series comparisons.
- Operator tip: Use histogram bucket metrics and sensible bucket units.

Example query

```promql
sum(increase(http_request_duration_seconds_bucket{job="$service"}[$__interval])) by (le)
```

Review question
- What decision should this panel help an on-call engineer make within 30 seconds?

### Bar chart

- Primary purpose: Comparison between discrete categories.
- Good uses: Errors by status class, latency by route, incidents by service.
- Anti-pattern: Bars over time often belong in time series instead.
- Operator tip: Sort categories and limit series count.

Example query

```promql
topk(10, sum(rate(http_requests_total{job="$service",status_code=~"5.."}[5m])) by (route))
```

Review question
- What decision should this panel help an on-call engineer make within 30 seconds?

### Gauge

- Primary purpose: Current usage against a fixed limit or target.
- Good uses: CPU request usage, memory headroom, queue fill percentage.
- Anti-pattern: Gauges waste space for highly volatile metrics.
- Operator tip: Use them for bounded values with clear meaning.

Example query

```promql
100 * sum(container_memory_working_set_bytes{pod=~"$pod"}) / sum(kube_pod_container_resource_limits{resource="memory",pod=~"$pod"})
```

Review question
- What decision should this panel help an on-call engineer make within 30 seconds?

### Logs panel

- Primary purpose: Inline operational log context from Loki or Elasticsearch.
- Good uses: Recent errors for a selected service and time range.
- Anti-pattern: Do not use logs panels as your only search experience.
- Operator tip: Keep labels and parsers tuned so queries remain focused.

Example query

```logql
{namespace="$namespace", app="$service"} |= "ERROR" | json | line_format "{{.level}} {{.message}} {{.trace_id}}"
```

Review question
- What decision should this panel help an on-call engineer make within 30 seconds?

### Traces panel

- Primary purpose: Trace waterfall and span search summaries.
- Good uses: High-latency traces for the selected service.
- Anti-pattern: Do not load massive trace searches on every dashboard refresh.
- Operator tip: Prefer links to Explore or scoped traces panels.

Tempo search example

```yaml
service.name = "$service"
status.code = error
span.http.target =~ "/checkout|/payment"
```

Review question
- What decision should this panel help an on-call engineer make within 30 seconds?

### Canvas

- Primary purpose: Custom topology or workflow views with bound fields.
- Good uses: Dependency maps, incident war rooms, business flow overlays.
- Anti-pattern: Canvas can become decorative instead of actionable.
- Operator tip: Use it when shape and flow matter more than raw plots.

Canvas use checklist

- [ ] Bind each shape to a real field, not a manually typed status.
- [ ] Keep navigation links to logs, traces, and runbooks on the object.
- [ ] Avoid turning the dashboard into a static architecture poster.

Review question
- What decision should this panel help an on-call engineer make within 30 seconds?


## 10. Transformations

### Merge

- What it does: Combines frames from multiple queries so related fields can be shown together.
- When to use it: Join request rate, error rate, and p95 latency into one service table.
- Example: Query A returns traffic, query B returns errors, merge on the service label.

Operator notes

- Prefer source-side aggregation in PromQL first; transformations are powerful but should not replace efficient queries.
- Inspect the data frame before and after each transform so you know which field names exist.
- Order matters: a reduce before a sort gives a different result than a sort before a reduce.

JSON fragment

```json
{
  "id": "merge",
  "options": {}
}
```
### Filter by name

- What it does: Keeps only useful fields after a verbose query.
- When to use it: Hide metadata columns and show only route, value, and threshold.
- Example: Filter out internal Prometheus labels before publishing a table panel.

Operator notes

- Prefer source-side aggregation in PromQL first; transformations are powerful but should not replace efficient queries.
- Inspect the data frame before and after each transform so you know which field names exist.
- Order matters: a reduce before a sort gives a different result than a sort before a reduce.

JSON fragment

```json
{
  "id": "filterFieldsByName",
  "options": {}
}
```
### Calculate field

- What it does: Creates a new derived column from existing fields.
- When to use it: Compute error percentage or headroom inside the panel.
- Example: Calculate `errors / total * 100` when the source system does not provide the ratio.

Operator notes

- Prefer source-side aggregation in PromQL first; transformations are powerful but should not replace efficient queries.
- Inspect the data frame before and after each transform so you know which field names exist.
- Order matters: a reduce before a sort gives a different result than a sort before a reduce.

JSON fragment

```json
{
  "id": "calculateField",
  "options": {}
}
```
### Group by

- What it does: Aggregates rows around one or more keys.
- When to use it: Summarize pod-level data to deployment or zone level.
- Example: Group by namespace and service, then sum the latest values.

Operator notes

- Prefer source-side aggregation in PromQL first; transformations are powerful but should not replace efficient queries.
- Inspect the data frame before and after each transform so you know which field names exist.
- Order matters: a reduce before a sort gives a different result than a sort before a reduce.

JSON fragment

```json
{
  "id": "groupBy",
  "options": {}
}
```
### Sort

- What it does: Orders rows so the most important items are on top.
- When to use it: Show the noisiest routes or most saturated pods first.
- Example: Sort descending on error rate after reducing each series.

Operator notes

- Prefer source-side aggregation in PromQL first; transformations are powerful but should not replace efficient queries.
- Inspect the data frame before and after each transform so you know which field names exist.
- Order matters: a reduce before a sort gives a different result than a sort before a reduce.

JSON fragment

```json
{
  "id": "sortBy",
  "options": {}
}
```
### Reduce

- What it does: Turns time-series values into single summary values.
- When to use it: Latest p95 latency, max queue depth, or average CPU.
- Example: Reduce before stat or table panels to avoid many samples per row.

Operator notes

- Prefer source-side aggregation in PromQL first; transformations are powerful but should not replace efficient queries.
- Inspect the data frame before and after each transform so you know which field names exist.
- Order matters: a reduce before a sort gives a different result than a sort before a reduce.

JSON fragment

```json
{
  "id": "reduce",
  "options": {}
}
```
### Convert field type

- What it does: Casts strings to numbers, times, or booleans for later transforms.
- When to use it: Fix JSON-derived log fields so Grafana can sort numerically.
- Example: Convert a latency string to numeric milliseconds before thresholding.

Operator notes

- Prefer source-side aggregation in PromQL first; transformations are powerful but should not replace efficient queries.
- Inspect the data frame before and after each transform so you know which field names exist.
- Order matters: a reduce before a sort gives a different result than a sort before a reduce.

JSON fragment

```json
{
  "id": "convertFieldType",
  "options": {}
}
```

## 11. Alerting engine

- Grafana managed alerting stores alert rules, groups, contact points, notification policies, silences, and mute timings in Grafana state.
- Rule evaluation runs on intervals; notifications are routed only when rule states and policy matches align.
- Alert labels are the routing contract, so label hygiene matters as much as the PromQL expression.
- A clean alert path is query -> reduce -> condition -> labels and annotations -> route -> contact point -> human response.

### Alerting objects

| Object | Purpose | Operational advice |
| --- | --- | --- |
| Alert rule | Defines the expression and threshold | Keep expressions readable and annotate with runbook links |
| Evaluation group | Defines cadence for related rules | Align interval with signal volatility and datasource load |
| Contact point | Notification destination such as PagerDuty or Slack | Test every receiver after creation |
| Notification policy | Routes alerts based on labels | Model it like a tree, not a flat list |
| Silence | Temporary suppression for specific label matchers | Use for known work, not permanent exceptions |
| Mute timing | Scheduled suppression window | Use for recurring maintenance or business hours patterns |

### Alert rule example

```yaml
apiVersion: 1
groups:
  - orgId: 1
    name: service-reliability
    folder: SRE Alerts
    interval: 1m
    rules:
      - uid: checkout-error-rate
        title: Checkout high error rate
        condition: C
        data:
          - refId: A
            datasourceUid: prometheus-main
            relativeTimeRange:
              from: 300
              to: 0
            model:
              expr: sum(rate(http_requests_total{job="checkout",status_code=~"5.."}[5m])) / sum(rate(http_requests_total{job="checkout"}[5m]))
          - refId: C
            datasourceUid: __expr__
            model:
              type: threshold
              conditions:
                - evaluator:
                    type: gt
                    params: [0.02]
                  reducer:
                    type: last
        for: 5m
        labels:
          severity: critical
          team: payments
        annotations:
          summary: Checkout error rate above 2%
          runbook: https://runbooks.example.com/checkout-errors
```

### Contact points and routing

| Receiver | Use for | Typical matchers | Notes |
| --- | --- | --- | --- |
| PagerDuty | Critical customer impact | service=payments or severity=critical | 24x7 paging |
| Slack | Warning and informational alerts | severity=warning | Team triage channel |
| Email | Daily summaries or lower urgency notifications | environment=dev | Avoid paging humans for low-risk alerts |

### Silence and mute timing guidance

- Use silences for one-off changes such as maintenance windows, controlled failovers, or incident-specific noise suppression.
- Use mute timings for recurring windows such as non-production quiet hours or weekly batch job maintenance.
- Document who created a silence and why; vague silence comments become future confusion.
- Verify whether a silence suppresses notifications only or changes dashboard state visibility in your operational workflow.

### Alerting verification checklist

- [ ] Rule expression returns expected data in the rule preview.
- [ ] Contact point test message succeeds.
- [ ] Labels match the intended notification policy branch.
- [ ] A silence or mute timing explains any expected suppression.

## 12. Grafana OnCall

- Grafana OnCall connects schedules, escalation chains, routing rules, and responder workflows to the alert stream.
- The key design goal is not only sending notifications but ensuring they result in ownership and response.
- OnCall works best when alert labels already identify service, severity, team, and environment clearly.

### OnCall building blocks

| Object | Description | Good practice |
| --- | --- | --- |
| Schedule | Defines who is primary and secondary over time | Model follow-the-sun and backup coverage explicitly |
| Escalation chain | Defines what happens if the first receiver does not acknowledge | Include timing steps and fallback channels |
| Integration | Connects Grafana Alerting, Alertmanager, PagerDuty, Slack, or webhook sources | Normalize labels early |
| Route | Maps an incoming alert to a schedule or chain | Route by service ownership labels |

### Example escalation policy

1. Step 1: page primary on-call for the owning service.
2. Step 2: after 5 minutes without acknowledgement, notify backup on-call.
3. Step 3: after 10 minutes, escalate to the incident commander or platform lead.
4. Step 4: post status to the shared incident Slack channel.

### OnCall operator checklist

- [ ] Schedules have coverage for nights, weekends, and holidays.
- [ ] Escalation timing matches expected response objectives.
- [ ] Each integration is tested after credential rotation.
- [ ] Service labels in alerts map unambiguously to an owning schedule.

## 13. Provisioning

- Provisioning loads declarative configuration from files at startup and on periodic refresh, depending on the object type.
- Use provisioning for repeatable datasources, dashboards, alert rules, contact points, and policy trees.
- Provisioning reduces drift, but you must decide whether the UI is allowed to update or whether code is the only source of truth.

### Datasource provisioning YAML

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    uid: prometheus-main
    type: prometheus
    access: proxy
    url: http://prometheus-operated.monitoring.svc:9090
    isDefault: true
    editable: false
    jsonData:
      httpMethod: POST
      manageAlerts: true
      timeInterval: 30s
      exemplarTraceIdDestinations:
        - name: trace_id
          datasourceUid: tempo-main
  - name: Loki
    uid: loki-main
    type: loki
    access: proxy
    url: http://loki-gateway.monitoring.svc:3100
    editable: false
    jsonData:
      maxLines: 1000
      derivedFields:
        - name: TraceID
          matcherRegex: 'trace_id=(\w+)'
          url: '$${__value.raw}'
          datasourceUid: tempo-main
```

### Dashboard provisioning with ConfigMaps

```yaml
apiVersion: 1
providers:
  - name: sre-dashboards
    orgId: 1
    folder: SRE Services
    type: file
    updateIntervalSeconds: 30
    disableDeletion: false
    allowUiUpdates: false
    options:
      path: /var/lib/grafana/dashboards/sre
      foldersFromFilesStructure: true
```

### Kubernetes ConfigMap example

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-checkout
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
data:
  checkout-reliability.json: |
    {
      "title": "Checkout Service Reliability",
      "uid": "checkout-reliability",
      "schemaVersion": 39,
      "panels": []
    }
```

### Alert provisioning example

```yaml
apiVersion: 1
contactPoints:
  - orgId: 1
    name: Slack-SRE
    receivers:
      - uid: slack-sre
        type: slack
        settings:
          url: ${SLACK_WEBHOOK_URL}
          recipient: '#sre-alerts'
policies:
  - orgId: 1
    receiver: Slack-SRE
    routes:
      - receiver: PagerDuty-Critical
        object_matchers:
          - ['severity', '=', 'critical']
```

### Provisioning review checklist

- [ ] Datasource UIDs are stable and referenced from dashboards by UID, not display name alone.
- [ ] ConfigMap labels match the Grafana sidecar configuration.
- [ ] Provisioned dashboard folders and org IDs match the intended tenancy.
- [ ] Alert rule files are loaded in the correct folder and evaluation group.

## 14. Grafana as code

- Provisioning is the entry point, but mature teams often generate dashboard JSON instead of hand-editing it.
- Grafonnet and Jsonnet help you compose reusable dashboard templates with functions, variables, and shared panel fragments.
- Terraform provider for Grafana manages folders, dashboards, data sources, alerting resources, teams, and permissions through code and state.

### Tool comparison

| Tool | Strength | Trade-off | Best fit |
| --- | --- | --- | --- |
| Raw JSON | Exact Grafana model, easy export/import | Hard to review and reuse manually | Small numbers of dashboards |
| Grafonnet / Jsonnet | Composable, DRY, can build many similar dashboards | Requires template discipline and build tooling | Platform teams with repeated patterns |
| Terraform provider grafana | Resource lifecycle management and integration with infrastructure workflows | State management and import complexity | End-to-end platform automation |

### Grafonnet example

```jsonnet
local g = import 'grafonnet/grafana.libsonnet';

g.dashboard.new('checkout-reliability')
+ g.dashboard.withUid('checkout-reliability')
+ g.dashboard.withTags(['sre', 'golden-signals'])
+ g.dashboard.withPanels([
  g.panel.timeSeries.new('Request Rate')
  + g.panel.timeSeries.queryOptions.withTargets([
      g.query.prometheus.new('sum(rate(http_requests_total{job="checkout"}[5m]))')
    ])
])
```

### Terraform example

```hcl
provider "grafana" {
  url  = "https://grafana.example.com"
  auth = var.grafana_token
}

resource "grafana_folder" "services" {
  title = "SRE Services"
}

resource "grafana_dashboard" "checkout" {
  folder      = grafana_folder.services.id
  config_json = file("dashboards/checkout-reliability.json")
}
```

### Code review checklist

- [ ] UIDs are stable and not regenerated on every apply.
- [ ] Reusable snippets capture platform standards such as thresholds and links.
- [ ] Generated JSON is committed or reproducible in CI.
- [ ] Terraform state access is controlled because it may contain sensitive identifiers.

## 15. Performance and scaling

- Most Grafana performance problems begin with expensive queries, excessive panel count, or badly scoped variables rather than with the Grafana binary itself.
- Dashboard query optimization is usually the fastest path to better user experience and lower data source cost.
- Recorded queries or recording rules are valuable when the same expensive expression is used across many dashboards and alerts.

### Dashboard query optimization

- Prefer recording rules for expensive histogram and aggregation queries that many panels share.
- Use `$__rate_interval` and `$__interval` so queries adapt to time range and resolution.
- Avoid querying raw high-cardinality labels such as path, pod, and status together unless the panel truly needs all three.
- Reduce default time range for operational dashboards; an on-call dashboard usually does not need 30 days by default.
- Split overview and deep-dive dashboards so every page does not execute every expensive query.

### Caching and recorded queries

| Technique | What it helps | Notes |
| --- | --- | --- |
| Datasource query caching | Repeated identical queries | Useful for shared dashboards with short refresh intervals |
| Prometheus recording rules | Expensive aggregations and histogram quantiles | Shifts cost to Prometheus rule evaluation |
| Pre-computed warehouse tables | Business tables or long-range reports | Better than forcing Grafana to act like ETL |
| Library panels | Consistency rather than speed | Still helps avoid many slightly different expensive queries |

### Performance commands

```bash
# Find panels making slow Prometheus calls by watching backend logs
kubectl logs -n monitoring deploy/grafana --since=15m | grep -i 'query'

# Inspect Prometheus top queries if enabled
curl -s http://prometheus-operated.monitoring.svc:9090/api/v1/status/tsdb | jq

# Check Grafana health and version
curl -s http://localhost:3000/api/health | jq '.version'
```

### Optimization checklist

- [ ] Repeated panels are capped and collapsed when possible.
- [ ] Variables do not default to all pods in a large cluster.
- [ ] Tables are reduced or sorted before rendering thousands of rows.
- [ ] Large dashboards are broken into overview and drilldown variants.

## 16. Multi-tenancy: organizations, teams, folders, and RBAC

- Grafana multi-tenancy can be coarse-grained with organizations or fine-grained with folders, teams, and RBAC.
- Organizations isolate many settings and assets completely but also add administration overhead.
- Teams simplify group membership and permission assignment inside one organization.
- Folders and RBAC control who can view, edit, or administer dashboards and alerting resources.

### Multi-tenancy controls

| Control | Isolation level | Use case | Caution |
| --- | --- | --- | --- |
| Organization | High | Separate business units or customers | Cross-org visibility and reuse become harder |
| Team | Medium | Map service ownership or platform groups | Needs disciplined membership management |
| Folder permissions | Medium | Restrict dashboard collections | Inheritance can surprise new admins |
| RBAC roles | Fine | Grant admin/editor/viewer or custom roles | Custom role sprawl can become complex |

### Folder permission model

- Keep shared platform dashboards in read-only folders for most teams.
- Give service teams edit access only to folders they own.
- Separate incident or executive folders if they require different audiences.
- Document which roles can edit alert rules versus dashboards.

### Example Terraform for teams and folder permissions

```hcl
resource "grafana_team" "payments" {
  name = "payments"
}

resource "grafana_folder_permission" "payments_folder" {
  folder_uid = grafana_folder.services.uid
  permissions {
    team_id    = grafana_team.payments.id
    permission = "Edit"
  }
}
```

### Tenant review checklist

- [ ] Folder ownership is clear and documented.
- [ ] Service teams can edit only what they own.
- [ ] Global admins are limited and monitored.
- [ ] Alert routes align with service ownership labels and OnCall schedules.

## 17. Operational reference tables

| Task | API or file | Quick check |
| --- | --- | --- |
| List dashboards | /api/search?type=dash-db | Ensure expected folder and UID exist |
| List datasources | /api/datasources | Check UID stability before imports |
| Check alert rules | /api/ruler/grafana/api/v1/rules | Validate rule presence and folder |
| Check silences | /api/alertmanager/grafana/api/v2/silences | Confirm maintenance suppression state |
| Check annotations | /api/annotations | Verify deployment markers appear on dashboards |

### Sample API calls

```bash
# Search dashboards
curl -s -u admin:admin http://localhost:3000/api/search?type=dash-db | jq '.[].title'

# List alertmanager contact points through Grafana API
curl -s -u admin:admin http://localhost:3000/api/alertmanager/grafana/config/api/v1/receivers | jq

# Fetch a provisioned dashboard by UID
curl -s -u admin:admin http://localhost:3000/api/dashboards/uid/checkout-reliability | jq '.dashboard.title'
```

## 18. Final review checklist

- [ ] You can explain the difference between Grafana state and observability data source storage.
- [ ] You can choose an appropriate panel type for a latency distribution, a current percentage, and a categorical comparison.
- [ ] You can build chained variables without causing uncontrolled cardinality.
- [ ] You can describe the path from alert rule to routed notification to OnCall escalation.
- [ ] You can provision dashboards, datasources, and alerting resources through code.
- [ ] You can explain why a multi-team Grafana deployment often outgrows SQLite.

## 19. Self-check questions

1. When should you prefer proxy access mode over browser mode for a datasource?
2. Why do repeated panels become dangerous on high-cardinality labels?
3. What is the practical difference between a silence and a mute timing?
4. Why are stable datasource UIDs more important than datasource display names in provisioned dashboards?
5. Which panel type best shows latency distribution over time and why?
6. What are the first levers to pull when Grafana dashboards feel slow?
