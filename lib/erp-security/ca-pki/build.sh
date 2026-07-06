#!/bin/bash
set -euo pipefail

# build.sh - Build ca-pki Docker image and deploy locally
# Supports direct KinD loading (recommended/simplest) or internal registry push.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

IMAGE_NAME="erpuno/ca-pki:latest"
CLUSTER_NAME="${CLUSTER_NAME:-synrc}"

echo "🔨 Building Docker image: $IMAGE_NAME..."
docker build -t "$IMAGE_NAME" .

USE_REGISTRY=false
if [ $# -gt 0 ] && [ "$1" = "--registry" ]; then
  USE_REGISTRY=true
fi

if [ "$USE_REGISTRY" = true ]; then
  REGISTRY_IMAGE="localhost:5000/ca-pki:latest"
  echo "🏷️  Tagging for internal registry: $REGISTRY_IMAGE..."
  docker tag "$IMAGE_NAME" "$REGISTRY_IMAGE"
  
  # Ensure port-forward is running on host port 5000
  if ! nc -z localhost 5000 2>/dev/null; then
    echo "🌐 Starting registry port-forward on host..."
    kubectl port-forward -n erp-infra svc/docker-registry 5000:5000 &
    PORT_FORWARD_PID=$!
    sleep 2
  fi
  
  echo "🚀 Pushing image to internal registry..."
  docker push "$REGISTRY_IMAGE"
  
  if [ -n "${PORT_FORWARD_PID:-}" ]; then
    echo "🛑 Stopping port-forward..."
    kill "$PORT_FORWARD_PID"
  fi
  echo "✅ Image successfully pushed to internal registry!"
  echo "ℹ️  Update deployment.yaml image to: docker-registry.erp-infra.svc.cluster.local:5000/ca-pki:latest"
else
  echo "📦 Loading image directly into KinD cluster: $CLUSTER_NAME..."
  kind load docker-image "$IMAGE_NAME" --name "$CLUSTER_NAME"
  echo "✅ Image successfully loaded into KinD!"
fi
