# Lab 02 — Error Budget Tracking & Policy

## Overview
Set up automated error budget tracking and implement the error budget policy workflow.

## Step 1 — Simulate SLO breach
```bash
# Deploy a deliberately broken service
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: error-generator
spec:
  replicas: 1
  selector:
    matchLabels:
      app: error-gen
  template:
    metadata:
      labels:
        app: error-gen
    spec:
      containers:
      - name: app
        image: nginx:alpine
        command: ["/bin/sh", "-c"]
        args:
          - |
            # Return 500 errors 10% of the time
            while true; do
              echo "Simulating traffic..."
              sleep 1
            done
EOF
```

## Step 2 — Error Budget Burn Rate Alert Test
```bash
# Port-forward Prometheus and check burn rate
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &

# Query current burn rate (should be near 0 with no errors)
curl -s 'http://localhost:9090/api/v1/query?query=job:http_error_ratio:rate5m' | python3 -m json.tool
```

## Step 3 — Create Weekly Error Budget Report Script
```bash
cat > ~/error-budget-report.sh << 'SCRIPT'
#!/bin/bash
PROMETHEUS_URL="http://localhost:9090"
SLO_TARGET=0.999

echo "=== Error Budget Report - $(date +%Y-%m-%d) ==="
echo ""

# Get current error ratio (last 7 days)
RATIO=$(curl -s "${PROMETHEUS_URL}/api/v1/query?query=1-sum(rate(http_requests_total{status!~'5..'}[7d]))/sum(rate(http_requests_total[7d]))" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['result'][0]['value'][1] if d['data']['result'] else '0')" 2>/dev/null || echo "0")

BUDGET_USED=$(echo "$RATIO $(1 - $SLO_TARGET)" | awk '{printf "%.1f", ($1 / $2) * 100}')
echo "SLO Target:        ${SLO_TARGET} (99.9%)"
echo "Current Error Rate: ${RATIO}"
echo "Budget Used:        ${BUDGET_USED}%"
echo "Budget Remaining:   $(echo $BUDGET_USED | awk '{printf "%.1f", 100 - $1}')%"
echo ""
if (( $(echo "$BUDGET_USED > 100" | bc -l) )); then
  echo "⛔ STATUS: SLO BREACHED — Feature freeze required"
elif (( $(echo "$BUDGET_USED > 75" | bc -l) )); then
  echo "🔴 STATUS: High burn — freeze risky changes"
elif (( $(echo "$BUDGET_USED > 50" | bc -l) )); then
  echo "🟡 STATUS: Elevated — slow down risky deploys"
else
  echo "✅ STATUS: Healthy — normal operations"
fi
SCRIPT
chmod +x ~/error-budget-report.sh
bash ~/error-budget-report.sh
```
