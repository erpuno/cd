#!/bin/bash
# ERP/1 K8S Deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════════════════════╗"
echo "║    ERP/1: Підприємство / Kubernetes Dev Deployment     ║"
echo "╚════════════════════════════════════════════════════════╝"

# Step 1: Create namespaces and RBAC
echo -e "\n[1/8] Setting up namespaces..."
kubectl apply -f "$SCRIPT_DIR/share/namespaces.yaml"
kubectl apply -f "$SCRIPT_DIR/share/rbac.yaml"
kubectl apply -f "$SCRIPT_DIR/share/storage-class.yaml"
kubectl apply -f "$SCRIPT_DIR/share/networkpolicy.yaml"
echo "    ✓ Namespaces, RBAC, and network policies created"

# Function to deploy service
deploy_service() {
  local namespace=$1
  local service=$2
  local service_path="$SCRIPT_DIR/lib/$namespace/$service"
  if [ -d "$service_path" ]; then
    echo "    Deploying $service to $namespace..."
    for kind in pvc.yaml deployment.yaml service.yaml hpa.yaml ingress.yaml; do
      if [ -f "$service_path/$kind" ]; then
        if [ "$kind" = "pvc.yaml" ]; then
          kubectl apply -f "$service_path/$kind" || true
        else
          kubectl apply -f "$service_path/$kind"
        fi
      fi
    done
  fi
}

# Prepare locally built images for the active KinD cluster
prepare_kind_image() {
  local image=$1
  local build_script=$2
  local context cluster_name node

  context=$(kubectl config current-context 2>/dev/null || true)
  case "$context" in
    kind-*) ;;
    *) return 0 ;;
  esac

  cluster_name="${context#kind-}"
  node=$(kind get nodes --name "$cluster_name" 2>/dev/null | head -n 1 || true)

  if [ -n "$node" ] && docker exec "$node" crictl inspecti "$image" >/dev/null 2>&1; then
    echo "    Local image $image already available in KinD"
    return 0
  fi

  echo "    Preparing local image $image for KinD..."
  CLUSTER_NAME="$cluster_name" bash "$build_script"
}

# Step 2: Deploy erp-infra (infrastructure only)
echo -e "\n[2/8] Deploying erp-infra..."
deploy_service "erp-infra" "ns-dns"
deploy_service "erp-infra" "traefik-ingress"
deploy_service "erp-infra" "docker-registry"

# Step 3: Deploy erp-telemetry
echo -e "\n[3/8] Deploying erp-telemetry..."
deploy_service "erp-telemetry" "prometheus"
deploy_service "erp-telemetry" "grafana"
deploy_service "erp-telemetry" "loki"
deploy_service "erp-telemetry" "otel-collector"

# Step 4: Deploy erp-security
echo -e "\n[4/8] Deploying erp-security..."
prepare_kind_image "erpuno/ca-pki:latest" "$SCRIPT_DIR/lib/erp-security/ca-pki/build.sh"
deploy_service "erp-security" "ca-pki"
deploy_service "erp-security" "vpn-wireguard"
deploy_service "erp-security" "ias-auth"

# Step 5: Deploy erp-ai
echo -e "\n[5/8] Deploying erp-ai..."
deploy_service "erp-ai" "ai-generation"

# Step 6: Deploy erp-services (core application services)
echo -e "\n[6/8] Deploying erp-services..."
deploy_service "erp-services" "kvs-database"
deploy_service "erp-services" "bpe-engine"
deploy_service "erp-services" "rest-bpe"
deploy_service "erp-services" "n2o-server"
deploy_service "erp-services" "nitro-portal"

# Step 7: Deploy erp-apps (business logic applications)
echo -e "\n[7/8] Deploying erp-apps..."
deploy_service "erp-apps" "lms-education"
deploy_service "erp-apps" "hl7-health"
deploy_service "erp-apps" "crm-documents"
deploy_service "erp-apps" "acc-accounting"
deploy_service "erp-apps" "wms-warehouse"
deploy_service "erp-apps" "cart-registers"
deploy_service "erp-apps" "pm-projects"
deploy_service "erp-apps" "itsm-incidents"
deploy_service "erp-apps" "chat-messenger"

# Step 8: Summary
echo -e "\n[8/8] Deployment Summary"
echo "    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

deployment_failed=0
for ns in erp-infra erp-telemetry erp-security erp-ai erp-services erp-apps; do
  pod_count=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l | xargs)
  running=$(kubectl get pods -n "$ns" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | xargs)
  n=$(printf %\ 20s "$ns")
  echo "    $n: $running/$pod_count pods running"

  if [ "$running" -ne "$pod_count" ]; then
    deployment_failed=1
  fi
done

if [ "$deployment_failed" -ne 0 ]; then
  echo
  echo "Non-running pods:"
  kubectl get pods -A --field-selector=status.phase!=Running \
    -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,REASON:.status.containerStatuses[0].state.waiting.reason'
  echo
  echo "╔════════════════════════════════════════════════════════╗"
  echo "║              Deployment Incomplete ✗                   ║"
  echo "╚════════════════════════════════════════════════════════╝"
  exit 1
fi

echo
echo "╔════════════════════════════════════════════════════════╗"
echo "║           Multi-Namespace Deployment Done ✓            ║"
echo "╚════════════════════════════════════════════════════════╝"

echo
echo "📊 Check Status:"
echo "   All pods: kubectl get pods -A"
echo "   All namespaces: kubectl get ns"

echo
echo "🌐 Access Services:"
echo "   UI (Nitro): kubectl port-forward -n erp-services svc/nitro-portal 8510:8510"
echo "   Prometheus: kubectl port-forward -n erp-telemetry svc/prometheus 9090:9090"
echo "   Grafana: kubectl port-forward -n erp-telemetry svc/grafana 3000:3000"
echo "   Registry: kubectl port-forward -n erp-infra svc/docker-registry 5000:5000"

echo
echo "📁 Namespace Organization:"
echo "       erp-infra: ns-dns, docker-registry"
echo "   erp-telemetry: prometheus, grafana, loki, otel-collector"
echo "    erp-security: ca-pki, vpn-wireguard, ias-auth"
echo "          erp-ai: ai-generation"
echo "    erp-services: kvs-database, bpe-engine, rest-bpe, n2o-server, nitro-portal"
echo "        erp-apps: lms-education, hl7-health, acc-accounting, wms-warehouse, cart-registers"
echo "        erp-apps: crm-documents, pm-projects, itsm-incidents, chat-messenger"

echo ""
