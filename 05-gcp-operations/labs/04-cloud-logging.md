# Lab 04: Cloud Logging and Export

## Log Export to BigQuery
```bash
# Create BigQuery dataset
bq mk --dataset $PROJECT_ID:sre_logs

# Create log sink
gcloud logging sinks create sre-audit-logs \
  bigquery.googleapis.com/projects/$PROJECT_ID/datasets/sre_logs \
  --log-filter='resource.type="k8s_container" AND severity>=WARNING'

# Grant sink SA write permission to BQ
sink_sa=$(gcloud logging sinks describe sre-audit-logs --format='value(writerIdentity)')
bq add-iam-policy-binding --member=$sink_sa --role=roles/bigquery.dataEditor $PROJECT_ID:sre_logs
```

## Query Logs in BigQuery
```sql
SELECT
  timestamp,
  resource.labels.container_name,
  jsonPayload.message,
  severity
FROM `sre_logs.k8s_container_*`
WHERE severity = 'ERROR'
  AND timestamp > TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
ORDER BY timestamp DESC
LIMIT 100;
```

## Log Router for Multi-Destination
```bash
# Route critical errors to Pub/Sub for PagerDuty
gcloud logging sinks create critical-errors-pd \
  pubsub.googleapis.com/projects/$PROJECT_ID/topics/critical-alerts \
  --log-filter='severity=CRITICAL OR severity=EMERGENCY'
```

## Verification
- [ ] Log sink created and routing to BigQuery
- [ ] BigQuery dataset has logs populated
- [ ] SQL query returns log records
