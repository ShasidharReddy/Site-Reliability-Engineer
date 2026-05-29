# SRE Core Concepts Q&A

**Q1: What is SRE and how does it differ from DevOps/traditional ops?**
SRE applies software engineering to operations. Key differentiator: SREs write code to eliminate operational work. Traditional ops reacts manually; SRE proactively engineers reliability with SLOs and error budgets. DevOps is a culture/philosophy; SRE is a specific job function with defined practices from Google's SRE book.

**Q2: What is the difference between SLI, SLO, and SLA?**
SLI (Service Level Indicator): the measurement — e.g., % of requests returning 2xx. SLO (Service Level Objective): your internal target for that SLI — e.g., 99.9% availability over 30 days. SLA (Service Level Agreement): business contract with customers including penalties. SLOs are tighter than SLAs so you catch problems before breaching customer commitments.

**Q3: How do you calculate an error budget?**
Error budget = 1 - SLO_target. For 99.9% SLO over 30 days: budget = 0.1% = 43.8 minutes of allowed downtime. Or expressed as requests: 0.1% × total monthly requests = allowed failures. When budget is healthy, ship features. When exhausted, freeze features and focus on reliability.

**Q4: What is multi-window burn rate alerting?**
Instead of a single threshold, compare error burn rate over two time windows simultaneously. Critical: error ratio > 14.4x sustainable rate for both last 5m AND 1h (will exhaust budget in ~2h). Warning: error ratio > 6x for both 30m AND 6h. This catches both sudden big outages (fast burn) and chronic degradation (slow burn) with few false positives.

**Q5: What is toil? How much is acceptable?**
Toil is manual, repetitive, automatable work that scales linearly with service growth: restarting pods, rotating certs, manual deploys, acknowledging false alerts. SREs should spend at most 50% on toil. Above 50% = burnout and declining reliability. The other 50% is engineering work that permanently improves systems.

**Q6: What are the 4 Golden Signals?**
1. Latency: how long requests take (always measure separately for success vs failure).
2. Traffic: demand on the system (RPS, QPS, transactions/sec).
3. Errors: rate of failed requests (explicit 5xx + implicit timeouts/wrong content).
4. Saturation: how full the system is (CPU %, memory %, queue depth, disk %).

**Q7: Explain the SRE error budget policy.**
When budget >50%: ship freely. When 25-50%: add review gates, no risky changes. When <25%: freeze features, reliability sprint. When 0%/breached: full freeze, mandatory postmortem, recovery plan required. This policy must be agreed BEFORE an incident, not negotiated under pressure.

**Q8: What is chaos engineering?**
Proactively injecting failures (pod kills, network latency, disk full) in a controlled way to find weaknesses before they cause real incidents. Process: form hypothesis ("system X survives losing service Y"), inject failure, measure impact vs SLO, fix weaknesses found. Tools: Chaos Mesh, LitmusChaos, Istio fault injection.

**Q9: How do you measure toil?**
Track weekly: task name, time spent, automatable (Y/N), effort to automate. Rule: if automation effort < 4× current monthly toil cost, automate it. Track toil percentage per sprint. Report to leadership: "X% of SRE time is toil, here is the roadmap to reduce it."

**Q10: What is an SRE's relationship with the development team?**
SREs act as reliability consultants and gatekeepers. They define SLOs jointly with product/dev, review architectures for reliability, set reliability requirements for launches (SLO targets, runbooks, dashboards, alerts must exist before launch). They also handle on-call escalations from dev teams and provide reliability guidance. The error budget creates a shared incentive: dev wants to ship, SRE wants reliability — the budget balances both.

**Q11: Describe your approach to capacity planning.**
1. Measure current utilization (CPU, memory, throughput, latency at p95/p99).
2. Project demand: historical growth rate + product roadmap + upcoming events.
3. Target 50-70% utilization (headroom for spikes + safety margin).
4. Cloud: use HPA + cluster autoscaler for dynamic scaling, right-size with VPA recommendations.
5. Run load tests before major events to validate capacity assumptions.
6. Review quarterly and after major traffic events.

**Q12: What is a CUJ (Critical User Journey)?**
A CUJ is the sequence of steps a user takes to accomplish a key task. Example: user logs in → searches → adds to cart → checks out. SLIs should map to CUJs: if any step in the journey fails or is slow, the user experience is degraded. SLOs for Tier 1 services should cover every step of critical CUJs.

**Q13: How do you handle a service that keeps breaching its SLO?**
1. Verify the SLO is set correctly (not aspirational, based on actual capability).
2. Run postmortems for each incident and track action item completion.
3. Look for patterns: same root cause? Same time of day? Same code path?
4. Error budget policy kicks in: freeze features until reliability improves.
5. Reliability sprint: the SRE and dev team focus exclusively on the top reliability issues.
6. If after 2 quarters still breaching: re-evaluate if the SLO target is achievable or if the service needs re-architecting.

**Q14: What is blameless postmortem culture?**
Blameless postmortems assume humans make mistakes and that the system should be resilient to single human errors. Instead of "Alice caused the outage," we say "the deployment process allowed a misconfigured change to reach production without detection." This builds trust: engineers report near-misses and errors without fear of punishment. Blame creates fear; fear creates hidden problems; hidden problems create worse outages.

**Q15: What's the difference between MTTR, MTTD, and MTTF?**
MTTD (Mean Time To Detect): avg time from failure to alert firing. Improve with better monitoring coverage. MTTR (Mean Time To Resolve): avg time from detection to resolution. Improve with runbooks, automation, better dashboards. MTTF (Mean Time To Failure): avg time between failures. Improve with chaos engineering, better architecture, redundancy. MTBF = MTTF + MTTR (Mean Time Between Failures, for repairable systems).
