# Complete Device-Level Backup & Restore

## Overview

Three scripts for backing up and restoring ALL PVCs and StatefulSets as device-level snapshots:

* `backup.sh` - Creates device snapshots (tar.gz) for all PVCs, stops pods during backup
* `restore.sh` - Restores all device snapshots, stops pods during restore  
* `view.sh` - Explore and inspect backup contents without extraction

## Backup Process

```bash
./backup.sh
```

Steps:

1. Export all Kubernetes manifests (StatefulSets, Deployments, PVCs, Services)
2. Stop all pods (unmounts volumes for clean device snapshots)
3. Create device image for each PVC via `tar -czf` (filesystem snapshot)
4. Create backup metadata (PVC list, file counts, sizes)
5. Restart all pods
6. Output: `./backups/YYYYMMDD-HHMMSS/`

Output Structure:

```
backups/20260705-234654/
├── BACKUP_INFO.txt                           # Metadata
├── manifests.yaml                            # All K8s resources
├── erp-infra-registry-data.tar.gz            # Docker registry device snapshot (4KB)
├── monitoring-storage-grafana-0.tar.gz       # Grafana data device snapshot (20MB)
└── monitoring-storage-prometheus-0.tar.gz    # Prometheus data device snapshot (16KB)
```

## Restore Process

```bash
./restore.sh ./backups/YYYYMMDD-HHMMSS
```

Steps:

1. Apply all Kubernetes manifests (recreate StatefulSets, Deployments, PVCs)
2. Stop all pods (unmounts volumes)
3. Clear existing PVC data
4. Extract each device image via `tar -xzf`
5. Restart all pods
6. Verify PVCs bound and pods restarting

## Explore Backups

```bash
view.sh ./backups/YYYYMMDD-HHMMSS
```

Shows:

* Backup summary (backup date, type, format)
* List of PVCs and their sizes
* Device images with file counts

Subcommands:

```bash
view.sh ./backups/20260705-234654 list monitoring-storage-prometheus-0
view.sh ./backups/20260705-234654 tree monitoring-storage-grafana-0
view.sh ./backups/20260705-234654 extract monitoring-storage-grafana-0 ./restored-grafana
view.sh ./backups/20260705-234654 cat monitoring-storage-prometheus-0 /prometheus/prometheus.yml
```

## Device Image Format

Each backup file is a **tar.gz** (gzip-compressed tar archive):

* **Complete filesystem snapshot** - all files, directories, permissions preserved
* **Mountable** - can extract to any filesystem
* **Portable** - works across systems
* **Compressed** - typically 30-50% of original size

# Author

* 5HT
