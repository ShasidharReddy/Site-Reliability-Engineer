# Troubleshooting Patterns for Application Support

- This guide focuses on high-friction issues where the first symptom is misleading.
- Each pattern shows how to prove the failing layer before escalating.
- Examples assume Kubernetes, centralized logging, metrics, tracing, and ServiceNow.

## Pattern 1: App responds 200 but users report errors

- HTTP 200 only confirms transport success, not business success.
- Users may still see validation failures, missing async completion, stale reads, or front-end rendering errors.
- Check payload meaning, not only the status code.

### Questions to answer

1. Does the response body contain a business error field?
2. Is the browser failing after the API returns 200?
3. Did an async worker or webhook fail after the synchronous call finished?
4. Is stale cache or replica lag showing outdated state?

### Command pack

```bash
curl -sk -D - https://app.example.com/api/order/123
kubectl logs deploy/web-frontend -n prod-web --since=20m | tail -100
kubectl logs deploy/orders-api -n prod-orders --since=20m | grep orderId=123
kubectl logs deploy/order-worker -n prod-orders --since=20m | tail -120
```

### Verification steps

1. Confirm the API body contains expected status and identifiers.
2. Compare front-end console errors with API logs.
3. Verify the downstream event or database row actually completed.
4. Document the exact point where the user journey diverges from the successful 200 response.

### Ticket note template

```text
Symptom:
User impact:
What was checked:
What was ruled out:
Evidence attached:
Next action / escalation owner:
```

## Pattern 2: Intermittent failures that do not appear in logs

- No application log line does not mean no failure occurred.
- The request may fail at the proxy, network, client, or be lost due to log sampling.
- Use metrics and traces to prove the gap.

### Questions to answer

1. Do edge logs show more requests than the app logs?
2. Are failures tied to one node, subnet, or availability zone?
3. Is the logger sampling or dropping short-lived failures?
4. Do traces stop before the application span starts?

### Command pack

```bash
kubectl describe ingress app -n prod-web
kubectl logs deploy/ingress-controller -n ingress-nginx --since=20m | tail -120
kubectl get events -n prod-web --sort-by=.lastTimestamp | tail -30
kubectl get pods -n prod-app -o wide
```

### Verification steps

1. Reproduce with a known request or correlation ID.
2. Check edge, service mesh, and application telemetry for the same minute.
3. If the request never reached the app, redirect the escalation toward edge or networking.
4. If the request reached the app but did not log, open a follow-up for observability gaps.

### Ticket note template

```text
Symptom:
User impact:
What was checked:
What was ruled out:
Evidence attached:
Next action / escalation owner:
```

## Pattern 3: Works in staging, fails in production

- Environment parity is often assumed and usually wrong in at least one important detail.
- Production has real traffic, real data, stricter policies, and full integrations.
- Compare configuration, dependencies, and load characteristics.

### Questions to answer

1. Is the image tag identical between environments?
2. Are feature flags, secrets, or resource limits different?
3. Does production use a real vendor endpoint or certificate chain?
4. Is data size or concurrency the actual difference?

### Command pack

```bash
kubectl get deploy app -n staging -o yaml
kubectl get deploy app -n prod -o yaml
kubectl get configmap app -n staging -o yaml
kubectl get configmap app -n prod -o yaml
```

### Environment comparison table

| Dimension | Staging check | Production check |
| --- | --- | --- |
| Image | kubectl get deploy app -n staging | kubectl get deploy app -n prod |
| Config | ConfigMap and Secret refs | ConfigMap and Secret refs |
| Resources | CPU/memory requests and limits | CPU/memory requests and limits |
| Network | DNS, policy, proxy rules | DNS, policy, proxy rules |

### Verification steps

1. List all confirmed environment differences.
2. Test one variable at a time or use a canary.
3. Move the approved state into source control or GitOps.
4. Create a prevention action for drift detection if drift caused the incident.

### Ticket note template

```text
Symptom:
User impact:
What was checked:
What was ruled out:
Evidence attached:
Next action / escalation owner:
```

## Pattern 4: Timeout vs connection refused vs 502 bad gateway

- These errors point to different layers and must not be treated as synonyms.
- Timeout usually means slow path or packet loss.
- Connection refused usually means no listener or rejected TCP connection.
- 502 usually means proxy-to-upstream failure.

### Questions to answer

1. Did the failure happen before TCP connection was established?
2. Is the refusal immediate or after a delay?
3. Does the proxy show no healthy endpoints or upstream TLS errors?
4. Did the symptom change after a rollback or restart?

### Command pack

```bash
kubectl get svc,endpoints -n prod-web app
kubectl describe ingress app -n prod-web
kubectl logs deploy/app -n prod-app --since=15m | tail -120
curl -sk -o /dev/null -w "%{http_code} %{time_total}
" https://app.example.com/health
```

### Symptom comparison

| Symptom | What it usually means | First owner to check |
| --- | --- | --- |
| Timeout | Slow path, queueing, retransmission, or dependency wait | Application plus dependency owner |
| Connection refused | No listener, wrong port, firewall reject | Service/app owner or network owner |
| 502 bad gateway | Proxy failed to reach or accept upstream response | Edge/proxy plus app owner |

### Verification steps

1. Replicate the request from the same network path as the user.
2. Confirm whether the fix removed the original symptom or only changed it to another.
3. Attach both client-side and server-side timestamps in the ticket.
4. Update the runbook with the layer-specific interpretation.

### Ticket note template

```text
Symptom:
User impact:
What was checked:
What was ruled out:
Evidence attached:
Next action / escalation owner:
```

## Pattern 5: Memory leak vs normal memory growth

- Not every upward memory chart means a leak.
- Warm caches, JIT compilation, and delayed memory return to the OS can look suspicious but be normal.
- Post-GC baseline tells the clearer story.

### Questions to answer

1. Does memory stabilize after warmup?
2. Does post-GC heap continue to rise?
3. Does the pattern reset after restart and then recur at the same slope?
4. Is one endpoint or batch job correlated with the growth?

### Command pack

```bash
kubectl top pod -n prod-app -l app=invoice-api
kubectl logs deploy/invoice-api -n prod-app --since=12h | grep -E "GC|OutOfMemory"
kubectl exec -n prod-app <pod> -- jcmd 1 GC.class_histogram | head -40
kubectl exec -n prod-app <pod> -- jcmd 1 GC.heap_info
```

### Leak versus normal growth table

| Observation | Normal growth | Leak pattern |
| --- | --- | --- |
| After deploy | Rises then stabilizes | Rises continuously |
| After GC | Returns near stable baseline | Baseline rises over time |
| During low traffic | Flattens or falls | Keeps rising or stays abnormally high |
| After restart | Returns to expected baseline | Returns then repeats at same slope |

### Verification steps

1. Track memory across a full traffic cycle.
2. Compare RSS, heap used after GC, and request volume.
3. Escalate to L3 with heap or class histogram evidence if the slope is monotonic.
4. Add a memory-slope alert if the current monitoring only watches absolute thresholds.

### Ticket note template

```text
Symptom:
User impact:
What was checked:
What was ruled out:
Evidence attached:
Next action / escalation owner:
```

## Cross-pattern decision aids

1. Always prove whether the failure is user-specific, environment-specific, or systemic.
2. Prefer one safe mitigation and one clean escalation over many speculative changes.
3. Preserve timestamps, request IDs, trace IDs, and rollback times in the incident record.
4. Close the loop with verification from both telemetry and user perspective.

## Rapid verification checklist

- [ ] direct test reproduced or disproved the symptom.
- [ ] at least two telemetry sources were checked.
- [ ] recent change window was reviewed.
- [ ] escalation, if needed, included business impact and evidence.

## Appendix A: Signal-to-layer map

| Signal | Likely layer | What to compare |
| --- | --- | --- |
| Browser console error after 200 response | Client or API payload contract | Network tab, response body, feature flags |
| Edge requests exceed app requests | Proxy, network, or service mesh | Ingress logs, mesh metrics, app metrics |
| Staging healthy but production slow | Capacity or environment drift | Resource limits, pool settings, data volume |
| Immediate connection refused | Listener or firewall | Container port, Service targetPort, security policy |
| Rising post-GC baseline | Memory retention | Heap histogram, cache size, traffic mix |

## Appendix B: Triage note examples

```text
Example 1
Symptom: Users receive success banner, but order status remains pending.
Impact: 12% of orders require manual reconciliation.
Checked: API 200 payload, worker logs, queue depth, replica lag.
Ruled out: ingress outage, frontend deployment issue.
Evidence: trace ID 4ac1..., worker timeout log at 14:12 UTC.
Next action: L3 to inspect worker retry logic and idempotency handling.
```

```text
Example 2
Symptom: Intermittent checkout failures not visible in app logs.
Impact: Unknown user count; edge error rate 3% in EU.
Checked: ingress controller logs, app logs, node placement, traces.
Ruled out: database saturation, TLS expiry.
Evidence: failures terminate at edge before application span starts.
Next action: platform networking team to inspect node subnet path.
```

## Appendix C: Verification patterns by symptom

1. For false-success 200 responses, verify both UI outcome and stored state.
2. For logless failures, verify edge count equals application count after fix.
3. For staging-versus-production gaps, verify the approved configuration is source-controlled.
4. For timeout and 502 issues, verify symptom class with repeated curl or synthetic checks.
5. For suspected leaks, verify baseline across at least one full traffic cycle.
6. For all cases, verify ServiceNow notes include timestamps and evidence links.

## Appendix D: Escalation cues

- Escalate to L3 when the fix requires code reasoning, heap analysis, thread analysis, or transaction redesign.
- Escalate to platform when failures are node-specific, network-specific, or ingress-specific.
- Escalate to vendor when managed service telemetry or status events point outside internal control.
- Escalate to management when business deadlines, SLA breach risk, or customer commitments are in danger.

Final reminder: verify the user journey, not only the infrastructure symptom.
Keep one direct test, one metric, and one trace in every final incident note.
Use recovery verification that matches the original complaint.
Do not close the ticket until telemetry and user checks agree.
