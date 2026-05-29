# Escalation Matrix

| Service / Area | SEV1 (P1) | SEV2 (P2) | SEV3 (P3) | After-Hours |
|----------------|-----------|-----------|-----------|-------------|
| **Production API** | @sre-primary (PagerDuty) | @sre-team Slack | #sre-alerts ticket | @sre-primary (PD) |
| **Database** | @dba-oncall + @sre-lead | @dba-team | Create JIRA ticket | @dba-oncall (PD) |
| **Kubernetes / Platform** | @platform-sre | @platform-sre | Slack + Ticket | @platform-sre (PD) |
| **Networking / VPN** | @network-oncall | @network-team | Ticket | @network-oncall (PD) |
| **Security Incident** | @security-oncall + @ciso | @security-team | @security-team | @security-oncall (PD) |
| **GCP / Cloud** | @sre-lead + GCP Support | @sre-team | Ticket | @sre-lead (PD) |

## Notification Channels

| Channel | Purpose |
|---------|---------|
| `#inc-active` | Active SEV1/SEV2 incidents |
| `#sre-alerts` | All automated alerts |
| `#releases` | Deployment notifications |
| `#status-updates` | Stakeholder communications |

## Leadership Escalation

| When to Escalate to Leadership | Contact |
|-------------------------------|---------|
| SEV1 > 30 min unresolved | Engineering Director |
| Data breach suspected | CISO + Legal |
| External SLA breach | VP Engineering + Customer Success |
| Media coverage / social media | Communications team |
