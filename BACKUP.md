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
6. Output: `./priv/YYYYMMDD-HHMMSS/`

Output Structure:

```
priv/20260706-004359/
├── BACKUP_INFO.txt                           # Metadata
├── manifests.yaml                            # All K8s resources
├── erp-infra@registry-data.tar.gz            # Docker registry device snapshot (4KB)
├── erp-telemetry@grafana-data.tar.gz         # Grafana data device snapshot (1MB)
└── erp-telemetry@prometheus-data.tar.gz      # Prometheus data device snapshot (16KB)
```

## Restore Process

```bash
./restore.sh ./priv/YYYYMMDD-HHMMSS
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
view.sh ./priv/YYYYMMDD-HHMMSS
```

Shows:

* Backup summary (backup date, type, format)
* List of PVCs and their sizes
* Device images with file counts

Subcommands:

```bash
view.sh ./priv/20260706-004359 list erp-telemetry@prometheus-data
view.sh ./priv/20260706-004359 tree erp-telemetry@grafana-data
view.sh ./priv/20260706-004359 extract erp-telemetry@grafana-data ./restored-grafana
view.sh ./priv/20260706-004359 cat erp-telemetry@prometheus-data queries.active
```

## Device Image Format

Each backup file is a **tar.gz** (gzip-compressed tar archive):

* **Complete filesystem snapshot** - all files, directories, permissions preserved
* **Mountable** - can extract to any filesystem
* **Portable** - works across systems
* **Compressed** - typically 30-50% of original size

# Author

* 5HT
