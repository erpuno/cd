#!/bin/bash
# argocd-portforward.sh - Start kubectl port-forward for argocd-server
# Dynamically picks the first kind-* context so the cluster name is not hardcoded.

KUBECTL="/usr/local/bin/kubectl"
if [ ! -x "$KUBECTL" ]; then
  KUBECTL="$(command -v kubectl 2>/dev/null)"
fi

# Find the appropriate kind-* context (prioritize kind-synrc)
if "$KUBECTL" config get-contexts -o name 2>/dev/null | grep -q '^kind-synrc$'; then
  CONTEXT="kind-synrc"
else
  CONTEXT=$("$KUBECTL" config get-contexts -o name 2>/dev/null | grep '^kind-' | head -1)
fi

if [ -z "$CONTEXT" ]; then
  echo "$(date): No kind-* context found in kubeconfig, retrying in 10s..." >&2
  exit 1
fi

echo "$(date): Using context: $CONTEXT"
exec "$KUBECTL" port-forward \
  --address 0.0.0.0 \
  --context "$CONTEXT" \
  -n argocd \
  svc/argocd-server \
  8080:80
