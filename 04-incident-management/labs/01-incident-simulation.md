# Lab 01 — Incident Simulation

## Prerequisites

- A Kubernetes cluster you can safely break: kind, k3d, minikube, or a non-production shared environment.
- `kubectl`, `curl`, `watch`, and `jq` installed on your workstation.
- A Prometheus and Alertmanager stack reachable from the cluster or from a local port-forward.
- Optional but useful: Slack incoming webhook test URL, PagerDuty Events API v2 integration key, and a second engineer for role-play.
- Familiarity with the templates in [templates/sev-incident-runbook.md](../templates/sev-incident-runbook.md) and [templates/postmortem-template.md](../templates/postmortem-template.md).
- Permission to create namespaces, deployments, network policies, and configmaps in the training cluster.

## Overview

This lab simulates the full incident lifecycle for a small checkout system with a database dependency. You will deploy the workload, inject realistic failures, and practice the operational behavior expected during a production event: detection, triage, communication, mitigation, validation, and follow-up learning.

| Level | Learning objectives |
|---|---|
| Basic | Detect incidents from alerts, inspect pod health, and perform first-response mitigation with `kubectl`. |
| Intermediate | Coordinate incident roles, use Prometheus and Alertmanager evidence, and execute contained recovery steps without making impact worse. |
| Advanced | Handle ambiguous symptoms, run multiple communication channels in parallel, and capture an evidence-based postmortem while the system is still stabilizing. |

### Lab Architecture

```text
users --> ingress --> checkout-api --> payment-service --> postgres
                    |                  |
                    |                  +--> Prometheus scrape targets
                    +--> Alertmanager --> PagerDuty / Slack / status updates
```

### Role Card Suggestions

| Role | Primary focus during the exercise |
|---|---|
| Incident Commander (IC) | Declare severity, assign owners, keep time, decide when to mitigate vs continue diagnosis. |
| Technical Lead (TL) | Run commands, inspect logs, propose mitigations, and report technical facts back to IC. |
| Communications Lead | Write stakeholder updates, manage Slack or bridge notes, and keep user-facing language accurate. |

If you are practicing solo, time-box yourself and explicitly switch hats: first IC for 2 minutes, then TL for 5 minutes, then comms for 2 minutes.

## Environment Setup

### Create Namespace and Shared Variables

```bash
export NS=incident-lab
kubectl create namespace "$NS"
kubectl config set-context --current --namespace="$NS"
export PD_ROUTING_KEY='replace-with-training-key'
export PD_DEDUP_KEY='checkout-api-sev2-training'
export SLACK_WEBHOOK='https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXX'
```

### Deploy the Sample Microservices Stack

For this lab, speed matters more than authoring perfect manifests. Use imperative commands to stand up the dependency chain quickly, then save YAML later if you want to keep the stack around.

```bash
kubectl create secret generic db-auth \
  --from-literal=POSTGRES_DB=checkout \
  --from-literal=POSTGRES_USER=checkout \
  --from-literal=POSTGRES_PASSWORD=checkoutpass \
  -n "$NS" --dry-run=client -o yaml | kubectl apply -f -

kubectl create deployment db --image=postgres:15-alpine -n "$NS"
kubectl set env deployment/db -n "$NS" \
  POSTGRES_DB=checkout POSTGRES_USER=checkout POSTGRES_PASSWORD=checkoutpass
kubectl expose deployment db --name db --port 5432 --target-port 5432 -n "$NS"

kubectl create deployment payment-service \
  --image=ghcr.io/examplecorp/sre-labs/payment-service:v1.0.0 -n "$NS"
kubectl set env deployment/payment-service -n "$NS" \
  DB_HOST=db DB_NAME=checkout DB_USER=checkout DB_PASSWORD=checkoutpass
kubectl set resources deployment/payment-service -n "$NS" \
  --requests=cpu=100m,memory=128Mi --limits=cpu=500m,memory=256Mi
kubectl scale deployment/payment-service --replicas=2 -n "$NS"
kubectl expose deployment payment-service --port 8080 --target-port 8080 -n "$NS"

kubectl create deployment checkout-api \
  --image=ghcr.io/examplecorp/sre-labs/checkout-api:v1.0.0 -n "$NS"
kubectl set env deployment/checkout-api -n "$NS" \
  PAYMENT_URL=http://payment-service:8080 LATENCY_MS=25
kubectl set resources deployment/checkout-api -n "$NS" \
  --requests=cpu=100m,memory=128Mi --limits=cpu=500m,memory=256Mi
kubectl scale deployment/checkout-api --replicas=3 -n "$NS"
kubectl expose deployment checkout-api --port 8080 --target-port 8080 -n "$NS"

kubectl rollout status deployment/db -n "$NS"
kubectl rollout status deployment/payment-service -n "$NS"
kubectl rollout status deployment/checkout-api -n "$NS"
```

If you want to preserve a manifest for later replay, export it after the deployments are healthy:

```bash
kubectl get deploy,svc,secret -n "$NS" -o yaml > checkout-stack.yaml
```

### Verification

```bash
kubectl get pods -n "$NS" -o wide
kubectl get svc -n "$NS"
kubectl logs deployment/checkout-api -n "$NS" --tail=10
kubectl logs deployment/payment-service -n "$NS" --tail=10
```
Expected output should show all pods in `Running` or `Ready` state and the services exposing port `8080` for the APIs and `5432` for the database.

```text
NAME                               READY   STATUS    RESTARTS   AGE
checkout-api-7b8f6f5667-k6lh2      1/1     Running   0          2m
checkout-api-7b8f6f5667-r9xhz      1/1     Running   0          2m
checkout-api-7b8f6f5667-zj4hn      1/1     Running   0          2m
payment-service-6d4d7cbd66-f6j7x   1/1     Running   0          2m
payment-service-6d4d7cbd66-wb2sr   1/1     Running   0          2m
db-7dc6c5667d-c95rv                1/1     Running   0          2m
```

### Optional Prometheus and Alertmanager Access

```bash
kubectl -n monitoring port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090
kubectl -n monitoring port-forward svc/prometheus-kube-prometheus-alertmanager 9093:9093
```
In separate shells, query alert state and service latency before you start breaking things.

```bash
curl -sG http://127.0.0.1:9090/api/v1/query   --data-urlencode 'query=sum(rate(http_requests_total{job="checkout-api",status=~"5.."}[5m]))'

curl -s http://127.0.0.1:9093/api/v2/alerts | jq '.[] | {labels: .labels, startsAt: .startsAt}'
```

## Exercise Flow and Severity Model

Use the following severity guideline during the lab. The point is not to guess a perfect severity, but to be explicit and consistent.

| Severity | Customer impact | Expected response pattern |
|---|---|
| SEV1 | Checkout unavailable for most users, data at risk, or multi-region failure | IC immediately, all hands, stakeholder updates every 15 minutes |
| SEV2 | Partial outage, elevated checkout errors, or major latency increase | IC and TL assigned, updates every 30 minutes |
| SEV3 | Single replica issue or degraded dependency with available workaround | Service owner responds, updates as needed |

### Incident Timeline Template

```text
alert fired -> acknowledge -> severity declared -> war room opened -> mitigation chosen -> metrics recover -> all-clear
```

## Scenario 1 — Pod Crash Loop in checkout-api

Practice identifying an application startup failure, reducing blast radius, and restoring service with a rollback.

### Inject the Failure

```bash
kubectl set image deployment/checkout-api   checkout-api=ghcr.io/examplecorp/sre-labs/checkout-api:broken-startup   -n "$NS"
kubectl rollout status deployment/checkout-api -n "$NS" --timeout=60s || true
```

### Detect and Triage

```bash
kubectl get pods -n "$NS" -l app=checkout-api -w
kubectl describe pod -n "$NS" $(kubectl get pod -n "$NS" -l app=checkout-api -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n "$NS" deploy/checkout-api --previous --tail=40
kubectl get events -n "$NS" --sort-by='.lastTimestamp' | tail -20
```

### Verification Signals

Look for evidence like the following before you change anything:

```text
Warning  BackOff    39s (x8 over 2m11s)  kubelet  Back-off restarting failed container
Error: failed to start HTTP listener: bind: permission denied
```

### Communication Practice

Use one PagerDuty event and one Slack update even if you are running the lab alone. The exercise is about building muscle memory for structured communication under pressure.

```bash
curl -X POST https://events.pagerduty.com/v2/enqueue   -H 'Content-Type: application/json'   -d '{
    "routing_key": "'"$PD_ROUTING_KEY"'",
    "event_action": "trigger",
    "dedup_key": "'"$PD_DEDUP_KEY"'-crashloop",
    "payload": {
      "summary": "SEV2 training incident: checkout-api crash looping",
      "source": "incident-lab.checkout-api",
      "severity": "critical",
      "custom_details": {"namespace": "incident-lab", "failure": "CrashLoopBackOff"}
    }
  }'

curl -X POST "$SLACK_WEBHOOK"   -H 'Content-type: application/json'   -d '{"text":"[training] SEV2 declared for checkout-api. Impact: checkout failures rising. IC=@you TL=@you Comms=@you. Mitigation in progress."}'
```

### Mitigate and Resolve

```bash
kubectl rollout undo deployment/checkout-api -n "$NS"
kubectl rollout status deployment/checkout-api -n "$NS"
kubectl get rs -n "$NS" -l app=checkout-api
```

### Verify Recovery

```bash
kubectl get pods -n "$NS" -l app=checkout-api
kubectl logs -n "$NS" deploy/checkout-api --tail=20
curl -s http://127.0.0.1:9090/api/v1/query --data-urlencode 'query=sum(rate(http_requests_total{job="checkout-api",status=~"5.."}[5m]))'
```

All checkout-api replicas return to `Running`, the crash loop stops growing, and the 5xx error query trends back toward zero.

### Advanced Variation

- Redo the scenario but only roll back one replica first and explain why partial mitigation is unsafe for stateless APIs under load.
- Assign a separate IC and TL. Have the IC forbid speculative changes until the TL provides direct evidence from logs.
- Write a 4-line stakeholder note that explains what changed without blaming the deployer.

## Scenario 2 — Memory Pressure and OOM in payment-service

Diagnose container memory exhaustion and compare immediate mitigation with durable corrective actions.

### Inject the Failure

```bash
kubectl patch deployment payment-service -n "$NS" --type='json' -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"96Mi"},
  {"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"CHAOS_ALLOCATE_MB","value":"180"}}
]'
kubectl rollout status deployment/payment-service -n "$NS"
```

### Detect and Triage

```bash
kubectl get pods -n "$NS" -l app=payment-service -w
kubectl describe pod -n "$NS" $(kubectl get pod -n "$NS" -l app=payment-service -o jsonpath='{.items[0].metadata.name}') | sed -n '/Last State/,+12p'
kubectl top pod -n "$NS" -l app=payment-service
kubectl logs -n "$NS" deploy/payment-service --previous --tail=40
```

### Verification Signals

Look for evidence like the following before you change anything:

```text
Last State:     Terminated
  Reason:       OOMKilled
  Exit Code:    137
Memory working set peaked at 183Mi while container limit was 96Mi
```

### Communication Practice

Use one PagerDuty event and one Slack update even if you are running the lab alone. The exercise is about building muscle memory for structured communication under pressure.

```bash
curl -X POST "$SLACK_WEBHOOK"   -H 'Content-type: application/json'   -d '{"text":"[training] payment-service is OOMKilled. Checkout errors may follow if both replicas fail. Investigating memory regression and considering temporary scale-out."}'
```

### Mitigate and Resolve

```bash
kubectl set resources deployment/payment-service -n "$NS"   --limits=cpu=500m,memory=256Mi   --requests=cpu=100m,memory=128Mi
kubectl scale deployment/payment-service -n "$NS" --replicas=3
kubectl rollout status deployment/payment-service -n "$NS"
```

### Verify Recovery

```bash
kubectl get pods -n "$NS" -l app=payment-service
kubectl top pod -n "$NS" -l app=payment-service
curl -sG http://127.0.0.1:9090/api/v1/query   --data-urlencode 'query=sum(kube_pod_container_status_restarts_total{namespace="incident-lab",container="payment-service"})'
```

Pods stop restarting, memory stays below the new limit, and checkout latency drops as healthy payment-service capacity returns.

### Advanced Variation

- Instead of raising the memory limit first, add one replica and compare whether that changes OOM behavior or only hides it.
- Document how to tell the difference between a real leak and a one-time startup allocation spike.
- Add a note to your draft postmortem explaining why `Exit Code 137` alone is not enough evidence.

## Scenario 3 — Network Partition Between checkout-api and payment-service

Practice dependency isolation diagnosis and safe rollback of an incorrect network policy.

### Inject the Failure

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-checkout-to-payment
  namespace: incident-lab
spec:
  podSelector:
    matchLabels:
      app: payment-service
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: never-match
EOF
```

### Detect and Triage

```bash
kubectl get networkpolicy -n "$NS"
kubectl exec -n "$NS" deploy/checkout-api -- sh -c 'wget -qO- http://payment-service:8080/healthz || true'
kubectl logs -n "$NS" deploy/checkout-api --tail=50 | grep -i 'timeout\|connection'
kubectl get events -n "$NS" --sort-by='.lastTimestamp' | tail -20
```

### Verification Signals

Look for evidence like the following before you change anything:

```text
error contacting payment-service: Get "http://payment-service:8080/pay": dial tcp 10.96.184.77:8080: i/o timeout
```

### Communication Practice

Use one PagerDuty event and one Slack update even if you are running the lab alone. The exercise is about building muscle memory for structured communication under pressure.

```bash
curl -X POST "$SLACK_WEBHOOK"   -H 'Content-type: application/json'   -d '{"text":"[training] Suspected east-west network issue between checkout-api and payment-service. User impact: checkout requests timing out after 3s. Looking for recent policy or service mesh change."}'
```

### Mitigate and Resolve

```bash
kubectl delete networkpolicy deny-checkout-to-payment -n "$NS"
kubectl exec -n "$NS" deploy/checkout-api -- sh -c 'wget -qO- http://payment-service:8080/healthz'
```

### Verify Recovery

```bash
kubectl get networkpolicy -n "$NS"
kubectl logs -n "$NS" deploy/checkout-api --tail=20
curl -sG http://127.0.0.1:9090/api/v1/query   --data-urlencode 'query=histogram_quantile(0.95,sum(rate(http_request_duration_seconds_bucket{job="checkout-api"}[5m])) by (le))'
```

Connectivity tests succeed again, checkout timeout errors disappear from logs, and the p95 latency query falls back toward the pre-incident baseline.

### Advanced Variation

- Recreate the issue with an egress policy instead of an ingress policy and note the different troubleshooting path.
- Ask the IC to justify whether this is SEV1 or SEV2 if only one dependency path is blocked.
- Capture the exact policy diff that caused the outage so it can be linked in the postmortem.

## Scenario 4 — High Latency Without Immediate Errors

Handle a gray failure where the service still works but user experience is degraded and alert fatigue can delay action.

### Inject the Failure

```bash
kubectl set env deployment/checkout-api -n "$NS" LATENCY_MS=900
kubectl rollout status deployment/checkout-api -n "$NS"
```

### Detect and Triage

```bash
kubectl logs -n "$NS" deploy/checkout-api --tail=50 | grep -i latency
curl -sG http://127.0.0.1:9090/api/v1/query   --data-urlencode 'query=histogram_quantile(0.95,sum(rate(http_request_duration_seconds_bucket{job="checkout-api"}[5m])) by (le))'
curl -sG http://127.0.0.1:9090/api/v1/query   --data-urlencode 'query=sum(rate(http_requests_total{job="checkout-api",status=~"5.."}[5m]))'
```

### Verification Signals

Look for evidence like the following before you change anything:

```text
{status="success",data={result=[{value=[1713021900.321,"1.84"]}]}}
5xx query remains near zero while p95 latency climbs above the 1.5s SLO threshold
```

### Communication Practice

Use one PagerDuty event and one Slack update even if you are running the lab alone. The exercise is about building muscle memory for structured communication under pressure.

```bash
curl -X POST "$SLACK_WEBHOOK"   -H 'Content-type: application/json'   -d '{"text":"[training] Elevated checkout latency detected with low error rate. Treating as a customer-impacting incident because users are timing out in browsers before the API fails hard."}'
```

### Mitigate and Resolve

```bash
kubectl rollout undo deployment/checkout-api -n "$NS"
kubectl rollout status deployment/checkout-api -n "$NS"
kubectl annotate deployment/checkout-api -n "$NS" incident.example.com/latency-note='rolled back latency regression caused by config change' --overwrite
```

### Verify Recovery

```bash
curl -sG http://127.0.0.1:9090/api/v1/query   --data-urlencode 'query=histogram_quantile(0.95,sum(rate(http_request_duration_seconds_bucket{job="checkout-api"}[5m])) by (le))'
kubectl logs -n "$NS" deploy/checkout-api --tail=20
kubectl describe deployment checkout-api -n "$NS" | tail -20
```

The p95 latency query falls below the alert threshold, user-facing timeouts stop, and the deployment annotation records what was changed.

### Advanced Variation

- Keep the latency regression in place and see whether autoscaling helps or simply spreads the slow behavior across more replicas.
- Have the comms lead write a status page message that explains slowness without using internal jargon.
- Compare whether your alerting catches latency faster than synthetic probes or customer reports.

## Prometheus Alert Simulation

If your lab cluster has the Prometheus Operator installed, create a short-lived training rule that fires on high error rate or latency. The alert is useful because it gives you a canonical source of truth for when the incident started.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: checkout-training-alerts
  namespace: incident-lab
spec:
  groups:
  - name: incident-training.rules
    rules:
    - alert: CheckoutApiHighErrorRate
      expr: sum(rate(http_requests_total{job="checkout-api",status=~"5.."}[5m])) / sum(rate(http_requests_total{job="checkout-api"}[5m])) > 0.05
      for: 2m
      labels:
        severity: warning
        service: checkout-api
      annotations:
        summary: checkout-api error rate is above 5%
        description: checkout-api is returning elevated 5xx responses in the training namespace.
        runbookUrl: https://internal.example.com/runbooks/checkout/high-error-rate
    - alert: CheckoutApiHighLatency
      expr: histogram_quantile(0.95,sum(rate(http_request_duration_seconds_bucket{job="checkout-api"}[5m])) by (le)) > 1.5
      for: 5m
      labels:
        severity: warning
        service: checkout-api
      annotations:
        summary: checkout-api p95 latency is above 1.5s
        description: checkout-api is slower than the service SLO budget allows.
        runbookUrl: https://internal.example.com/runbooks/checkout/high-latency
```

```bash
cat <<'EOF' > checkout-training-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: checkout-training-alerts
  namespace: incident-lab
spec:
  groups:
  - name: incident-training.rules
    rules:
    - alert: CheckoutApiHighErrorRate
      expr: sum(rate(http_requests_total{job="checkout-api",status=~"5.."}[5m])) / sum(rate(http_requests_total{job="checkout-api"}[5m])) > 0.05
      for: 2m
      labels:
        severity: warning
        service: checkout-api
      annotations:
        summary: checkout-api error rate is above 5%
        description: checkout-api is returning elevated 5xx responses in the training namespace.
        runbookUrl: https://internal.example.com/runbooks/checkout/high-error-rate
    - alert: CheckoutApiHighLatency
      expr: histogram_quantile(0.95,sum(rate(http_request_duration_seconds_bucket{job="checkout-api"}[5m])) by (le)) > 1.5
      for: 5m
      labels:
        severity: warning
        service: checkout-api
      annotations:
        summary: checkout-api p95 latency is above 1.5s
        description: checkout-api is slower than the service SLO budget allows.
        runbookUrl: https://internal.example.com/runbooks/checkout/high-latency
EOF
kubectl apply -f checkout-training-alerts.yaml
curl -s http://127.0.0.1:9093/api/v2/alerts | jq '.[] | select(.labels.service=="checkout-api")'
```

Expected alert payload example:

```text
{
  "labels": {
    "alertname": "CheckoutApiHighLatency",
    "namespace": "incident-lab",
    "service": "checkout-api",
    "severity": "warning"
  },
  "annotations": {
    "summary": "checkout-api p95 latency is above 1.5s",
    "runbookUrl": "https://internal.example.com/runbooks/checkout/high-latency"
  }
}
```

## Brief Postmortem Exercise

After any of the scenarios above, write a short postmortem while the evidence is still fresh. Keep it concise: six to eight bullets is enough for the lab.

### Minimum Postmortem Fields

- Incident title and severity.
- Start time, detection time, mitigation time, and resolution time.
- User impact in one sentence and one metric.
- Root cause and contributing factors separated clearly.
- What worked well, what slowed you down, and one preventive action item.

### Example Prompt

```text
Incident: checkout-api crash loop after rollout
Impact: 62% of checkout attempts failed for 11 minutes
Detection: Prometheus alert fired 2 minutes after rollout
Mitigation: deployment rollback
Root cause: bad container image and missing pre-deploy startup smoke test
```

## Teardown

```bash
kubectl delete namespace "$NS"
rm -f checkout-stack.yaml checkout-training-alerts.yaml
unset NS PD_ROUTING_KEY PD_DEDUP_KEY SLACK_WEBHOOK
```

## Key Takeaways

- Treat communication as part of the response, not as optional admin overhead.
- Verify before and after every mitigation so you do not trade one unknown for another.
- Crash loops, OOM, dependency partitions, and latency regressions all need different evidence, even when the alert looks similar.
- A short, factual postmortem drafted immediately after recovery is usually more accurate than a perfect one written days later.
- Practice role clarity: a calm IC and a focused TL reduce noisy, uncoordinated changes.
