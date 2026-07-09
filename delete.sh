#!/bin/bash
set -e
helm uninstall erp-uno --ignore-not-found 2>/dev/null || true
kubectl delete ns argocd erp-infra erp-telemetry erp-ai erp-security erp-services erp-apps erp-uno --ignore-not-found --grace-period=0 2>/dev/null || true
kind delete cluster --name synrc 2>/dev/null || true
