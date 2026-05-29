# Lab 03: Grafana Unified Alerting

## Overview
Configure production-quality alert rules and routing using Grafana's unified alerting.

## Part 1: Create Contact Points

1. Grafana → Alerting → Contact Points → Add contact point
2. Create "PagerDuty-Critical":
   - Type: PagerDuty
   - Integration Key: (from PagerDuty service)
3. Create "Slack-SRE":
   - Type: Slack
   - Webhook URL: https://hooks.slack.com/...
   - Channel: #sre-alerts
4. Test each contact point

## Part 2: Create Notification Policy

1. Alerting → Notification Policies
2. Root policy: Grafana → Slack-SRE (all alerts default)
3. Add nested policy:
   - Matching labels: severity=critical
   - Contact point: PagerDuty-Critical
   - Group by: alertname, job

## Part 3: Create Alert Rule

1. Alerting → Alert Rules → New Alert Rule
2. Rule name: "High Error Rate - Production"
3. Set rule type: Grafana managed alert
4. Queries:
   - A: Prometheus query:
     ```
     sum(rate(http_requests_total{status_code=~"5.."}[5m])) by (job)
     / sum(rate(http_requests_total[5m])) by (job) * 100
     ```
   - B: Reduce → Last → A
   - C: Threshold → B is above 5
5. Set evaluation:
   - Folder: SRE Alerts
   - Evaluation group: critical-alerts (every 1m)
   - Pending period: 5m
6. Annotations:
   - Summary: High error rate on {{ $labels.job }}: {{ $values.B }}%
   - Runbook URL: https://wiki/runbooks/high-error-rate
7. Labels: severity=critical, team=sre

## Part 4: Add Silence
```bash
# Silence during maintenance window via API
curl -X POST http://admin:admin@localhost:3000/api/alertmanager/grafana/api/v2/silences \
  -H 'Content-Type: application/json' \
  -d '{
    "matchers": [{"name": "job", "value": "my-service", "isRegex": false}],
    "startsAt": "2024-01-01T02:00:00Z",
    "endsAt": "2024-01-01T04:00:00Z",
    "comment": "Maintenance window",
    "createdBy": "oncall-engineer"
  }'
```

## Verification
- [ ] Contact points created and tested
- [ ] Alert rule fires in pending state within 1m
- [ ] Transitions to Firing after 5m
- [ ] Notification received in Slack
- [ ] Silence suppresses notification
