#!/bin/bash
set -euo pipefail

BACKUP_DIR="${1:-.}"

if [ ! -d "$BACKUP_DIR" ] || [ ! -f "$BACKUP_DIR/manifests.yaml" ]; then
  echo "❌ Error: Invalid backup directory"
  echo "Usage: $0 <backup_directory>"
  exit 1
fi

echo "📦 Complete Restore (All PVCs & StatefulSets)"
echo "Backup: $BACKUP_DIR"
echo ""

# Step 1: Apply manifests
echo "[1] Applying Kubernetes manifests..."
kubectl apply -f "$BACKUP_DIR/manifests.yaml" 2>&1 | grep -E "(created|configured|unchanged)" | head -20 || true
echo "✅ Manifests applied"
echo ""

# Step 2: Stop pods for PVC restore
echo "[2] Stopping pods (unmounting volumes for restore)..."

# Get all StatefulSets
STS_LIST=$(kubectl get statefulset --all-namespaces -o json 2>/dev/null | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' || true)
while read -r ns sts; do
  if [ -n "$ns" ] && [ -n "$sts" ]; then
    echo "   Scaling down: $ns/$sts"
    kubectl scale statefulset -n "$ns" "$sts" --replicas=0 2>/dev/null || true
  fi
done <<< "$STS_LIST"

# Get all Deployments with PVCs
DEPLOY_WITH_PVC=$(kubectl get deployment --all-namespaces -o json 2>/dev/null | jq -r '.items[] | select(.spec.template.spec.volumes[]?.persistentVolumeClaim) | "\(.metadata.namespace) \(.metadata.name)"' || true)
while read -r ns deploy; do
  if [ -n "$ns" ] && [ -n "$deploy" ]; then
    echo "   Scaling down: $ns/$deploy"
    kubectl scale deployment -n "$ns" "$deploy" --replicas=0 2>/dev/null || true
  fi
done <<< "$DEPLOY_WITH_PVC"

sleep 3
echo "✅ Pods stopped"
echo ""

# Step 3: Restore each PVC device image
echo "[3] Restoring PVC device images..."

for backup_file in "$BACKUP_DIR"/*.tar.gz; do
  if [ ! -f "$backup_file" ]; then
    continue
  fi
  
  basename=$(basename "$backup_file" .tar.gz)
  
  # Parse namespace and pvc name from backup filename
  # Format: namespace-pvcname
  ns=$(echo "$basename" | cut -d'-' -f1)
  pvc=$(echo "$basename" | cut -d'-' -f2-)
  
  # Get PVC and its backing PV
  PV_NAME=$(kubectl get pvc -n "$ns" "$pvc" -o jsonpath='{.spec.volumeName}' 2>/dev/null || echo "")
  HOSTPATH=$(kubectl get pv "$PV_NAME" -o jsonpath='{.spec.hostPath.path}' 2>/dev/null || echo "")
  
  if [ -z "$HOSTPATH" ]; then
    echo "   ⚠️  $basename: PVC not found or has no HostPath"
    continue
  fi
  
  echo "   Restoring: $ns/$pvc"
  echo "      Backup: $basename.tar.gz"
  echo "      Target: $HOSTPATH"
  
  # Clear existing data
  docker exec synrc-control-plane rm -rf "$HOSTPATH"/* 2>/dev/null || true
  
  # Extract device image
  docker exec synrc-control-plane mkdir -p "$(dirname "$HOSTPATH")" 2>/dev/null || true
  
  # Use stdin streaming for tar extraction
  tar -xzf "$backup_file" -C "$(dirname "$HOSTPATH")" 2>/dev/null || {
    echo "      ❌ Restore failed"
    continue
  }
  
  SIZE=$(du -sh "$HOSTPATH" 2>/dev/null | cut -f1)
  FILE_COUNT=$(find "$HOSTPATH" -type f 2>/dev/null | wc -l)
  echo "      ✅ Restored ($SIZE, $FILE_COUNT files)"
done

echo ""

# Step 4: Restart pods
echo "[4] Restarting pods..."

# Restart StatefulSets
while read -r ns sts; do
  if [ -n "$ns" ] && [ -n "$sts" ]; then
    REPLICAS=$(kubectl get statefulset -n "$ns" "$sts" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    echo "   Scaling up: $ns/$sts to $REPLICAS replicas"
    kubectl scale statefulset -n "$ns" "$sts" --replicas="$REPLICAS" 2>/dev/null || true
  fi
done <<< "$STS_LIST"

# Restart Deployments
while read -r ns deploy; do
  if [ -n "$ns" ] && [ -n "$deploy" ]; then
    REPLICAS=$(kubectl get deployment -n "$ns" "$deploy" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    echo "   Scaling up: $ns/$deploy to $REPLICAS replicas"
    kubectl scale deployment -n "$ns" "$deploy" --replicas="$REPLICAS" 2>/dev/null || true
  fi
done <<< "$DEPLOY_WITH_PVC"

sleep 5
echo "✅ Pods restarted"
echo ""

# Step 5: Verify
echo "[5] Verifying restoration..."
echo ""
echo "PVC Status:"
kubectl get pvc --all-namespaces
echo ""
echo "Pod Status:"
kubectl get pods --all-namespaces | grep -E "(Running|Pending|CrashLoop)" | head -15
echo ""

echo "✅ Complete restore finished!"
echo ""
echo "Next steps:"
echo "  kubectl get pods -A          # Check pod status"
echo "  kubectl logs <pod> -n <ns>   # Check pod logs"
echo "  ./view.sh $BACKUP_DIR         # Verify backup contents"
