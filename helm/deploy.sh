#!/bin/bash
# Helm multi-namespace deployment script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$SCRIPT_DIR"

echo "╔════════════════════════════════════════════════════════╗"
echo "║    ERP.uno Multi-Namespace Helm Deployment            ║"
echo "╚════════════════════════════════════════════════════════╝"

# Create namespaces first
echo -e "\n[1/3] Creating namespaces..."
kubectl apply -f "$SCRIPT_DIR/../shared/namespaces.yaml"
echo "    ✓ Namespaces created"

# Deploy shared resources
echo -e "\n[2/3] Deploying shared infrastructure..."
kubectl apply -f "$SCRIPT_DIR/../shared/rbac.yaml"
kubectl apply -f "$SCRIPT_DIR/../shared/storage-class.yaml"
kubectl apply -f "$SCRIPT_DIR/../shared/networkpolicy.yaml"
echo "    ✓ Shared resources deployed"

# Deploy Helm chart
echo -e "\n[3/3] Deploying Helm chart..."
helm upgrade --install erp-uno "$CHART_DIR" \
  --values "$CHART_DIR/values.yaml" \
  --set global.domain=erp.uno \
  --set global.environment=production \
  >&1 | tail -10

echo -e "\n╔════════════════════════════════════════════════════════╗"
echo "║           Helm Deployment Complete ✓                  ║"
echo "╚════════════════════════════════════════════════════════╝"

echo -e "\n📊 Check Status:"
echo "   kubectl get pods -A"
echo "   kubectl get ns"

echo ""
