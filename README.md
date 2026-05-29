# 🛡️ Site Reliability Engineer (SRE) — Complete Course Kit

> **Theory + Hands-on Labs + Interview Prep + Ready-to-Execute Scripts**
> Aligned to production SRE roles covering on-prem + GCP environments with Grafana/Kubernetes focus.

---

## 📋 Who This Is For

- Engineers preparing for SRE interviews or transitioning into reliability engineering
- DevOps/Platform engineers expanding into observability and incident management
- Teams building or improving monitoring/alerting stacks on Kubernetes + GCP

---

## 🗺️ Course Modules

| # | Module | What You Learn |
|---|--------|----------------|
| 01 | [Monitoring & Observability](01-monitoring-observability/) | Prometheus, PromQL, Grafana, Alertmanager, Loki, Tracing |
| 02 | [SRE Principles](02-sre-principles/) | SLIs, SLOs, Error Budgets, Toil, Chaos Engineering |
| 03 | [Kubernetes Reliability](03-kubernetes-reliability/) | K8s internals, GKE, PDB, HPA/VPA, debugging |
| 04 | [Incident Management](04-incident-management/) | SEV levels, Runbooks, RCA, Postmortems, PagerDuty |
| 05 | [GCP Operations](05-gcp-operations/) | Cloud Monitoring, GKE ops, IAM, Cloud Logging |
| 06 | [Linux & Networking](06-linux-networking/) | Kernel, memory, TCP/IP, DNS, performance tools |
| 07 | [Grafana Advanced](07-grafana-advanced/) | Dashboard design, alerting, provisioning, OnCall |
| 08 | [Application Support L2/L3](08-application-support-l2l3/) | Triage, ServiceNow, L2/L3 workflows |
| 📝 | [Interview Prep](interview-prep/) | 250+ Q&A, scenario-based, SRE-specific questions |

---

## 🔧 Prerequisites

Install these tools before starting labs:

```bash
# macOS
brew install kubectl helm minikube kind terraform python3
brew install --cask google-cloud-sdk

# Verify
kubectl version --client
helm version
minikube version
gcloud version
```

---

## 🚀 Quick Start (Get a Lab Running in 5 Minutes)

```bash
# 1. Bootstrap your lab environment
bash scripts/bootstrap-lab.sh

# 2. Deploy the full monitoring stack (Prometheus + Grafana + Loki)
bash scripts/deploy-monitoring-stack.sh

# 3. Open Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &
open http://localhost:3000  # admin / prom-operator
```

---

## 🎯 Job Description Alignment

| JD Requirement | Primary Module | Secondary Module |
|---|---|---|
| Grafana dashboards & alerting | 07-grafana-advanced | 01-monitoring-observability |
| Prometheus & observability stack | 01-monitoring-observability | — |
| SLIs, SLOs, error budgets | 02-sre-principles | — |
| Kubernetes (GKE + on-prem) | 03-kubernetes-reliability | 05-gcp-operations |
| Incident response, RCA, postmortems | 04-incident-management | — |
| GCP operations | 05-gcp-operations | — |
| Linux systems & troubleshooting | 06-linux-networking | — |
| L2/L3 application support | 08-application-support-l2l3 | 04-incident-management |
| On-call rotation | 04-incident-management | 07-grafana-advanced |

---

## 📌 ATS Keywords

`Site Reliability Engineering` · `SRE` · `Grafana` · `Prometheus` · `PromQL` · `Alertmanager`
`Kubernetes` · `GKE` · `Google Cloud Platform` · `GCP` · `Observability` · `Monitoring`
`SLI` · `SLO` · `Error Budget` · `Incident Management` · `On-Call` · `PagerDuty`
`ServiceNow` · `Linux` · `Bash` · `Python` · `Loki` · `Distributed Tracing`
`Helm` · `Terraform` · `Docker` · `CI/CD` · `DevOps` · `Platform Engineering`
`kube-prometheus-stack` · `Thanos` · `Grafana OnCall` · `RCA` · `Postmortem`
`High Availability` · `Reliability Engineering` · `L2/L3 Support` · `On-premises`

---

## 📂 Repository Structure

```
.
├── 01-monitoring-observability/   # Metrics, logs, traces
├── 02-sre-principles/             # SLIs, SLOs, error budgets
├── 03-kubernetes-reliability/     # K8s reliability patterns
├── 04-incident-management/        # Incidents, runbooks, postmortems
├── 05-gcp-operations/             # GCP + GKE operations
├── 06-linux-networking/           # Linux internals + networking
├── 07-grafana-advanced/           # Advanced Grafana
├── 08-application-support-l2l3/   # L2/L3 support workflows
├── interview-prep/                # 250+ interview Q&A
└── scripts/                       # Bootstrap + deploy scripts
```
