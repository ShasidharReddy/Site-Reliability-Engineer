# Grafana Advanced Scenarios

## Scenario use

- These scenarios are timed drills for SREs who need to combine dashboards, alerting, provisioning, and access control quickly.
- Treat each one as a tabletop or hands-on exercise and record evidence as you go.

## Scenario matrix

| Scenario | Primary skill | Expected artifact |
| --- | --- | --- |
| 30-minute dashboard | Dashboard design and PromQL | Golden signals dashboard JSON |
| Routing trace | Alerting investigation | Working notification path or documented suppression |
| Grafana 9 -> 11 migration | Upgrade planning | Validated migrated dashboard set |
| Dedicated alert dashboard | OnCall and tenancy design | Team-scoped alert operations dashboard |

## 1. Build a complete service reliability dashboard in 30 minutes

### Goal

Deliver a production-usable golden signals dashboard quickly for a service that already exposes metrics.

### Timeline

| Window | Focus |
| --- | --- |
| 0-5 min | Choose service, datasource, naming, and variables |
| 5-20 min | Add golden signal panels and thresholds |
| 20-25 min | Add annotations and links |
| 25-30 min | Export JSON and handoff |

### Action plan

1. Create folder and dashboard shell.
2. Build environment, service, and pod variables.
3. Add traffic, error, latency, and saturation rows.
4. Add deployment and incident annotations.
5. Export JSON and commit it for provisioning.

### Useful command

```bash
curl -s -u admin:admin http://localhost:3000/api/search?type=dash-db | jq
```

### Useful YAML snippet

```yaml
providers:
  - name: sre-dashboards
    folder: SRE Services
```

### Useful JSON snippet

```json
{
  "title": "Checkout Service Reliability",
  "uid": "checkout-reliability"
}
```

### Verification checklist

- [ ] The dashboard answers the four golden signal questions on one screen.
- [ ] Variables work for at least one service and one pod.
- [ ] The JSON is exported and ready for GitOps.

### Debrief questions

- What assumption did the team make that could have been validated sooner?
- Which part of the workflow should move into code or automation?
- What evidence would you want available in a real incident ticket?

## 2. Alert routing broken — trace from firing to silence

### Goal

Find why a firing alert is not reaching the responder and determine whether routing or suppression is responsible.

### Timeline

| Window | Focus |
| --- | --- |
| 0-10 min | Confirm rule is firing and inspect labels |
| 10-20 min | Walk the policy tree and contact point tests |
| 20-25 min | Inspect silences and mute timings |
| 25-30 min | Fix and retest |

### Action plan

1. Open the alert rule and capture labels.
2. Check notification policy matcher branches.
3. Test the selected contact point.
4. Review active silences and recurring mute timings.
5. Resolve the issue and rerun an end-to-end test.

### Useful command

```bash
curl -s -u admin:admin http://localhost:3000/api/alertmanager/grafana/api/v2/silences | jq
```

### Useful YAML snippet

```yaml
object_matchers:
  - ["team", "=", "payments"]
receiver: PagerDuty-Critical
```

### Useful JSON snippet

```json
{
  "matchers": [{"name": "service", "value": "checkout", "isRegex": false}]
}
```

### Verification checklist

- [ ] A test alert reaches the intended receiver.
- [ ] Suppression behavior is understood and documented.
- [ ] Routing labels are normalized for future alerts.

### Debrief questions

- What assumption did the team make that could have been validated sooner?
- Which part of the workflow should move into code or automation?
- What evidence would you want available in a real incident ticket?

## 3. Dashboard migration from Grafana 9 to 11

### Goal

Safely move dashboards, plugins, and alerting resources across a major Grafana upgrade.

### Timeline

| Window | Focus |
| --- | --- |
| 0-10 min | Inventory dashboards, plugins, and datasources |
| 10-20 min | Test imports in staging and fix deprecated fields |
| 20-30 min | Validate alerting, variables, and data links |
| 30-40 min | Promote and verify production |

### Action plan

1. Export dashboard JSON and list plugin dependencies.
2. Check release notes for visualization or alerting changes.
3. Import into staging with stable datasource UIDs.
4. Validate panel rendering, links, and variable behavior.
5. Roll out with database backup and rollback plan.

### Useful command

```bash
curl -s -u admin:admin http://localhost:3000/api/plugins | jq '.[].id'
```

### Useful YAML snippet

```yaml
database:
  type: postgres
  max_open_conn: 50
```

### Useful JSON snippet

```json
{
  "schemaVersion": 39,
  "fiscalYearStartMonth": 0
}
```

### Verification checklist

- [ ] No critical panels fail after import.
- [ ] Alert rules evaluate in the new version.
- [ ] Plugin compatibility is confirmed before production cutover.

### Debrief questions

- What assumption did the team make that could have been validated sooner?
- Which part of the workflow should move into code or automation?
- What evidence would you want available in a real incident ticket?

## 4. Oncall team needs dedicated alert dashboard per service

### Goal

Create a per-service alert operations view that the owning OnCall team can use during incidents.

### Timeline

| Window | Focus |
| --- | --- |
| 0-10 min | Gather service ownership labels and teams |
| 10-20 min | Build or templatize the alert dashboard |
| 20-30 min | Assign folder permissions and OnCall links |
| 30-35 min | Verify routing and handoff |

### Action plan

1. Use service labels to filter alert lists and active silences.
2. Create one dashboard template reused per service with variables.
3. Add links to contact points, runbooks, and OnCall schedules.
4. Grant folder permissions to the owning team.
5. Provision dashboards and document ownership.

### Useful command

```bash
curl -s -u admin:admin http://localhost:3000/api/teams/search | jq
```

### Useful YAML snippet

```yaml
permissions:
  - team: payments
    permission: Edit
```

### Useful JSON snippet

```json
{
  "title": "Payments Alert Operations",
  "tags": ["alerts", "oncall"]
}
```

### Verification checklist

- [ ] The service team can view and edit its own alert dashboard.
- [ ] OnCall links and runbooks are visible from the dashboard.
- [ ] Alert routing labels match the service ownership model.

### Debrief questions

- What assumption did the team make that could have been validated sooner?
- Which part of the workflow should move into code or automation?
- What evidence would you want available in a real incident ticket?

## Scoring rubric

Use a simple scoring model when you run these scenarios as drills.

| Score | Meaning | Guidance |
| --- | --- | --- |
| 1 | Incomplete | The team changed configuration but did not verify the result |
| 2 | Functional | The team reached the goal with manual workarounds |
| 3 | Repeatable | The team captured commands, artifacts, and rollback steps |
| 4 | Production-ready | The team also updated GitOps or provisioning so the solution persists |

### Drill review checklist

- [ ] The team stated assumptions before changing Grafana state.
- [ ] Verification evidence was captured, not just verbally confirmed.
- [ ] Ownership, routing labels, and folder permissions were explicit.
- [ ] Follow-up automation opportunities were written down.

## Cross-scenario checklist

- [ ] All created dashboards and alert routes are committed to Git or exported for follow-up.
- [ ] Stable datasource UIDs are used everywhere.
- [ ] Folder permissions and ownership are clear.
- [ ] Every scenario ends with a verification step, not just a configuration change.

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

### Reference 2: Review checklist

- Titles are stable and descriptive.
- Thresholds and units are explicit.
- UIDs are stable across environments.

```yaml
review:
  dashboard_title: stable
  datasource_uid: prometheus-main
  alert_labels: normalized
```

### Reference 3: Hand-off notes

- Store exported JSON in Git.
- Capture screenshots for incident or change records.
- Record the final verification output.

```json
{
  "owner": "sre",
  "artifact": "dashboard-json",
  "verified": true
}
```
