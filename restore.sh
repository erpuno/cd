#!/bin/bash
set -euo pipefail

NAMESPACE="erp-telemetry"
BACKUP_DIR="$1"  # path to backup dir

echo "Restoring to $NAMESPACE..."

# Apply manifests first
kubectl apply -f "$BACKUP_DIR/manifests.yaml"

for tarfile in "$BACKUP_DIR"/*-data.tar.gz; do
  pod=$(basename "$tarfile" | sed 's/-data.tar.gz//')
  echo "Restoring to pod: $pod"
  kubectl cp "$tarfile" -n $NAMESPACE $pod:/tmp/data-backup.tar.gz
  kubectl exec -n $NAMESPACE $pod -- tar -xzf /tmp/data-backup.tar.gz -C /
done

echo "Restore complete. Restart pods if needed."
