# Lab 01: L2 Triage and Escalation

- This lab practices real L2 response patterns instead of abstract theory.
- Each scenario includes triage flow, commands, expected findings, escalation decisions, and verification steps.
- Use the examples as both a training exercise and a ticket-handling reference.

## Lab objectives

- Run a structured triage process for production symptoms.
- Use the five questions to narrow the failing layer quickly.
- Decide whether L2 can resolve or must escalate to L3 or vendors.
- Document evidence so the next team does not repeat the same checks.

## Tooling assumed

- kubectl access to production and staging namespaces.
- Centralized logs with request IDs.
- Metrics dashboard showing latency, error rate, throughput, and saturation.
- Tracing dashboard.
- ServiceNow incident access.
- Read-only database diagnostics.

## Standard triage worksheet

1. Confirm the symptom with direct evidence.
2. Bound the impact by user, region, service, and timeframe.
3. Check recent changes and dependency health.
4. Eliminate layers from edge to dependency.
5. Apply the safest viable mitigation.
6. Verify recovery with technical and user-facing checks.
7. Document findings and decide whether to escalate.

```text
Incident note skeleton
Symptom:
Impact:
Start time / last known good:
Recent changes checked:
Evidence gathered:
Mitigation attempted:
Verification result:
Escalation decision and reason:
```

## Triage decision tree

```text
Is the symptom reproducible now?
├─ No -> collect evidence, check monitoring history, ask for timestamps, keep priority tied to business impact.
└─ Yes
   ├─ Is the impact broad or business critical?
   │  ├─ Yes -> open/raise incident priority, notify resolver leads, continue triage in parallel.
   │  └─ No -> continue standard triage.
   ├─ Did a recent change occur in the same window?
   │  ├─ Yes -> compare current vs previous state and consider rollback readiness.
   │  └─ No -> investigate dependencies and resource saturation.
   ├─ Is there a safe L2 mitigation?
   │  ├─ Yes -> execute with approval and verify.
   │  └─ No -> escalate with evidence package.
   └─ After mitigation, is user impact gone?
      ├─ Yes -> move to monitoring and follow-up actions.
      └─ No -> escalate severity and widen investigation.
```

## Scenario 1: Payment API 503s

- Business context: checkout payments are failing intermittently in production.
- Monitoring shows HTTP 503 from payment-api beginning at 14:05 UTC.
- Current estimate is 20 percent failed payment submissions.

### Five-question triage

1. What is failing? POST /v2/payments returns 503 for a subset of requests.
2. Who is affected? Checkout users in all regions, with higher failure in EU.
3. When did it start? 14:05 UTC, seven minutes after deployment revision 44.
4. What is the narrowest likely failure point? payment-api or a shared dependency such as database or token service.
5. What is the safest mitigation? Roll back revision 44 if evidence points to deployment-induced failure.

### Initial commands

```bash
kubectl get pods -n prod-payments -l app=payment-api
kubectl get svc,endpoints -n prod-payments payment-api
kubectl describe deployment payment-api -n prod-payments
kubectl rollout history deployment/payment-api -n prod-payments
kubectl logs deploy/payment-api -n prod-payments --since=15m | tail -120
```

### Expected observations

- Two of eight pods are failing readiness because downstream database checks exceed timeout.
- Logs show `HikariPool-1 - Connection is not available` and occasional 503 responses.
- Metrics show request latency increased before error rate increased.
- The database itself is healthy but connection acquisition time spiked after a config change lowered pool size.

### Elimination approach

1. Ingress is not the primary issue because healthy pods still answer and TLS is normal.
2. Payment application process is up, so this is not a startup failure.
3. Errors correlate with pool starvation, making the database access layer the tightest failing component.
4. The new deployment introduced a smaller maximum pool and lower acquisition timeout.

### Resolution path

```yaml
env:
  - name: DB_POOL_MAX_SIZE
    value: "15"
  - name: DB_POOL_CONNECTION_TIMEOUT_MS
    value: "3000"
```

1. Confirm the previous deployment used pool size 50 and timeout 10000 ms.
2. Roll back deployment revision 44 or reapply the previous ConfigMap value.
3. Restart only the affected pods after rollback to reload configuration cleanly.
4. Monitor request success rate, acquisition time, and queue depth for at least 15 minutes.

```bash
kubectl rollout undo deployment/payment-api -n prod-payments --to-revision=43
kubectl rollout status deployment/payment-api -n prod-payments
kubectl get pods -n prod-payments -l app=payment-api -w
```

### Verification

- 503 rate returns to baseline within five minutes.
- Database pool wait time falls under 100 ms.
- Checkout synthetic test succeeds three times consecutively.
- No further readiness probe failures are observed.

### Escalation rule for this scenario

- Escalate to L3 if rollback fails or if pool starvation continues after configuration correction.
- Escalate to DBA or vendor only if database saturation or engine-side errors are proven.

## Scenario 2: Login service high latency

- Business context: users can still log in, but the login page takes 8 to 15 seconds.
- Error rate is low, but p95 latency violates SLO and authentication timeouts are imminent.

### End-to-end debug map

| Layer | Question | Useful check |
| --- | --- | --- |
| Browser/edge | Is latency visible before reaching the app? | CDN timing and ingress access logs |
| Application | Are requests queued or blocked in worker threads? | Thread pool metrics and traces |
| Dependency | Is Redis, IdP, or database slow? | Dependency latency dashboards |
| Code path | Did a new auth step or retry loop appear? | Recent commits and feature flags |

### Commands and dashboards

```bash
kubectl top pod -n prod-auth -l app=login-service
kubectl logs deploy/login-service -n prod-auth --since=20m | tail -150
kubectl get hpa -n prod-auth login-service
kubectl describe deploy login-service -n prod-auth
```

### Trace-driven investigation

1. Open several slow traces for POST /login.
2. Compare a healthy 700 ms trace to a slow 12 s trace.
3. Observe that the longest span is a Redis session lookup with repeated retries.
4. Check Redis connection errors and latency metrics for the same window.

### Likely findings

- Application CPU is normal, but worker threads are occupied waiting on Redis.
- A network policy change caused packet loss to the Redis subnet in one node pool.
- Requests routed to pods on that node pool exhibit extreme latency.

### Resolution

1. Cordon or drain the affected nodes if allowed by operations policy.
2. Scale login-service to shift traffic away from the impacted node pool.
3. Engage platform networking team with node, subnet, and timing evidence.
4. If the policy change is confirmed, roll it back under emergency or approved operational change.

```bash
kubectl get pods -n prod-auth -l app=login-service -o wide
kubectl cordon <bad-node>
kubectl scale deploy/login-service -n prod-auth --replicas=12
```

### Verification

- p95 latency drops below SLO threshold.
- Redis dependency spans return to normal duration.
- No new packet-drop alerts appear on the affected subnet.

### Escalation rule for this scenario

- Escalate technically to platform networking when node or subnet behavior is implicated.
- Escalate to L3 if trace analysis reveals application retry storms or lock contention instead.

## Scenario 3: Batch job not completing

- Business context: nightly settlement job should finish by 03:00 UTC but remains running at 05:30 UTC.
- Downstream finance reports are delayed, but customer-facing APIs remain healthy.

### Investigation steps

1. Confirm whether the job is still processing or stuck.
2. Check last successful run and the amount of data processed today versus normal.
3. Inspect job logs for progress markers, retry loops, or deadlocks.
4. Check database locks, queue depth, and dependency latency.
5. Determine whether the batch can be safely restarted, resumed, or skipped.

```bash
kubectl get jobs -n prod-batch
kubectl describe job settlement-close -n prod-batch
kubectl logs job/settlement-close -n prod-batch --tail=200
kubectl get cronjob settlement-close -n prod-batch -o yaml
```

```sql
SELECT state, count(*)
FROM settlement_records
WHERE business_date = CURRENT_DATE - INTERVAL "1 day"
GROUP BY state;
```

### Likely findings

- The job is blocked waiting on a reporting table lock held by an ad hoc analyst query.
- Batch progress stopped at the same minute the lock appeared.
- No code defect is immediately visible; the issue is resource contention.

### Resolution options

- Work with the database team to terminate the blocking session if policy allows.
- Restart the batch only after confirming it is idempotent or restart-safe.
- If restart is unsafe, let the lock clear and confirm the job resumes automatically.

### Verification

1. Observe the blocking lock disappear.
2. Confirm batch processed record count begins rising again.
3. Validate completion status and downstream report generation.
4. Record whether a problem ticket is needed for recurring lock contention.

### Escalation rule for this scenario

- Escalate to L3 if the job logic hangs after the lock is removed.
- Escalate to database engineering if lock patterns recur or transaction design must change.

## Escalation decision matrix

| Condition | Stay in L2 | Escalate to L3 | Escalate to vendor/management |
| --- | --- | --- | --- |
| Known config mistake or failed rollout | Yes | Only if rollback fails | No |
| Code defect, memory leak, deadlock, or repeated crash with unknown cause | No | Yes | No |
| Managed service shows provider-side fault | No | Yes for coordination | Yes vendor |
| Severe business impact or contractual risk | Continue triage | Yes | Yes management |
| Unsafe mitigation or required production change outside policy | No | Yes | Maybe depending on risk |

## Lab closeout checklist

1. Update ServiceNow with root symptom, evidence, and mitigation.
2. Attach dashboard and trace links used in triage.
3. State whether the issue was configuration, deployment, dependency, or code related.
4. Create a problem record if the same pattern has occurred before.
5. Capture one prevention action for runbook or automation improvement.

## Shift handoff template

Use this handoff block when the issue crosses teams or shifts.

```text
Current priority:
Current impact:
Latest verified symptom:
What has been ruled out:
What changed recently:
Mitigation already attempted:
Open technical questions:
Next action owner:
Next update due:
Related incident/problem/change IDs:
```

## Scenario scoring rubric

Score each triage exercise from 1 to 5 on:
- symptom confirmation speed.
- impact assessment quality.
- evidence depth.
- mitigation safety.
- escalation quality.

## Verification drill

Before closing the lab, prove that you can answer these prompts for each scenario:
1. What was the narrowest point of failure?
2. Which signal identified the issue first?
3. What evidence justified the mitigation?
4. Why did the escalation path make sense?
5. What prevention action should be tracked after recovery?

Keep one dashboard link and one trace ID in every final note.
