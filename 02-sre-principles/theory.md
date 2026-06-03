# SRE Principles — Advanced Theory

## How to use this guide

This module moves from introductory SRE ideas to operational decision-making.
Each section is written for engineers who need both conceptual clarity and practical implementation detail.
Examples intentionally mix user-facing services, background jobs, and data systems.
PromQL and YAML snippets are written in a way that can be adapted to a Prometheus-based stack.
The goal is not to memorize formulas.
The goal is to build reliable instincts.

---

## 1. SRE foundations

### 1.1 What SRE is

Site Reliability Engineering is the practice of applying software engineering to operations and reliability work.
It originated at Google as a way to scale service operations without relying on ever-growing manual effort.
SRE assumes that reliability is an engineering problem, not only an operations staffing problem.
SRE also assumes that perfect reliability is usually economically irrational.
A service should be reliable enough for user expectations and business commitments.
Anything more may reduce feature velocity with little user benefit.

### 1.2 The core idea behind the Google SRE model

The Google SRE books emphasize a few recurring ideas.
Those ideas are portable even outside Google.

- Reliability must be measured.
- Reliability targets must be explicit.
- Operational work should be automated away whenever possible.
- Incidents should produce learning, not blame.
- Teams need a shared language for balancing reliability and release speed.
- Error budgets are the mechanism that creates this balance.
- SRE time is too expensive to spend primarily on repetitive manual work.
- Operational readiness must be designed into the service, not bolted on after launch.

### 1.3 Reliability as a product feature

Users do not experience your architecture diagrams.
Users experience whether the product works when they need it.
That means reliability is part of the product.
A checkout API that fails during peak traffic is a product failure.
A data pipeline that delivers yesterday's data during a finance close is a product failure.
A batch job that eventually succeeds after missing every business deadline is still a product failure.

### 1.4 The classic SRE principles from the Google books

#### Embrace risk

A system can always be made more reliable.
The question is whether the additional cost is worth the lost velocity or engineering effort.
SRE replaces abstract arguments with measured risk.
If the service has budget left, teams can take more change risk.
If the budget is depleted, the organization must invest in reliability.

#### Service level objectives are the contract for reliability

Without an SLO, every reliability debate turns subjective.
With an SLO, teams can answer questions such as:

- Are we healthy enough to ship?
- Did this incident materially harm users?
- Are we measuring the right thing?
- Is the current reliability target realistic?

#### Eliminate toil

A service that depends on endless manual intervention is not truly operating.
It is being hand-carried.
SRE treats recurring manual work as a defect in the system design.

#### Monitor symptoms first

Symptoms describe what users notice.
Examples include failed requests, elevated latency, or stale data.
Cause-based alerts can help with diagnosis, but symptom-based alerts determine urgency.
CPU saturation matters because it may drive user-visible latency.
CPU saturation alone is not the user experience.

#### Automate emergency response where possible

Humans should make higher-level decisions.
Computers should execute repetitive mechanical steps.
Rollback automation, traffic shifting, cluster rescheduling, and safe restart logic are all examples.

#### Learn through blameless postmortems

Blamelessness is not the absence of accountability.
It is the recognition that system failures usually emerge from interacting conditions.
Good postmortems improve system design, documentation, automation, and training.

### 1.5 SRE versus DevOps versus Platform Engineering

These terms overlap, but they are not identical.

| Dimension | SRE | DevOps | Platform Engineering |
|---|---|---|---|
| Primary concern | Reliability outcomes | Collaboration and delivery flow | Internal platforms and paved roads |
| Main control mechanism | SLOs and error budgets | Culture and automation practices | Productized internal developer platform |
| Success measure | Reliability at agreed targets | Faster safer delivery | Reduced cognitive load for teams |
| Common outputs | Alerting, incident response, reliability reviews | CI/CD, shared ownership, automation | Golden paths, self-service infra, APIs |
| Main anti-pattern | Becoming reactive ops | Staying too abstract and unmeasured | Building a platform no one wants |

### 1.6 How these disciplines fit together

DevOps is best understood as a cultural and process philosophy.
It aims to reduce silos between development and operations.
SRE is a concrete implementation model for achieving reliability within that broader philosophy.
Platform Engineering creates reusable internal products so teams can deploy and operate systems consistently.
In mature organizations:

- DevOps shapes collaboration and incentives.
- Platform Engineering reduces implementation friction.
- SRE provides measurable reliability governance.

### 1.7 When an organization needs dedicated SRE capability

You may need formal SRE involvement when:

- incidents are frequent and recurring,
- reliability expectations differ across stakeholders,
- teams argue about whether to ship or stabilize,
- manual operational work scales with traffic growth,
- on-call is unsustainable,
- platform complexity exceeds what feature teams can manage alone.

### 1.8 Common misconceptions about SRE

| Misconception | Why it is wrong | Better framing |
|---|---|---|
| SRE is just production support | Support responds to symptoms; SRE changes systems | SRE engineers reliability into the service |
| SRE means 100% uptime | Infinite reliability is not achievable or affordable | Reliability is optimized to user and business needs |
| SRE replaces developers | Reliability is shared | SRE partners with service owners |
| SRE is only for web services | Any measurable service can use SRE ideas | APIs, batch jobs, pipelines, data platforms all apply |
| SRE only works at Google scale | The math scales down | Even small teams benefit from explicit SLOs |

### 1.9 A practical shared-responsibility model

A healthy operating model often looks like this:

| Activity | Product team | Platform team | SRE |
|---|---|---|---|
| Service code quality | Owns | Enables | Advises |
| Deployment safety | Owns | Enables | Reviews critical paths |
| SLI instrumentation | Owns with support | Provides telemetry platform | Defines good measurement practice |
| SLO target setting | Co-owns | Advises | Facilitates and challenges |
| Incident response | Owns first response | Supports platform issues | Coaches, responds, escalates |
| Toil reduction | Owns service-specific automation | Owns shared automation tools | Prioritizes and drives systemic fixes |

---

## 2. Service level indicators deep dive

### 2.1 What an SLI actually measures

A service level indicator is a quantitative measure of service behavior over time.
A good SLI answers a user-centric question.
Examples include:

- Did the request succeed?
- Was the response fast enough?
- Did the batch job finish by the deadline?
- Is the dashboard showing data fresh enough to use?

An SLI is not just any metric.
Many metrics are useful for debugging.
Only some deserve to drive an SLO.

### 2.2 Event-based versus resource-based metrics

Resource metrics are things like CPU, memory, queue depth, or disk fullness.
They are useful for diagnosis and capacity planning.
They are poor top-level SLIs because users do not directly consume CPU.
Event metrics are request outcomes, job completions, records processed, or freshness lag.
These are usually better SLI candidates.

### 2.3 Characteristics of a good SLI

A good SLI is:

- strongly correlated with user experience,
- simple enough to explain to non-specialists,
- derived from trustworthy telemetry,
- stable over time,
- actionable when it changes,
- hard to game.

### 2.4 Characteristics of a bad SLI

A bad SLI is:

- easy to measure but unrelated to user impact,
- based only on infrastructure symptoms,
- averaged in ways that hide outliers,
- sensitive to low-volume noise without guardrails,
- impossible to reason about during an incident.

### 2.5 Good versus bad SLI examples

| Domain | Good SLI | Why it works | Bad SLI | Why it fails |
|---|---|---|---|---|
| HTTP API | fraction of valid requests returning non-5xx within 300 ms | Measures success and timeliness | average CPU below 70% | Users do not care about CPU directly |
| Batch processing | percent of scheduled runs completed by deadline | Measures timeliness of job outcome | job container restarted count | Restart count may not impact delivered result |
| Data pipeline | percent of tables updated within freshness target | Measures usable data freshness | Kafka broker memory | Too indirect |
| Search | percent of searches returning a result page under threshold | User-visible outcome | p50 latency | Hides slow tail |

### 2.6 Where to measure from

The measurement point matters.
For an HTTP service, measurements at the load balancer or edge often best represent user experience.
Application metrics can add detail, but they may exclude failed requests that never reached application code.
For batch jobs, orchestration and scheduler metrics may be the most trustworthy denominator.
For pipelines, freshness is often derived from timestamps in outputs rather than raw processing counters.

### 2.7 Denominator discipline

Every SLI needs a clearly defined denominator.
Ask these questions:

- What counts as an eligible event?
- Which requests are excluded and why?
- Are health checks included?
- Are internal admin endpoints included?
- Are synthetic probes part of the same denominator as user traffic?

If the denominator is unstable or unclear, the SLI becomes untrustworthy.

### 2.8 Availability SLIs

Availability answers a simple question.
Was the service available for eligible requests?
The exact definition of success depends on the product.
For many APIs, non-5xx and non-timeout responses count as available.
For some products, certain 4xx codes are also failures if they reflect user-impacting issues caused by the system.

#### Availability formula

```text
availability = successful_events / eligible_events
```

#### Common success criteria for APIs

- HTTP status is not 5xx.
- Response is returned before the client timeout threshold.
- TLS handshake and routing succeed.
- The response body passes basic contract validation when quality matters.

#### Availability instrumentation options

1. Edge proxy metrics.
2. Ingress controller metrics.
3. Load balancer logs converted to metrics.
4. Application counters with route and status labels.
5. Synthetic probes for externally reachable paths.

#### PromQL example: API availability from ingress metrics

```promql
sum(rate(http_requests_total{job="api-gateway",route!="/healthz",status!~"5.."}[5m]))
/
sum(rate(http_requests_total{job="api-gateway",route!="/healthz"}[5m]))
```

#### PromQL example: request success ratio over 30 days

```promql
sum(increase(http_requests_total{service="payments",status!~"5..",route!="/healthz"}[30d]))
/
sum(increase(http_requests_total{service="payments",route!="/healthz"}[30d]))
```

#### Good availability SLI practices

- Exclude probes and health endpoints unless they represent real user value.
- Keep status code handling explicit.
- Verify low-traffic behavior.
- Handle missing metrics carefully.
- Document whether timeouts are counted as failures.

#### Bad availability SLI practices

- Counting only app-level responses when upstream routing fails are invisible.
- Treating all 4xx responses as successful without service-specific review.
- Measuring pod readiness instead of request success.
- Using uptime of one instance rather than service availability.

### 2.9 Latency SLIs

Latency is usually the second most important SLI after availability.
Users care whether the service is responsive enough for the task.
For interactive systems, tail latency matters far more than averages.
A p50 of 50 ms can coexist with a p99 of 4 seconds.
Users remember the tail.

#### Two common latency SLI patterns

1. Threshold-based success ratio.
2. Percentile target.

Threshold-based success ratio asks:
What fraction of requests completed within a threshold such as 300 ms?
This works very well for SLOs because it maps directly to a success ratio.

Percentile target asks:
Is p99 below 500 ms?
This is intuitive, but percentile-based alerting can be noisier and harder to compose with error budgets.
Many teams track percentiles for diagnostics and threshold-based ratios for SLOs.

#### Instrument latency using histograms

Prometheus histograms are generally preferable for SLI math.
They let you compute the fraction of requests under a threshold.
Classic metrics look like:

- `http_request_duration_seconds_bucket`
- `http_request_duration_seconds_count`
- `http_request_duration_seconds_sum`

#### PromQL example: latency success ratio under 300 ms

```promql
sum(rate(http_request_duration_seconds_bucket{service="checkout",le="0.3",route!="/healthz"}[5m]))
/
sum(rate(http_request_duration_seconds_count{service="checkout",route!="/healthz"}[5m]))
```

#### PromQL example: p99 latency for debugging

```promql
histogram_quantile(
  0.99,
  sum by (le) (
    rate(http_request_duration_seconds_bucket{service="checkout",route!="/healthz"}[5m])
  )
)
```

#### Good latency SLI thresholds

Choose thresholds from user expectations and interaction type.
Examples:

| Workload | Example threshold |
|---|---|
| Login API | 300 ms |
| Search suggestions | 150 ms |
| Checkout submit | 500 ms |
| Report generation sync call | 2 s |
| Background data API | 3 s |

#### Latency instrumentation pitfalls

- Buckets do not include a meaningful threshold.
- Averages are used instead of tail-aware measures.
- Internal retries inflate duration while hiding failures.
- Client-perceived latency differs from server processing time due to queues or network.
- Low-volume services produce unstable percentile estimates.

### 2.10 Throughput SLIs

Throughput is sometimes an SLI and sometimes a capacity indicator.
It becomes an SLI when users explicitly require the system to process a minimum rate.
Examples include stream processors, ingestion systems, and batch pipelines with deadline guarantees.

#### Example throughput questions

- Can the event pipeline sustain 50,000 events per minute?
- Can the email system send all campaign messages before the deadline?
- Can the queue consumer drain backlog within the business recovery objective?

#### Throughput SLI formula

```text
throughput_sli = compliant_intervals / total_intervals
```

Where a compliant interval means the system processed at least the required rate.

#### PromQL example: intervals meeting throughput target

```promql
avg_over_time(
  (
    sum(rate(processed_messages_total{pipeline="etl"}[5m])) >= bool 1000
  )[24h:5m]
)
```

This yields the fraction of five-minute intervals in the last day that met the minimum target.

#### Good throughput instrumentation

- Measure processed units, not queued units.
- Align the window with operational reality.
- Pair throughput with backlog growth metrics.
- Keep throughput separate from success quality if failures can still count as processing.

### 2.11 Quality SLIs

Quality SLIs measure correctness, not just successful transport.
A service can return HTTP 200 and still fail users.
Examples:

- a recommendation API returns malformed JSON,
- a search API returns empty results due to a ranking bug,
- a payment service authorizes duplicate charges,
- a pipeline publishes records missing required fields.

#### Quality SLI examples

| Service type | Quality question | Example metric |
|---|---|---|
| API | Did responses pass schema validation? | valid responses / total responses |
| Search | Did queries return a result set above minimum quality score? | high-quality query responses / total queries |
| Payments | Were transactions processed exactly once? | duplicate-free transactions / total transactions |
| Pipeline | Did outputs pass data quality checks? | passing batches / total batches |

#### PromQL example: API response contract quality

```promql
sum(rate(api_response_contract_valid_total{service="catalog"}[1h]))
/
sum(rate(api_response_contract_checked_total{service="catalog"}[1h]))
```

#### Quality SLI advice

- Avoid purely internal correctness proxies unless they map to a real user problem.
- Combine quality with availability when a bad response should count as a failed request.
- Beware sampling bias if only a subset of responses is validated.

### 2.12 Freshness SLIs

Freshness matters for data products.
A pipeline may be fully available but still useless if data is stale.
Freshness measures how current outputs are compared with expectation.

#### Freshness questions

- How old is the newest successfully processed record?
- How long since the dashboard table was updated?
- How many datasets are within their freshness threshold?

#### Freshness SLI formula

```text
freshness_sli = outputs_within_freshness_target / eligible_outputs
```

#### PromQL example: fraction of tables updated within 30 minutes

```promql
avg by (domain) (
  (time() - dataset_last_success_timestamp_seconds{domain="analytics"} <= bool 1800)
)
```

#### PromQL example: freshness lag for debugging

```promql
time() - max(dataset_last_success_timestamp_seconds{domain="analytics"})
```

#### Freshness anti-patterns

- Measuring pipeline CPU instead of output staleness.
- Averaging lag across datasets with very different criticality.
- Ignoring downstream publish steps.
- Using only successful job completion counts without deadline context.

### 2.13 Composite SLIs

Sometimes a single user journey needs more than one signal.
For example, an API may require both transport success and data correctness.
A composite SLI can define good events as requests that were both available and under latency threshold and correct.
Use composites carefully.
If they become too complex, they are hard to explain and debug.
Often it is better to keep separate SLIs and define multiple SLOs.

### 2.14 SLI review checklist

Before accepting an SLI, ask:

- Does it represent a real user journey?
- Can stakeholders explain it?
- Do we trust the telemetry source?
- Is the denominator documented?
- Is the threshold justified?
- Are excluded events documented?
- Does it behave sensibly during outages and low traffic?
- Will improving the SLI actually improve user experience?

---

## 3. Service level objectives

### 3.1 What an SLO is

An SLO is a target value for an SLI over a defined measurement window.
It tells the organization what level of reliability is good enough.
It is not a legal commitment.
That would be an SLA.
It is not an internal team aspiration either.
It is an operating target tied to user expectations.

### 3.2 SLOs versus SLAs versus OLAs

| Term | Meaning | Audience | Consequence |
|---|---|---|---|
| SLI | Measured indicator | Internal | Observability and decision input |
| SLO | Reliability target for an SLI | Internal stakeholders | Drives release and prioritization decisions |
| SLA | Contractual promise | Customers | Financial or legal consequence |
| OLA | Operational agreement between teams | Internal teams | Coordination and accountability |

### 3.3 How to set an SLO target

A practical target-setting flow is:

1. Measure current behavior.
2. Understand user criticality.
3. Estimate cost of failure.
4. Understand engineering effort required to improve.
5. Choose a target that balances user value and delivery velocity.

### 3.4 Questions to ask before picking a target

- Is the service user-facing or internal?
- Is it synchronous or asynchronous?
- What happens to the business when it is unavailable?
- Is the service tier-0, tier-1, or non-critical?
- How much historical data do we have?
- How fast can we detect and recover from issues?
- Are downstream dependencies less reliable than the proposed target?

### 3.5 Why overly aggressive SLOs are harmful

An unrealistic SLO creates bad incentives.
Teams may:

- hide failure classes,
- exclude too much traffic,
- avoid valuable releases,
- burn out on-call engineers,
- spend disproportionate effort on the last tiny fraction of reliability.

A 99.99% target sounds impressive.
But if the service does not justify it, the organization pays for complexity without matching user value.

### 3.6 Rolling windows versus calendar windows

#### Rolling windows

A rolling window always looks backward from now.
Examples include 7 days or 30 days.
Benefits:

- reflects current user experience more continuously,
- removes month-boundary artifacts,
- fits continuous operations.

Trade-offs:

- harder to communicate to finance or compliance functions that report monthly,
- can make recovery feel slow after a severe incident because bad periods remain inside the window.

#### Calendar windows

A calendar window resets at a fixed boundary such as month or quarter.
Benefits:

- easier for executive reporting,
- aligns with customer contract periods.

Trade-offs:

- teams may take excess risk early in the month,
- reliability may look artificially healthy right after reset.

### 3.7 Multi-window SLO thinking

The SLO target window and the alert window do not have to be identical.
A service may have a 30-day SLO but use 1-hour, 6-hour, 24-hour, and 72-hour burn-rate views for alerting and management.
This is common and recommended.

### 3.8 Multi-window SLO example

A service could define:

- Availability SLO: 99.9% over 30 days.
- Latency SLO: 99% of requests under 300 ms over 7 days.
- Freshness SLO: 99.5% of tables updated within 30 minutes over 7 days.

This mix acknowledges that different failure modes matter at different cadences.

### 3.9 SLO documents should be explicit

A useful SLO document normally includes:

- service name and owner,
- user journey described,
- SLI formula,
- data source,
- numerator and denominator definitions,
- target and window,
- exclusions,
- alert policy,
- review cadence,
- change history,
- escalation and policy linkage.

### 3.10 Example SLO YAML document

```yaml
service: checkout-api
service_tier: tier-1
owners:
  product_team: commerce-platform
  sre_team: reliability-engineering
user_journey: "Customer submits checkout and receives a success or failure response"
slos:
  - name: availability
    objective: 99.9
    window: 30d
    description: "Eligible checkout requests succeed without 5xx or timeout"
    sli:
      source: prometheus
      metric_type: request_ratio
      numerator: 'sum(increase(http_requests_total{service="checkout",status!~"5..",route="/checkout"}[{{ .window }}]))'
      denominator: 'sum(increase(http_requests_total{service="checkout",route="/checkout"}[{{ .window }}]))'
    exclusions:
      - internal synthetic canary traffic
      - load-test traffic labeled test="true"
    alerts:
      - name: slo-burn-fast
        windows: [5m, 1h]
        burn_rate: 14.4
      - name: slo-burn-slow
        windows: [30m, 6h]
        burn_rate: 6
    review:
      cadence: monthly
      stakeholders:
        - product-manager
        - engineering-manager
        - sre-lead
  - name: latency
    objective: 99.0
    window: 7d
    description: "Checkout responses complete in 500 ms or less"
    sli:
      source: prometheus
      metric_type: threshold_ratio
      numerator: 'sum(increase(http_request_duration_seconds_bucket{service="checkout",route="/checkout",le="0.5"}[{{ .window }}]))'
      denominator: 'sum(increase(http_request_duration_seconds_count{service="checkout",route="/checkout"}[{{ .window }}]))'
```

### 3.11 Stakeholder alignment for SLOs

SLOs are social agreements as much as technical definitions.
A reliability engineer may prefer stricter targets.
A product manager may prefer faster feature delivery.
A support leader may want targets aligned to customer pain.
Alignment meetings should therefore include the right people.

Typical stakeholders:

- engineering lead,
- product manager,
- service owner,
- SRE or platform representative,
- support or customer success for externally visible services,
- data consumers for pipelines.

### 3.12 A practical SLO alignment agenda

1. Review the user journey.
2. Review current telemetry quality.
3. Review historical incident patterns.
4. Decide which events belong in the denominator.
5. Select the target and window.
6. Agree on alert thresholds and policy actions.
7. Record exclusions and assumptions.
8. Set review cadence.

### 3.13 SLO review triggers

You should review SLOs when:

- the product criticality changes,
- architecture changes substantially,
- major telemetry gaps are fixed,
- the service has exceeded the target comfortably for multiple quarters,
- the service repeatedly fails despite strong engineering effort,
- customers or internal consumers report a mismatch between metrics and experience.

### 3.14 SLO anti-patterns

- Setting targets before you have trustworthy telemetry.
- Using the same target for every service.
- Creating too many SLOs for one service.
- Choosing impossible latency thresholds disconnected from network reality.
- Failing to define exclusions.
- Never revisiting the document after launch.

---

## 4. Error budgets

### 4.1 What an error budget means

If an SLO target is less than 100%, the difference is the allowed unreliability.
That allowance is the error budget.
An error budget is not permission to be careless.
It is permission to make informed trade-offs.

### 4.2 Request-count calculation method

For request-based SLIs, calculate budget in failed events.

```text
error_budget_fraction = 1 - slo_target
allowed_bad_events = total_eligible_events * error_budget_fraction
```

#### Example

- SLO = 99.9%.
- Eligible requests in 30 days = 42,000,000.
- Error budget fraction = 0.001.
- Allowed failed requests = 42,000.

### 4.3 Time-based calculation method

For uptime-style services, budget can also be expressed in downtime minutes.

```text
allowed_downtime = window_duration * (1 - slo_target)
```

#### Monthly downtime examples

| SLO | 30-day budget |
|---|---|
| 99.0% | 432 minutes |
| 99.5% | 216 minutes |
| 99.9% | 43.2 minutes |
| 99.95% | 21.6 minutes |
| 99.99% | 4.32 minutes |

Time-based budgets are intuitive.
Request-count budgets are usually better for uneven traffic because they align more directly with user impact.

### 4.4 Which calculation method should you use

Use request count when:

- traffic varies significantly across the day,
- the user journey is request driven,
- you need consistent treatment of partial outages.

Use time-based thinking when:

- the service is truly uptime oriented,
- non-request failures still matter to the business,
- you need a simple explanation for stakeholders.

In practice, many teams explain the budget in time and operate it in requests.

### 4.5 Budget remaining, used, and consumed

Useful expressions include:

```text
budget_used_percent = bad_events / allowed_bad_events * 100
budget_remaining_percent = 100 - budget_used_percent
```

Always be explicit about whether a chart shows remaining or used.
Confusion here causes poor decisions.

### 4.6 Burn rate math

Burn rate tells you how fast you are consuming the error budget relative to the allowed rate.

```text
burn_rate = actual_error_rate / error_budget_fraction
```

If burn rate is 1, you are consuming budget at exactly the allowed pace.
If burn rate is 2, you are burning budget twice as fast as planned.
If burn rate is 14.4, you are in serious trouble.

#### Example

- SLO = 99.9%, so error budget fraction = 0.001.
- Current measured error rate = 0.0144.
- Burn rate = 0.0144 / 0.001 = 14.4.

At 14.4x burn, a 30-day budget lasts about 30 / 14.4 = 2.08 days.
That is why fast-burn alerts are urgent.

### 4.7 Why multi-burn-rate alerting matters

Single-window alerts are weak.
A short window alone is noisy.
A long window alone is slow.
Multi-burn-rate alerts pair a short confirmation window with a longer validation window.
This catches both acute and sustained problems.

### 4.8 Standard fast and slow burn patterns

Common patterns inspired by the Google workbook include:

| Alert type | Short window | Long window | Burn rate | Meaning |
|---|---|---|---|---|
| Critical fast burn | 5m | 1h | 14.4 | Severe issue burning budget rapidly |
| Warning slow burn | 30m | 6h | 6 | Sustained elevated errors |
| Daily degradation | 2h | 24h | 3 | Meaningful drift over a day |
| Long-tail trend | 6h | 72h | 1 | Slow reliability erosion |

### 4.9 PromQL recording rules for error ratios

```yaml
groups:
  - name: slo.recording.rules
    interval: 30s
    rules:
      - record: service:error_ratio:rate5m
        expr: |
          sum(rate(http_requests_total{service="checkout",status=~"5.."}[5m])) by (service)
          /
          sum(rate(http_requests_total{service="checkout"}[5m])) by (service)
      - record: service:error_ratio:rate1h
        expr: |
          sum(rate(http_requests_total{service="checkout",status=~"5.."}[1h])) by (service)
          /
          sum(rate(http_requests_total{service="checkout"}[1h])) by (service)
      - record: service:error_ratio:rate6h
        expr: |
          sum(rate(http_requests_total{service="checkout",status=~"5.."}[6h])) by (service)
          /
          sum(rate(http_requests_total{service="checkout"}[6h])) by (service)
      - record: service:error_ratio:rate24h
        expr: |
          sum(rate(http_requests_total{service="checkout",status=~"5.."}[24h])) by (service)
          /
          sum(rate(http_requests_total{service="checkout"}[24h])) by (service)
      - record: service:error_ratio:rate72h
        expr: |
          sum(rate(http_requests_total{service="checkout",status=~"5.."}[72h])) by (service)
          /
          sum(rate(http_requests_total{service="checkout"}[72h])) by (service)
```

### 4.10 PromQL alert rules for 1h, 6h, 24h, and 72h views

Assume SLO = 99.9%, so budget fraction = `0.001`.

```yaml
groups:
  - name: slo.burn.alerts
    rules:
      - alert: SLOErrorBudgetBurnFast
        expr: |
          service:error_ratio:rate5m > (14.4 * 0.001)
          and
          service:error_ratio:rate1h > (14.4 * 0.001)
        for: 2m
        labels:
          severity: critical
          slo: availability
        annotations:
          summary: "Fast burn for {{ $labels.service }}"
          description: "Service is burning error budget at >14.4x across 5m and 1h windows"

      - alert: SLOErrorBudgetBurnHigh
        expr: |
          service:error_ratio:rate30m > (6 * 0.001)
          and
          service:error_ratio:rate6h > (6 * 0.001)
        for: 15m
        labels:
          severity: warning
          slo: availability
        annotations:
          summary: "High burn for {{ $labels.service }}"
          description: "Service is burning error budget at >6x across 30m and 6h windows"

      - alert: SLOErrorBudgetBurnDay
        expr: |
          service:error_ratio:rate2h > (3 * 0.001)
          and
          service:error_ratio:rate24h > (3 * 0.001)
        for: 30m
        labels:
          severity: warning
          slo: availability
        annotations:
          summary: "Daily burn trend for {{ $labels.service }}"
          description: "Meaningful daily burn across 2h and 24h windows"

      - alert: SLOErrorBudgetBurnTrend
        expr: |
          service:error_ratio:rate6h > (1 * 0.001)
          and
          service:error_ratio:rate72h > (1 * 0.001)
        for: 1h
        labels:
          severity: info
          slo: availability
        annotations:
          summary: "Long trend burn for {{ $labels.service }}"
          description: "Budget is being consumed faster than planned over 72h"
```

### 4.11 Budget policies translate metrics into decisions

Without a policy, error budgets become dashboard art.
A useful policy defines what actions follow from different budget states.
That policy must be pre-agreed.
It should not be invented in the middle of an incident.

### 4.12 Example policy thresholds

| Budget remaining | Operational posture | Change policy |
|---|---|---|
| > 50% | Healthy | Normal delivery |
| 25% to 50% | Watch closely | Extra review for risky changes |
| 10% to 25% | Guarded | Reduce change scope and prioritize reliability work |
| 0% to 10% | Emergency caution | Freeze risky changes; ship only fixes and safety work |
| ≤ 0% | Breached | Feature freeze until recovery plan approved |

### 4.13 What should happen when budget is healthy

When more than half the budget remains:

- normal deploy cadence can continue,
- teams can run experiments with standard safeguards,
- roadmap delivery is not constrained by reliability posture,
- reliability backlog still exists, but it is balanced with features.

### 4.14 What should happen when burn accelerates

When burn rate alerts fire or remaining budget falls materially:

- review recent changes,
- examine whether the SLI is reflecting real user pain,
- slow down or batch risky releases,
- shift engineering effort to top reliability risks,
- increase review discipline for dependency and migration changes.

### 4.15 Freeze does not mean do nothing

A feature freeze means you stop shipping risk-increasing work.
It does not mean engineers are idle.
During freeze, teams typically:

- fix top incident causes,
- pay down reliability debt,
- improve automation,
- add missing tests,
- tune alerts,
- improve capacity margins,
- update runbooks and rollback plans.

### 4.16 Budget recovery strategies

Recovery plans often include:

- reducing incident recurrence,
- reducing blast radius,
- shortening mean time to detect,
- shortening mean time to recover,
- improving deployment safety,
- reducing alert noise,
- removing chronic toil that delays response.

### 4.17 A detailed decision tree for error budget policy

```text
Start
 |
 +-- Is the SLO currently being measured accurately?
 |     |
 |     +-- No --> Fix telemetry gaps, annotate reports, avoid policy action based on bad data
 |     |
 |     +-- Yes
 |
 +-- Is budget remaining > 50%?
 |     |
 |     +-- Yes --> Normal delivery, continue standard review and monitoring
 |     |
 |     +-- No
 |
 +-- Is budget remaining between 25% and 50%?
 |     |
 |     +-- Yes --> Weekly review, extra scrutiny on risky deploys, prioritize top reliability tasks
 |     |
 |     +-- No
 |
 +-- Is budget remaining between 10% and 25%?
 |     |
 |     +-- Yes --> Daily review, limit scope of changes, require senior approval for critical-path deploys
 |     |
 |     +-- No
 |
 +-- Is budget remaining between 0% and 10%?
 |     |
 |     +-- Yes --> Freeze risky feature work, focus on stabilizing actions, leadership visibility required
 |     |
 |     +-- No
 |
 +-- Budget exhausted or negative
       |
       +-- Breach declared --> Feature freeze, postmortem, recovery plan, exec review for exceptions
```

### 4.18 Policy exceptions

Sometimes a risky change must ship even when budget is low.
Examples include security patches, regulatory fixes, or urgent customer commitments.
An exception process should require:

- explicit risk statement,
- approval from engineering and product leadership,
- rollback plan,
- incident response ownership,
- post-change evaluation.

### 4.19 Error budget anti-patterns

- Treating budget as a punishment tool.
- Freezing all changes for trivial blips.
- Ignoring slow-burn consumption until breach occurs.
- Applying one policy to every service regardless of criticality.
- Using budget reports without validating SLI correctness.

---

## 5. Toil and its reduction

### 5.1 Formal definition of toil

The classic SRE definition describes toil as work directly tied to service operations that is:

- manual,
- repetitive,
- automatable,
- tactical,
- reactive,
- and scales linearly with service growth.

A task does not need every property to be concerning.
But the more boxes it checks, the more likely it is toil.

### 5.2 Examples of toil

- manually restarting unhealthy pods,
- hand-running database cleanup scripts every week,
- repeatedly scaling deployments before peak traffic,
- triaging the same false-positive alert every night,
- copying release steps from a wiki into a shell session,
- manually updating dashboard JSON across environments.

### 5.3 Examples that are not toil

- designing a safer deployment strategy,
- writing automation to replace manual restarts,
- running a one-time migration with durable value,
- performing a postmortem that changes system design,
- capacity modeling for next quarter.

### 5.4 Why toil is dangerous

Toil has multiple costs:

- it steals time from engineering improvements,
- it increases cognitive fatigue,
- it creates inconsistent execution,
- it increases dependency on tribal knowledge,
- it often masks underlying product or platform defects.

### 5.5 Toil budget and the 50% rule

The Google guidance is that SRE teams should spend at most roughly half of their time on toil.
If the number is higher for sustained periods, the team is effectively doing reactive operations rather than engineering.
Some organizations set stricter targets such as 30% or less.
The exact number matters less than the operating principle.
Track it.
Act on it.

### 5.6 A simple toil audit method

Record for each operational task:

- task name,
- trigger,
- frequency,
- average time spent,
- urgency level,
- automation feasibility,
- root cause category,
- owner.

#### Sample toil audit table

| Task | Frequency | Avg time | Monthly cost | Automatable? | Root cause |
|---|---|---:|---:|---|---|
| Restart flapping pod | 3/day | 10 min | 900 min | Yes | Missing liveness/readiness design |
| Scale API before sale event | 2/week | 20 min | 160 min | Yes | No autoscaling policy |
| Re-run stuck batch job | 5/week | 15 min | 300 min | Partly | Weak retry and idempotency |
| Ack noisy alert | 4/night | 2 min | 240 min | Yes | Bad threshold / missing aggregation |

### 5.7 Prioritizing toil reduction

A good heuristic is:

```text
priority = frequency * cost * user_impact * automatable_confidence
```

You do not need perfect scoring.
You need a consistent method to avoid chasing low-value automation.

### 5.8 Typical toil-reduction strategies

- fix health checks and restart policies,
- add horizontal pod autoscaling,
- create self-healing workflows,
- improve idempotency and retry logic,
- codify runbooks in automation,
- remove false-positive alerts,
- standardize platform golden paths.

### 5.9 Measure before and after

Always capture baseline effort before automating.
Common measures include:

- manual minutes per week,
- pages per week,
- incidents triggered by the toil item,
- MTTR contribution,
- error rate caused by manual execution mistakes.

### 5.10 Toil reduction is not only scripting

Some toil should be removed at the application layer.
Examples:

- liveness probes instead of manual restarts,
- HPA instead of manual scaling,
- circuit breakers instead of manual traffic blocking,
- better schema evolution instead of manual data repair.

---

## 6. Reliability engineering practices

### 6.1 Load testing

Load testing answers whether the system can handle expected and unexpected demand.
It is not only for launch week.
It should be part of major architectural changes, scaling events, and capacity reviews.

#### Common load-test types

- baseline test,
- ramp test,
- stress test,
- spike test,
- soak test,
- failover under load test.

#### Questions load tests should answer

- Where does latency begin to degrade?
- Which dependency saturates first?
- Does autoscaling respond quickly enough?
- Are retries amplifying traffic during failures?
- Does the system recover cleanly after the test stops?

#### Useful load-test metrics

- p50, p90, p95, p99 latency,
- error rate,
- saturation of CPU, memory, network, and thread pools,
- queue depth,
- connection pool utilization,
- database lock contention,
- autoscaling time to add capacity.

#### Example k6 snippet

```javascript
import http from 'k6/http';
import { sleep } from 'k6';

export const options = {
  stages: [
    { duration: '5m', target: 100 },
    { duration: '10m', target: 500 },
    { duration: '5m', target: 0 }
  ],
  thresholds: {
    http_req_failed: ['rate<0.001'],
    http_req_duration: ['p(99)<500']
  }
};

export default function () {
  http.get('https://api.example.com/checkout/health');
  sleep(1);
}
```

### 6.2 Capacity planning

Capacity planning converts growth expectations into resource and architecture decisions.
It should not be a once-a-year spreadsheet exercise.
A strong practice includes:

- demand forecasting,
- headroom targets,
- failure-domain awareness,
- dependency bottleneck analysis,
- cost-awareness.

#### Capacity planning workflow

1. Collect historical traffic and seasonal patterns.
2. Identify service saturation points.
3. Model demand for normal and peak scenarios.
4. Reserve headroom for failure of a zone or node group.
5. Validate with load tests.
6. Review monthly or before major events.

#### Capacity formulas worth knowing

```text
required_capacity = peak_expected_load * safety_factor
headroom_percent = (available_capacity - expected_peak_load) / available_capacity * 100
```

#### Capacity planning anti-patterns

- sizing only for average traffic,
- ignoring background jobs during peak periods,
- assuming autoscaling is instantaneous,
- forgetting dependency limits like database connections.

### 6.3 Failure injection

Failure injection validates whether the system behaves as designed under fault conditions.
Unlike accidental incidents, failure injection is intentional and instrumented.
It should answer a hypothesis.

Examples:

- What happens if one instance crashes?
- What if a dependent service returns 500s for ten minutes?
- What if latency increases by 300 ms on a critical dependency?
- What if one availability zone disappears during peak traffic?

### 6.4 Game days

Game days are structured exercises where teams simulate failure scenarios and practice response.
They are part technical validation and part human training.
A good game day includes:

- explicit objectives,
- a scenario script,
- roles and observers,
- success criteria,
- guardrails,
- post-exercise actions.

#### Good game day outcomes

- broken runbooks are discovered,
- missing dashboards become obvious,
- ambiguous ownership is clarified,
- recovery steps are practiced before a real outage,
- dependencies and hidden coupling are exposed.

### 6.5 Postmortems as a reliability practice

A high-quality postmortem should document:

- what happened,
- user impact,
- timeline,
- contributing factors,
- why existing controls failed,
- corrective actions,
- owners and due dates.

The focus is system improvement.
Not blame.

---

## 7. Chaos engineering

### 7.1 What chaos engineering is

Chaos engineering is the disciplined practice of experimenting on a system to build confidence in its resilience.
It is not random destruction.
It is controlled learning.
The experiment must be hypothesis-driven and safety-bounded.

### 7.2 Principles of good chaos experiments

- start from a steady-state hypothesis,
- define expected behavior,
- change one variable at a time when possible,
- keep blast radius limited,
- monitor user-impacting SLIs during the test,
- abort automatically if safety thresholds are crossed,
- turn findings into engineering work.

### 7.3 Steady state and hypothesis examples

Example steady-state metric:
Checkout availability remains above 99.9% while traffic is 300 RPS.

Example hypothesis:
If one checkout pod is terminated, the deployment and load balancer configuration will keep availability above target and p99 latency below 500 ms.

### 7.4 Blast radius design

Blast radius is the scope of potential impact.
Good blast-radius controls include:

- limit to one service or environment,
- start in staging or a low-risk slice of production,
- target one pod or one zone first,
- define rollback and abort conditions,
- notify stakeholders before and after.

### 7.5 Common chaos experiment types

- instance termination,
- network latency,
- packet loss,
- DNS failure,
- dependency 500 injection,
- CPU or memory stress,
- disk pressure,
- node drain,
- regional traffic failover.

### 7.6 Tooling overview

| Tool | Best known use | Notes |
|---|---|---|
| Chaos Monkey | Random instance termination | Historically popular; best used with strong guardrails |
| LitmusChaos | Kubernetes-native chaos workflows | Good for CRD-based experiments and GitOps integration |
| Gremlin | Commercial chaos platform | Strong controls, scheduling, and blast-radius management |
| k6 | Load and resilience validation | Often paired with fault injection to validate steady-state impact |
| Chaos Mesh | Kubernetes chaos experiments | Useful in CNCF-oriented clusters |

### 7.7 Example LitmusChaos experiment

```yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosEngine
metadata:
  name: checkout-pod-delete
  namespace: litmus
spec:
  appinfo:
    appns: production
    applabel: app=checkout
    appkind: deployment
  chaosServiceAccount: litmus-admin
  experiments:
    - name: pod-delete
      spec:
        components:
          env:
            - name: TOTAL_CHAOS_DURATION
              value: '60'
            - name: CHAOS_INTERVAL
              value: '30'
            - name: FORCE
              value: 'false'
```

### 7.8 Using k6 during chaos tests

Chaos without realistic traffic can miss failure modes.
Running k6 during experiments helps answer:

- Did availability fall?
- Did latency degrade beyond the SLO threshold?
- Did retries amplify load?
- Did the system recover after the injected fault ended?

### 7.9 What to measure during chaos experiments

- SLI compliance,
- burn rate,
- saturation metrics,
- autoscaling behavior,
- queue backlog,
- failover timing,
- alert firing correctness,
- operator intervention required.

### 7.10 Chaos engineering anti-patterns

- running experiments without a hypothesis,
- starting with huge blast radius,
- measuring only infrastructure metrics,
- failing to capture learning in backlog items,
- treating chaos as theater rather than engineering validation.

---

## 8. On-call engineering

### 8.1 Why on-call design matters

On-call is where reliability policy becomes lived reality.
A bad on-call system burns out engineers and hides systemic issues.
A good on-call system creates fast response, sustainable staffing, and continuous learning.

### 8.2 Principles of sustainable on-call

- alerts should indicate actionable symptoms,
- primary responders need clear ownership,
- escalation paths must be documented,
- runbooks should reduce cognitive load,
- page volume must be measured,
- follow-the-sun or regional coverage should be considered when scale demands it,
- chronic night pages require engineering fixes, not heroic endurance.

### 8.3 Rotation design considerations

Questions to answer:

- How many engineers are in the rotation?
- What is the weekly page volume?
- Is there a secondary or shadow responder?
- Are handoffs structured?
- Is business-hours coverage sufficient for low-severity alerts?
- Do specialists need separate escalation layers?

### 8.4 Healthy rotation patterns

Common patterns include:

- primary plus secondary rotation,
- regional weekday rotation with centralized escalation,
- shadow rotation for training,
- split infra and application rotations when ownership is clear.

A rotation with too few people becomes dangerous quickly.
As a rough guide, very small rotations below five to six engineers often create fatigue unless page volume is minimal.

### 8.5 Escalation policies

A sound escalation policy defines:

- who responds first,
- when to involve a secondary,
- when to page management,
- how long to wait before escalation,
- what communication channels are used,
- who owns incident command for multi-team incidents.

### 8.6 Runbook quality

A runbook should be optimized for stress.
It should answer:

- What does this alert mean?
- What user impact does it imply?
- How do I confirm the problem?
- What immediate mitigations are safe?
- When do I escalate?
- What dashboards and logs matter?
- What rollback or failover options exist?

#### Runbook quality checklist

- concise title,
- owner and last review date,
- alert explanation,
- command examples that actually work,
- decision points,
- links to dashboards,
- known false positives,
- escalation contacts.

### 8.7 Alert fatigue

Alert fatigue happens when responders receive too many low-value notifications.
Symptoms include:

- pages are ignored or delayed,
- responders mute channels,
- incidents blend into noise,
- morale declines,
- people lose trust in monitoring.

### 8.8 Sources of alert fatigue

- threshold alerts on noisy low-level metrics,
- duplicate alerts from multiple layers,
- no aggregation or deduplication,
- warning pages sent overnight,
- alerts without clear remediation,
- flapping checks.

### 8.9 Alert quality standards

A page-worthy alert should usually meet all of the following:

- indicates likely user impact,
- requires timely human action,
- has a known first-response path,
- is rare enough to preserve urgency,
- is measured from trustworthy data.

### 8.10 On-call metrics to watch

- pages per shift,
- pages per night,
- actionable page ratio,
- mean time to acknowledge,
- mean time to mitigate,
- repeat incidents,
- postmortem action completion,
- percentage of alerts with runbooks.

### 8.11 Sustainable staffing practices

- compensate on-call fairly,
- provide recovery time after severe incidents,
- rotate incident command responsibilities,
- train new responders gradually,
- revisit ownership boundaries when page volume changes.

### 8.12 Decision tree for paging policy

```text
Alert triggers
 |
 +-- Is user impact likely or already visible?
 |     |
 |     +-- No --> Route to ticket, dashboard, or business-hours notification
 |     |
 |     +-- Yes
 |
 +-- Can the service self-heal safely?
 |     |
 |     +-- Yes --> Run automation, notify if automation fails
 |     |
 |     +-- No
 |
 +-- Is immediate human action needed to avoid budget burn or outage expansion?
       |
       +-- No --> Use non-paging alert with clear ownership
       |
       +-- Yes --> Page primary on-call and activate runbook
```

---

## 9. Error budget policy in detail

### 9.1 Why detailed policy matters

A policy turns SLO math into organizational behavior.
Without detailed policy:

- one manager may continue shipping aggressively,
- another may impose an ad hoc freeze,
- incident reviews become political,
- teams optimize for opinion rather than evidence.

### 9.2 Policy components to define explicitly

A strong policy defines:

- which SLOs are policy-driving,
- which services are covered,
- how budget is calculated,
- who reviews budget state,
- which actions occur at each threshold,
- how exceptions are approved,
- how policy compliance is audited.

### 9.3 Example action matrix

| Condition | Required action | Owner |
|---|---|---|
| Fast-burn alert fires | Incident triage within minutes | On-call engineer |
| 25% budget remaining | Weekly reliability review | Engineering manager |
| 10% budget remaining | Daily budget review and change restriction | Service owner + SRE |
| Budget exhausted | Freeze risky changes, open recovery plan | Engineering leadership |
| Exception requested | Review risk memo and rollback plan | Product + Eng + SRE leadership |

### 9.4 Policy workflow

```text
Measure SLI
  -> Calculate budget remaining and burn rate
  -> Classify posture
  -> Apply policy actions
  -> Review reliability backlog
  -> Track recovery progress
  -> Resume normal delivery when threshold clears
```

### 9.5 Example weekly review questions

- What percentage of budget remains?
- Which incidents consumed the most budget?
- Are current alerts catching burn early enough?
- What recurring toil delayed mitigation?
- Which fixes would buy back the most reliability?
- Are there upcoming risky launches that should be delayed?

### 9.6 Example exception memo outline

```yaml
service: checkout-api
requested_by: product-director
reason: "Critical tax compliance release"
current_budget_remaining: 8%
risk_summary:
  - "Change touches pricing path"
  - "Rollback is available within 5 minutes"
mitigations:
  - "Canary to 2% traffic for 30 minutes"
  - "Dedicated incident commander on standby"
  - "Feature flag rollback tested in staging"
approvals:
  - engineering-director
  - sre-manager
  - product-director
```

### 9.7 Policy enforcement signals

Useful audit questions include:

- Did the team slow or freeze changes when required?
- Were incidents during low-budget periods followed by postmortems?
- Did leadership override policy repeatedly?
- Were recovery actions completed?
- Did budget reports reflect real user experience?

### 9.8 Policy anti-patterns

- policy is written but unknown to engineers,
- thresholds exist but no one owns the response,
- exceptions become the default path,
- policy drives blame instead of prioritization,
- budget state is reviewed too infrequently.

---

## 10. Practical checklists and reference material

### 10.1 SLI checklist

- User journey defined.
- Numerator documented.
- Denominator documented.
- Telemetry source trusted.
- Exclusions justified.
- Window documented.
- Validation against user complaints performed.

### 10.2 SLO checklist

- Target justified by user need.
- Window chosen intentionally.
- Owners listed.
- Review cadence defined.
- Policy link included.
- Alerting mapped to burn rates.

### 10.3 Error budget checklist

- Budget fraction calculated.
- Remaining budget displayed on dashboard.
- Burn rate panels created for multiple windows.
- Alert thresholds reviewed.
- Freeze and exception process documented.

### 10.4 Toil checklist

- Toil log exists.
- Top items quantified.
- Automation candidates prioritized.
- Before and after time saved measured.
- Toil percentage reported monthly.

### 10.5 On-call checklist

- Rotation size sustainable.
- Primary and secondary roles defined.
- Escalation timers configured.
- Page-worthy criteria documented.
- Runbooks reviewed quarterly.
- Alert noise tracked and reduced.

### 10.6 Final summary

SRE is not a dashboard collection.
It is a decision system.
SLIs tell you what users experience.
SLOs define what good enough means.
Error budgets govern the balance between change and stability.
Toil reduction keeps engineering effort focused on durable improvements.
Reliability practices such as load testing, capacity planning, failure injection, game days, and sustainable on-call make the model real.
When these pieces work together, reliability becomes measurable, actionable, and continuously improvable.
