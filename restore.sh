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
kubectl apply --server-side --force-conflicts -f "$BACKUP_DIR/manifests.yaml"
echo "✅ Manifests applied"
echo ""

# Step 1.5: Wait for PVCs to bind (triggers dynamic volume provisioning)
echo "[1.5] Waiting for PVCs to be Bound..."
for backup_file in "$BACKUP_DIR"/*.tar.gz; do
  if [ ! -f "$backup_file" ]; then
    continue
  fi
  basename=$(basename "$backup_file" .tar.gz)
  ns=$(echo "$basename" | cut -d'@' -f1)
  pvc=$(echo "$basename" | cut -d'@' -f2)
  echo "   Waiting for PVC: $ns/$pvc to be Bound..."
  for i in {1..60}; do
    STATUS=$(kubectl get pvc -n "$ns" "$pvc" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
    if [ "$STATUS" = "Bound" ]; then
      echo "      Bound!"
      break
    fi
    sleep 1
  done

  FINAL_STATUS=$(kubectl get pvc -n "$ns" "$pvc" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Pending")
  if [ "$FINAL_STATUS" != "Bound" ]; then
    echo "   ⚠️  Warning: PVC $ns/$pvc is still $FINAL_STATUS after 60s"
  fi
done
echo ""

# Step 2: Stop pods for PVC restore
echo "[2] Stopping pods (unmounting volumes for restore)..."

# Get all StatefulSets
STS_LIST=$(kubectl get statefulset --all-namespaces -o json 2>/dev/null | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name) \(.spec.replicas // 1)"' || true)
while read -r ns sts replicas; do
  if [ -n "$ns" ] && [ -n "$sts" ]; then
    echo "   Scaling down: $ns/$sts"
    kubectl scale statefulset -n "$ns" "$sts" --replicas=0 2>/dev/null || true
  fi
done <<< "$STS_LIST"

# Get all Deployments with PVCs
DEPLOY_WITH_PVC=$(kubectl get deployment --all-namespaces -o json 2>/dev/null | jq -r '.items[] | select(.spec.template.spec.volumes != null) | select(any(.spec.template.spec.volumes[]; .persistentVolumeClaim != null)) | "\(.metadata.namespace) \(.metadata.name) \(.spec.replicas // 1)"' || true)
while read -r ns deploy replicas; do
  if [ -n "$ns" ] && [ -n "$deploy" ]; then
    echo "   Scaling down: $ns/$deploy"
    kubectl scale deployment -n "$ns" "$deploy" --replicas=0 2>/dev/null || true
  fi
done <<< "$DEPLOY_WITH_PVC"


echo "   Waiting for pods to terminate completely (unmount volumes)..."
NAMESPACES="erp-infra erp-telemetry erp-security erp-ai erp-services erp-apps"
for i in {1..45}; do
  ACTIVE_PODS=""
  for ns in $NAMESPACES; do
    NS_PODS=$(kubectl get pods -n "$ns" -o json 2>/dev/null | jq -r '.items[] | select(.spec.volumes != null) | select(any(.spec.volumes[]; .persistentVolumeClaim != null)) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || true)
    if [ -n "$NS_PODS" ]; then
      ACTIVE_PODS="${ACTIVE_PODS}${NS_PODS}"$'\n'
    fi
  done
  ACTIVE_PODS=$(echo "$ACTIVE_PODS" | sed '/^$/d' || true)
  
  if [ -z "$ACTIVE_PODS" ]; then
    break
  fi
  
  echo "      Still waiting for pods to terminate..."
  sleep 1
done
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
  # Format: namespace@pvcname
  ns=$(echo "$basename" | cut -d'@' -f1)
  pvc=$(echo "$basename" | cut -d'@' -f2)

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

  # Clear and recreate target directory to ensure it is clean
  docker exec synrc-control-plane rm -rf "$HOSTPATH" 2>/dev/null || true
  docker exec synrc-control-plane mkdir -p "$HOSTPATH" 2>/dev/null || true

  # Use stdin streaming for tar extraction directly into HOSTPATH stripping the old directory name
  docker exec -i synrc-control-plane tar -xzf - --strip-components=1 -C "$HOSTPATH" < "$backup_file" 2>/dev/null || {
    echo "      ❌ Restore failed"
    continue
  }

  SIZE=$(docker exec synrc-control-plane du -sh "$HOSTPATH" 2>/dev/null | cut -f1 || echo "0")
  FILE_COUNT=$(docker exec synrc-control-plane find "$HOSTPATH" -type f 2>/dev/null | wc -l | xargs || echo "0")
  echo "      ✅ Restored ($SIZE, $FILE_COUNT files)"
done

echo ""

# Step 4: Restart pods
echo "[4] Restarting pods..."

# Restart StatefulSets
while read -r ns sts replicas; do
  if [ -n "$ns" ] && [ -n "$sts" ] && [ -n "$replicas" ]; then
    echo "   Scaling up: $ns/$sts to $replicas replicas"
    kubectl scale statefulset -n "$ns" "$sts" --replicas="$replicas" 2>/dev/null || true
  fi
done <<< "$STS_LIST"

# Restart Deployments
while read -r ns deploy replicas; do
  if [ -n "$ns" ] && [ -n "$deploy" ] && [ -n "$replicas" ]; then
    echo "   Scaling up: $ns/$deploy to $replicas replicas"
    kubectl scale deployment -n "$ns" "$deploy" --replicas="$replicas" 2>/dev/null || true
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
