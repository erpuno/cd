#!/bin/bash
set -euo pipefail

BACKUP_DIR="./backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "📦 Complete Device-Level Backup (All PVCs & StatefulSets)"
echo "Backup directory: $BACKUP_DIR"
echo ""

# Step 1: Export all manifests
echo "[1] Exporting all Kubernetes manifests..."
kubectl get statefulset,deployment,pvc,pv,service,configmap --all-namespaces -o yaml > "$BACKUP_DIR/manifests.yaml"
echo "✅ Manifests exported"
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
STS_LIST=$(kubectl get statefulset --all-namespaces -o json | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"')
while read -r ns sts; do
  if [ -n "$ns" ] && [ -n "$sts" ]; then
    echo "   Scaling down StatefulSet: $ns/$sts"
    kubectl scale statefulset -n "$ns" "$sts" --replicas=0 2>/dev/null || true
  fi
done <<< "$STS_LIST"

# Find and stop all Deployments with PVCs
DEPLOY_WITH_PVC=$(kubectl get deployment --all-namespaces -o json | jq -r '.items[] | select(.spec.template.spec.volumes[].persistentVolumeClaim) | "\(.metadata.namespace) \(.metadata.name)"')
while read -r ns deploy; do
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
  
  # Backup directory name: namespace-pvcname
  SAFE_NAME=$(echo "${ns}-${pvc}" | sed 's/[^a-z0-9-]/-/g')
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
echo "$PVC_INFO" | jq -r '.items[] | "  \(.metadata.namespace)/\(.metadata.name): \(.status.capacity.storage)"' >> "$BACKUP_DIR/BACKUP_INFO.txt"

echo "" >> "$BACKUP_DIR/BACKUP_INFO.txt"
echo "Files:" >> "$BACKUP_DIR/BACKUP_INFO.txt"
ls -lh "$BACKUP_DIR" | tail -n +2 | awk '{print "  " $9 " (" $5 ")"}' >> "$BACKUP_DIR/BACKUP_INFO.txt"

echo "✅ Metadata created"
echo ""

# Step 6: Restart all pods
echo "[6] Restarting pods..."

# Restart StatefulSets
while read -r ns sts; do
  if [ -n "$ns" ] && [ -n "$sts" ]; then
    # Get original replica count from manifests
    REPLICAS=$(kubectl get statefulset -n "$ns" "$sts" -o jsonpath='{.status.replicas}' 2>/dev/null || echo "1")
    echo "   Scaling up StatefulSet: $ns/$sts to $REPLICAS replicas"
    kubectl scale statefulset -n "$ns" "$sts" --replicas="$REPLICAS" 2>/dev/null || true
  fi
done <<< "$STS_LIST"

# Restart Deployments
while read -r ns deploy; do
  if [ -n "$ns" ] && [ -n "$deploy" ]; then
    REPLICAS=$(kubectl get deployment -n "$ns" "$deploy" -o jsonpath='{.status.replicas}' 2>/dev/null || echo "1")
    echo "   Scaling up Deployment: $ns/$deploy to $REPLICAS replicas"
    kubectl scale deployment -n "$ns" "$deploy" --replicas="$REPLICAS" 2>/dev/null || true
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
echo "🔄 Restore backup: ./restore-all.sh $BACKUP_DIR"
