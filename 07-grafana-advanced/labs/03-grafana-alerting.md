# Lab 03: Grafana Alerting and Routing

## Lab goals

- Create PagerDuty, Slack, and email contact points.
- Build alert rules from PromQL for traffic, error, latency, and saturation signals.
- Route notifications by labels using notification policies.
- Use silences and mute timings safely.
- Introduce recording rules for complex alert expressions.
- Test alert routing end to end from firing condition to delivered notification.

## Alerting architecture for the lab

```
Prometheus metrics -> Grafana alert rule -> labels and annotations -> notification policy tree
                     -> contact point -> Slack / PagerDuty / email
                     -> silence or mute timing may suppress notification delivery
```

## Prerequisites

- [ ] Grafana unified alerting is enabled.
- [ ] Prometheus datasource exists and can be used for alert rules.
- [ ] PagerDuty integration key, Slack webhook, and SMTP or email settings are available.
- [ ] At least one test service produces metrics that can intentionally cross a threshold.

## Step 1: Create contact points

| Contact point | Use case | Required secret |
| --- | --- | --- |
| PagerDuty-Critical | Critical customer-impacting alerts | PagerDuty integration key |
| Slack-SRE | Warning and informational notifications | Slack webhook URL |
| Email-OnCall | Fallback or audit notifications | SMTP credentials already configured |

### UI workflow

1. Open Alerting -> Contact points.
2. Create a PagerDuty contact point named `PagerDuty-Critical` and paste the integration key.
3. Create a Slack contact point named `Slack-SRE` and configure the webhook URL and channel.
4. Create an email contact point named `Email-OnCall` and provide the destination address.
5. Use the built-in test feature for each contact point.

### Provisioning YAML alternative

```yaml
apiVersion: 1
contactPoints:
  - orgId: 1
    name: PagerDuty-Critical
    receivers:
      - uid: pagerduty-critical
        type: pagerduty
        settings:
          integrationKey: ${PAGERDUTY_INTEGRATION_KEY}
          severity: critical
  - orgId: 1
    name: Slack-SRE
    receivers:
      - uid: slack-sre
        type: slack
        settings:
          url: ${SLACK_WEBHOOK_URL}
          recipient: '#sre-alerts'
  - orgId: 1
    name: Email-OnCall
    receivers:
      - uid: email-oncall
        type: email
        settings:
          addresses: oncall@example.com
```

### Verification

- [ ] Each contact point test succeeds.
- [ ] PagerDuty event appears in the correct service.
- [ ] Slack message lands in the intended channel.
- [ ] Email arrives and is not rejected by SMTP policy.

## Step 2: Create alert rules from PromQL

### Rule: High Error Rate

- Severity label: critical
- Condition: Above 2 for 5m
- Routing labels: team=payments, signal=errors

PromQL

```promql
100 * sum(rate(http_requests_total{job="$service",status_code=~"5.."}[5m])) / sum(rate(http_requests_total{job="$service"}[5m]))
```

Build steps

1. Create a new Grafana managed alert rule.
2. Use the Prometheus query as query A.
3. Add a reduce expression if the query returns time series.
4. Add a threshold expression and set the pending period.
5. Add labels for team, environment, severity, and signal.
6. Add annotations for summary, description, dashboard URL, and runbook URL.

Verification

- [ ] Preview data shows the rule can enter pending and firing states.
- [ ] Labels appear exactly as expected in the preview.
- [ ] Runbook and dashboard annotations are clickable.
### Rule: High Latency p95

- Severity label: warning
- Condition: Above 300 for 10m
- Routing labels: team=payments, signal=latency

PromQL

```promql
1000 * histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{job="$service"}[5m])) by (le))
```

Build steps

1. Create a new Grafana managed alert rule.
2. Use the Prometheus query as query A.
3. Add a reduce expression if the query returns time series.
4. Add a threshold expression and set the pending period.
5. Add labels for team, environment, severity, and signal.
6. Add annotations for summary, description, dashboard URL, and runbook URL.

Verification

- [ ] Preview data shows the rule can enter pending and firing states.
- [ ] Labels appear exactly as expected in the preview.
- [ ] Runbook and dashboard annotations are clickable.
### Rule: CPU Saturation

- Severity label: warning
- Condition: Above 85 for 15m
- Routing labels: team=payments, signal=saturation

PromQL

```promql
100 * sum(rate(container_cpu_usage_seconds_total{pod=~"$service-.*"}[5m])) / sum(kube_pod_container_resource_requests{resource="cpu",pod=~"$service-.*"})
```

Build steps

1. Create a new Grafana managed alert rule.
2. Use the Prometheus query as query A.
3. Add a reduce expression if the query returns time series.
4. Add a threshold expression and set the pending period.
5. Add labels for team, environment, severity, and signal.
6. Add annotations for summary, description, dashboard URL, and runbook URL.

Verification

- [ ] Preview data shows the rule can enter pending and firing states.
- [ ] Labels appear exactly as expected in the preview.
- [ ] Runbook and dashboard annotations are clickable.

## Step 3: Build notification policies

Route alerts by labels, not by alert names, so policies survive naming changes.


### Recommended routing tree

| Matcher | Receiver | Group by | Reason |
| --- | --- | --- | --- |
| severity=critical | PagerDuty-Critical | team,service,alertname | Immediate paging |
| severity=warning | Slack-SRE | team,service | Triage without waking responders |
| environment=dev | Email-OnCall | service | Low-risk environments |

### Provisioning example

```yaml
apiVersion: 1
policies:
  - orgId: 1
    receiver: Slack-SRE
    group_by: ['team', 'service']
    routes:
      - receiver: PagerDuty-Critical
        group_by: ['team', 'service', 'alertname']
        object_matchers:
          - ['severity', '=', 'critical']
      - receiver: Email-OnCall
        object_matchers:
          - ['environment', '=', 'dev']
```

### Verification

- [ ] Critical alerts hit PagerDuty and do not stop at the root Slack route unless intended.
- [ ] Warnings land in Slack.
- [ ] Development alerts follow the low-priority branch.

## Step 4: Silences and mute timings

- Use silences for one-off maintenance or incident noise suppression.
- Use mute timings for recurring schedules such as non-production quiet hours.
- Always include a clear comment and creator identity.

### Silence API example

```bash
curl -s -u admin:admin   -H 'Content-Type: application/json'   -X POST http://localhost:3000/api/alertmanager/grafana/api/v2/silences   -d '{
    "matchers":[{"name":"service","value":"checkout","isRegex":false}],
    "startsAt":"2025-01-01T02:00:00Z",
    "endsAt":"2025-01-01T03:00:00Z",
    "createdBy":"sre-lab",
    "comment":"Checkout maintenance"
  }' | jq
```

### Mute timing provisioning example

```yaml
apiVersion: 1
muteTimes:
  - orgId: 1
    name: nonprod-nightly
    time_intervals:
      - times:
          - start_time: '00:00'
            end_time: '06:00'
        weekdays: ['monday:friday']
```

### Verification

- [ ] The silence matches only the intended labels.
- [ ] Suppressed alerts still appear in Grafana with silence context.
- [ ] Mute timings work only during the configured recurring window.

## Step 5: Add recording rules for complex queries

- Recording rules move repeated expensive calculations into Prometheus so both dashboards and alert rules stay readable.
- This is especially valuable for multi-window burn rates, long histogram quantile chains, or service-level aggregations.

### Example recording rules

```yaml
groups:
  - name: service-recordings
    interval: 30s
    rules:
      - record: job:http_errors:rate5m
        expr: sum(rate(http_requests_total{status_code=~"5.."}[5m])) by (job)
      - record: job:http_requests:rate5m
        expr: sum(rate(http_requests_total[5m])) by (job)
      - record: job:http_error_rate:ratio5m
        expr: job:http_errors:rate5m / job:http_requests:rate5m
```

### Alert rule using the recording rule

```promql
100 * job:http_error_rate:ratio5m{job="$service"}
```

## Step 6: Test alert routing end to end

1. Temporarily lower a threshold on a non-production service so the alert will fire quickly.
2. Use the rule preview to confirm pending and firing transitions.
3. Watch Alerting -> Alert rules, then Alerting -> Notification policies for the event path.
4. Confirm the notification arrives at the expected receiver.
5. Create a silence and confirm the alert still evaluates but notifications stop.
6. Remove the silence and restore the real threshold.

### Test matrix

| Case | Expected rule state | Expected receiver |
| --- | --- | --- |
| High error rate in prod | Firing | PagerDuty-Critical |
| High latency warning | Firing | Slack-SRE |
| Dev alert | Firing | Email-OnCall |
| Silenced prod alert | Suppressed | No external notification |

### Final verification checklist

- [ ] Contact points, policies, and rules are all visible in Grafana.
- [ ] At least one end-to-end test reached the correct receiver.
- [ ] A silence suppressed only the intended alert scope.
- [ ] Recording rules simplified at least one alert expression.

## Step 7: Capture evidence for handoff

Store proof of routing so the next operator does not need to reconstruct what happened.

### Evidence to capture

| Evidence | Why it matters | Example |
| --- | --- | --- |
| Rule preview screenshot | Shows threshold and labels at test time | `High Error Rate` firing with `severity=critical` |
| Contact point test result | Proves the receiver itself works | PagerDuty test event ID or Slack timestamp |
| Policy tree screenshot | Documents routing logic | Critical branch to PagerDuty |
| Silence or mute timing output | Explains suppressed notifications | Maintenance silence ID |

### Evidence commands

```bash
curl -s -u admin:admin http://localhost:3000/api/ruler/grafana/api/v1/rules | jq
curl -s -u admin:admin http://localhost:3000/api/alertmanager/grafana/api/v2/silences | jq
curl -s -u admin:admin http://localhost:3000/api/alertmanager/grafana/config/api/v1/receivers | jq
```

### Verification

- [ ] A teammate can read the saved evidence and understand why a notification did or did not fire.
- [ ] Alert labels, receiver names, and silence IDs are recorded in the change ticket or incident notes.

## Appendix: Fast reference

### Reference 1: Verification commands

- Use API calls to validate Grafana state.
- Use `kubectl logs` for sidecar and backend inspection.
- Use `jq` to validate dashboard JSON.

```bash
curl -s -u admin:admin http://localhost:3000/api/health | jq
kubectl logs -n monitoring deploy/grafana --since=5m
jq . dashboards/service-reliability.json > /dev/null
```
