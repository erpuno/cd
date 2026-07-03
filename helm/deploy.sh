#!/bin/bash
# helm/deploy.sh - Clean & robust Helm deployment for ERP.uno

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$SCRIPT_DIR"

echo "╔════════════════════════════════════════════════════════╗"
echo "║    ERP.uno Multi-Namespace Helm Deployment            ║"
echo "╚════════════════════════════════════════════════════════╝"

# 1. Cleanup immutable resources (prevents common StatefulSet / HPA conflicts)
echo -e "\n[1/4] Cleaning up immutable resources..."
kubectl delete statefulset prometheus -n erp-telemetry --ignore-not-found --force --grace-period=0 || true
kubectl delete hpa --all --all-namespaces --ignore-not-found || true

# 2. Deploy namespaces (Helm will manage them)
echo -e "\n[2/4] Ensuring namespaces..."
kubectl apply -f "$SCRIPT_DIR/../shared/namespaces.yaml"

# 3. Deploy shared resources
echo -e "\n[3/4] Deploying shared infrastructure..."
kubectl apply -f "$SCRIPT_DIR/../shared/rbac.yaml"
kubectl apply -f "$SCRIPT_DIR/../shared/storage-class.yaml"
kubectl apply -f "$SCRIPT_DIR/../shared/networkpolicy.yaml"
echo "    ✓ Shared resources applied"

# 4. Deploy main Helm chart
echo -e "\n[4/4] Deploying Helm chart..."
helm upgrade --install erp-uno "$CHART_DIR" \
  --values "$CHART_DIR/values.yaml" \
  --set global.domain=erp.uno \
  --set global.environment=production \
  --cleanup-on-fail

echo -e "\n╔════════════════════════════════════════════════════════╗"
echo "║           Helm Deployment Complete ✓                  ║"
echo "╚════════════════════════════════════════════════════════╝"

echo -e "\n📊 Quick Status:"
kubectl get ns
echo "Pods:"
kubectl get pods -A --no-headers | wc -l | xargs echo "   Total running pods:"

echo -e "\n🌐 Useful commands:"
echo "   kubectl get pods -A"
echo "   kubectl get hpa -A"
echo "   helm status erp-uno"
echo "   helm history erp-uno"
