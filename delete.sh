helm uninstall erp-uno --ignore-not-found 2>/dev/null || true
kubectl delete namespace erp-ai erp-infra erp-security erp-services erp-apps erp-telemetry erp-uno --ignore-not-found
