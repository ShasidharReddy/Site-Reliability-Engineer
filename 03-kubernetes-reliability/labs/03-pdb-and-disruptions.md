# Lab 03: PodDisruptionBudget

## Create PDB
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: api-pdb
  namespace: production
spec:
  selector:
    matchLabels:
      app: api
  minAvailable: 2      # OR: maxUnavailable: 1
```

```bash
kubectl apply -f pdb.yaml
kubectl get pdb -n production
```

## Test with Drain
```bash
# Cordon a node (no new pods)
kubectl cordon <node-name>

# Drain (evicts pods, respects PDB)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Watch: if PDB would be violated, drain blocks
# kubectl get pdb shows DISRUPTIONS ALLOWED
kubectl get pdb api-pdb -n production -w
```

## Uncordon
```bash
kubectl uncordon <node-name>
```

## Verify Zero Downtime
```bash
# While draining: continuously curl the service
while true; do curl -o /dev/null -s -w "%{http_code}" http://api-service/health; sleep 0.5; done
```

## Verification
- [ ] PDB created for all production deployments
- [ ] Drain blocked when PDB would be violated
- [ ] Service responded 200 throughout drain
