# SRE Principles — Theory

## 1. What Is SRE?

Site Reliability Engineering (SRE) is a discipline that applies software engineering principles to infrastructure and operations problems. Coined at Google in 2003, SRE bridges the gap between development and operations by treating ops as a software problem.

### SRE vs DevOps vs Traditional Ops
| Aspect | Traditional Ops | DevOps | SRE |
|--------|----------------|--------|-----|
| Primary goal | Keep lights on | Ship faster | Reliability at scale |
| Automation | Manual runbooks | CI/CD pipelines | Engineering away toil |
| Risk | Avoid change | Embrace change | Error budgets manage risk |
| Feedback loops | Slow | Fast | Data-driven SLOs |
| On-call | Reactive | Shared | Structured rotations |

---

## 2. SLIs — Service Level Indicators

An **SLI** is a quantitative measure of some aspect of the level of service provided.

### 2.1 Good SLI Characteristics
- Directly related to user experience
- Measurable from existing telemetry
- Bounded (has a clear good/bad threshold)
- Aggregatable over a time window

### 2.2 SLI Types

**Availability SLI**
```
availability = successful_requests / total_requests
```
- Successful = HTTP 2xx/3xx (not 5xx, not timeout)
- Source: application metrics or load balancer logs

**Latency SLI**
```
latency_sli = requests_under_threshold / total_requests
```
- Example: % of requests completing in < 200ms
- Use percentiles (p99), not averages (averages hide tail latency)

**Error Rate SLI**
```
error_sli = (total_requests - error_requests) / total_requests
```

**Freshness SLI** (for data pipelines)
```
freshness_sli = % of data items updated within acceptable staleness window
```

**Throughput SLI**
```
throughput_sli = % of time system processes >= N requests/sec
```

### 2.3 PromQL for SLIs
```promql
# Availability SLI (1-hour window)
sum(rate(http_requests_total{status!~"5.."}[1h]))
/
sum(rate(http_requests_total[1h]))

# Latency SLI — % requests < 200ms
sum(rate(http_request_duration_seconds_bucket{le="0.2"}[1h]))
/
sum(rate(http_request_duration_seconds_count[1h]))
```

---

## 3. SLOs — Service Level Objectives

An **SLO** is a target value for an SLI, measured over a rolling window.

### 3.1 Setting Realistic SLOs
1. **Start with what you measure today** — look at historical SLI data
2. **Ask: what do users actually need?** — not "maximum reliability"
3. **Make it achievable** — 99.99% is harder than you think
4. **Give yourself headroom** — internal SLO should be tighter than external SLA

### 3.2 SLO Examples
| Service | SLI | SLO Target | Window |
|---------|-----|-----------|--------|
| API gateway | Availability | 99.9% | 30 days |
| Payment service | Latency p99 < 500ms | 99.5% | 7 days |
| Search | Error rate < 0.1% | 99.9% | 30 days |
| Data pipeline | Freshness < 1 hour | 99.5% | 7 days |

### 3.3 Availability SLO to Downtime Table
| SLO | Monthly downtime | Yearly downtime |
|-----|----------------|----------------|
| 99% | 7.2 hours | 3.65 days |
| 99.5% | 3.6 hours | 1.83 days |
| 99.9% | 43.8 minutes | 8.76 hours |
| 99.95% | 21.9 minutes | 4.38 hours |
| 99.99% | 4.4 minutes | 52.6 minutes |

---

## 4. Error Budgets

### 4.1 What Is an Error Budget?
Error budget = 1 - SLO target

**Example**: SLO = 99.9% availability over 30 days
- Budget = 0.1% of all requests may fail
- If you serve 1M req/day (30M/month): budget = 30,000 failed requests
- Or in time: 0.1% × 30 days × 24h = **43.8 minutes of downtime**

### 4.2 Error Budget Policy
When budget is:
- **> 50% remaining**: Ship features freely, take calculated risks
- **25–50% remaining**: Slow down risky deploys, add automated tests
- **< 25% remaining**: Feature freeze, focus on reliability improvements
- **0% or negative**: No new features until budget recovers; mandatory postmortem

### 4.3 Multi-Window Burn Rate Alerting (Google SRE Book Chapter 5)
Single-window alerting misses slow burns. Use multiple windows:

```
Fast burn (critical): 14.4× budget rate in last 1h AND 5m
Slow burn (warning): 6× budget rate in last 6h AND 30m
```

**PromQL — Multi-window burn rate for 99.9% SLO**:
```promql
# Error ratio in short window
job:http_error_ratio:rate5m > 0.001 * 14.4

# Error ratio in long window (confirm it's sustained)
job:http_error_ratio:rate1h > 0.001 * 14.4
```

Meaning: if error ratio exceeds 14.4× the acceptable budget burn rate, you'll exhaust 100% budget in 1 hour.

### 4.4 Budget Burn Rate Calculation
```
burn_rate = actual_error_rate / (1 - SLO)

# Example: SLO = 99.9%, actual error rate = 1.44%
burn_rate = 0.0144 / 0.001 = 14.4x

# At 14.4x: budget exhausted in 30d / 14.4 = 2.08 days
```

---

## 5. Toil

### 5.1 What Is Toil?
Toil is work tied to running a production service that:
- Is **manual** (not automated)
- Is **repetitive** (done over and over)
- Can be **automated** (a computer could do it)
- Scales **linearly** with service growth
- Has no **enduring value** (doing it doesn't improve the service)

### 5.2 Toil vs Engineering Work
| Toil | Engineering Work |
|------|----------------|
| Manually rotating certificates | Building cert-manager automation |
| Restarting pods after OOM | Fixing memory leak in application |
| Manually scaling deployments | Configuring HPA |
| Copy-pasting deploy commands | Writing CI/CD pipeline |
| Acknowledging false-positive alerts | Tuning alert thresholds |

### 5.3 The 50% Rule
SRE teams should spend ≤ 50% of time on toil. When toil exceeds 50%:
- Quality of engineering work degrades
- Team burnout increases
- Service reliability actually decreases (less time for proactive work)

### 5.4 Measuring Toil
Track weekly in a toil log:
- Task name
- Time spent
- Is it automatable? (Y/N)
- Automation effort estimate

When automation effort < 4× current toil cost → automate it.

---

## 6. Reliability Patterns

### 6.1 Circuit Breaker
- Detects repeated failures → opens circuit (fails fast) → prevents cascade
- States: Closed (normal) → Open (failing fast) → Half-Open (testing recovery)
- Implementation: Hystrix (Java), resilience4j, Envoy, Istio

### 6.2 Bulkhead
- Isolate resources between services (separate thread pools, connection pools)
- Prevents one slow service from exhausting shared resources

### 6.3 Retry with Exponential Backoff + Jitter
```python
import random, time
def retry_with_backoff(fn, max_retries=5):
    for attempt in range(max_retries):
        try:
            return fn()
        except Exception:
            if attempt == max_retries - 1:
                raise
            sleep = (2 ** attempt) + random.uniform(0, 1)  # jitter
            time.sleep(sleep)
```

### 6.4 Graceful Degradation
- If a dependency fails, serve degraded but functional response
- Example: recommendation service down → serve default recommendations (not 500)

### 6.5 Timeouts
- Every external call MUST have a timeout
- Default: 30s is too long; set 2-5s for synchronous user-facing calls
- Use P99 latency × 2 as a starting point

---

## 7. Capacity Planning

### 7.1 Process
1. **Measure current utilization** — CPU, memory, disk, network, RPS
2. **Project demand** — historical growth rate, upcoming events, product roadmap
3. **Model headroom** — target 50-70% utilization (leave room for spikes)
4. **Provision ahead** — lead time for cloud capacity can be 0 days, for hardware 6-12 weeks

### 7.2 Load Testing
- **Goals**: find the breaking point BEFORE users do
- **Tools**: k6, Locust, JMeter, Artillery, Gatling
- **Scenarios**: ramp-up, steady state, spike, soak (long-duration)
- **Metrics to watch**: latency p99, error rate, CPU saturation, connection pool exhaustion

---

## 8. Chaos Engineering

### 8.1 Principles
1. Start with a hypothesis: "System X can survive the loss of service Y"
2. Inject failure in a controlled way
3. Measure impact against SLOs
4. Fix weaknesses found

### 8.2 Failure Types to Test
- Pod termination (Chaos Monkey / `kubectl delete pod`)
- Node failure (`kubectl cordon` + `kubectl drain`)
- Network latency injection (tc netem, Istio fault injection)
- CPU/memory pressure (stress-ng)
- Disk full (dd)

### 8.3 Kubernetes Chaos Tools
```bash
# Chaos Mesh (CNCF)
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm install chaos-mesh chaos-mesh/chaos-mesh -n chaos-testing

# Inject pod failure
kubectl apply -f - <<EOF
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: pod-kill-example
spec:
  action: pod-kill
  mode: one
  selector:
    namespaces: [production]
    labelSelectors:
      app: api
  scheduler:
    cron: "@every 10m"
EOF
```
