#!/bin/bash
set -euo pipefail

# kind.sh - KinD cluster management and kubeconfig context helpers
# Merges KinD contexts into ~/.kube/config so they are available to kubectl

CLUSTER_NAME="${2:-synrc}"
KIND_CLUSTER_NAME="${CLUSTER_NAME}"

# Ensure KinD is installed
if ! command -v kind &> /dev/null; then
  echo "Error: kind is not installed. Install it from https://kind.sigs.k8s.io/"
  exit 1
fi

# Ensure docker is running
if ! docker info &> /dev/null; then
  echo "Error: Docker is not running"
  exit 1
fi

# Ensure ~/.kube directory exists
mkdir -p ~/.kube

merge_kubeconfig() {
  local temp_config="/tmp/kind-kubeconfig-$$.yaml"
  # Get KinD kubeconfig and save to temp
  kind get kubeconfig --name "${KIND_CLUSTER_NAME}" > "${temp_config}"
  # Merge using kubectl
  KUBECONFIG=~/.kube/config:"${temp_config}" kubectl config view --flatten > ~/.kube/config.tmp
  mv ~/.kube/config.tmp ~/.kube/config
  chmod 600 ~/.kube/config
  rm -f "${temp_config}"
}

create() {
  echo "Creating KinD cluster: ${KIND_CLUSTER_NAME}"

  # Create kind cluster
  if [ -f kind-config.yaml ]; then
    kind create cluster --name "${KIND_CLUSTER_NAME}" --config kind-config.yaml \
      2>&1 | grep -v "^WARNING: IPv4 forwarding" || true
  else
    kind create cluster --name "${KIND_CLUSTER_NAME}" \
      2>&1 | grep -v "^WARNING: IPv4 forwarding" || true
  fi
  echo "✓ KinD cluster created"

  # Merge kubeconfig into ~/.kube/config
  merge_kubeconfig
  echo "✓ Context merged into ~/.kube/config"
  echo ""
  echo "To switch to KinD context:"
  echo "  kubectl config use-context kind-${KIND_CLUSTER_NAME}"
  echo ""
  echo "To return to docker-desktop:"
  echo "  kubectl config use-context docker-desktop"
}

delete() {
  echo "Deleting cluster: $CLUSTER_NAME"
  kind delete cluster --name "$KIND_CLUSTER_NAME" 2>/dev/null || true
  kubectl config delete-context "$KIND_CLUSTER_NAME" 2>/dev/null || true
  kubectl config delete-cluster "$CLUSTER_NAME" 2>/dev/null || true
  kubectl config delete-user "$CLUSTER_NAME" 2>/dev/null || true
  echo "✓ Deleted $CLUSTER_NAME"
}

list() {
  echo "KinD clusters:"
  kind get clusters || echo "  (none)"
  echo ""
  echo "Kubectl contexts:"
  kubectl config get-contexts
}

use() {
  if ! kind get clusters | grep -q "^${KIND_CLUSTER_NAME}$"; then
    echo "Error: KinD cluster '${KIND_CLUSTER_NAME}' not found"
    kind get clusters
    exit 1
  fi
  kubectl config use-context "kind-${KIND_CLUSTER_NAME}"
  echo "✓ Switched to KinD context: ${KIND_CLUSTER_NAME}"
  echo "  Current context: $(kubectl config current-context)"
}

use_docker_desktop() {
  kubectl config use-context docker-desktop
  echo "✓ Switched to Docker Desktop context"
  echo "  Current context: $(kubectl config current-context)"
}

merge_existing() {
  echo "Merging existing KinD clusters into ~/.kube/config"
  for cluster in $(kind get clusters); do
    echo "  Merging context: ${cluster}"
    KIND_CLUSTER_NAME="${cluster}" merge_kubeconfig
  done
  echo "✓ All KinD contexts merged"
  echo ""
  kubectl config get-contexts
}

# Main logic
case "${1:-help}" in
  create) create ;;
  delete) delete ;;
  kind) use ;;
  docker) use_docker_desktop ;;
  list) list ;;
  merge) merge_existing ;;
  *)
    cat << 'EOF'
kind.sh - KinD cluster management and kubeconfig context helpers

USAGE:
  ./kind.sh [COMMAND]

COMMANDS:
  create          Create a new KinD cluster and merge into ~/.kube/config
  delete          Delete the KinD cluster
  kind            Switch kubectl to KinD context
  docker          Switch kubectl back to docker-desktop context
  list            List KinD clusters and kubectl contexts
  merge           Merge existing KinD clusters into ~/.kube/config
  help            Show this message

ENVIRONMENT:
  CLUSTER_NAME    Name of the cluster (default: synrc)

EXAMPLES:
  ./kind.sh merge
  ./kind.sh create [name]
  ./kind.sh delete [name]
  ./kind.sh kind
  ./kind.sh docker
  ./kind.sh list
EOF
    ;;
esac
