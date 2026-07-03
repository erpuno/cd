helm uninstall erp-uno --wait || true
kubectl delete hpa,deployment,statefulset,service --all --all-namespaces --ignore-not-found
