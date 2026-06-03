# Scenario-Based SRE Interview Questions

## 3am Production Down Scenarios

**Q: [Advanced] It is 3am and the primary database stops responding for your checkout service. How would you handle it?**
**Situation:** Checkout requests are timing out, revenue is dropping, and the latest deployment finished 20 minutes ago.  
**What the interviewer is looking for:** Calm incident leadership, mitigation-first thinking, fast validation of user impact, and clear communication.  
**Model answer:** 1) Acknowledge the page, declare severity, and verify impact from the customer path instead of trusting only one alert. 2) Check recent changes and database health immediately, then choose the fastest safe mitigation such as rollback, failover, or connection pool reduction. 3) Communicate status on a fixed cadence while assigning parallel investigations for database logs, application errors, and infrastructure health. 4) After recovery, preserve evidence, write the timeline, and ensure the postmortem covers both the trigger and the missing safeguards.

**Q: [Advanced] It is 3am and every Pod in the production namespace is stuck in Pending. What do you do?**
**Situation:** No new replicas can start, autoscaling is not helping, and the existing fleet is shrinking under load.  
**What the interviewer is looking for:** Strong Kubernetes triage, prioritization of scheduling signals, and clear reasoning under pressure.  
**Model answer:** 1) Confirm user impact and inspect events from one representative Pending Pod before touching cluster-wide settings. 2) Check node capacity, taints, quotas, persistent volume constraints, and recent cluster maintenance or scaling failures. 3) Mitigate by adding capacity, removing bad constraints, or pausing noncritical workloads that are consuming scarce resources. 4) After stability returns, fix the structural cause such as bad requests, quota misconfiguration, or autoscaler guardrails.

**Q: [Advanced] It is 3am and your API is returning intermittent 503s, but only from one region. How would you respond?**
**Situation:** A global load balancer is serving traffic, but one region shows elevated errors and latency while other regions look healthy.  
**What the interviewer is looking for:** Regional isolation thinking, traffic management, and fast mitigation with controlled blast radius.  
**Model answer:** 1) Confirm the regional pattern from user-facing telemetry and load balancer logs. 2) Shift traffic away from the unhealthy region if capacity elsewhere is sufficient, then investigate health checks, deployments, dependency failures, and node or zone conditions in that region. 3) Keep stakeholders updated with clear regional impact statements and expected next actions. 4) Use the post-incident review to decide whether failover should have been automatic or faster.

**Q: [Advanced] It is 3am and services across the cluster cannot resolve DNS names. What is your plan?**
**Situation:** Application logs show dependency timeouts, and failures span multiple teams even though Pods themselves are still running.  
**What the interviewer is looking for:** Recognition of shared infrastructure failure, systematic narrowing, and safe mitigation steps.  
**Model answer:** 1) Verify the symptom with an in-cluster debug Pod and check whether both internal and external DNS lookups fail. 2) Inspect CoreDNS health, recent config changes, network policies, and node networking issues before restarting anything blindly. 3) Mitigate by restoring CoreDNS capacity, rolling back a bad configuration, or shifting workloads if the problem is isolated to part of the cluster. 4) Follow up with dependency mapping and stronger alerts on shared control-plane services.

**Q: [Advanced] It is 3am and all HTTPS requests suddenly fail after a certificate rotation. How would you handle it?**
**Situation:** The load balancer is reachable, but clients see TLS errors immediately after a maintenance window.  
**What the interviewer is looking for:** Safe rollback instincts, understanding of certificate chains and expiry, and customer-focused communication.  
**Model answer:** 1) Confirm the exact TLS failure from an external client and check whether the issue is certificate expiry, wrong private key, missing intermediate chain, or bad load balancer binding. 2) Restore the last known-good certificate or route traffic to a healthy endpoint before attempting deeper cleanup. 3) Communicate clearly because TLS failures are customer-visible and often look like a total outage to users. 4) Afterward, add validation steps and pre-expiry alerting so certificate work cannot bypass verification again.

## Architecture Design Scenarios

**Q: [Advanced] Design a highly available e-commerce checkout platform for heavy seasonal traffic. What would you propose?**
**Situation:** The service must tolerate zone failure, support traffic spikes, and protect the payment path from cascading failures.  
**What the interviewer is looking for:** Clear architecture tradeoffs, dependency isolation, scaling strategy, and reliability-first design choices.  
**Model answer:** 1) Start with critical user journeys and define SLOs for browse, cart, checkout, and payment authorization. 2) Use stateless application tiers across multiple zones, resilient data stores, caching, queues for noncritical side effects, and circuit breakers around payment dependencies. 3) Add autoscaling, backpressure, load shedding, and clear observability around the checkout path so spikes do not collapse the whole system. 4) Finish by explaining failover testing, capacity planning, and how to degrade gracefully when payment or inventory systems are unhealthy.

**Q: [Advanced] Design an internal platform for logs, metrics, and traces used by many engineering teams. How would you approach it?**
**Situation:** The company wants shared observability with strong multi-tenancy, cost control, and self-service onboarding.  
**What the interviewer is looking for:** Platform thinking, data lifecycle awareness, and understanding of usability versus cost tradeoffs.  
**Model answer:** 1) Separate collection, storage, query, and access-control concerns so each layer can scale independently. 2) Standardize telemetry formats, labels, retention tiers, and tenant boundaries to prevent chaos and runaway cardinality. 3) Provide templates, dashboards, alert patterns, and onboarding automation so teams can use the platform without filing tickets. 4) Close by discussing retention, sampling, chargeback or showback, and operational SLOs for the observability platform itself.

**Q: [Advanced] Design a background job platform that processes millions of events per day with strict reliability requirements. What would you include?**
**Situation:** Jobs can be retried, but duplicates are dangerous and downstream systems have variable throughput.  
**What the interviewer is looking for:** Queue-based design, idempotency, backpressure, and failure-mode thinking.  
**Model answer:** 1) Choose a durable queue and require idempotent consumers so retries are safe. 2) Use worker autoscaling based on lag, dead-letter queues for poison messages, and per-dependency concurrency controls to prevent overload. 3) Build observability around queue depth, processing latency, error classes, and replay workflows. 4) Explain how you would test failure scenarios such as downstream slowness, duplicate delivery, or partial outages.

## Reliability Engineering Scenarios

**Q: [Advanced] A new customer-facing service is launching next quarter and has no SLOs yet. How would you define them?**
**Situation:** Product wants aggressive delivery speed, but leadership also wants reliable launch criteria and measurable readiness.  
**What the interviewer is looking for:** Ability to connect business goals, user journeys, and telemetry into practical reliability targets.  
**Model answer:** 1) Identify the critical user journeys and decide which user-visible signals best represent success, latency, and freshness. 2) Set initial SLOs using customer expectations, historical benchmarks, and what the team can realistically operate. 3) Define the error budget policy, burn-rate alerts, and review cadence before launch so reliability work is not improvised later. 4) Make launch readiness depend on dashboards, runbooks, ownership, and alert quality as well as on feature completeness.

**Q: [Advanced] One service has exhausted its error budget in three of the last four months. What would you do?**
**Situation:** The team keeps patching incidents, but product pressure makes it hard to slow releases.  
**What the interviewer is looking for:** Policy-driven decision making, recurring issue analysis, and willingness to trade short-term velocity for long-term stability.  
**Model answer:** 1) Group the incidents by cause and quantify which failure modes consume the most budget. 2) Use the agreed error budget policy to limit risky changes and create a focused reliability plan with owners and deadlines. 3) Prioritize fixes that remove recurring classes of failure such as unsafe deploys, weak dependencies, or bad capacity assumptions. 4) If the target is still unreachable after focused work, revisit the architecture or the SLO definition with stakeholders.

**Q: [Advanced] Your SRE team spends most of its time on repetitive operational work. How would you reduce toil?**
**Situation:** Engineers are burning out, roadmap work is slipping, and the same manual tasks happen every week.  
**What the interviewer is looking for:** Data-driven prioritization, automation mindset, and realistic change management.  
**Model answer:** 1) Measure the toil explicitly by frequency, time cost, risk, and ease of automation. 2) Automate the highest-leverage items first, especially repeated pages, manual deploy steps, and repetitive diagnostics. 3) Move recurring work behind tooling, runbooks, or self-service workflows owned by the right teams. 4) Track toil percentage over time so leadership sees whether reliability investment is actually creating engineering capacity.

**Q: [Advanced] Traffic is expected to triple during an upcoming launch. How would you handle capacity planning?**
**Situation:** The current system is stable at normal traffic, but there is little confidence in its headroom or failure behavior under spike conditions.  
**What the interviewer is looking for:** Forecasting, testing, dependency analysis, and practical risk reduction steps.  
**Model answer:** 1) Estimate demand using historical growth, product assumptions, and failure scenarios such as losing a zone. 2) Load test the full path, including databases, caches, third-party dependencies, and asynchronous workers, not just the front end. 3) Add headroom, autoscaling guardrails, and clear rollback or feature degradation plans before launch day. 4) Staff the event, watch SLO burn in real time, and capture lessons for the next planning cycle.

## Monitoring & Observability Scenarios

**Q: [Advanced] You are asked to onboard a new Tier 1 service into the observability stack. What is your checklist?**
**Situation:** The service is business critical, but its team is new and currently only has basic application logs.  
**What the interviewer is looking for:** End-to-end thinking across metrics, alerts, dashboards, logs, traces, and ownership.  
**Model answer:** 1) Confirm the service exposes user-relevant metrics, structured logs, and tracing with stable labels and ownership metadata. 2) Build dashboards around golden signals and critical user journeys, then define SLO-based alerts with runbook links. 3) Test alert routing, incident ownership, and trace-log correlation before the service is considered production-ready. 4) Document onboarding standards so future teams can follow a repeatable path.

**Q: [Advanced] Prometheus starts running out of memory after a new instrumentation rollout. How would you respond?**
**Situation:** Query latency is rising, scrape failures are increasing, and the issue appears tied to new high-cardinality labels.  
**What the interviewer is looking for:** Rapid triage, understanding of metric design, and safe rollback or containment choices.  
**Model answer:** 1) Identify the new or fastest-growing series and confirm whether labels such as IDs, paths, or pod-specific values exploded the cardinality. 2) Roll back or relabel the worst offenders quickly so the monitoring system stays alive. 3) Restore stability with retention, recording-rule, or sharding adjustments only after the root instrumentation problem is contained. 4) Add metric review gates so unsafe labels cannot reach production casually.

**Q: [Advanced] Customers report latency, but dashboards look green. How would you investigate?**
**Situation:** Core service metrics are within thresholds, yet support tickets describe slow or inconsistent user experience from a subset of clients.  
**What the interviewer is looking for:** Healthy skepticism, segmentation thinking, and use of multiple telemetry sources.  
**Model answer:** 1) Gather exact times, regions, customer segments, and request paths from support before assuming the dashboards are complete. 2) Compare synthetic checks, CDN or load balancer logs, and trace samples to see whether the issue is isolated by geography, client type, or dependency. 3) Look for blind spots such as missing percentiles, aggregation hiding one noisy backend, or metrics that exclude retries and timeouts. 4) Close the gap by adding telemetry where the investigation proves the current dashboard is not telling the full story.

**Q: [Advanced] Traces are sampled so aggressively that incident responders cannot find failing requests. What would you change?**
**Situation:** The tracing platform is affordable, but it is no longer useful for debugging rare failures or latency spikes.  
**What the interviewer is looking for:** Practical understanding of tracing economics, sampling strategy, and incident usability.  
**Model answer:** 1) Review whether the current design uses head-based sampling only and what kinds of traces are being lost. 2) Keep or prioritize traces for errors, slow requests, and key customer journeys while reducing coverage for repetitive healthy traffic. 3) Consider tail-based or hybrid sampling if the platform supports it and the diagnostic value justifies the extra complexity. 4) Tie the answer back to cost control by explaining how sampling policy should reflect debugging needs, not just storage savings.

## Post-Incident Scenarios

**Q: [Advanced] An outage was mitigated quickly with a rollback, and leadership wants to move on. How would you run the post-incident process?**
**Situation:** Service is healthy again, but nobody has yet written the timeline or identified why the bad change passed safeguards.  
**What the interviewer is looking for:** Commitment to learning, not just restoring service, and ability to preserve urgency after impact ends.  
**Model answer:** 1) Capture the timeline, responders, evidence, and exact mitigation steps while memories are fresh. 2) Run a blameless postmortem that separates the triggering change from the systemic gaps such as missing tests, unsafe rollout, or weak alerting. 3) Turn findings into owned action items with deadlines instead of vague improvement ideas. 4) Report both what worked well and what must change so the organization learns from the near miss.

**Q: [Advanced] Your team writes postmortem action items, but they rarely get completed. What would you do?**
**Situation:** The same classes of incidents keep returning, and postmortems are starting to feel performative.  
**What the interviewer is looking for:** Operational follow-through, prioritization, and process design that survives roadmap pressure.  
**Model answer:** 1) Make action items visible in the normal engineering tracking system with owners, due dates, and progress review. 2) Distinguish urgent tactical remediations from larger strategic work so leaders understand the cost and value of each. 3) Review overdue items in a recurring reliability forum and escalate when customer risk remains unaddressed. 4) Measure recurrence so teams can show whether postmortem work is reducing actual incident load.

**Q: [Advanced] After a major outage, executives want a customer-facing summary and an internal technical review. How do you handle both?**
**Situation:** Different audiences need different levels of detail, but both communications must stay consistent and credible.  
**What the interviewer is looking for:** Audience-aware communication, transparency, and discipline around facts versus speculation.  
**Model answer:** 1) Build one verified incident timeline first so every summary starts from the same facts. 2) For customers and executives, explain impact, duration, mitigation, and next steps in plain language without dumping internal jargon. 3) For internal teams, include the deeper technical chain of events, contributing factors, and preventive actions. 4) Be explicit about what is confirmed, what is still under investigation, and when more detail will be shared.

**Q: [Advanced] The same dependency failure has caused three incidents in six months. What would you recommend after the latest event?**
**Situation:** Each outage was mitigated, but the architecture still depends heavily on one fragile upstream service.  
**What the interviewer is looking for:** Systemic thinking, willingness to challenge architecture, and a focus on reducing recurrence.  
**Model answer:** 1) Quantify the cumulative customer and business impact of the repeated incidents to justify deeper change. 2) Propose structural mitigations such as caching, graceful degradation, fallback data paths, circuit breakers, or dependency diversification. 3) Update SLOs, alerting, and capacity assumptions to reflect the real dependency risk. 4) Make sure the recommendation includes ownership and a plan to verify the fix with drills or controlled failure testing.
