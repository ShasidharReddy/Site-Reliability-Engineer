# 05 — Troubleshooting Playbooks

Use a deterministic flow: **Detect -> Scope -> Contain -> Mitigate -> Recover -> Learn**.

## Fast Triage Checklist

```bash
kubectl get nodes
kubectl get pods -A | grep -vE "Running|Completed"
kubectl get events -A --field-selector type=Warning | tail -20
```

## Common Production Failures

### 1. Grafana is unreachable

1. Confirm pod and service:
   ```bash
   kubectl get pods,svc -n monitoring | grep grafana
   ```
2. Verify port-forward:
   ```bash
   kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
   ```
3. Confirm credentials:
   ```bash
   kubectl get secret grafana-admin-credentials -n monitoring \
     -o jsonpath='{.data.admin-password}' | base64 --decode; echo
   ```

### 2. Prometheus scrape targets are down

1. Open Prometheus targets page.
2. Validate ServiceMonitor/PodMonitor selectors and namespace labels.
3. Check network policies and TLS settings.

### 3. Alert storm / noisy paging

1. Silence duplicate alerts in Alertmanager.
2. Tune alert thresholds and `for:` duration.
3. Add dedup labels and route by ownership.

### 4. Node drain blocked in GKE

Use safe drain helper:

```bash
bash 05-gcp-operations/scripts/gke-node-drain.sh <node-name>
```

It checks PDB impact before attempting eviction.

### 5. High latency or error spikes

1. Correlate Grafana metrics + Loki logs + Tempo traces.
2. Find first bad deploy/change window.
3. Roll back or scale out, then capture evidence for RCA.

## Post-Incident Standards

- Create/update runbook in `04-incident-management/templates/`.
- Capture a blameless postmortem with action items and owners.
- Add a preventive alert or dashboard panel if visibility was missing.

