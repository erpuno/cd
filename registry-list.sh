#!/bin/bash
set -euo pipefail

# Check if kubectl is working
if ! kubectl cluster-info &>/dev/null; then
  echo "❌ Error: Cannot connect to Kubernetes cluster." >&2
  exit 1
fi

# Diagnostic check for port 5000 occupancy (macOS AirPlay Receiver / Control Center conflict)
if command -v lsof &>/dev/null; then
  port_owner=$(lsof -i :5000 -t 2>/dev/null | head -n 1 || true)
  if [ -n "$port_owner" ]; then
    owner_name=$(ps -p "$port_owner" -o comm= 2>/dev/null | xargs basename || true)
    if [[ "$owner_name" =~ "ControlCenter" || "$owner_name" =~ "ControlCe" ]]; then
      echo "⚠️  Warning: Port 5000 is occupied by macOS AirPlay Receiver (Control Center)."
      echo "   This will prevent docker pushes to the local registry (127.0.0.1:5000)."
      echo "   Please disable AirPlay Receiver in: System Settings > General > AirPlay & Handoff"
      echo ""
    else
      echo "ℹ️  Note: Port 5000 is currently occupied by process '$owner_name' (PID $port_owner)."
      echo "   Make sure to stop it if you want to push images to the local registry."
      echo ""
    fi
  fi
fi

# Fetch the list of repositories
repos_json=$(kubectl get --raw "/api/v1/namespaces/erp-infra/services/docker-registry:http/proxy/v2/_catalog" 2>/dev/null)

if [ -z "$repos_json" ]; then
  echo "❌ Error: Failed to fetch catalog from docker-registry service." >&2
  exit 1
fi

repos=$(echo "$repos_json" | jq -r '.repositories[]? // empty')

if [ -z "$repos" ]; then
  echo "ℹ️  No images found in the local registry."
  exit 0
fi

echo "========================================================="
echo "       Images in Local Docker Registry"
echo "========================================================="
printf "%-35s %s\n" "Repository" "Tags"
printf "%-35s %s\n" "----------" "----"

for repo in $repos; do
  tags_json=$(kubectl get --raw "/api/v1/namespaces/erp-infra/services/docker-registry:http/proxy/v2/${repo}/tags/list" 2>/dev/null)
  if [ -n "$tags_json" ]; then
    tags=$(echo "$tags_json" | jq -r '.tags[]? // empty' 2>/dev/null | paste -sd ", " -)
    if [ -z "$tags" ]; then
      tags="(no tags)"
    fi
    printf "%-35s %s\n" "$repo" "$tags"
  else
    printf "%-35s %s\n" "$repo" "[error fetching tags]"
  fi
done
echo "========================================================="
