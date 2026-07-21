# Sev2: Application / Service Degradation

**Impact**: `erp-services` or `erp-apps` (nitro-portal, rest-bpe, databases, etc.)

## Detection
- High 5xx error rate or latency in Prometheus
- HPA alerts
- User reports via ITSM

## Immediate Actions
```bash
kubectl get hpa -A
kubectl get pods -n erp-services -n erp-apps
kubectl top pods -A
```

## Diagnosis
```bash
kubectl logs --previous <pod>
kubectl describe pod <pod>
# Test connectivity
kubectl exec -it <pod> -n <ns> -- curl -I http://<service>:<port>
```

## Resolution
- Scale deployment: `kubectl scale deployment <name> --replicas=3 -n <ns>`
- Restart affected services
- Apply hotfix via GitOps PR
- Check Circuit Breaker / Rate Limiting status

## Prevention
- Strengthen resilience patterns (retries, circuit breakers, fallbacks)
- Ingress rate limiting
- Regular load & chaos testing

**Postmortem Recommended**
