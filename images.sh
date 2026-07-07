#!/bin/bash
set -euo pipefail

SHOW_LOCAL=false

# docker exec synrc-control-plane crictl images

# Parse command-line options
while [[ $# -gt 0 ]]; do
  case $1 in
    --local)
      SHOW_LOCAL=true
      shift
      ;;
    *)
      echo "Usage: $0 [--local]" >&2
      exit 1
      ;;
  esac
done

echo "╔════════════════════════════════════════════════════════╗"
echo "║          ERP/1: Docker Registry Catalog                ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Check Kubernetes cluster connectivity
echo "[1] Checking Kubernetes cluster connectivity..."
if ! kubectl cluster-info &>/dev/null; then
  echo "   ❌ Error: Cannot connect to Kubernetes cluster." >&2
  exit 1
fi
echo "   ✓ Connected to Kubernetes cluster"
echo ""

# Step 2: Diagnostic check for port 5000 occupancy
echo "[2] Diagnostic check for port 5000 occupancy..."
if command -v lsof &>/dev/null; then
  port_owner=$(lsof -i :5000 -t 2>/dev/null | head -n 1 || true)
  if [ -n "$port_owner" ]; then
    owner_name=$(ps -p "$port_owner" -o comm= 2>/dev/null | xargs basename || true)
    if [[ "$owner_name" =~ "ControlCenter" || "$owner_name" =~ "ControlCe" ]]; then
      echo "   ⚠️  Warning: Port 5000 is occupied by macOS AirPlay Receiver (Control Center)."
      echo "      This will prevent docker pushes to the local registry (127.0.0.1:5000)."
      echo "      Please disable AirPlay Receiver in: System Settings > General > AirPlay & Handoff"
    else
      echo "   ℹ️  Note: Port 5000 is currently occupied by process '$owner_name' (PID $port_owner)."
      echo "      Make sure to stop it if you want to push images to the local registry."
    fi
  else
    echo "   ✓ Port 5000 is available"
  fi
else
  echo "   ℹ️  lsof not installed, skipping port 5000 diagnostic check"
fi
echo ""

if [ "$SHOW_LOCAL" = true ]; then
  # Step 3: Docker Desktop Local Builder
  echo "[3] Listing Docker Desktop local builders..."
  if command -v docker &>/dev/null; then
    if command -v jq &>/dev/null; then
      printf "   %-20s %-10s %-10s %-10s %s\n" "NAME" "DRIVER" "STATUS" "BUILDKIT" "PLATFORMS"
      docker buildx ls --format json 2>/dev/null | jq -r '[.Name + (if .Current then "*" else "" end) , .Driver, (.Nodes[0].Status // "-"), (.Nodes[0].Version // "-"), ((.Nodes[0].Platforms | join(", ")) // "-")] | @tsv' 2>/dev/null | while IFS=$'\t' read -r name driver node_status version platforms; do
        printf "   %-20s %-10s %-10s %-10s %s\n" "$name" "$driver" "$node_status" "$version" "$platforms"
      done
    else
      docker buildx ls | sed 's/^/   /'
    fi
  else
    echo "   ❌ Error: Docker is not installed or not in PATH." >&2
  fi
  echo ""

  # Step 4: Discovering local Docker daemon & KinD images
  echo "[4] Discovering local Docker daemon & KinD images..."
  echo "   Local Docker Daemon Images (erpuno/*):"
  if command -v docker &>/dev/null; then
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}" | grep -E '^erpuno/|^REPOSITORY' | sed 's/^/   /' || echo "   (none)"
  else
    echo "   ❌ Docker not available."
  fi

  echo ""
  echo "   KinD Cluster Loaded Images (erpuno/*):"
  if command -v kind &>/dev/null && command -v docker &>/dev/null; then
    kind_clusters=$(kind get clusters 2>/dev/null || true)
    if [ -n "$kind_clusters" ]; then
      for cluster in $kind_clusters; do
        echo "   Cluster: $cluster"
        nodes=$(docker ps --filter "label=io.x-k8s.kind.cluster=${cluster}" --format "{{.Names}}" 2>/dev/null || true)
        for node in $nodes; do
          echo "     Node: $node"
          images_list=$(docker exec "$node" crictl images 2>/dev/null || true)
          if [ -n "$images_list" ]; then
            echo "$images_list" | grep -E 'erpuno/|IMAGE' | sed 's/^/       /' || echo "       No erpuno/ images found on node."
          else
            echo "       Unable to list images (crictl failed or node not running)."
          fi
        done
      done
    else
      echo "   No KinD clusters found."
    fi
  else
    echo "   ℹ️  kind or docker command not available to check KinD images."
  fi
  echo ""

  # Step 5: Images in Local Docker Registry
  echo "[5] Listing images in local Docker Registry..."
else
  # Step 3: Images in Local Docker Registry (when --local is false)
  echo "[3] Listing images in local Docker Registry..."
fi

repos_json=$(kubectl get --raw "/api/v1/namespaces/erp-infra/services/docker-registry:http/proxy/v2/_catalog" 2>/dev/null || true)

if [ -z "$repos_json" ]; then
  echo "   ❌ Error: Failed to fetch catalog from docker-registry service." >&2
  exit 1
fi

repos=$(echo "$repos_json" | jq -r '.repositories[]? // empty')

if [ -z "$repos" ]; then
  echo "   ℹ️  No images found in the local registry."
else
  printf "   %-35s %s\n" "Repository" "Tags"
  printf "   %-35s %s\n" "----------" "----"
  for repo in $repos; do
    tags_json=$(kubectl get --raw "/api/v1/namespaces/erp-infra/services/docker-registry:http/proxy/v2/${repo}/tags/list" 2>/dev/null || true)
    if [ -n "$tags_json" ]; then
      tags=$(echo "$tags_json" | jq -r '.tags[]? // empty' 2>/dev/null | paste -sd ", " -)
      if [ -z "$tags" ]; then
        tags="(no tags)"
      fi
      printf "   %-35s %s\n" "$repo" "$tags"
    else
      printf "   %-35s %s\n" "$repo" "[error fetching tags]"
    fi
  done
fi

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║             Registry Listing Complete ✓                ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
