#!/bin/bash
# ERP/1 Helm Deployment with auto-patch on ownership errors

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$SCRIPT_DIR"

echo "╔════════════════════════════════════════════════════════╗"
echo "║    ERP/1: Підпримємство Helm Deployment                ║"
echo "╚════════════════════════════════════════════════════════╝"

# 1. Cleanup immutable resources (StatefulSet specs and Service clusterIPs are immutable)
echo -e "\n[1/5] Cleaning up immutable resources..."
# Delete conflicting StatefulSets / Deployments
kubectl delete statefulset prometheus -n erp-telemetry --ignore-not-found --force --grace-period=0 2>/dev/null || true
kubectl delete statefulset ldap-directory -n erp-security --ignore-not-found --force --grace-period=0 2>/dev/null || true
kubectl delete statefulset opensearch -n erp-telemetry --ignore-not-found --force --grace-period=0 2>/dev/null || true
kubectl delete deployment traefik-ingress -n erp-infra --ignore-not-found --force --grace-period=0 2>/dev/null || true

# Delete conflicting Services (transitioning from standard ClusterIP to Headless None, or port merges)
kubectl delete svc docker-registry -n erp-infra --ignore-not-found 2>/dev/null || true
kubectl delete svc ca-pki -n erp-security --ignore-not-found 2>/dev/null || true
kubectl delete svc ldap-directory -n erp-security --ignore-not-found 2>/dev/null || true
kubectl delete svc grafana -n erp-telemetry --ignore-not-found 2>/dev/null || true
kubectl delete svc opensearch -n erp-telemetry --ignore-not-found 2>/dev/null || true
kubectl delete svc prometheus -n erp-telemetry --ignore-not-found 2>/dev/null || true
kubectl delete svc traefik-ingress -n erp-infra --ignore-not-found 2>/dev/null || true

kubectl delete hpa --all --all-namespaces --ignore-not-found 2>/dev/null || true

# 2. Ensure namespaces exist before applying RBAC
echo -e "\n[2/5] Ensuring namespaces..."
kubectl apply -f "$SCRIPT_DIR/../share/namespaces.yaml"

# 3. Deploy shared infrastructure resources
echo -e "\n[3/5] Deploying shared infrastructure..."
kubectl apply -f "$SCRIPT_DIR/../share/rbac.yaml"
kubectl apply -f "$SCRIPT_DIR/../share/storage-class.yaml"
kubectl apply -f "$SCRIPT_DIR/../share/networkpolicy.yaml"
echo "    ✓ Shared resources applied"

# 4. Patch Helm ownership metadata (idempotent — safe to run every time)
#    Required because kubectl apply creates resources without Helm annotations.
echo -e "\n[4/5] Patching Helm ownership metadata..."
bash "$SCRIPT_DIR/patch.sh" 2>/dev/null
echo "    ✓ Ownership metadata patched"

# 5. Deploy main Helm chart (install or upgrade)
echo -e "\n[5/5] Deploying Helm chart..."
helm upgrade --install erp-uno "$CHART_DIR" \
  --values "$CHART_DIR/values.yaml" \
  --set global.domain=erp.uno \
  --set global.environment=production \
  --server-side=true \
  --force-conflicts

echo
echo "╔════════════════════════════════════════════════════════╗"
echo "║           Helm Deployment Complete ✓                   ║"
echo "╚════════════════════════════════════════════════════════╝"

echo -e "\n📊 Quick Status:"
kubectl get ns | grep erp
echo "Pods:"
kubectl get pods -A --no-headers 2>/dev/null | awk '{print $4}' | sort | uniq -c | sort -rn
echo ""
echo "🌐 Useful commands:"
echo "   kubectl get pods -A"
echo "   kubectl get hpa -A"
echo "   helm status erp-uno"
echo "   helm history erp-uno"
