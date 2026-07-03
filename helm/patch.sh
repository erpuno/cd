#!/bin/bash
RELEASE_NAME="erp-uno"
NAMESPACES=("erp-infra" "erp-telemetry" "erp-security" "erp-ai" "erp-services" "erp-apps")

echo "Applying Helm ownership metadata to all resources..."

for ns in "${NAMESPACES[@]}"; do
  echo "→ Processing namespace: $ns"

  # Namespace
  kubectl label ns $ns app.kubernetes.io/managed-by=Helm --overwrite 2>/dev/null || true
  kubectl annotate ns $ns \
    meta.helm.sh/release-name=$RELEASE_NAME \
    meta.helm.sh/release-namespace=default --overwrite 2>/dev/null || true

  # ServiceAccounts
  kubectl label serviceaccount -n $ns ${ns}-sa app.kubernetes.io/managed-by=Helm --overwrite 2>/dev/null || true
  kubectl annotate serviceaccount -n $ns ${ns}-sa \
    meta.helm.sh/release-name=$RELEASE_NAME \
    meta.helm.sh/release-namespace=default --overwrite 2>/dev/null || true

  # Services, Deployments, StatefulSets, HPAs
  for kind in service deployment statefulset horizontalpodautoscaler; do
    kubectl label $kind -n $ns --all app.kubernetes.io/managed-by=Helm --overwrite 2>/dev/null || true
    kubectl annotate $kind -n $ns --all \
      meta.helm.sh/release-name=$RELEASE_NAME \
      meta.helm.sh/release-namespace=default --overwrite 2>/dev/null || true
  done
done

echo "✅ All resources patched with Helm ownership metadata."
