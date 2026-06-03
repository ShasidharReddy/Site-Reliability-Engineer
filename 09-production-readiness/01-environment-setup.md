# 01 — Environment Setup

This setup is intentionally production-aligned: reproducible, multi-node, and automation-friendly.

## Toolchain Baseline

Required:
- `kubectl`
- `helm`

Recommended:
- `kind` for local multi-node parity
- `gcloud` for GKE labs
- `terraform` for IaC exercises

Run:

```bash
make setup
```

## Local Lab (kind)

The repository ships with `configs/kind-sre-lab.yaml` (1 control plane + 3 workers).

```bash
make run-local
```

This creates (or reuses) a local cluster and deploys:
- `kube-prometheus-stack`
- `loki`
- `tempo`

## Production / Cloud Lab (GKE)

1. Authenticate and choose project:

```bash
gcloud auth login
gcloud config set project <PROJECT_ID>
```

2. Connect cluster context:

```bash
gcloud container clusters get-credentials <CLUSTER> --zone <ZONE> --project <PROJECT_ID>
```

3. Deploy stack:

```bash
make deploy
```

## Secrets and Credentials

- Grafana admin credentials are stored in `monitoring/grafana-admin-credentials`.
- Alert routing placeholders are stored in `monitoring/alertmanager-secrets`.
- Replace placeholders with real PagerDuty/Slack values before production use.

