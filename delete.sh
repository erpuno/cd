helm uninstall erp-uno --ignore-not-found 2>/dev/null || true
kubectl delete ns erp-infra erp-telemetry erp-ai erp-security erp-services erp-apps erp-uno --ignore-not-found --grace-period=0
