# Lab 01: L2 Triage Methodology

## Scenario
Payment API returning intermittent 503s. Users report checkout hanging.

## Triage Steps

### Step 1: Reproduce and Scope
```bash
kubectl exec -n default debug-pod -- curl -o /dev/null -w "%{http_code} %{time_total}s" http://payment-api:8080/health
```

### Step 2: Check Recent Changes
```bash
kubectl rollout history deployment/payment-api -n default
kubectl get events -n default --sort-by=lastTimestamp | tail -10
```

### Step 3: Check Logs
```bash
kubectl logs -n default -l app=payment-api --tail=200 | grep -i "timeout\|connection\|pool"
```

### Step 4: Check Dependencies
```bash
kubectl exec -n default payment-api-xxx -- psql $DB_URL -c "SELECT 1" -t
kubectl exec -n default payment-api-xxx -- curl -o /dev/null -w "%{time_total}s" https://api.stripe.com/v1 2>&1
```

### Step 5: Check Resources
```bash
kubectl top pods -n default | grep payment
kubectl describe pod payment-api-xxx -n default | grep -A10 Limits
```

## Decision Points
1. Logs: "DB connection pool exhausted" — next action?
2. External gateway 503 — escalate? To who?
3. High CPU, no errors — is this a problem?

## Verification
- [ ] Bottleneck layer identified
- [ ] Findings documented with timestamps
- [ ] ServiceNow opened with proper description
- [ ] Status communicated to requester
