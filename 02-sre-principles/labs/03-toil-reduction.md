# Lab 03: Toil Reduction

## What is Toil?
Manual, repetitive, automatable, reactive work that scales with service growth.
Target: <50% SRE time on toil.

## Part 1: Toil Audit (1 week log)

| Date | Task | Time | Automatable? |
|------|------|------|--------------|
| Mon  | Restart flapping pod | 5min | Yes — liveness probe |
| Mon  | Update Grafana manually | 20min | Yes — provisioning |
| Tue  | False-positive alert | 10min | Yes — tune alert |
| Wed  | Rotate API key | 15min | Yes — auto-rotation |

## Part 2: Automate Common Toil

### Auto-Restart via Liveness Probe
```yaml
livenessProbe:
  httpGet:
    path: /health/live
    port: 8080
  periodSeconds: 10
  failureThreshold: 3
```

### Cleanup Stale Pods (CronJob)
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cleanup-failed-pods
spec:
  schedule: "*/30 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: cleanup
            image: bitnami/kubectl
            command: ["/bin/sh", "-c",
              "kubectl get pods -A --field-selector=status.phase=Failed -o name | xargs kubectl delete --ignore-not-found"]
          restartPolicy: OnFailure
```

## Part 3: Measure Progress

Track weekly:
- Pages per week
- MTTR trend
- Manual tasks count
- Time spent on toil vs project work

## Verification
- [ ] Toil log for 1 week completed
- [ ] Top 3 toil items identified
- [ ] At least 1 automation implemented
- [ ] Time savings estimated
