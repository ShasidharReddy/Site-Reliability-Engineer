# 05 — GCP Operations

This module focuses on day-to-day operational work in Google Cloud Platform, especially the areas that intersect directly with SRE responsibilities: IAM, GKE, Cloud Monitoring, and Cloud Logging. It helps bridge the gap between local labs and managed-cloud reality.

## Prerequisites

- Basic cloud concepts such as projects, regions, and managed services
- Comfort with Linux command line and Kubernetes basics
- Recommended completion of [03-kubernetes-reliability](../03-kubernetes-reliability/) and [04-incident-management](../04-incident-management/)

## What you'll learn

### Basic

- how GCP projects, IAM, and managed services relate to operations work
- how GKE differs from purely local Kubernetes labs
- where Cloud Monitoring and Cloud Logging fit into incident investigation

### Intermediate

- how to inspect cluster health and operational posture in GKE
- how IAM roles and permissions affect troubleshooting and safety
- how to query logs, inspect metrics, and validate access patterns in GCP
- how to use repository scripts for health checks and planned maintenance tasks

### Advanced

- how to approach production changes in managed Kubernetes carefully
- how to think about least privilege, operational access, and auditability together
- how to compare control-plane responsibilities between self-managed and managed clusters
- how to combine GCP-native telemetry with Kubernetes-native troubleshooting

## File index

| File | Description |
|---|---|
| [theory.md](theory.md) | Overview of IAM, VPC context, Cloud Monitoring, GKE operations, and Cloud Logging |
| [labs/01-gcp-monitoring.md](labs/01-gcp-monitoring.md) | Lab for setting up and using monitoring and alerting in GCP |
| [labs/02-gke-operations.md](labs/02-gke-operations.md) | Lab for GKE operational checks, workload review, and platform reliability tasks |
| [labs/03-iam-and-access.md](labs/03-iam-and-access.md) | Lab for secure access patterns, permissions, and IAM reasoning |
| [labs/04-cloud-logging.md](labs/04-cloud-logging.md) | Lab for Cloud Logging search, filters, and investigation workflows |
| [scripts/gcp-health-check.sh](scripts/gcp-health-check.sh) | Script for basic GCP infrastructure and service health validation |
| [scripts/gke-node-drain.sh](scripts/gke-node-drain.sh) | Script for safer node drain execution with pre-checks and operator guardrails |

## Key concepts covered

- GCP operational model and shared responsibility
- IAM and least-privilege thinking
- GKE cluster operations and maintenance safety
- Cloud Monitoring and alert visibility
- Cloud Logging queries and evidence collection
- automation support for repetitive platform checks

## Practice suggestions

- Authenticate to a non-production project and review active configuration before every command.
- Compare what you can see in `kubectl` versus what you can see in Cloud Monitoring and Cloud Logging.
- Read IAM bindings for a project and explain which roles are needed for day-to-day operations.
- Practice safe maintenance thinking by reviewing the node-drain script before attempting cluster changes.

## Continue with the learning path

This module fits best after Kubernetes and incident-response work. Continue with [07-grafana-advanced](../07-grafana-advanced/), [09-production-readiness](../09-production-readiness/), or the full roadmap in [10-learning-paths](../10-learning-paths/README.md).
