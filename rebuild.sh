#!/bin/bash
set -euo pipefail

# rebuild.sh - Empties the docker-registry and rebuilds all components

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🧹 [1/3] Resetting docker-registry to empty state..."

# 1. Scale down and delete the registry resources to clean up data
kubectl delete deployment docker-registry -n erp-infra --ignore-not-found
kubectl delete pvc registry-data -n erp-infra --ignore-not-found

# 2. Re-create the registry resources
kubectl apply -f lib/erp-infra/docker-registry/pvc.yaml \
              -f lib/erp-infra/docker-registry/deployment.yaml \
              -f lib/erp-infra/docker-registry/service.yaml

# 3. Wait for the registry pod to be ready
echo "⏳ Waiting for docker-registry to be ready..."
kubectl rollout status deployment docker-registry -n erp-infra

echo "✅ Docker registry is reset and ready!"

echo -e "\n🔨 [2/3] Finding and executing all component build scripts..."

# Find all build.sh scripts in lib/ subdirectories and run them
while IFS= read -r build_script; do
  dir_path="$(dirname "$build_script")"
  echo -e "\n▶️  Building in: $dir_path..."
  (
    cd "$dir_path"
    chmod +x build.sh
    ./build.sh
  )
done < <(find lib -type f -name "build.sh" | sort)

echo -e "\n🚀 [3/3] Deploying updated components..."
./deploy.sh

echo -e "\n🎉 Rebuild and deploy completed successfully!"
