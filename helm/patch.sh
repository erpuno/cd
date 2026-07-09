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
    meta.helm.sh/release-namespace=default \
    argocd.argoproj.io/tracking-id="$RELEASE_NAME:/Namespace:$ns" --overwrite 2>/dev/null || true

  # Loop through all kinds of resources to patch individually
  for kind in serviceaccount service deployment statefulset horizontalpodautoscaler; do
    resources=$(kubectl get $kind -n $ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    for name in $resources; do
      # Annotate with Helm metadata
      kubectl label $kind -n $ns $name app.kubernetes.io/managed-by=Helm --overwrite 2>/dev/null || true
      kubectl annotate $kind -n $ns $name \
        meta.helm.sh/release-name=$RELEASE_NAME \
        meta.helm.sh/release-namespace=default --overwrite 2>/dev/null || true

      # Construct ArgoCD tracking ID
      case "$kind" in
        serviceaccount)           gk="/ServiceAccount" ;;
        service)                  gk="/Service" ;;
        deployment)               gk="apps/Deployment" ;;
        statefulset)              gk="apps/StatefulSet" ;;
        horizontalpodautoscaler)  gk="autoscaling/HorizontalPodAutoscaler" ;;
        *)                        gk="" ;;
      esac

      if [ -n "$gk" ]; then
        tracking_id="$RELEASE_NAME:$gk:$ns/$name"
        kubectl annotate $kind -n $ns $name argocd.argoproj.io/tracking-id="$tracking_id" --overwrite 2>/dev/null || true
      fi
    done
  done
done

echo "✅ All resources patched with Helm ownership metadata."
