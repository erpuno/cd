# Resource Exhaustion (CPU/Memory/PV)

**Impact**: Pods OOMKilled, High CPU, PersistentVolume full

## Detection
- Prometheus resource alerts
- Node pressure events

## Immediate Actions
```bash
kubectl top pods -A --sort-by=cpu
kubectl top nodes
df -h   # inside affected pods
```

## Diagnosis
- Check HPA status
- Review retention policies (Prometheus)
- PVC usage

## Resolution
```bash
# Temporary scale
kubectl scale deployment <name> --replicas=<higher> -n <ns>

# Clean Prometheus TSDB if needed
# Adjust resources in lib/*/deployment.yaml → regenerate values.yaml
```

## Prevention
- Improve resource budgeting (Handbook Section 16)
- Vertical Pod Autoscaler
- Automated compaction jobs
- Better PV sizing & retention policies
