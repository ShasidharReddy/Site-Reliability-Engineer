# Application Support L1/L2/L3/L4 Theory

- This module explains how support tiers collaborate during operational issues.
- It focuses on the practical boundary between application support and SRE.
- Examples assume Kubernetes-hosted services with centralized logs, metrics, traces, and ServiceNow.
- Every section is written to support both training and real incident execution.

## Learning outcomes

- Differentiate L1, L2, L3, and L4 ownership without ambiguity.
- Apply support SLAs and escalation triggers consistently.
- Perform L2 triage on configuration, deployment, and environment-specific issues.
- Understand what L3 and SRE teams own during production incidents and reliability work.
- Use a repeatable triage method built on five key questions and elimination logic.
- Debug applications from logs to metrics to traces to code.
- Investigate database, network, TLS, and dependency issues using safe evidence-first methods.
- Operate incident, problem, and change workflows in ServiceNow.
- Communicate clearly in war rooms, stakeholder updates, and customer notices.
- Escalate to engineering, management, or vendors with the right evidence package.

## Support tier model

| Tier | Primary role | Typical actions | Default SLA focus | Escalate when |
| --- | --- | --- | --- | --- |
| L1 | Intake and first validation | Collect facts, check known errors, route correctly | Fast acknowledgement | Issue is not covered by KB or impact is broad |
| L2 | Application support and operational triage | Check config, deployments, health, dependencies, safe mitigations | Restore service or isolate failing layer | Code, design, or systemic reliability issue is suspected |
| L3 | Engineering and SRE deep investigation | Mitigate incidents, analyze reliability, identify root cause | Mitigation speed and durable fixes | Problem requires product/vendor/platform owner |
| L4 | Vendor or external provider resolution | Analyze proprietary platform defects or managed service failures | Contractual response and fix times | Formal support engagement or workaround fails |

- The goal of the tier model is not bureaucracy; it is controlled flow of information and risk.
- Every tier should leave better evidence than it received.
- Escalation should increase problem-solving capability, not simply move pressure.
- Misrouted incidents waste SLA time and create duplicate communication channels.

## L1 support tier

- L1 is the front door for users, monitoring, and business operations.
- L1 confirms whether the symptom is real, current, and reproducible.
- L1 validates user identity, affected business service, tenant, region, and time of failure.
- L1 searches knowledge articles, known errors, maintenance notices, and active major incidents.
- L1 performs approved actions such as password reset, browser cache guidance, or standard restart request routing.
- L1 must avoid speculative root cause statements.
- L1 must not downgrade priority simply because the technical cause is unknown.
- L1 must capture screenshots, request IDs, usernames, timestamps, and exact error text.

### Typical L1 SLA expectations

| Work item | Response target | Expected L1 result |
| --- | --- | --- |
| User ticket | 10-15 minutes | Validate and route or resolve with known procedure |
| Monitoring-generated incident | 5-10 minutes | Confirm alert, attach impact statement, assign resolver group |
| Major outage call | Immediate | Open incident bridge, notify on-call distribution list |

### L1 escalation triggers

- No documented L1 action exists for the symptom.
- Multiple users or a business-critical workflow are affected.
- There is evidence of production outage, data loss, security risk, or deadline breach.
- A workaround is unavailable or unsafe.
- The issue maps to application behavior rather than user guidance.

## L2 support tier

- L2 owns application-aware triage and operational troubleshooting.
- L2 understands service topology, environment variables, feature flags, deployment patterns, and runbooks.
- L2 works most effectively when it can inspect logs, dashboards, traces, and deployment metadata.
- L2 should solve incidents caused by misconfiguration, failed rollout, expired credentials, disabled schedulers, or environment-specific drift.
- L2 should not patch production code unless local policy explicitly places that authority in the support team.
- L2 is accountable for safe mitigation, precise documentation, and clear escalation to L3 when deeper engineering work is required.

### L2 responsibilities in detail

- Validate that the issue is still active and measure user impact.
- Review recent changes to deployments, ConfigMaps, secrets, certificates, DNS, jobs, and dependent services.
- Compare healthy and unhealthy environments to isolate drift.
- Check readiness probes, liveness probes, autoscaling, pod events, and load balancer health.
- Investigate application configuration errors, credential mismatches, and environment-specific overrides.
- Handle deployment issues such as bad image tags, stuck rollouts, probe misconfiguration, failed migrations, and startup exceptions.
- Investigate environment-specific problems such as production-only traffic patterns, firewall changes, higher concurrency, or larger datasets.
- Apply safe mitigations such as rollback, scale-out, restart with approval, draining a bad node, or disabling a failing feature flag.
- Preserve evidence for L3 through ticket notes, timestamps, screenshots, log snippets, and dashboard links.

### L2 SLA examples

| Incident class | Acknowledge | Target next update | Escalate to L3 by |
| --- | --- | --- | --- |
| P1 production outage | 15 minutes | 15 minutes | Immediately if no clear mitigation in first 15-30 minutes |
| P2 major degradation | 30 minutes | 30 minutes | Within 60 minutes if service risk persists |
| P3 moderate user impact | 4 business hours | 4 business hours | Same shift if diagnosis stalls |
| P4 low impact request | 1 business day | As agreed | Only if engineering change is required |

### L2 escalation triggers

- Multiple services are failing and a systemic platform issue is suspected.
- There is evidence of code defect, memory leak, thread deadlock, or race condition.
- Database schema, query plan, or service code change is needed to restore stability.
- Mean time to recovery is threatened because current mitigations do not reduce impact.
- A post-incident corrective action will require engineering design or automation changes.

## L3 support tier and SRE responsibilities

- L3 owns deep technical analysis, production incident leadership, and durable reliability improvements.
- L3 is often staffed by software engineers, SREs, platform engineers, or senior application specialists.
- L3 investigates issues that require source-level understanding, architecture knowledge, or systemic reliability changes.
- During live incidents, L3 focuses on mitigation first, then containment, then root cause, then prevention.

### Core L3 responsibilities

- Lead or support major incident response for application and platform failures.
- Perform advanced production debugging using traces, profilers, heap dumps, thread dumps, and code review.
- Identify root cause, contributing factors, and failed controls.
- Design durable fixes such as code changes, capacity adjustments, circuit breakers, retry tuning, or alert improvements.
- Improve reliability engineering practices including SLOs, error budgets, runbooks, dashboards, synthetic checks, and chaos validation.
- Partner with L2 to refine escalation criteria and reduce repeat tickets.

### SRE-specific view of L3

- SRE work is not limited to fixing incidents; it is about reducing future incident load.
- SRE measures service health using availability, latency, throughput, error rate, and saturation indicators.
- SRE treats every major incident as feedback on architecture, toil, observability, and change safety.
- Root cause is rarely one line of code; it often includes trigger, weakness, failed detection, and delayed response.

### L3 escalation triggers toward L4 or leadership

- A managed database, SaaS dependency, or cloud load balancer shows a provider-side fault.
- Vendor documentation confirms a product defect or version-specific regression.
- Business risk exceeds acceptable thresholds and executive decision is required.
- Regulatory or customer contractual exposure requires management oversight.

## L4 support tier

- L4 represents the external party that owns a proprietary platform or managed service.
- Examples include cloud providers, database vendors, payment gateways, identity providers, and packaged software vendors.
- L4 should receive a complete evidence package so time is not lost on basic validation.
- Internal teams remain accountable for business communication even when L4 is engaged.

### Evidence package for vendor escalation

- Clear business impact and current severity.
- Timeline of first occurrence, detection time, and mitigation attempts.
- Affected regions, tenants, APIs, or customer segments.
- Request IDs, trace IDs, transaction IDs, and sanitized logs.
- Version numbers, configuration references, certificate fingerprints, and screenshots.
- Statement of why an internal root cause is unlikely based on completed checks.

## Triage methodology for L2 and L3

- Good triage reduces uncertainty before it increases activity.
- The responder should ask the same first five questions on almost every incident.

### The five triage questions

1. What exactly is failing, and what is still working?
2. Who is affected, how many users are affected, and in which environment or region?
3. When did the issue start, and what changed shortly before it started?
4. Which component or dependency is the narrowest shared point of failure?
5. What is the safest available mitigation right now?

### Elimination approach

- Start broad, then narrow the failing layer: client, edge, service, dependency, data, or platform.
- Compare healthy versus unhealthy requests to identify what is common and what differs.
- Rule out false correlations by checking timestamps, change windows, and baseline metrics.
- Test one hypothesis at a time and capture evidence before moving on.
- Avoid changing multiple variables simultaneously during a live incident.

### Impact assessment

- Measure customer impact in terms the business understands: failed checkouts, blocked logins, missed settlements, or delayed reports.
- Separate symptom severity from user count; a small number of executive users can still create high business urgency.
- Confirm whether there is data corruption, only latency, only retries, or a complete outage.
- Check whether a workaround exists and whether it is sustainable.

### Triage evidence checklist

- Exact error message or HTTP status.
- First known bad time and timezone.
- Last known good time.
- Affected business service, API, host, pod, region, and version.
- Recent deployment, config, secret, or network change.
- Links to logs, metrics, traces, and ticket record.

```bash
kubectl get pods -n prod -o wide
kubectl get events -n prod --sort-by=.lastTimestamp | tail -30
kubectl rollout history deployment/myapp -n prod
kubectl logs deploy/myapp -n prod --since=15m | tail -100
```

## Application debugging pattern: logs to metrics to traces to code

- Use logs first to see explicit failures, stack traces, retries, or dependency errors.
- Use metrics second to quantify scope, duration, latency, error rate, and saturation.
- Use traces third to locate the slow span or failing downstream hop.
- Use code or configuration last to confirm why the observed behavior is possible.
- This order prevents responders from diving into code before proving the failing path.

### Logs

- Search by correlation ID, request ID, tenant, or endpoint.
- Check both current and previous container logs when restart loops occur.
- Look for startup exceptions, authentication failures, timeout chains, and dependency-specific error codes.

```bash
kubectl logs pod/payment-api-7c9b -n prod-payments --tail=200
kubectl logs pod/payment-api-7c9b -n prod-payments --previous --tail=200
kubectl logs deploy/payment-api -n prod-payments --since=10m | grep 'trace_id=' | tail -50
```

### Metrics

- Confirm whether latency, error rate, CPU, memory, GC pauses, or queue depth moved before the incident.
- Use percentiles rather than averages for latency analysis.
- Correlate service metrics with dependency metrics to avoid blaming the wrong layer.

### Traces

- Identify the span with the longest duration or terminal error.
- Compare slow and fast traces for the same operation.
- Check whether failures originate from database calls, downstream APIs, or internal locks.

### Code and config review

- Review recent changes, feature flags, timeout values, retry counts, and circuit breaker thresholds.
- Validate that production configuration matches tested expectations.
- Do not assume the latest code change is the cause until logs and metrics support that conclusion.

## Database debugging patterns

- Database symptoms often appear as application errors, so responders must connect the two views.
- The most common patterns are slow queries, connection pool exhaustion, deadlocks, and replication lag.

### Slow query investigation

- Identify which endpoint or job issues the slow query.
- Check whether latency is new or simply reached a traffic threshold.
- Review execution plans, index usage, row counts, and parameter patterns.

```sql
SELECT query, calls, total_exec_time, mean_exec_time
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

### Connection pool exhaustion

- Symptoms include request timeouts, "could not obtain connection" errors, and rising wait time.
- Check pool size, active connections, idle connections, and long-running transactions.
- Pool exhaustion can be caused by leaks, downstream slowness, or traffic spikes.

```bash
kubectl exec -n prod deploy/orders-api -- printenv | grep DB_
kubectl top pod -n prod -l app=orders-api
```

### Deadlock investigation

- Look for deadlock errors in application logs and database engine logs.
- Capture the conflicting statements and lock order.
- Confirm whether code changes introduced a new transaction sequence.

```sql
SHOW ENGINE INNODB STATUS;
SELECT * FROM pg_locks WHERE NOT granted;
```

### Replication lag

- Read-after-write failures, stale dashboards, or delayed jobs often indicate replication lag.
- Check primary-to-replica lag, apply queue length, and replica CPU or I/O saturation.
- Understand whether the application reads from replicas for the affected workflow.

```sql
SELECT now() - pg_last_xact_replay_timestamp() AS replica_lag;
```

### Database verification steps

1. Confirm application error rate drops after mitigation.
2. Verify pool wait time and query latency return to baseline.
3. Check replication lag returns within accepted threshold.
4. Record whether a schema or code fix is still required.

## Network debugging patterns

- Network issues must be classified by layer to avoid chasing the wrong team.
- L4 issues affect TCP and transport connectivity.
- L7 issues affect HTTP routing, headers, session behavior, or application gateway features.

### L4 versus L7 examples

| Symptom | Likely layer | Typical indicators | First checks |
| --- | --- | --- | --- |
| Connection refused | L4 or service listener | No process listening or firewall reject | Pod listening port, service targetPort, security rules |
| TLS handshake failure | L4/L7 boundary | Certificate mismatch or unsupported cipher | Ingress cert, trust chain, SNI, expiry |
| 502 Bad Gateway | L7 proxy to upstream | Ingress cannot reach healthy backend | Endpoints, readiness, upstream timeout |
| 404 from edge only | L7 routing | Host/path rule mismatch | Ingress route, rewrite rules, host header |

### Load balancer health

- Confirm that backends are registered and passing health checks.
- Check whether health endpoints depend on downstream systems unnecessarily.
- Inspect readiness probe failures, node health, and endpoint slices.

```bash
kubectl get svc,ep,endpointslices -n prod | grep payment-api
kubectl describe ingress checkout -n prod-web
kubectl get pods -n prod-payments -l app=payment-api -o wide
```

### TLS investigation

- Verify certificate expiry, common name or SAN coverage, and full chain presentation.
- Check whether the client trusts the issuer and whether mTLS certificates were rotated together.
- Confirm SNI and host headers match the served certificate.

```bash
openssl s_client -connect api.example.com:443 -servername api.example.com </dev/null
kubectl get secret ingress-tls -n prod-web -o yaml
```

## ServiceNow incident management

- ServiceNow is the operational record of what happened, who owns the incident, and how SLA is being managed.
- Priority should be set using published impact and urgency criteria, not personal intuition.
- Work notes must tell the story of investigation and mitigation in chronological order.

### Priority matrix

| Impact x Urgency | High urgency | Medium urgency | Low urgency |
| --- | --- | --- | --- |
| High impact | P1 | P2 | P3 |
| Medium impact | P2 | P3 | P4 |
| Low impact | P3 | P4 | P4 |

### SLA breach prevention

- Acknowledge quickly and set the ticket to the correct assignment group early.
- Add a next update deadline to the work notes or bridge chat.
- Reassign only after contacting the next resolver group when severity is high.
- Use On Hold only with a documented reason such as waiting for customer, vendor, or approved change window.
- Create follow-up tasks before shift handoff so ownership is explicit.

### Problem management

- Create a problem record when incidents repeat, root cause is unknown, or a workaround is being reused.
- A problem record should capture recurring pattern, affected services, business risk, and known workaround.
- Known error articles and permanent fixes should reference the problem record.

## Change management

- Operational fixes must align with change policy even during pressure.
- Standard changes are pre-approved, low-risk, and repeatable.
- Normal changes require risk assessment, peer review, scheduling, and approval through the normal workflow.
- Emergency changes are used only when restoring service cannot wait for normal lead time.

### Change categories

| Type | Use case | Approval pattern | Examples |
| --- | --- | --- | --- |
| Standard | Low-risk repeat action | Pre-approved template | Routine certificate reload, known scaling action |
| Normal | Planned production change | Risk review and CAB or delegated approval | Application release, config update, schema change |
| Emergency | Urgent change to restore service or reduce severe risk | Expedited approval with retrospective review | Rollback, hotfix, failover |

### CAB process

1. Submit the change with implementation plan, validation plan, backout plan, and risk statement.
2. Map the change to correct service and environment.
3. Review dependencies, blackout windows, and customer commitments.
4. Obtain CAB or delegated approval for normal changes.
5. Execute during approved window with a named implementer and verifier.
6. Document results, deviations, and closure evidence.

## Communication during incidents

- Technical work fails without disciplined communication.
- Every major incident needs one owner for command, one for technical lead, and one for communications when possible.

### War room protocols

- State incident commander, technical lead, scribe, and communications owner at the start.
- Use short updates with timestamp, observation, action, and outcome.
- Do not let multiple people make production changes without explicit acknowledgement.
- Capture decisions, rejected hypotheses, and next checkpoints.

### Customer communication

- Explain impact in user terms, not internal jargon.
- State what is affected, what is not affected, and whether a workaround exists.
- Never promise a recovery time without technical confirmation.

### Stakeholder updates

- Executives need business impact, mitigation status, ETA confidence, and next update time.
- Support leaders need current queue impact, staffing needs, and handoff risks.
- Engineers need current hypothesis, evidence gaps, and approved change path.

```text
Update template
Time: 14:35 UTC
Current impact: Checkout failures reduced from 20% to 3% after rollback of payment-api.
Current action: Team is validating database connection reuse on two remaining slow pods.
Risk: Retry queue is elevated but draining.
Next update: 14:50 UTC.
```

## Escalation procedures

### Technical escalation

- Escalate technically when deeper product, platform, or code expertise is required.
- Send a concise summary: symptom, impact, timeline, actions tried, evidence, and requested help.
- Include commands run, dashboards checked, and mitigations applied.

### Management escalation

- Escalate to management when business risk, compliance exposure, or communication complexity increases.
- Examples include breach of contractual SLA, major customer impact, prolonged outage, or need for cross-team staffing.
- Management escalation should never replace technical escalation; both may be required in parallel.

### Vendor escalation

- Open vendor cases early when evidence points to managed service, licensed product, or SaaS dependency failure.
- Attach sanitized logs, timestamps, affected resource identifiers, and reproduction details.
- Track vendor case ID in the incident record and include vendor response target in the timeline.

### Escalation handoff template

```text
Service: login-api production
Impact: 35% of EU users see login times above 12 seconds; no data loss observed.
Start time: 09:12 UTC; last known good 09:05 UTC.
What changed: deployment revision 118 and Redis parameter group update.
Evidence: p95 latency jump, thread pool saturation on two pods, Redis connect timeout spans.
Actions taken: scaled pods from 6 to 10, rollback tested in canary, issue persists.
Requested help: L3 analysis of thread usage and Redis client configuration.
```

## Operational checklists

### L2 first 15 minutes checklist

1. Confirm symptom with at least one direct and one synthetic check.
2. Measure impact and assign preliminary priority.
3. Check recent deployments, config, certificate, and dependency status.
4. Gather logs, metrics, and traces for the same time window.
5. Apply one safe mitigation if available.
6. Update ServiceNow and notify required stakeholders.

### L3 first 30 minutes checklist

1. Stabilize service with rollback, failover, scaling, traffic shaping, or feature disablement.
2. Protect data integrity before chasing latency improvements.
3. Assign owners for investigation threads such as application, database, network, and external dependency.
4. Decide whether emergency change or vendor escalation is required.
5. Capture a precise incident timeline for later root cause review.

### Post-incident review prompts

- What was the trigger?
- What technical weakness allowed the trigger to become user impact?
- Which detector noticed the issue first and was it fast enough?
- Which action restored service and why?
- What permanent control will reduce recurrence?
