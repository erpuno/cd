#!/bin/bash
# argocd-portforward.sh - Start kubectl port-forward for argocd-server
# Dynamically picks the first kind-* context so the cluster name is not hardcoded.

KUBECTL="/usr/local/bin/kubectl"
if [ ! -x "$KUBECTL" ]; then
  KUBECTL="$(command -v kubectl 2>/dev/null)"
fi

# Find the first available kind-* context
CONTEXT=$("$KUBECTL" config get-contexts -o name 2>/dev/null | grep '^kind-' | head -1)

if [ -z "$CONTEXT" ]; then
  echo "$(date): No kind-* context found in kubeconfig, retrying in 10s..." >&2
  exit 1
fi

echo "$(date): Using context: $CONTEXT"
exec "$KUBECTL" port-forward \
  --context "$CONTEXT" \
  -n argocd \
  svc/argocd-server \
  8080:80
