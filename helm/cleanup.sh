helm uninstall erp-uno
kubectl delete hpa,deployment,statefulset,service --all --all-namespaces --ignore-not-found
