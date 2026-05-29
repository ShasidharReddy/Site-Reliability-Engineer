# Lab 05: Network Policies

## Default Deny All
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}    # Matches all pods
  policyTypes:
  - Ingress
  - Egress
```

## Allow DNS
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - ports:
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP
```

## Allow Specific Service
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-api-from-frontend
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - port: 8080
```

## Test
```bash
kubectl apply -f network-policies/

# Should succeed (frontend -> api)
kubectl exec frontend-pod -- wget -qO- http://api:8080/health

# Should fail (other pods)
kubectl exec other-pod -- wget -qO- http://api:8080/health
```

## Verification
- [ ] Default-deny applied
- [ ] DNS still works after default-deny
- [ ] Only frontend can reach api
- [ ] Other pods receive connection refused/timeout
