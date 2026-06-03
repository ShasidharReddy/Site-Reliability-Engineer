# Lab 03 — Toil Reduction, Automation, and Measurement

## Lab goal

This lab teaches you how to identify toil, quantify it, remove it with engineering improvements, and prove that the change reduced operational load.
You will complete a toil audit and implement two practical fixes:

- replacing repeated manual pod restarts with a liveness-probe-based self-healing design,
- replacing manual scaling with a Horizontal Pod Autoscaler.

You will also build a simple toil tracking dashboard so the gains remain visible.

---

## Learning objectives

After this lab you should be able to:

1. identify work that qualifies as toil,
2. run a repeatable toil audit,
3. estimate toil cost in minutes and incidents,
4. implement an automation or design change that removes repeated manual work,
5. compare before and after toil levels with evidence,
6. create a dashboard that keeps toil visible to the team.

---

## Scenario

The `orders-api` team has a painful on-call pattern.
Three issues keep recurring:

- a pod occasionally hangs and someone manually restarts it,
- traffic spikes require manual scaling before promotions,
- engineers spend time explaining the same issues in weekly review because no toil trend dashboard exists.

Your goal is to reduce these manual tasks and document the operational improvement.

---

## What qualifies as toil in this lab

For a task to count as toil, it should be mostly:

- manual,
- repetitive,
- automatable,
- reactive,
- and linearly scaling with service growth.

### Examples from the scenario

| Task | Why it is toil |
|---|---|
| restarting a hung pod | manual, repeated, automatable |
| scaling replicas before a sale | manual, predictable, automatable |
| triaging the same scaling alert every promotion | repeated and likely reducible |

### Non-toil examples

| Task | Why it is not toil |
|---|---|
| designing a better health endpoint | durable engineering value |
| implementing HPA | durable engineering value |
| writing a postmortem and changing architecture | improves the system long term |

---

## Step 1 — Run a toil audit

A toil audit is how you move from complaint to evidence.
Do not start by guessing what to automate.
Start by measuring.

### 1.1 Audit period

Use one full week if possible.
If you need a shorter lab simulation, use at least a few days of realistic records.

### 1.2 Fields to capture

For each task, record:

- date and time,
- task description,
- trigger,
- service,
- who performed it,
- duration,
- business urgency,
- how often it happens,
- whether it is automatable,
- likely root cause,
- proposed fix.

### 1.3 Toil audit template

```yaml
audit_period: 2026-01-12 to 2026-01-18
team: orders-api
entries:
  - timestamp: 2026-01-12T02:14:00Z
    task: "Restart hung pod"
    service: orders-api
    trigger: "High latency alert and stuck health endpoint"
    duration_minutes: 12
    repeated: true
    automatable: true
    root_cause: "No liveness probe and blocking thread issue"
    proposed_fix: "Add liveness probe and investigate blocking dependency call"

  - timestamp: 2026-01-13T17:40:00Z
    task: "Scale deployment from 4 to 10 replicas before promotion"
    service: orders-api
    trigger: "Expected campaign traffic"
    duration_minutes: 15
    repeated: true
    automatable: true
    root_cause: "No HPA and no demand-based scaling"
    proposed_fix: "Add HPA based on CPU and request rate"

  - timestamp: 2026-01-14T03:08:00Z
    task: "Acknowledge repeat warning after traffic spike"
    service: orders-api
    trigger: "Threshold alert on CPU > 80%"
    duration_minutes: 5
    repeated: true
    automatable: partially
    root_cause: "Alert on symptom too low in stack and no HPA"
    proposed_fix: "Tune alerting after HPA rollout"
```

### 1.4 Simple spreadsheet or table version

| Date | Task | Frequency | Minutes | Repeated? | Automatable? | Root cause | Fix idea |
|---|---|---:|---:|---|---|---|---|
| Mon | Restart hung pod | 3/day | 12 | Yes | Yes | no liveness probe | add probe and debug app hang |
| Tue | Manual scale for traffic | 2/week | 15 | Yes | Yes | no HPA | add autoscaling |
| Wed | Ack repeated CPU alert | 4/week | 5 | Yes | Partial | noisy threshold | retune after scaling fix |

### 1.5 Toil scoring model

Use a lightweight score to rank candidates.

```text
toil_priority = frequency_score + duration_score + user_impact_score + automatable_score
```

Example scoring scale:

- `1` = low,
- `2` = medium,
- `3` = high.

### 1.6 Prioritize the top two items

In this lab, the top two items are:

1. manual pod restart,
2. manual pre-traffic scaling.

---

## Step 2 — Establish the baseline

Before changing anything, capture a before-state.
Without this, you cannot prove improvement.

### 2.1 Baseline metrics to capture

- number of manual restarts per week,
- minutes spent per restart,
- number of manual scaling actions per week,
- minutes spent per scale event,
- pages related to these issues,
- MTTR contribution,
- number of incidents where these tasks appeared in the timeline.

### 2.2 Example baseline table

| Metric | Before value |
|---|---:|
| Manual pod restarts per week | 14 |
| Minutes per restart | 10 |
| Manual scaling actions per week | 3 |
| Minutes per scaling action | 15 |
| Related pages per week | 9 |
| Total toil minutes per week | 185 |

### 2.3 Optional Prometheus counters to track manual actions

If you have an internal operations tool, consider tracking manual interventions explicitly.
Example metric names:

- `manual_pod_restart_total`
- `manual_scale_action_total`
- `toil_minutes_logged_total`

These metrics are not a substitute for engineering judgment, but they make the cost visible.

---

## Step 3 — Automate pod restart toil with a liveness probe

### 3.1 Understand the failure pattern

Do not add a liveness probe blindly.
Confirm the problem:

- Is the pod truly hung?
- Is the app deadlocked or blocked on a dependency?
- Would a restart actually help?
- Could a restart make data corruption worse?

In this lab, assume the pod sometimes stops serving traffic but recovers cleanly after restart.
That makes a liveness probe appropriate.

### 3.2 Add readiness and liveness intentionally

Use readiness for traffic admission.
Use liveness for self-healing when the process is unhealthy beyond acceptable limits.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders-api
spec:
  replicas: 4
  selector:
    matchLabels:
      app: orders-api
  template:
    metadata:
      labels:
        app: orders-api
    spec:
      containers:
        - name: orders-api
          image: ghcr.io/example/orders-api:1.0.0
          ports:
            - containerPort: 8080
          readinessProbe:
            httpGet:
              path: /health/ready
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
            timeoutSeconds: 2
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /health/live
              port: 8080
            initialDelaySeconds: 20
            periodSeconds: 15
            timeoutSeconds: 2
            failureThreshold: 3
```

### 3.3 Why this removes toil

Before:

- alert fires,
- on-call checks the pod,
- on-call manually restarts it,
- service recovers.

After:

- kubelet detects failed liveness,
- container is restarted automatically,
- manual intervention is needed only if recovery fails repeatedly.

### 3.4 Validation steps for the liveness probe

1. Deploy the updated manifest in staging.
2. Simulate the hung state or use a debug endpoint.
3. Confirm readiness fails before traffic is routed.
4. Confirm liveness eventually restarts the container.
5. Confirm recovery occurs without manual action.
6. Confirm alerting is updated so a self-healed single restart does not page unnecessarily.

### 3.5 Important cautions

- Liveness probes must not be too aggressive.
- A failing dependency does not always mean the pod should restart.
- For stateful workloads, restart policies require extra care.
- Probe handlers must be fast and deterministic.

---

## Step 4 — Automate manual scaling with HPA

### 4.1 Understand the scaling toil

The team currently scales from 4 to 10 replicas before marketing events.
This is predictable manual work.
It qualifies as toil because it repeats and can be encoded into platform behavior.

### 4.2 Pick a scaling signal

For a first version, choose one or two stable signals.
Common choices:

- CPU utilization,
- memory utilization for memory-bound services,
- custom request rate,
- queue depth for async workers.

In this lab, start with CPU and optionally add request-rate metrics later.

### 4.3 Example HPA configuration

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: orders-api
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: orders-api
  minReplicas: 4
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 65
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
        - type: Percent
          value: 100
          periodSeconds: 60
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Percent
          value: 25
          periodSeconds: 60
```

### 4.4 Optional custom metric scaling

If CPU is too indirect, scale from request rate or queue depth.
Example concept:

```yaml
metrics:
  - type: Pods
    pods:
      metric:
        name: requests_per_second
      target:
        type: AverageValue
        averageValue: "50"
```

### 4.5 Why HPA removes toil

Before:

- engineer watches forecast,
- engineer scales manually,
- engineer forgets to scale down later,
- alerts fire if traffic exceeds expectations.

After:

- service scales according to demand,
- behavior is reviewable as code,
- scale-up and scale-down rules are consistent,
- operators focus on outliers, not routine adjustments.

### 4.6 HPA validation steps

1. Apply the HPA in staging.
2. Generate a traffic ramp with k6 or equivalent.
3. Observe replica count increase.
4. Verify latency improves or remains stable during scale-up.
5. Stop traffic and observe safe scale-down.
6. Ensure scale oscillation is not excessive.

### 4.7 Common HPA pitfalls

- scaling on CPU when the bottleneck is actually I/O,
- setting max replicas too low,
- setting scale-down too aggressively,
- ignoring startup time and cold-cache behavior,
- forgetting capacity limits in downstream dependencies.

---

## Step 5 — Measure before and after toil time

This is the proof step.
Repeat the same measurements from Step 2 after rollout.

### 5.1 Example after-state table

| Metric | Before | After | Improvement |
|---|---:|---:|---:|
| Manual pod restarts per week | 14 | 2 | -85.7% |
| Minutes per restart | 10 | 5 | -50.0% |
| Manual scaling actions per week | 3 | 0 | -100.0% |
| Minutes per scaling action | 15 | 0 | -100.0% |
| Related pages per week | 9 | 3 | -66.7% |
| Total toil minutes per week | 185 | 25 | -86.5% |

### 5.2 Formula for time saved

```text
time_saved = before_minutes - after_minutes
percent_reduction = (time_saved / before_minutes) * 100
```

### 5.3 Example interpretation

If weekly toil dropped from `185` minutes to `25` minutes:

- time saved = `160` minutes,
- reduction = `86.5%`.

That is not only a staffing win.
It also reduces fatigue, inconsistency, and risk of human error.

### 5.4 Capture qualitative improvement too

Quantitative evidence is important.
Also capture:

- fewer overnight wake-ups,
- less context switching during business hours,
- more time available for preventive engineering,
- better confidence in release windows.

---

## Step 6 — Build a toil tracking dashboard

Create a dashboard called `orders-api-toil`.
The goal is not perfect accounting.
The goal is to keep operational drag visible.

### Panel 1 — Manual restarts over time

If you emit a metric such as `manual_pod_restart_total`:

```promql
increase(manual_pod_restart_total{service="orders-api"}[7d])
```

### Panel 2 — Manual scaling actions over time

```promql
increase(manual_scale_action_total{service="orders-api"}[7d])
```

### Panel 3 — Logged toil minutes

```promql
increase(toil_minutes_logged_total{service="orders-api"}[7d])
```

### Panel 4 — Related alert volume

```promql
increase(alerts_fired_total{service="orders-api",category="toil"}[7d])
```

### Panel 5 — Self-healing events

If you export restart or auto-recovery metrics:

```promql
increase(kube_pod_container_status_restarts_total{namespace="production",pod=~"orders-api-.*"}[7d])
```

Interpret carefully.
More restarts are not automatically good or bad.
You want fewer manual interventions and a lower user impact rate.

### Panel 6 — Toil versus engineering time

If the team logs time categories, visualize them directly.
If not, create a simple manually updated stat in your team process.
The target is usually to keep toil under 50% of team time, and much lower for mature services.

---

## Step 7 — Operational follow-up

Automation is not the end of the story.
Review whether the toil item was truly removed or merely hidden.

### Questions to ask after rollout

- Did liveness restarts reduce user impact, or only mask a deeper app bug?
- Did HPA reduce pages, or did a downstream dependency become the new bottleneck?
- Are alerts now better aligned to user symptoms?
- Did the team actually reclaim time for engineering work?

### When to stop and redesign

If the app still hangs frequently after adding liveness probes, investigate root causes.
Repeated automatic restarts may indicate:

- deadlocks,
- memory leaks,
- bad dependency behavior,
- poor connection handling,
- incorrect probe logic.

Likewise, if HPA is scaling constantly without improving latency, review:

- bottleneck choice,
- CPU requests and limits,
- startup performance,
- database connection limits,
- cache behavior.

---

## Step 8 — Completion checklist

- [ ] Toil audit completed with useful fields.
- [ ] Top toil items ranked and justified.
- [ ] Before-state time cost measured.
- [ ] Liveness probe solution implemented and validated.
- [ ] HPA implemented and validated.
- [ ] After-state time cost measured.
- [ ] Dashboard created for toil visibility.
- [ ] Follow-up review performed to ensure toil was truly reduced.

---

## Stretch exercises

1. Replace a noisy manual certificate rotation process with cert-manager.
2. Turn a repetitive operational script into a Kubernetes Job or controller.
3. Add a runbook section called `Can this be automated?` to every recurring incident.
4. Track toil categories by source: deploy, incident, scaling, data repair, access management.
5. Estimate quarterly engineering time returned to the team after automation.
