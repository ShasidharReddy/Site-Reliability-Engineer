# Runbook: [Alert Name]

**Alert**: `[PrometheusAlertName]`  
**Severity**: [critical / warning]  
**Team**: Platform SRE  
**Last Updated**: YYYY-MM-DD  
**ServiceNow CI**: [CI name in CMDB]

---

## 1. Overview

**What this alert means**: [1-2 sentence explanation of what condition triggered this alert]

**Typical causes**:
- [Cause 1]
- [Cause 2]
- [Cause 3]

**Expected resolution time**: [X minutes for standard case]

---

## 2. Impact Assessment

**Check user impact first**:
```bash
# Check error rate in Grafana
open https://grafana.example.com/d/[dashboard-id]

# Or via PromQL
curl -s 'http://prometheus:9090/api/v1/query?query=sum(rate(http_requests_total{status=~"5.."}[5m]))/sum(rate(http_requests_total[5m]))*100'
```

**Impact matrix**:
| Metric value | Impact level |
|-------------|-------------|
| [threshold 1] | Low — monitor |
| [threshold 2] | Medium — investigate |
| [threshold 3] | High — escalate |

---

## 3. Diagnosis Steps

### Step 1: Confirm the alert is real
```bash
kubectl get pods -n [namespace] | grep -v Running
kubectl top pods -n [namespace] | sort -k3 -rn | head -10
```

### Step 2: Check recent changes
```bash
# Recent deployments
kubectl rollout history deployment/[name] -n [namespace]

# Recent events
kubectl get events -n [namespace] --sort-by='.lastTimestamp' | tail -20
```

### Step 3: Check logs
```bash
kubectl logs -n [namespace] -l app=[app-name] --tail=100 | grep -i "error\|warn\|fatal"
```

### Step 4: Check dependencies
```bash
# Database connectivity
kubectl exec -it [app-pod] -n [namespace] -- [db-ping-command]

# Downstream services
curl -v http://[downstream-service]/health
```

---

## 4. Mitigation Options

### Option A: Quick Mitigation (< 5 minutes) — TRY FIRST
```bash
# Rollback to previous deployment
kubectl rollout undo deployment/[name] -n [namespace]
kubectl rollout status deployment/[name] -n [namespace]

# Verify rollback worked
kubectl get pods -n [namespace]
```

### Option B: Disable Feature Flag
```bash
# If the issue is a new feature
kubectl set env deployment/[name] FEATURE_X_ENABLED=false -n [namespace]
```

### Option C: Scale Up (if load-related)
```bash
kubectl scale deployment/[name] --replicas=10 -n [namespace]
```

---

## 5. Escalation

**Escalate if**:
- Error rate > X% for more than 15 minutes
- Rollback did not resolve the issue
- Data corruption is suspected

**Escalate to**:
- Primary: [Team/Person] via PagerDuty escalation policy [Policy Name]
- Secondary: [Engineering Lead] at [contact]
- Database issues: [DBA on-call] via [contact method]

---

## 6. Verification

```bash
# Confirm alert is resolved in Prometheus
open http://prometheus:9090/alerts

# Verify error rate is back to normal
watch -n5 'curl -s http://prometheus:9090/api/v1/query?query=sum(rate(http_requests_total{status=~"5.."}[5m]))/sum(rate(http_requests_total[5m]))*100'

# Check SLO burn rate returned to normal
open https://grafana.example.com/d/slo-dashboard
```

**Resolution criteria**:
- [ ] Alert resolved in Prometheus
- [ ] Error rate < 0.1% for 10 consecutive minutes
- [ ] No new related alerts firing
- [ ] ServiceNow ticket updated and resolved
