#!/bin/bash
set -euo pipefail

BACKUP_DIR="./backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "📦 Backing up stateful data and StatefulSets..."
echo "Backup directory: $BACKUP_DIR"
echo ""

# Backup all manifests (Deployments, StatefulSets, PVCs, etc.)
echo "[1] Exporting manifests..."
kubectl get statefulset,deployment,pvc,service,configmap --all-namespaces -o yaml > "$BACKUP_DIR/manifests.yaml" 2>/dev/null || {
  echo "⚠️  Warning: Could not export some manifests"
}

# Backup persistent volume data via KinD container
echo "[2] Backing up /var/local-path-provisioner from KinD..."
if docker exec synrc-control-plane test -d /var/local-path-provisioner 2>/dev/null; then
  echo "   Found /var/local-path-provisioner in KinD"
  
  if docker exec synrc-control-plane sh -c 'tar -czf /tmp/stateful.tgz -C /var/local-path-provisioner . 2>/dev/null' 2>/dev/null; then
    echo "   Tar created, attempting copy..."
    
    # Primary: docker cp
    if docker cp synrc-control-plane:/tmp/stateful.tgz "$BACKUP_DIR/all-stateful.tgz" 2>/dev/null; then
      size=$(du -h "$BACKUP_DIR/all-stateful.tgz" | cut -f1)
      echo "   ✅ Volume data backed up ($size)"
    else
      # Fallback: use tar inside container and stream via stdout
      echo "   ⚠️  docker cp failed, attempting streaming..."
      if docker exec synrc-control-plane cat /tmp/stateful.tgz > "$BACKUP_DIR/all-stateful.tgz" 2>/dev/null; then
        echo "   ✅ Volume data backed up via streaming"
      else
        echo "   ⚠️  Could not copy volume backup (directory may be empty)"
      fi
    fi
  else
    echo "   ⚠️  Failed to create tar in container"
  fi
else
  echo "   ⚠️  /var/local-path-provisioner not found"
fi

# Backup individual StatefulSet PVCs
echo "[3] Backing up StatefulSet PVCs..."
statefulset_count=0
for namespace in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  for sts in $(kubectl get statefulset -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true); do
    statefulset_count=$((statefulset_count + 1))
    echo "   StatefulSet: $namespace/$sts"
    replica_count=$(kubectl get statefulset -n "$namespace" "$sts" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 0)
    
    if [ "$replica_count" -gt 0 ]; then
      for i in $(seq 0 $((replica_count - 1))); do
        pod_name="${sts}-${i}"
        for data_path in /data /var/lib/data /var/lib/postgresql /var/lib/mysql /srv/data; do
          if kubectl exec -n "$namespace" "$pod_name" -- test -d "$data_path" 2>/dev/null; then
            echo "     Backing up $pod_name:$data_path"
            if kubectl exec -n "$namespace" "$pod_name" -- tar -czf /tmp/pod-backup.tgz -C "$data_path" . 2>/dev/null; then
              kubectl cp "$namespace/$pod_name:/tmp/pod-backup.tgz" "$BACKUP_DIR/${namespace}-${sts}-${i}-data.tar.gz" 2>/dev/null || true
            fi
            break
          fi
        done
      done
    fi
  done
done

if [ $statefulset_count -eq 0 ]; then
  echo "   (No StatefulSets found)"
fi

echo ""
echo "✅ Backup completed!"
echo "Backup location: $BACKUP_DIR"
echo "Files:"
ls -lh "$BACKUP_DIR"
echo "Total size: $(du -sh "$BACKUP_DIR" | cut -f1)"
