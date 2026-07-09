#!/usr/bin/env bash
# monitor.sh - Real-time cluster bootstrap and stabilization monitor loop

set -euo pipefail

# Ensure kubectl is configured
if ! kubectl cluster-info &>/dev/null; then
  echo "❌ Kubernetes cluster is unreachable!"
  exit 1
fi

ARGOCD_NS="argocd"
ERP_NAMESPACES=("erp-infra" "erp-security" "erp-telemetry" "erp-ai" "erp-services" "erp-apps")
APP_NAME="erp-uno"

# Setup trap to restore cursor and exit clean on Ctrl+C
trap 'tput cnorm; echo -e "\n👋 Monitoring stopped."; exit 0' INT TERM

# Hide cursor during loop
tput civis

while true; do
  clear
  current_time=$(date +"%Y-%m-%d %H:%M:%S")
  current_context=$(kubectl config current-context)
  
  echo "================================================================================"
  echo "📊 ERP/1 Cluster Monitor | Time: $current_time | Context: $current_context"
  echo "================================================================================"
  
  # 1. Show ArgoCD Application Sync and Health Status
  echo -e "\n📌 ArgoCD Application Status [APP: $APP_NAME]"
  echo "--------------------------------------------------------------------------------"
  if ARGOCD_NAMESPACE=$ARGOCD_NS argocd app get "$APP_NAME" --core &>/dev/null; then
    ARGOCD_NAMESPACE=$ARGOCD_NS argocd app get "$APP_NAME" --core | grep -E "^(Name:|Sync Status:|Health Status:|Condition:)" || true
  else
    echo "⚠️ Application '$APP_NAME' not found or ArgoCD not running yet."
  fi
  
  # 2. Show ArgoCD component pods
  echo -e "\n⚙️ ArgoCD System Pods"
  echo "--------------------------------------------------------------------------------"
  kubectl get pods -n "$ARGOCD_NS" -o custom-columns="NAME:.metadata.name,READY:.status.containerStatuses[0].ready,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount" --no-headers 2>/dev/null || echo "No pods in $ARGOCD_NS namespace."

  # 3. Show ERP namespace pods
  echo -e "\n📦 ERP Application Pods"
  echo "--------------------------------------------------------------------------------"
  printf "%-18s %-45s %-7s %-8s %s\n" "NAMESPACE" "POD NAME" "READY" "STATUS" "RESTARTS"
  printf "%-18s %-45s %-7s %-8s %s\n" "---------" "--------" "-----" "------" "--------"
  
  for ns in "${ERP_NAMESPACES[@]}"; do
    kubectl get pods -n "$ns" -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.containerStatuses[0].ready}{"\t"}{.status.phase}{"\t"}{.status.containerStatuses[0].restartCount}{"\n"}{end}' 2>/dev/null | while read -r p_ns p_name p_ready p_status p_restarts; do
      if [ -n "$p_name" ]; then
        # Format the ready status from true/false to 1/1 or 0/1
        ready_str="0/1"
        if [ "$p_ready" = "true" ]; then
          ready_str="1/1"
        fi
        # Truncate pod name if it's too long
        printf "%-18s %-45.45s %-7s %-8s %s\n" "$p_ns" "$p_name" "$ready_str" "$p_status" "$p_restarts"
      fi
    done
  done
  
  # 4. Show recent warning/error events
  echo -e "\n⚠️ Recent Kubernetes Events (ERP & ArgoCD)"
  echo "--------------------------------------------------------------------------------"
  kubectl get events -A --sort-by='.metadata.creationTimestamp' 2>/dev/null \
    | grep -E "erp-|argocd|default" \
    | tail -n 8 \
    | awk '{
        ns = $1
        type = $3
        obj = $5
        msg = ""
        for(i=6; i<=NF; i++) {
          msg = msg (i==6 ? "" : " ") $i
        }
        line = sprintf("%-13.13s %-7.7s %-32.32s %-50.50s", ns, type, obj, msg)
        print line
      }' || echo "No recent events."
  
  echo "================================================================================"
  echo "💡 Tip: Press Ctrl+C to exit monitoring loop"
  
  sleep 3
done
