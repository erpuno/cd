# Sev1: Cluster-Wide or Core Service Outage

**Impact**: Multiple namespaces or core platform (telemetry, security, ArgoCD) unavailable. SLO breach.

## Detection
- Prometheus `up` metric == 0 for critical components
- ArgoCD sync failures
- Grafana critical alerts

## Immediate Actions
```bash
kubectl get pods -A --field-selector=status.phase!=Running
kubectl get nodes
kubectl get events -A --sort-by=.metadata.creationTimestamp
argocd app list
```

## Diagnosis
- `kubectl describe pod <name> -n <ns>`
- `kubectl logs <pod> -n <ns> --previous`
- Node resources: `kubectl top nodes`
- Check NetworkPolicies and RBAC

## Resolution
1. Restart failing components (`kubectl rollout restart`)
2. Roll back via ArgoCD or Helm: `argocd app rollback` / `helm rollback`
3. Restore PVCs if needed
4. Scale critical services manually if HPA failed

## Prevention
- Regular Chaos Mesh tests (pod kill, node drain)
- Enforce resource requests/limits
- Multi-node HA setup

**Postmortem Required**
