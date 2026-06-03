# Lab 03 — Postmortem Practice

## Prerequisites

- Completion of [Lab 01 — Incident Simulation](01-incident-simulation.md) and [Lab 02 — Runbook Creation](02-runbook-creation.md), or equivalent operational experience.
- Familiarity with the structure in [templates/postmortem-template.md](../templates/postmortem-template.md).
- Ability to collect facts from alerts, logs, ticket notes, and chat transcripts without rewriting history after the fact.
- A calendar or task tracker where you can assign owners and due dates for corrective actions.

## Overview

This lab practices the written follow-up that turns incidents into durable learning. You will build full postmortem drafts from two detailed scenarios, analyze causes with both 5-whys and fishbone methods, create action items, and review someone else’s document with a quality rubric.

| Level | Learning objectives |
|---|---|
| Basic | Distinguish summary, impact, timeline, root cause, and action items. |
| Intermediate | Write blameless narratives that separate contributing factors from the triggering failure. |
| Advanced | Facilitate review, score postmortem quality, and create action items that are specific enough to complete. |

## Setup

```bash
export PM_DIR="$HOME/postmortem-lab"
mkdir -p "$PM_DIR"
cd "$PM_DIR"
```

### Copy a Working Template

```bash
cp /Users/shasidharreddy_mallu/Site-Reliability-Engineer/04-incident-management/templates/postmortem-template.md   "$PM_DIR/postmortem-template.md"
sed -n '1,120p' "$PM_DIR/postmortem-template.md"
```

## Postmortem Writing Checklist

| Question | Good answer looks like |
|---|---|
| What happened? | A short factual summary with time, impact, and resolution. |
| Why did it happen? | A specific technical root cause plus systemic contributors. |
| How did we detect it? | Alert, report, or ticket source and any detection gap. |
| How did we recover? | Concrete mitigation steps with times and owners. |
| What will change? | Small set of actionable, owned, time-bound follow-ups. |

## Scenario A — Cascading Failure from a Bad Deployment

### Scenario Description

A new `checkout-api` release introduced aggressive retry behavior when `payment-service` returned `429` responses. The extra retries saturated the dependency, increased database write contention, and caused a broader cascade.

### System Details

| Component | Detail |
|---|---|
| Frontend | Web checkout served from `frontend-web` in `us-central1` |
| API | `checkout-api` version `2025.04.12-rc3` |
| Dependency | `payment-service` with PostgreSQL backend |
| Alerting | Prometheus, Alertmanager, PagerDuty, StatusPage |
| Release method | Rolling deployment through Argo CD |

### Timeline Input

```text
14:02 UTC  Argo CD begins rollout of checkout-api 2025.04.12-rc3
14:05 UTC  PaymentService429Rate warning fires
14:06 UTC  Checkout latency p95 climbs from 220ms to 1.4s
14:07 UTC  CheckoutApiHighErrorRate fires at 8%
14:08 UTC  On-call acknowledges PagerDuty incident P123ABC
14:10 UTC  SEV2 declared; IC opens incident channel and bridge
14:13 UTC  payment-service CPU reaches 92%; DB lock waits increase
14:16 UTC  TL identifies retry storm after comparing old and new configs
14:20 UTC  Rollback of checkout-api initiated
14:24 UTC  payment-service 429s start falling; DB lock waits trending down
14:31 UTC  Checkout error rate below 1%
14:38 UTC  Incident resolved; monitoring continues
```

### Evidence Gathering Commands

```bash
kubectl rollout history deployment/checkout-api -n incident-lab
kubectl logs deployment/checkout-api -n incident-lab --since=45m | grep -i 'retry\|429' | tail -20
kubectl logs deployment/payment-service -n incident-lab --since=45m | grep -i '429\|lock' | tail -20
curl -sG http://127.0.0.1:9090/api/v1/query   --data-urlencode 'query=sum(rate(http_requests_total{job="checkout-api",status=~"5.."}[5m]))'
```

### Write the Summary and Impact

Draft a two- or three-sentence summary that names the rollout, the cascade path, and the customer impact. Then fill the impact table.

| Metric | Value to use in your draft |
|---|---|
| Duration | 31 minutes of customer impact |
| Peak error rate | 18% checkout failures |
| Latency | p95 peaked at 3.2s |
| Estimated affected users | ~4,800 sessions |
| Revenue impact | Estimated $27,000 delayed or abandoned orders |
| SLO impact | 7.6% of monthly checkout availability budget consumed |

### Practice 5-Whys

Write your own answers first, then compare with this example path.

1. Why did checkout fail? Because checkout-api retried payment requests aggressively, increasing downstream load.
2. Why did retry volume increase so sharply? Because the new release changed the retry policy from capped exponential backoff to immediate retries.
3. Why did that change reach production? Because config review focused on feature behavior, not resilience behavior under throttling.
4. Why was there no guardrail? Because no automated canary or load-shed simulation validated dependency-protection settings.
5. Why was the blast radius so high? Because the same dependency handled both checkout authorization and idempotency lookups, so saturation spread quickly.

### Practice Fishbone Analysis

Use the categories below to avoid stopping at a single narrow human error explanation.

```text
People      -> reviewer unfamiliar with retry defaults
Process     -> release checklist omitted dependency-throttling verification
Technology  -> retry configuration allowed zero backoff
Monitoring  -> warning fired before SEV2 threshold but no clear playbook tied them together
Dependencies-> payment-service and db shared a constrained path
Change Mgmt -> canary promotion skipped because release window was compressed
```

### Action Item Table

| Action item | Owner | Due date | Why it matters |
|---|---|---|---|
| Add automated canary test for throttled dependency responses | @commerce-platform | 2025-05-02 | Prevent unsafe retry policies from promoting globally |
| Update checkout deployment review checklist with resilience config diff review | @release-manager | 2025-04-25 | Make risky config changes visible in approvals |
| Add dashboard panel correlating 429s, retries, and DB lock waits | @sre-observability | 2025-04-30 | Reduce time to identify cascade path |
| Split idempotency lookup traffic from payment authorization path | @payments-arch | 2025-05-20 | Reduce shared dependency blast radius |

### Verification

```bash
rg -n 'Incident Summary|Impact|Timeline|Root Cause|Contributing Factors|Action Items|Lessons Learned' "$PM_DIR/postmortem-template.md"
```

### Expected Output Fragment

```text
13:## Incident Summary
21:## Impact
34:## Timeline
51:## Root Cause
88:## Action Items
102:## Lessons Learned
```

## Scenario B — Capacity Event from a Traffic Spike

### Scenario Description

A social media mention drove a 6x increase in traffic to the storefront over 40 minutes. Autoscaling increased frontend pods, but checkout database connections and payment-service worker concurrency did not scale proportionally, producing a capacity event rather than a hard code bug.

### System Details

| Component | Detail |
|---|---|
| Traffic source | Influencer promotion and referral links |
| Frontend autoscaling | Enabled on CPU and requests per second |
| Checkout worker pool | Fixed at 40 workers per pod |
| DB connection pool | Max 120 shared connections |
| Existing alerts | CPU, error rate, and latency; no alert for connection pool saturation |

### Timeline Input

```text
19:00 UTC  Traffic begins climbing after social promotion
19:07 UTC  frontend-web scales from 8 to 18 pods
19:11 UTC  checkout-api request rate reaches 5.8x baseline
19:13 UTC  checkout latency p95 crosses 1.5s
19:16 UTC  payment-service queue depth warning fires
19:18 UTC  customer support reports intermittent please-try-again messages
19:20 UTC  SEV2 declared; IC requests traffic, queue, and DB pool snapshots
19:24 UTC  TL identifies DB connection pool saturation at 120/120
19:27 UTC  temporary mitigation: reduce non-critical background jobs and raise worker pool on two extra replicas
19:34 UTC  checkout success rate improves but latency remains elevated
19:42 UTC  referral cache rule enabled at CDN and marketing banner disabled
19:50 UTC  traffic stabilizes; DB pool usage drops to 72/120
19:58 UTC  incident resolved
```

### Evidence Gathering Commands

```bash
kubectl top pod -n incident-lab -l app=checkout-api
kubectl logs deployment/payment-service -n incident-lab --since=1h | grep -i 'pool\|queue' | tail -20
curl -sG http://127.0.0.1:9090/api/v1/query   --data-urlencode 'query=sum(rate(http_requests_total{job="checkout-api"}[5m]))'
curl -sG http://127.0.0.1:9090/api/v1/query   --data-urlencode 'query=max(db_pool_in_use{service="payment-service"})'
```

### Build the Impact Statement

| Metric | Value to use in your draft |
|---|---|
| Duration | 45 minutes degraded service |
| Peak traffic | 6x baseline request rate |
| Peak latency | p95 4.6s |
| Failure mode | 11% of checkouts failed, 34% exceeded user timeout budget |
| Business impact | support volume +210%, abandoned carts up 17% in window |
| SLO impact | 9.1% monthly latency budget consumed |

### Practice 5-Whys

1. Why did checkout become slow and fail intermittently? Because the payment path saturated its database connection pool under a rapid traffic increase.
2. Why did the connection pool saturate? Because frontend and API autoscaling outpaced worker and DB concurrency tuning.
3. Why was the pool size not sufficient? Because the service was sized for ordinary promotional spikes, not a 6x viral event.
4. Why was that capacity gap not detected earlier? Because no alert existed for pool saturation or queue depth relative to demand growth.
5. Why did mitigation take time? Because traffic-reduction levers and non-critical job shedding were not pre-documented in a runbook.

### Practice Fishbone Analysis

```text
People      -> marketing launch not shared with on-call ahead of time
Process     -> no capacity review for cross-functional promotions
Technology  -> DB pool fixed and not horizontally aware
Monitoring  -> no alert on connection saturation or queue depth SLO
Dependencies-> payment-service and reporting jobs shared the same database pool
External     -> viral traffic arrived faster than autoscaling stabilization
```

### Action Item Table

| Action item | Owner | Due date | Why it matters |
|---|---|---|---|
| Add alert for DB pool usage >85% for 10 minutes | @dba-oncall | 2025-05-03 | Detect capacity squeeze before failures start |
| Create runbook for traffic surge mitigation including marketing and CDN levers | @sre-duty-manager | 2025-04-28 | Reduce coordination delay during future spikes |
| Isolate background jobs to a separate pool or schedule | @payments-platform | 2025-05-15 | Preserve customer-critical capacity under burst traffic |
| Add campaign notification step to launch checklist | @marketing-ops | 2025-04-24 | Improve anticipatory scaling and staffing |

### Verification

```bash
cat <<'EOF' > "$PM_DIR/action-items.md"
| Action item | Owner | Due date | Status |
|---|---|---|---|
| Add DB pool saturation alert | @dba-oncall | 2025-05-03 | Open |
| Create traffic surge mitigation runbook | @sre-duty-manager | 2025-04-28 | Open |
| Isolate background jobs from primary pool | @payments-platform | 2025-05-15 | Open |
| Add campaign notice to launch checklist | @marketing-ops | 2025-04-24 | Open |
EOF
sed -n '1,20p' "$PM_DIR/action-items.md"
```

## Construct the Full Blameless Postmortem

### Create Working Drafts for Both Scenarios

```bash
cp "$PM_DIR/postmortem-template.md" "$PM_DIR/scenario-a-bad-deploy.md"
cp "$PM_DIR/postmortem-template.md" "$PM_DIR/scenario-b-capacity-event.md"
ls -1 "$PM_DIR"
```

Expected output should show both scenario files alongside the template:

```text
action-items.md
postmortem-template.md
scenario-a-bad-deploy.md
scenario-b-capacity-event.md
```

### Fill the Core Sections in Order

Write the document in the following order so you do not get stuck polishing early paragraphs before the facts are complete.

| Order | Section | Why this order helps |
|---|---|---|
| 1 | Timeline | It anchors every later claim to evidence. |
| 2 | Impact | It keeps the document customer-focused. |
| 3 | Root cause | It is easier once the chronology is stable. |
| 4 | Contributing factors | These become clearer after root cause is named. |
| 5 | What went well / improve | These are easier once you can see the whole response. |
| 6 | Action items | They should respond to the documented gaps, not generic wishes. |

### Draft Scenario A Timeline Table

Use the raw timeline notes and convert them into a clean table with actor, source, and decision.

```bash
cat <<'EOF' > "$PM_DIR/scenario-a-timeline.md"
| Time (UTC) | Actor | Event | Evidence source |
|---|---|---|---|
| 14:02 | Argo CD | Began rollout of checkout-api 2025.04.12-rc3 | deployment history |
| 14:05 | Monitoring | PaymentService429Rate warning fired | Prometheus |
| 14:10 | IC | Declared SEV2 and opened bridge | incident channel |
| 14:16 | TL | Identified retry storm after config comparison | logs + config diff |
| 14:20 | TL | Rolled back checkout-api | kubectl rollout history |
| 14:38 | IC | Declared incident resolved after sustained recovery | Alertmanager + dashboard |
EOF
sed -n '1,20p' "$PM_DIR/scenario-a-timeline.md"
```

### Draft Scenario B Timeline Table

```bash
cat <<'EOF' > "$PM_DIR/scenario-b-timeline.md"
| Time (UTC) | Actor | Event | Evidence source |
|---|---|---|---|
| 19:00 | Marketing / users | Traffic surge begins | edge request graph |
| 19:13 | Monitoring | Checkout latency p95 crosses threshold | Prometheus |
| 19:20 | IC | Declares SEV2 and requests capacity snapshots | incident channel |
| 19:24 | TL | Confirms DB pool saturation at 120/120 | application metric |
| 19:27 | TL | Pauses non-critical jobs and scales workers | change log |
| 19:58 | IC | Resolves incident after traffic and pool usage normalize | dashboard + support check |
EOF
sed -n '1,20p' "$PM_DIR/scenario-b-timeline.md"
```

### Example Summary Fragments

Use these only as style references; write your own final wording.

```text
Scenario A summary: A checkout-api rollout changed retry behavior and amplified load on payment-service, which in turn increased database lock waits. The resulting cascade caused elevated checkout errors for 31 minutes until the deployment was rolled back. Recovery was successful, but the incident exposed missing canary coverage for resilience configuration.

Scenario B summary: A viral traffic spike exceeded the effective concurrency envelope of payment-service and its shared database pool. Customer-visible latency and intermittent failures persisted for 45 minutes until background load was reduced, extra worker capacity was added, and traffic pressure eased. The event showed that autoscaling frontends without scaling shared bottlenecks is not enough.
```

### Verification for Draft Quality

```bash
rg -n 'Incident Summary|Impact|Timeline|Root Cause|Contributing Factors|What Went Well|What Could Be Improved|Action Items|Lessons Learned' "$PM_DIR"/scenario-*.md
```

A strong draft should contain every major heading from the template and should not leave placeholder tokens like `INC-XXXX`, `YYYY-MM-DD`, or `@name` in the final file.

## Facilitation and Review Practice

### Review Meeting Agenda

Use a short, structured agenda so the meeting does not drift into blame or unrelated architecture debates.

| Minute | Topic | Facilitator prompt |
|---|---|---|
| 0-5 | Incident summary | “Can someone unfamiliar with the service understand the impact from this summary?” |
| 5-15 | Timeline review | “What evidence supports each key timestamp?” |
| 15-25 | Root cause and contributing factors | “What made this failure path possible?” |
| 25-35 | Action items | “Which actions most reduce repeat risk?” |
| 35-40 | Ownership and due dates | “Who will carry each item to closure?” |

### Blameless Rewrite Exercise

Rewrite loaded language into factual language before the review meeting starts.

| Loaded wording | Better blameless wording |
|---|---|
| Alice deployed a bad config and broke checkout. | A config change altered retry behavior and was promoted without a dependency-throttling safety check. |
| The DBA team did not help quickly enough. | Cross-team escalation took 18 minutes because database and application evidence were reviewed separately. |
| Monitoring failed. | Existing alerts detected symptoms, but the signal was not specific enough to highlight the shared dependency bottleneck early. |
| The on-call engineer missed the issue. | The first alert did not clearly convey customer impact, which delayed severity declaration and escalation. |
| People should be more careful with launches. | Add an explicit launch checklist item and a canary validation step for resilience configuration changes. |

### Action Item Tracking Workflow

```bash
cat <<'EOF' > "$PM_DIR/postmortem-review-board.md"
| Action item | Scenario | Owner | Due date | Status | Last update |
|---|---|---|---|---|---|
| Add throttling canary test | Scenario A | @commerce-platform | 2025-05-02 | Open | awaiting test design |
| Publish traffic surge mitigation runbook | Scenario B | @sre-duty-manager | 2025-04-28 | Open | drafting commands |
| Add DB pool saturation alert | Scenario B | @dba-oncall | 2025-05-03 | Open | metric review scheduled |
| Update deployment review checklist | Scenario A | @release-manager | 2025-04-25 | Open | checklist diff in review |
EOF
sed -n '1,20p' "$PM_DIR/postmortem-review-board.md"
```

### Review Scoring Checklist

Before the document is final, confirm the following:

- The summary states impact, duration, and resolution without requiring the reader to infer them.
- Every major timeline event cites a source: alert, log, deploy record, ticket, or message timestamp.
- Root cause names the specific failure condition, not the person closest to it.
- Contributing factors explain why the incident was harder to detect or mitigate.
- Action items have owners, due dates, and an observable completion condition.
- Lessons learned are transferable to the broader team, not only the original responders.

### Bonus Facilitation Challenge

Run a 15-minute mock review where one participant intentionally introduces hindsight bias. The facilitator must redirect using questions like:

- What evidence was available at the time?
- What alternative choices seemed reasonable before the mitigation worked?
- Which condition in the system or process made this error path possible?
- Which action item would actually change future outcomes?

## Review Another Postmortem and Score It

Use the rubric below to review your own draft or a peer document. Score each category from 1 to 5.

| Category | 1 | 3 | 5 |
|---|---|---|
| Clarity | Hard to follow, vague summary | Mostly clear but some ambiguity | Crisp summary and unambiguous terminology |
| Timeline quality | Missing times or sources | Major events present | Minute-by-minute with evidence sources |
| Blameless tone | Focuses on who failed | Mixed tone | Consistently system-focused and respectful |
| Root cause depth | Stops at immediate trigger | Some systemic detail | Clear trigger and systemic contributors |
| Action item quality | Unowned or vague actions | Some actions are concrete | Small set of owned, dated, measurable actions |
| Learning value | Hard to reuse | Some useful notes | Strong lessons others can apply |

### Reviewer Prompts

- Can a reader unfamiliar with the service understand the incident in two minutes?
- Does the timeline explain why responders made the decisions they made at the time?
- Are action items actually likely to reduce risk, or are they generic be-more-careful statements?
- Does the document separate customer impact from internal inconvenience?

## Bonus Challenges

- Rewrite Scenario A as a seven-sentence executive summary and compare what technical detail you lose.
- Combine the fishbone categories from both scenarios and identify one repeated systemic weakness.
- Turn one action item into a ticket with acceptance criteria and dependency notes.

## Teardown

```bash
rm -rf "$PM_DIR"
unset PM_DIR
```

## Key Takeaways

- A postmortem is only useful if it is factual, specific, and easy for someone outside the incident to understand.
- 5-whys helps reveal causal chains; fishbone helps prevent tunnel vision by surfacing multiple contributing dimensions.
- Strong action items have owners and due dates because learning without follow-through does not change reliability.
- Blameless does not mean consequence-free; it means the document optimizes for learning over personal judgment.
- Review quality matters as much as writing quality because weak postmortems tend to fail silently after the meeting ends.
