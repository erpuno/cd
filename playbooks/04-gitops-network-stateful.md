# GitOps, Network, & StatefulSet Issues

**Impact**: Sync failures, NetworkPolicy blocks, DB/StatefulSet problems (e.g. split-brain)

## Detection
- ArgoCD OutOfSync alerts
- Connectivity failures
- Replication lag in databases

## Immediate Actions
```bash
argocd app list
kubectl get networkpolicy -A
kubectl get statefulset -A
kubectl get pvc -A
```

## Diagnosis
```bash
argocd app get erp-uno
kubectl exec -it <pod> -- curl -v http://<service>
kubectl describe statefulset <name>
```

## Resolution
- Fix & sync GitOps manifests
- Update NetworkPolicies (erp-allow-internal)
- Force StatefulSet reconciliation or PVC restore

## Prevention
- CI validation for policies & manifests
- Regular chaos network tests
- Automated merge handlers for databases

**Postmortem Recommended for Sev1/2**
