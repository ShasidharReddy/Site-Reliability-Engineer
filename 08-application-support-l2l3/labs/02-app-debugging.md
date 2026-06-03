# Lab 02: Application Debugging

## Lab goals

This lab builds practical debugging muscle for:
- application startup failures.
- memory leak investigation.
- thread deadlock analysis.
- database connection pool exhaustion.
- TLS certificate issues.
- configuration drift identification.

## General approach

For every issue in this lab:
1. confirm the symptom.
2. identify the failing layer.
3. collect evidence before changing anything.
4. apply the least risky mitigation.
5. verify with logs, metrics, and user checks.
6. document the root cause and prevention step.

## Useful baseline commands

```bash
kubectl get pods -A
kubectl describe pod <pod> -n <namespace>
kubectl logs <pod> -n <namespace> --since=15m
kubectl logs <pod> -n <namespace> --previous --tail=200
kubectl top pod <pod> -n <namespace>
kubectl exec -n <namespace> <pod> -- printenv | sort
kubectl get deploy <app> -n <namespace> -o yaml
```

---

## Scenario 1: Application startup failure debugging

### Situation

A new deployment of `orders-api` never becomes ready.
Pods enter `CrashLoopBackOff`.
The previous version was healthy.
Users see 503 from the ingress because there are no ready endpoints.

### Step 1: Confirm rollout state

```bash
kubectl rollout status deployment/orders-api -n prod-orders
kubectl get pods -n prod-orders -l app=orders-api
kubectl get endpoints orders-api -n prod-orders
```

### Step 2: Inspect pod events and previous logs

```bash
kubectl describe pod <orders-pod> -n prod-orders
kubectl logs <orders-pod> -n prod-orders --previous --tail=200
kubectl logs <orders-pod> -n prod-orders --tail=200
```

### Common startup failure causes

- missing secret or ConfigMap key.
- invalid environment variable.
- migration failure.
- port mismatch between container and probe.
- missing filesystem permission.
- failed TLS trust check to dependency at startup.
- unsupported JVM option.

### Step 3: Compare new and previous revisions

```bash
kubectl rollout history deployment/orders-api -n prod-orders
kubectl get rs -n prod-orders -l app=orders-api
kubectl get deploy orders-api -n prod-orders -o yaml | sed -n '1,240p'
```

### Step 4: Check probes and startup dependencies

```yaml
startupProbe:
  httpGet:
    path: /actuator/health/startup
    port: 8080
  failureThreshold: 30
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: /actuator/health/readiness
    port: 8080
```

Questions:
- does the app require database access during startup?
- is the probe path still valid?
- was the container port changed?
- are secrets mounted where the app expects them?

### Example finding

`orders-api` now expects `DB_SSL_ROOT_CERT`.
The variable exists in staging.
It was not added to production secret.
Startup fails during datasource initialization.

### Mitigation

- pause the rollout.
- restore last working revision if impact exists.
- fix secret or manifest through approved change.

```bash
kubectl rollout pause deployment/orders-api -n prod-orders
kubectl rollout undo deployment/orders-api -n prod-orders
```

### Verification

- pods become ready.
- endpoints are populated.
- ingress 503 stops.
- startup logs show successful datasource initialization.

---

## Scenario 2: Memory leak investigation

### Situation

A Java service called `pricing-engine` restarts every 8-12 hours.
Memory steadily climbs after each restart.
CPU is moderate.
Error rate rises shortly before the restart.

### Step 1: Confirm growth pattern

Look for:
- sawtooth growth with normal GC recovery.
- monotonic growth with no meaningful drop.
- growth correlated to traffic spikes.
- growth correlated to a single tenant or feature.

Example PromQL ideas:

```text
container_memory_working_set_bytes{namespace="prod-pricing",pod=~"pricing-engine-.*"}
rate(container_oom_events_total{namespace="prod-pricing",pod=~"pricing-engine-.*"}[1h])
```

### Step 2: Check JVM or runtime signals

```bash
kubectl exec -n prod-pricing deploy/pricing-engine -- jcmd 1 GC.heap_info
kubectl exec -n prod-pricing deploy/pricing-engine -- jcmd 1 VM.flags
kubectl exec -n prod-pricing deploy/pricing-engine -- jstat -gc 1s 5
```

### Step 3: Capture a heap artifact safely

Write evidence into a repository-local example folder name for the lab.
Do not use system temp paths.

```bash
kubectl exec -n prod-pricing <pricing-pod> -- \
  jcmd 1 GC.heap_dump /app/artifacts/pricing-engine.hprof
kubectl exec -n prod-pricing <pricing-pod> -- ls -lh /app/artifacts
```

### Step 4: Compare heap suspects

Common memory leak sources:
- unbounded cache.
- retained request objects.
- thread-local misuse.
- listener or callback accumulation.
- unclosed streams.
- metrics label cardinality explosion.

### Step 5: Review logs for leak hints

```bash
kubectl logs -n prod-pricing deploy/pricing-engine --since=2h | \
  grep -Ei 'OutOfMemory|GC overhead|cache|retained|allocator'
```

### Example finding

A new feature caches price rules by user ID.
The cache has no eviction policy.
The production user base is much larger than staging.
Objects accumulate over three days until pods restart.

### Mitigation options

- reduce cache size via config if supported.
- disable the feature flag.
- scale out to reduce per-pod cardinality.
- restart pods only as a temporary mitigation.

### Permanent fix expectations for L3

- bounded cache with TTL or maximum size.
- heap allocation dashboard.
- alert on abnormal growth slope.
- test with production-like cardinality.

### Verification

- memory returns to expected sawtooth pattern.
- GC pause time reduces.
- restart frequency stops.
- no new OOMKilled events occur.

---

## Scenario 3: Thread deadlock analysis

### Situation

A payment settlement service is up.
Health checks pass.
Users experience hanging requests.
CPU is low.
Thread count is high.
No clear exception appears.

### Signals that suggest deadlock or severe contention

- requests hang until timeout.
- few or no errors in logs.
- CPU lower than expected.
- thread pool active count is high but throughput is low.
- thread dump shows threads waiting on each other.

### Step 1: Capture thread dumps

```bash
kubectl exec -n prod-settlement deploy/settlement-api -- \
  jcmd 1 Thread.print > /Users/shasidharreddy_mallu/Site-Reliability-Engineer/08-application-support-l2l3/thread-dump-example.txt
```

The above path is a lab example only.
In real response, store evidence in an approved operational location.
After review, remove any temporary artifact you created.

### Alternative without writing inside the repo

```bash
kubectl exec -n prod-settlement deploy/settlement-api -- jcmd 1 Thread.print
```

### Step 2: Look for deadlock indicators

Search for:
- `Found one Java-level deadlock`.
- many threads blocked on the same monitor.
- executor threads waiting on downstream futures.
- request threads waiting on cache refresh lock.

### Step 3: Correlate with code or deploy change

```bash
kubectl rollout history deployment/settlement-api -n prod-settlement
kubectl logs -n prod-settlement deploy/settlement-api --since=30m | \
  grep -Ei 'lock|blocked|executor|future|timeout'
```

### Example finding

Two synchronized methods acquired locks in opposite order after a recent release.
Deadlock occurs under concurrent settlement retries.

### Mitigation

- shift traffic away from the affected pod if possible.
- restart pod as temporary relief.
- rollback release if issue reproduces.
- notify L3 because a code fix is required.

```bash
kubectl delete pod <settlement-pod> -n prod-settlement
kubectl rollout undo deployment/settlement-api -n prod-settlement
```

### Verification

- request throughput returns.
- thread dump no longer shows deadlock.
- p95 latency normalizes.
- retried settlements complete without hang.

---

## Scenario 4: Database connection pool exhaustion

### Situation

`customer-api` returns occasional 500 and 503.
Logs mention connection pool timeouts.
Database CPU is not saturated.
This is an application-side connection management problem until proven otherwise.

### Step 1: Check pool metrics

```bash
kubectl exec -n prod-customer deploy/customer-api -- \
  curl -s http://localhost:8080/actuator/metrics/hikaricp.connections.active
kubectl exec -n prod-customer deploy/customer-api -- \
  curl -s http://localhost:8080/actuator/metrics/hikaricp.connections.pending
kubectl exec -n prod-customer deploy/customer-api -- \
  curl -s http://localhost:8080/actuator/metrics/hikaricp.connections.max
```

### Step 2: Inspect logs

```bash
kubectl logs -n prod-customer deploy/customer-api --since=20m | \
  grep -Ei 'pool|connection|timeout|transaction'
```

### Step 3: Check DB activity

```sql
SELECT pid,
       usename,
       application_name,
       state,
       wait_event_type,
       wait_event,
       now() - query_start AS runtime,
       query
FROM pg_stat_activity
WHERE datname = 'customerdb'
ORDER BY query_start;
```

### Common causes

- connection leak in one code path.
- slow SQL holding connections too long.
- pool max size reduced by config drift.
- traffic burst exceeds pool sizing assumptions.
- transaction opened before remote call and closed too late.

### Example finding

A new export endpoint starts a transaction.
It then calls an external file service before committing.
Each request holds a DB connection for 40 seconds.
Pool saturates under low concurrency.

### Mitigation

- disable the export endpoint temporarily.
- reduce concurrency.
- increase pool size only if DB capacity allows.
- escalate to L3 for code correction.

### Verification

- pending connections drop.
- request failures stop.
- DB sessions no longer show long idle-in-transaction state.

---

## Scenario 5: TLS certificate issues

### Situation

A service worked yesterday.
Today it fails when calling a partner API.
Logs show `handshake_failure` and `PKIX path building failed`.
Only production is affected.

### Step 1: Validate certificate chain externally

```bash
openssl s_client -connect partner.example.com:443 -servername partner.example.com -showcerts
curl -vk https://partner.example.com/health
```

### Step 2: Validate from the pod

```bash
kubectl exec -n prod-integrations deploy/integration-api -- \
  curl -vk https://partner.example.com/health
kubectl exec -n prod-integrations deploy/integration-api -- \
  keytool -list -keystore /opt/app/truststore.jks -storepass changeit | head -40
```

### Step 3: Compare environments

Questions:
- does staging trust a newer CA chain?
- did production secret rotation miss a truststore update?
- did hostname change?
- are outbound proxies altering certificates?

### Example finding

Partner rotated from an intermediate CA not present in the production truststore.
Staging was updated last week.
Production missed the secret deployment.

### Mitigation

- update truststore secret through approved change.
- restart pods to load new truststore.
- verify full chain and hostname.

### Verification

- TLS handshake succeeds from the pod.
- partner API calls return 200.
- application error logs stop.

---

## Scenario 6: Configuration drift identification

### Situation

`reporting-api` works in staging.
In production it returns 401 against an internal auth service.
The same image tag is deployed in both environments.

### Step 1: Gather configuration from both environments

```bash
kubectl get deploy reporting-api -n staging-reporting -o yaml > /Users/shasidharreddy_mallu/Site-Reliability-Engineer/08-application-support-l2l3/artifacts-reporting-staging.yaml
kubectl get deploy reporting-api -n prod-reporting -o yaml > /Users/shasidharreddy_mallu/Site-Reliability-Engineer/08-application-support-l2l3/artifacts-reporting-prod.yaml
```

### Step 2: Compare relevant sections

Relevant fields include:
- env vars.
- mounted secrets.
- service account.
- network policy labels.
- ingress annotations.
- resource limits.

### Example auth-specific checks

- `AUTH_AUDIENCE`
- `AUTH_BASE_URL`
- client ID secret name
- trusted issuer URL
- service account token mount

### Example finding

Production uses `AUTH_AUDIENCE=reporting-prod`.
The auth service expects `reporting-api`.
Staging kept the correct value.
The token is issued successfully but rejected downstream.

### Mitigation

- correct the audience value through normal change.
- restart deployment or trigger rollout.
- verify token claims in a controlled test.

### Verification

- production call to auth-protected endpoint succeeds.
- no 401 spike remains.
- staging and production configs match where intended.

---

## Cross-scenario verification checklist

After each scenario, confirm:
- [ ] the failing layer is identified.
- [ ] evidence was collected before risky change.
- [ ] mitigation lowered customer impact.
- [ ] permanent fix owner is known.
- [ ] ServiceNow notes contain timeline and findings.
- [ ] monitoring confirms stability after recovery.

## Escalation guide for this lab

Escalate to L3 when:
- startup failure requires code or build correction.
- memory leak needs heap or code analysis.
- deadlock requires thread-level or code fix.
- connection pool issue is caused by transaction design.
- TLS issue depends on application truststore packaging.
- config drift reveals release engineering control gaps.

## Final reflection questions

1. Which issues were safe for L2 to mitigate directly?
2. Which issues required code ownership from L3?
3. Which signals were most useful in each scenario?
