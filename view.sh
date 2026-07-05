#!/bin/bash

BACKUP_DIR="${1:-.}"

# Show help if no arguments or help requested
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ "$1" = "help" ]; then
  cat <<'HELP'
🔍 Backup Explorer - PVC Viewer

USAGE:
  ./view.sh <backup_dir>                       Show backup summary
  ./view.sh <backup_dir> list <img>            List files in device image
  ./view.sh <backup_dir> tree <img>            Show directory tree
  ./view.sh <backup_dir> extract <img> <out>   Extract device image
  ./view.sh <backup_dir> cat <img> <file>      Show file contents
  ./view.sh -h, --help, help                   Show this help

ARGUMENTS:
  <backup_dir>  Path to backup directory (e.g., ./priv/20260706-004359)
  <img>         Device image name without .tar.gz (e.g., erp-telemetry@prometheus-data)
  <out>         Output directory for extraction
  <file>        File path inside image (e.g., wal/00000002)

EXAMPLES:
  ./view.sh ./priv/20260706-004359
  ./view.sh ./priv/20260706-004359 list erp-telemetry@prometheus-data
  ./view.sh ./priv/20260706-004359 tree erp-telemetry@grafana-data
  ./view.sh ./priv/20260706-004359 extract erp-telemetry@grafana-data ./restored-grafana
  ./view.sh ./priv/20260706-004359 cat erp-telemetry@prometheus-data queries.active


DEVICE IMAGE FORMAT:
  Each backup is a tar.gz (gzip-compressed tar archive):
  - Complete filesystem snapshot
  - All files, directories, permissions preserved
  - Mountable after extraction
  - Portable across systems

BACKUP CONTENTS:
  manifests.yaml          - Kubernetes resources
  BACKUP_INFO.txt         - Backup metadata
  *.tar.gz                - Device images (one per PVC)

HELP
  exit 0
fi

if [ ! -d "$BACKUP_DIR" ]; then
  echo "❌ Directory not found: $BACKUP_DIR"
  exit 1
fi

# If called with just backup_dir, show summary
if [ $# -eq 1 ]; then
  echo "🔍 Backup Explorer"
  echo "================="
  echo ""

  # Show backup info
  if [ -f "$BACKUP_DIR/BACKUP_INFO.txt" ]; then
    echo "📋 Backup Information:"
    cat "$BACKUP_DIR/BACKUP_INFO.txt"
    echo ""
  fi

  # List all device images
  echo "📦 Device Images (PVC Backups):"
  echo ""
  for img in "$BACKUP_DIR"/*.tar.gz; do
    if [ ! -f "$img" ]; then
      continue
    fi
    
    basename=$(basename "$img" .tar.gz)
    size=$(du -h "$img" | cut -f1)
    file_count=$(tar -tzf "$img" 2>/dev/null | wc -l)
    
    echo "  📄 $basename"
    echo "     Size: $size"
    echo "     Files: $file_count"
    echo ""
  done

  # Show manifests
  echo "📝 Kubernetes Manifests:"
  if [ -f "$BACKUP_DIR/manifests.yaml" ]; then
    echo ""
    echo "  StatefulSets:"
    grep -c "kind: StatefulSet" "$BACKUP_DIR/manifests.yaml" 2>/dev/null | xargs echo "    Count:" || echo "    Count: 0"
    
    echo ""
    echo "  Deployments:"
    grep -c "kind: Deployment" "$BACKUP_DIR/manifests.yaml" 2>/dev/null | xargs echo "    Count:" || echo "    Count: 0"
    
    echo ""
    echo "  PVCs:"
    grep -c "kind: PersistentVolumeClaim" "$BACKUP_DIR/manifests.yaml" 2>/dev/null | xargs echo "    Count:" || echo "    Count: 0"
    
    echo ""
    echo "  Services:"
    grep -c "kind: Service" "$BACKUP_DIR/manifests.yaml" 2>/dev/null | xargs echo "    Count:" || echo "    Count: 0"
  fi

  echo ""
  echo "ℹ️  For detailed exploration:"
  echo "   ./view.sh $BACKUP_DIR list <image>"
  echo "   ./view.sh $BACKUP_DIR tree <image>"
  echo "   ./view.sh $BACKUP_DIR extract <image> <output>"
  echo ""
  echo "   Use './view.sh -h' for full help"
  echo ""
  exit 0
fi

# Handle subcommands
if [ $# -lt 2 ]; then
  echo "❌ Missing command"
  echo "Usage: ./view.sh <backup_dir> <command> [args]"
  echo "Try: ./view.sh -h"
  exit 1
fi

COMMAND="$2"
IMAGE_NAME="${3:-}"

if [ -z "$IMAGE_NAME" ] && [ "$COMMAND" != "help" ] && [ "$COMMAND" != "-h" ] && [ "$COMMAND" != "--help" ]; then
  case "$COMMAND" in
    list|tree|extract|cat)
      echo "❌ Missing image name"
      echo "Usage: ./view.sh $BACKUP_DIR $COMMAND <image_name> [args]"
      echo ""
      echo "Available images:"
      ls "$BACKUP_DIR"/*.tar.gz 2>/dev/null | xargs -n1 basename | sed 's/.tar.gz//' | sed 's/^/  - /'
      exit 1
      ;;
  esac
fi

IMAGE_FILE="$BACKUP_DIR/${IMAGE_NAME}.tar.gz"

if [ -n "$IMAGE_NAME" ] && [ ! -f "$IMAGE_FILE" ]; then
  echo "❌ Image not found: $IMAGE_NAME"
  echo "Available images:"
  ls "$BACKUP_DIR"/*.tar.gz 2>/dev/null | xargs -n1 basename | sed 's/.tar.gz//' | sed 's/^/  - /'
  exit 1
fi

case "$COMMAND" in
  list)
    echo "📋 Contents of $IMAGE_NAME:"
    tar -tzf "$IMAGE_FILE" | head -30
    COUNT=$(tar -tzf "$IMAGE_FILE" | wc -l)
    if [ "$COUNT" -gt 30 ]; then
      echo ""
      echo "... and $((COUNT - 30)) more files"
    fi
    ;;
  tree)
    echo "🌳 Directory tree of $IMAGE_NAME:"
    tar -tzf "$IMAGE_FILE" | sed 's|/$||' | sort | awk '
      {
        depth = gsub(/\//, "/", $0)
        name = $0
        gsub(/.*\//, "", name)
        for (i = 0; i < depth; i++) printf "  "
        if ($0 ~ /\/$/) printf "📁 "
        else printf "📄 "
        print name
      }
    ' | head -50
    ;;
  cat)
    FILE_PATH="$4"
    if [ -z "$FILE_PATH" ]; then
      echo "❌ Missing file path"
      echo "Usage: ./view.sh $BACKUP_DIR cat $IMAGE_NAME <file_path>"
      exit 1
    fi
    echo "📄 Extracting: $FILE_PATH"
    # Try matching by subpath first (e.g., *wal/00000002), then fallback to basename
    tar -xzOf "$IMAGE_FILE" "*$FILE_PATH" 2>/dev/null | head -50 || \
    tar -xzOf "$IMAGE_FILE" "*/$(basename "$FILE_PATH")" 2>/dev/null | head -50 || {
      echo "❌ File not found or could not extract"
      exit 1
    }
    ;;
  extract)
    OUT_DIR="$4"
    if [ -z "$OUT_DIR" ]; then
      echo "❌ Missing output directory"
      echo "Usage: ./view.sh $BACKUP_DIR extract $IMAGE_NAME <output_dir>"
      exit 1
    fi
    echo "📤 Extracting to: $OUT_DIR"
    mkdir -p "$OUT_DIR"
    tar -xzf "$IMAGE_FILE" -C "$OUT_DIR" || {
      echo "❌ Extraction failed"
      exit 1
    }
    echo "✅ Extracted"
    echo ""
    du -sh "$OUT_DIR"
    ;;
  *)
    echo "❌ Unknown command: $COMMAND"
    echo "Valid commands: list, tree, extract, cat"
    echo "Try: ./view.sh -h"
    exit 1
    ;;
esac
