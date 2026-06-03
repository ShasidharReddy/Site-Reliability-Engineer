# 03 — Kubernetes Reliability

This module focuses on keeping Kubernetes workloads healthy, available, and debuggable. It moves beyond simple `kubectl` familiarity and teaches the reliability controls that matter in real clusters.

## Prerequisites

- Basic Kubernetes object awareness
- Comfort with Linux command line and container basics
- Recommended completion of [01-monitoring-observability](../01-monitoring-observability/) and [02-sre-principles](../02-sre-principles/)

## What you'll learn

### Basic

- the purpose of Deployments, StatefulSets, DaemonSets, Jobs, and CronJobs
- how readiness, liveness, and startup probes affect traffic and recovery
- how to inspect workloads, pods, and events with `kubectl`

### Intermediate

- how requests, limits, and QoS classes influence stability
- how PodDisruptionBudgets protect workloads during maintenance
- how HPA and related autoscaling controls change capacity behavior
- how network policies shape service communication and blast radius

### Advanced

- how to debug scheduling, rollout, restart, and connectivity failures methodically
- how to simulate failure safely and observe controller behavior
- how to reason about reliability patterns such as graceful shutdown, redundancy, and isolation
- how to connect Kubernetes symptoms back to platform or application causes

## File index

| File | Description |
|---|---|
| [theory.md](theory.md) | Reliability-focused overview of Kubernetes internals, scaling, networking, and debugging |
| [labs/01-probe-configuration.md](labs/01-probe-configuration.md) | Lab for configuring health probes and understanding recovery behavior |
| [labs/02-resource-management.md](labs/02-resource-management.md) | Lab for requests, limits, and resource-pressure behavior |
| [labs/03-pdb-and-disruptions.md](labs/03-pdb-and-disruptions.md) | Lab for disruption planning and PodDisruptionBudget usage |
| [labs/04-hpa-autoscaling.md](labs/04-hpa-autoscaling.md) | Lab for horizontal autoscaling and demand-aware reliability |
| [labs/05-network-policy.md](labs/05-network-policy.md) | Lab for service isolation and traffic control with network policies |
| [labs/06-k8s-debugging-runbook.md](labs/06-k8s-debugging-runbook.md) | Debugging workflow for common Kubernetes failure modes |
| [troubleshooting.md](troubleshooting.md) | Scenario-based troubleshooting reference for common reliability incidents |
| [scenarios.md](scenarios.md) | Incident drill scenarios for scaling, OOM, rollout, and eviction events |
| [manifests/hpa-example.yaml](manifests/hpa-example.yaml) | Deployment, Service, and CPU HPA example for autoscaling practice |
| [manifests/custom-metrics-hpa.yaml](manifests/custom-metrics-hpa.yaml) | Prometheus-backed custom metrics HPA example |
| [manifests/keda-scaledobject.yaml](manifests/keda-scaledobject.yaml) | Queue-driven KEDA scaling example |
| [manifests/cluster-autoscaler-values.yaml](manifests/cluster-autoscaler-values.yaml) | Sample Helm values for Cluster Autoscaler tuning |
| [manifests/cluster-autoscaler-burst-test.yaml](manifests/cluster-autoscaler-burst-test.yaml) | Unschedulable workload used to trigger node scale-up tests |
| [manifests/network-policy-default-deny.yaml](manifests/network-policy-default-deny.yaml) | Default-deny starter policies for app, data, monitoring, and untrusted namespaces |
| [manifests/network-policy-allow-dns.yaml](manifests/network-policy-allow-dns.yaml) | DNS egress restore policies after default deny |
| [manifests/network-policy-frontend-api.yaml](manifests/network-policy-frontend-api.yaml) | Least-privilege frontend-to-API policy pair |
| [manifests/network-policy-api-postgres.yaml](manifests/network-policy-api-postgres.yaml) | Least-privilege API-to-Postgres policy pair |
| [manifests/network-policy-monitoring.yaml](manifests/network-policy-monitoring.yaml) | Monitoring namespace scrape access example |
| [manifests/pdb-example.yaml](manifests/pdb-example.yaml) | Advanced PodDisruptionBudget examples for stateless and stateful workloads |
| [manifests/prometheus-adapter-configmap.yaml](manifests/prometheus-adapter-configmap.yaml) | Prometheus Adapter rules for custom metrics APIs |
| [manifests/resource-quota.yaml](manifests/resource-quota.yaml) | ResourceQuota and LimitRange examples for namespace governance |
| [manifests/vpa-example.yaml](manifests/vpa-example.yaml) | VPA recommendation and initial-update examples |

## Key concepts covered

- workload selection and controller behavior
- health probes and safe traffic serving
- capacity management and resource pressure
- disruption tolerance and maintenance safety
- autoscaling strategy and trade-offs
- cluster networking and service isolation
- repeatable Kubernetes debugging sequences

## Practice suggestions

- Apply each example manifest in a disposable lab and explain what reliability problem it solves.
- Delete pods, change probes, or restrict traffic to create safe failure drills.
- Build a personal debugging checklist around `kubectl get`, `describe`, `logs`, `top`, and `events`.
- Pair this module with dashboards from the observability module so you can see cluster symptoms from both CLI and UI perspectives.

## Continue with the learning path

After this module, move into [04-incident-management](../04-incident-management/) and keep the big-picture sequence handy in [10-learning-paths](../10-learning-paths/README.md).
