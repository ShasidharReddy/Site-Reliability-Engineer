Site Reliability Engineer (SRE) - Theory

1. Role Overview
- Focus: monitoring, observability, reliability across on-prem and GCP
- Primary tools: Grafana, Prometheus, Alertmanager, logging and tracing stacks
- Secondary: L2/L3 app support, on-call rotation, SEV response

2. Monitoring & Observability
- Signals: metrics (Prometheus), logs (ELK/Fluent/Cloud Logging), traces (Jaeger/Tempo)
- Target: high signal-to-noise alerts, useful dashboards
- Dashboards: infrastructure, k8s, app, SLO/SLA views

3. SRE Principles
- SLIs, SLOs, error budgets
- Automate toil, runbooks, blameless postmortems
- Capacity planning and resiliency patterns

4. Alerts & Incident Response
- Alert design: meaningful thresholds, avoid flapping, use grouping and dedupe
- Runbooks: triage steps, escalation, mitigation, RCA
- Tools: PagerDuty, ServiceNow, Slack

5. Kubernetes Reliability
- Monitor: node, kubelet, API server, scheduler, controller-manager
- Monitor workloads: pod restarts, OOMs, liveness/readiness failures
- Capacity: requests/limits, HPA, cluster autoscaler, resource quotas

6. Hybrid Clouds (On-prem + GCP)
- Centralize metrics and logs using federation or remote_write to managed backends
- Secure cross-site connectivity (VPN, VPC peering, private GKE)
- Use GCP tools where appropriate: Stackdriver/Cloud Monitoring, GKE-specific metrics

7. Observability Standards & Best Practices
- Naming conventions for metrics and labels
- Dashboards per service and shared infra views
- Alerting runbook linkage in each alert

