# SRE Core Concepts Q&A

## Basic

**Q: [Basic] What is SRE?**
SRE applies software engineering practices to operations and reliability work. The goal is to keep services dependable through automation, measured objectives, and disciplined incident response. Strong answers usually mention SLIs, SLOs, error budgets, and reducing toil.

**Q: [Basic] How is SRE different from DevOps?**
DevOps is a culture focused on collaboration and fast delivery, while SRE is a concrete operating model with explicit reliability practices. SRE teams usually use SLOs, error budgets, and automation to balance release velocity with production stability. Traditional operations often relies on manual work, but SRE tries to replace that work with code and self-service systems.

**Q: [Basic] What is an SLI?**
An SLI, or Service Level Indicator, is the metric that measures a user-relevant aspect of service behavior. Common examples are successful request rate, request latency, or job completion rate. A good SLI should reflect actual user experience instead of purely internal component health.

**Q: [Basic] What is the difference between an SLI, SLO, and SLA?**
An SLI is the measurement, such as the percentage of successful requests over 30 days. An SLO is the internal target for that measurement, such as 99.9% availability, and it guides engineering tradeoffs. An SLA is the external promise to customers and usually includes commercial or legal consequences if it is missed.

**Q: [Basic] How do you calculate an error budget?**
The error budget is simply 1 minus the SLO target over the chosen window. For a 99.9% monthly availability SLO, the budget is 0.1%, which is about 43.8 minutes of downtime in 30 days. The same concept can also be expressed as an allowed number of failed requests or failed transactions.

**Q: [Basic] What is toil?**
Toil is manual, repetitive, automatable work that scales linearly with service growth. Examples include restarting stuck jobs, rotating credentials by hand, and repeatedly handling the same noisy alerts. A common SRE guideline is to keep toil below about 50% of engineering time.

**Q: [Basic] Why are error budgets useful?**
Error budgets create a shared language between product, development, and operations teams. If reliability is healthy, teams can take more delivery risk, but if the budget is nearly exhausted, risky changes should slow down. This makes release decisions less emotional and more data-driven.

## Intermediate

**Q: [Intermediate] What should an error budget policy include?**
A good error budget policy defines who reviews budget health, what burn thresholds matter, and what actions happen at each threshold. It should clearly describe when to add review gates, when to freeze risky releases, and when to prioritize reliability work. The policy must be agreed before incidents happen so teams are not negotiating under pressure.

**Q: [Intermediate] What is burn rate alerting?**
Burn rate alerting measures how quickly a service is consuming its error budget relative to the sustainable rate. A burn rate of 2 means the service is spending budget twice as fast as planned, while 14.4 means the budget will disappear very quickly. It is more useful than a raw error threshold because it connects failures directly to the SLO window.

**Q: [Intermediate] Why use multi-window, multi-burn-rate alerts?**
Multi-window alerts compare a short window and a long window at the same time. The short window catches sharp outages, and the long window confirms that the issue is not just a brief spike or rollout blip. This pattern reduces false positives while still finding both fast and slow SLO burns.

**Q: [Intermediate] What is the difference between reliability and availability?**
Availability usually answers whether the service responded successfully at all, often as a percentage of successful requests. Reliability is broader and includes whether the system behaved correctly, consistently, and within acceptable latency or quality thresholds. A service can be available but still unreliable if it is consistently slow, inconsistent, or returning degraded results.

**Q: [Intermediate] What do MTTD, MTTR, and MTBF mean?**
MTTD is Mean Time To Detect, which measures how long it takes to notice a problem after it starts. MTTR is Mean Time To Repair or Resolve, which measures how long it takes to restore service after detection, and MTBF is Mean Time Between Failures, which describes how often repairable systems fail. Together they show whether you have a detection problem, a restoration problem, or a fundamental reliability problem.

**Q: [Intermediate] How do you improve MTTD?**
Improve MTTD by alerting on user-impacting signals, not just low-level infrastructure noise. Good dashboards, synthetic checks, blackbox probes, and ownership-aligned paging also help responders see the issue quickly. Detection improves most when alerts are high signal and clearly routed to the right team.

**Q: [Intermediate] How do you improve MTTR?**
Improve MTTR by making mitigation fast and predictable. Runbooks, safe rollback paths, feature flags, prebuilt dashboards, and practiced incident roles reduce time spent guessing during an outage. The biggest MTTR improvements usually come from standard response patterns rather than heroic debugging.

**Q: [Intermediate] What is capacity planning?**
Capacity planning is the process of forecasting demand and ensuring the system has enough headroom to meet performance and reliability goals. It usually combines historical growth, expected launches, seasonal traffic, and failure scenarios such as losing a zone. Good answers mention load testing, target utilization bands, and explicit safety margins.

**Q: [Intermediate] How do you choose realistic SLO targets?**
Realistic SLOs start with user expectations, business importance, and the current technical capability of the system. They should be ambitious enough to matter but not so unrealistic that teams ignore them. A common approach is to look at historical performance, critical user journeys, and the cost of making the target tighter.

**Q: [Intermediate] What is a critical user journey?**
A critical user journey is the end-to-end flow a user must complete to get value from the product. For an e-commerce site, that might include login, product search, add to cart, and checkout. SLOs are strongest when they map to these journeys rather than to isolated backend components.

## Advanced

**Q: [Advanced] What are the core principles of chaos engineering?**
Chaos engineering starts with a steady-state hypothesis about how the system should behave under normal conditions. Teams then introduce controlled failure, such as latency, instance loss, or dependency outages, and observe whether the hypothesis still holds. Good practice requires small blast radii, clear abort conditions, and measurable learning outcomes.

**Q: [Advanced] How do you run a safe chaos experiment in production?**
Start with a narrow scope, such as one service, one region, or a low-traffic slice, and define the exact signals that prove success or failure. Run the test during a staffed window, with rollback steps and alert suppression plans prepared in advance. The experiment is only successful if the team documents what broke, what held, and what will be improved.

**Q: [Advanced] What changes when you engineer reliability at scale?**
At scale, small inefficiencies become major reliability and cost issues, so standardization matters much more. Teams need consistent telemetry, automation, rollout patterns, dependency ownership, and production guardrails across many services. Reliability work shifts from fixing one-off incidents to building platforms and policies that prevent repeated classes of failure.

**Q: [Advanced] How should an SRE team be structured?**
There is no single structure, but healthy models usually separate product-specific operational ownership from broader platform reliability work. Some organizations embed SREs with product teams, while others keep a central SRE group that sets standards and handles critical services. The key is to keep ownership, escalation paths, and reliability responsibilities unambiguous.

**Q: [Advanced] How is SRE different from platform engineering?**
Platform engineering focuses on building paved roads, internal platforms, and self-service tooling for developers. SRE focuses on reliability outcomes, operational readiness, incident response, and policy mechanisms like SLOs and error budgets. In mature organizations the two functions work closely, but platform teams provide capabilities while SREs define and enforce reliability expectations.

**Q: [Advanced] How do you drive cross-team reliability improvements?**
Cross-team reliability work starts with shared visibility, such as common SLO reviews, incident trends, and dependency maps. It also needs agreed launch criteria, standardized runbooks, and clear owners for follow-up work that crosses service boundaries. The most effective approach is to make reliability a shared operating mechanism instead of a side request from one team.

**Q: [Advanced] How do you manage SLO discussions with product and business stakeholders?**
Stakeholders care about customer impact, revenue, and delivery speed, so SLO conversations should connect technical targets to those outcomes. Explain what tighter targets cost in engineering effort and infrastructure, and what looser targets risk in user trust or contractual exposure. Good SLO management is about negotiating tradeoffs transparently, not just declaring a number.

**Q: [Advanced] What should you do when a service repeatedly exhausts its error budget?**
Repeated budget exhaustion is a sign that the current operating model is not working. Teams should slow risky changes, analyze recurring failure patterns, and dedicate time to reliability fixes instead of just absorbing more incidents. If the service still cannot meet target after focused work, reevaluate the architecture or adjust the SLO based on real business requirements.

**Q: [Advanced] How do you measure and reduce toil over time?**
Measure toil explicitly by logging recurring operational tasks, time spent, frequency, and whether the work is automatable. Review that data regularly to prioritize the highest-volume and highest-risk manual work first. The best toil programs turn repeated pages, manual deploy steps, and repetitive diagnostics into tooling, automation, or self-service workflows.
