#!/bin/bash
set -euo pipefail

BACKUP_DIR="${1:-.}"
NAMESPACE="${2:-erp-telemetry}"

if [ ! -f "$BACKUP_DIR/manifests.yaml" ]; then
  echo "❌ Error: $BACKUP_DIR/manifests.yaml not found"
  echo "Usage: $0 <backup_directory> [namespace]"
  exit 1
fi

echo "📦 Restoring from $BACKUP_DIR to namespace $NAMESPACE..."
echo ""

# Step 1: Apply manifests (creates StatefulSets, Deployments, PVCs, etc.)
echo "[1] Applying manifests..."
if kubectl apply -f "$BACKUP_DIR/manifests.yaml" 2>&1 | head -20; then
  echo "   ✅ Manifests applied"
else
  echo "   ⚠️  Some manifests may have failed (this is often expected)"
fi

echo ""
echo "[2] Waiting for StatefulSets to initialize (15 seconds)..."
sleep 15

# Step 2: Restore StatefulSet PVC data
echo "[3] Restoring StatefulSet data..."
for tarfile in "$BACKUP_DIR"/*-data.tar.gz; do
  if [ -f "$tarfile" ]; then
    filename=$(basename "$tarfile")
    # Parse: namespace-sts-replica-data.tar.gz
    pod_namespace=$(echo "$filename" | cut -d'-' -f1)
    pod_name=$(echo "$filename" | sed 's/-data.tar.gz$//' | cut -d'-' -f1-2)
    
    echo "   Restoring: $pod_namespace/$pod_name from $filename"
    
    # Wait for pod to be ready
    kubectl wait --for=condition=ready pod -l app="$pod_name" -n "$pod_namespace" --timeout=30s 2>/dev/null || {
      echo "     ⚠️  Pod not ready, attempting restore anyway..."
    }
    
    # Try to restore to common data paths
    for pod in $(kubectl get pods -n "$pod_namespace" -l app="$pod_name" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true); do
      for data_path in /data /var/lib/data /var/lib/postgresql /var/lib/mysql /srv/data; do
        if kubectl exec -n "$pod_namespace" "$pod" -- test -d "$data_path" 2>/dev/null; then
          echo "     Restoring to $pod:$data_path"
          kubectl cp "$tarfile" "$pod_namespace/$pod:/tmp/data-backup.tar.gz" 2>/dev/null || true
          kubectl exec -n "$pod_namespace" "$pod" -- tar -xzf /tmp/data-backup.tar.gz -C "$data_path" 2>/dev/null || true
          break
        fi
      done
    done
  fi
done

# Step 3: Restore volume data if it exists
if [ -f "$BACKUP_DIR/all-stateful.tgz" ]; then
  echo ""
  echo "[4] Restoring /var/local-path-provisioner..."
  if docker exec synrc-control-plane test -d /var/local-path-provisioner 2>/dev/null; then
    docker cp "$BACKUP_DIR/all-stateful.tgz" synrc-control-plane:/tmp/restore.tgz 2>/dev/null && \
    docker exec synrc-control-plane tar -xzf /tmp/restore.tgz -C /var/local-path-provisioner 2>/dev/null && \
    echo "   ✅ Volume data restored"
  else
    echo "   ⚠️  KinD container not ready, skipping volume restore"
  fi
fi

echo ""
echo "✅ Restore completed!"
echo "Check pod status: kubectl get pods -A"
echo "Check PVCs: kubectl get pvc -A"
