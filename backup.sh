#!/bin/bash
set -euo pipefail

BACKUP_DIR="./priv/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "📦 Complete Device-Level Backup (All PVCs & StatefulSets)"
echo "Backup directory: $BACKUP_DIR"
echo ""

# Step 1: Export all manifests
echo "[1] Exporting all Kubernetes manifests..."
NAMESPACES="erp-infra erp-telemetry erp-security erp-ai erp-services erp-apps"
> "$BACKUP_DIR/manifests.yaml"
for ns in $NAMESPACES; do
  kubectl get statefulset,deployment,pvc,service,configmap -n "$ns" -o yaml 2>/dev/null >> "$BACKUP_DIR/manifests.yaml" || true
  echo "---" >> "$BACKUP_DIR/manifests.yaml"
done
# Clean manifests metadata to avoid apply conflicts
ruby "$(dirname "$0")/manifest.rb" "$BACKUP_DIR/manifests.yaml" "$BACKUP_DIR/manifests.yaml.tmp" && mv "$BACKUP_DIR/manifests.yaml.tmp" "$BACKUP_DIR/manifests.yaml"
echo "✅ Manifests exported and cleaned"
echo ""

# Step 2: Get all PVCs and their backing PVs
echo "[2] Discovering PVCs ..."
PVC_INFO=$(kubectl get pvc --all-namespaces -o json)
PVC_COUNT=$(echo "$PVC_INFO" | jq '.items | length')

echo "   Found $PVC_COUNT PVCs:"
echo "$PVC_INFO" | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name)"' | while read pvc; do
  echo "   - $pvc"
done
echo ""

# Step 3: Stop all pods with PVCs (scale StatefulSets to 0, scale Deployments with PVCs to 0)
echo "[3] Stopping pods (unmounting volumes)..."

# Find and stop all StatefulSets
STS_LIST=$(kubectl get statefulset --all-namespaces -o json | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name) \(.spec.replicas // 1)"')
while read -r ns sts replicas; do
  if [ -n "$ns" ] && [ -n "$sts" ]; then
    echo "   Scaling down StatefulSet: $ns/$sts"
    kubectl scale statefulset -n "$ns" "$sts" --replicas=0 2>/dev/null || true
  fi
done <<< "$STS_LIST"

# Find and stop all Deployments with PVCs
DEPLOY_WITH_PVC=$(kubectl get deployment --all-namespaces -o json | jq -r '.items[] | select(.spec.template.spec.volumes != null) | select(any(.spec.template.spec.volumes[]; .persistentVolumeClaim != null)) | "\(.metadata.namespace) \(.metadata.name) \(.spec.replicas // 1)"')
while read -r ns deploy replicas; do
  if [ -n "$ns" ] && [ -n "$deploy" ]; then
    echo "   Scaling down Deployment: $ns/$deploy"
    kubectl scale deployment -n "$ns" "$deploy" --replicas=0 2>/dev/null || true
  fi
done <<< "$DEPLOY_WITH_PVC"


sleep 3
echo "✅ All pods stopped, volumes unmounted"
echo ""

# Step 4: Backup each PVC as device image
echo "[4] Creating device image snapshots..."

echo "$PVC_INFO" | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name) \(.spec.volumeName)"' | while read ns pvc pv; do
  if [ -z "$ns" ] || [ -z "$pvc" ] || [ -z "$pv" ]; then
    continue
  fi
  
  # Get HostPath for this PV
  HOSTPATH=$(kubectl get pv "$pv" -o jsonpath='{.spec.hostPath.path}' 2>/dev/null || echo "")
  
  if [ -z "$HOSTPATH" ]; then
    echo "   ⚠️  $ns/$pvc: Could not find backing path"
    continue
  fi
  
  # Backup filename: namespace@pvcname
  SAFE_NAME="${ns}@${pvc}"
  BACKUP_FILE="$BACKUP_DIR/${SAFE_NAME}.tar.gz"
  
  echo "   Backing up: $ns/$pvc (from $HOSTPATH)"
  docker exec synrc-control-plane tar -czf - -C "$(dirname "$HOSTPATH")" "$(basename "$HOSTPATH")" > "$BACKUP_FILE" 2>/dev/null || {
    echo "   ❌ Failed to backup $ns/$pvc"
    continue
  }
  
  SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
  FILE_COUNT=$(tar -tzf "$BACKUP_FILE" 2>/dev/null | wc -l)
  echo "   ✅ $SAFE_NAME.tar.gz ($SIZE, $FILE_COUNT items)"
done

echo ""

# Step 5: Create metadata file
echo "[5] Creating backup metadata..."
cat > "$BACKUP_DIR/BACKUP_INFO.txt" <<'META'
Device-Level Backup - All PVCs & StatefulSets
==============================================

Created: $(date)
Backup Type: Complete filesystem snapshots (tar.gz)
Format: Raw device images (mountable after extraction)

Contents:
META

echo "" >> "$BACKUP_DIR/BACKUP_INFO.txt"
echo "PVCs Backed Up:" >> "$BACKUP_DIR/BACKUP_INFO.txt"
echo "$PVC_INFO" | jq -r '.items[] | "  \(.metadata.namespace)/\(.metadata.name): \(.status.capacity.storage // "Pending")"' >> "$BACKUP_DIR/BACKUP_INFO.txt"

echo "" >> "$BACKUP_DIR/BACKUP_INFO.txt"
echo "Files:" >> "$BACKUP_DIR/BACKUP_INFO.txt"
ls -lh "$BACKUP_DIR" | tail -n +2 | awk '{print "  " $9 " (" $5 ")"}' >> "$BACKUP_DIR/BACKUP_INFO.txt"

echo "✅ Metadata created"
echo ""

# Step 6: Restart all pods
echo "[6] Restarting pods..."

# Restart StatefulSets
while read -r ns sts replicas; do
  if [ -n "$ns" ] && [ -n "$sts" ] && [ -n "$replicas" ]; then
    echo "   Scaling up StatefulSet: $ns/$sts to $replicas replicas"
    kubectl scale statefulset -n "$ns" "$sts" --replicas="$replicas" 2>/dev/null || true
  fi
done <<< "$STS_LIST"

# Restart Deployments
while read -r ns deploy replicas; do
  if [ -n "$ns" ] && [ -n "$deploy" ] && [ -n "$replicas" ]; then
    echo "   Scaling up Deployment: $ns/$deploy to $replicas replicas"
    kubectl scale deployment -n "$ns" "$deploy" --replicas="$replicas" 2>/dev/null || true
  fi
done <<< "$DEPLOY_WITH_PVC"


sleep 5
echo "✅ Pods restarting"
echo ""

echo "✅ Complete backup finished!"
echo ""
echo "📁 Backup location: $BACKUP_DIR"
echo ""
echo "📊 Backup summary:"
du -sh "$BACKUP_DIR"
ls -lh "$BACKUP_DIR" | tail -n +2 | wc -l | xargs echo "Total files:"
echo ""
echo "🔍 Explore backup: ./view.sh $BACKUP_DIR"
echo "🔄 Restore backup: ./restore.sh $BACKUP_DIR"
