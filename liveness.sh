#!/usr/bin/env bash
# liveness.sh - Monitor erp-uno cluster liveness and retrieve latest events
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGOCD_SERVER="127.0.0.1:8080"
APP_NAME="erp-uno"

echo "╔════════════════════════════════════════════════════════════════════════════════╗"
echo "║                   ERP/1: Cluster Liveness & Events Monitor                     ║"
echo "╚════════════════════════════════════════════════════════════════════════════════╝"

# 1. Check Kubernetes Cluster liveness
echo -e "\n[1/4] Checking Kubernetes API Server and Node Liveness..."
if ! kubectl cluster-info &>/dev/null; then
  echo "❌ Kubernetes cluster is unreachable!"
  exit 1
fi
kubectl get nodes
echo "    ✓ Cluster nodes are active"

# 2. Check ArgoCD Server connectivity
echo -e "\n[2/4] Checking ArgoCD Server Connection ($ARGOCD_SERVER)..."
if ! curl -s --fail "http://$ARGOCD_SERVER" >/dev/null; then
  echo "❌ Cannot connect to ArgoCD Server at http://$ARGOCD_SERVER"
  echo "   Please verify that the background port-forward is running:"
  echo "   launchctl list | grep uno.erp.argocd-portforward"
  exit 1
fi
echo "    ✓ Connection successful"

# 3. Authenticate ArgoCD CLI if needed
if ! argocd account get-user-info --server "$ARGOCD_SERVER" --plaintext &>/dev/null; then
  echo "    Authenticating ArgoCD CLI..."
  PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
  argocd login "$ARGOCD_SERVER" --plaintext --skip-test-tls --username admin --password "$PASSWORD" >/dev/null
fi

# 4. Check ArgoCD Application and Cluster Liveness
echo -e "\n[3/4] Querying ArgoCD Cluster & App Liveness..."
argocd cluster list --server "$ARGOCD_SERVER" --plaintext
echo ""
argocd app get "$APP_NAME" --server "$ARGOCD_SERVER" --plaintext

# 5. Fetch latest events (Warning/Error/Info) from cluster namespaces
echo -e "\n[4/4] Retrieving latest events (Error/Warning/Info) in ERP namespaces..."
printf '%.0s-' {1..80}; echo ""
kubectl get events -A --sort-by='.metadata.creationTimestamp' \
  | grep -E "erp-|argocd|default" \
  | awk '{
      ns = $1
      time = $2
      type = $3
      obj = $5
      msg = ""
      for(i=6; i<=NF; i++) {
        msg = msg (i==6 ? "" : " ") $i
      }
      line = sprintf("%-13.13s %-5.5s %-7.7s %-38.38s %-40.80s", ns, time, type, obj, msg)
      print line
    }' \
  | tail -n 25 || echo "No recent events found"
printf '%.0s-' {1..80}; echo ""
