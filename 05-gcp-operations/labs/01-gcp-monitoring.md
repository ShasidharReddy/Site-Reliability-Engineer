# Lab 01: GCP Cloud Monitoring

## Setup
```bash
# Verify gcloud auth
gcloud auth list
gcloud config get-value project
```

## Create an Uptime Check
```bash
gcloud monitoring uptime create-http \
  --project=$PROJECT_ID \
  --display-name="API Health Check" \
  --uri="https://api.example.com/health" \
  --period=60 \
  --content-match="ok"
```

## Create an Alert Policy
```bash
# List available metrics
gcloud monitoring metrics list --filter="metric.type:kubernetes" | head -30

# Create alert for high CPU
gcloud alpha monitoring policies create \
  --notification-channels=<channel-id> \
  --display-name="High CPU Alert" \
  --condition-display-name="CPU > 80%" \
  --condition-threshold-filter='resource.type="k8s_container"' \
  --condition-threshold-value=0.8 \
  --condition-threshold-duration=300s \
  --condition-threshold-comparison=COMPARISON_GT
```

## Cloud Logging Queries
```bash
# Query logs via CLI
gcloud logging read 'resource.type="k8s_container" AND severity>=ERROR' \
  --project=$PROJECT_ID \
  --limit=50 \
  --format=json

# Specific service logs
gcloud logging read 'resource.labels.container_name="payment-api" AND severity="ERROR"' \
  --freshness=1h \
  --project=$PROJECT_ID
```

## Log-Based Metrics
```bash
# Create a log-based metric (count of 500 errors)
gcloud logging metrics create http-500-errors \
  --description="Count of HTTP 500 errors" \
  --log-filter='resource.type="k8s_container" AND jsonPayload.status_code=500'
```

## Verification
- [ ] Uptime check created and visible in Cloud Monitoring
- [ ] Alert policy configured with notification channel
- [ ] Log queries return results
- [ ] Log-based metric appears in Cloud Monitoring
