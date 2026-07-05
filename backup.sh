#!/bin/bash
BACKUP_DIR="./backups/$(date +%Y%m%d-%H%M)"
mkdir -p "$BACKUP_DIR"

echo "📦 Backing up stateful data from /var/local-path-provisioner..."

docker exec synrc-control-plane tar -czf /tmp/stateful.tgz -C /var/local-path-provisioner . && \
docker cp synrc-control-plane:/tmp/stateful.tgz "$BACKUP_DIR/all-stateful.tgz" && \
echo "✅ Full backup created successfully!" || echo "❌ Backup failed"

echo "Backup location:"
ls -lh "$BACKUP_DIR"
echo "Size:"
du -sh "$BACKUP_DIR" 2>/dev/null || true
