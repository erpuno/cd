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

# Ensure local-path-provisioner is installed
if ! kubectl get deployment -n local-path-storage local-path-provisioner &>/dev/null; then
  echo "    local-path-provisioner not found, installing..."
  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml
fi

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

# Step 2: Deploy erp-infra (infrastructure only)
echo -e "\n[2/8] Deploying erp-infra..."
deploy_service "erp-infra" "ns-dns"
deploy_service "erp-infra" "traefik-ingress"
deploy_service "erp-infra" "docker-registry"

# Step 3: Deploy erp-telemetry
echo -e "\n[3/8] Deploying erp-telemetry..."
deploy_service "erp-telemetry" "opensearch"
deploy_service "erp-telemetry" "prometheus"
deploy_service "erp-telemetry" "grafana"
deploy_service "erp-telemetry" "otel-collector"

# Step 4: Deploy erp-security
echo -e "\n[4/8] Deploying erp-security..."
deploy_service "erp-security" "ca-pki"
deploy_service "erp-security" "vpn-wireguard"
deploy_service "erp-security" "ldap-directory"

# Step 5: Deploy erp-ai
echo -e "\n[5/8] Deploying erp-ai..."
deploy_service "erp-ai" "ai-generation"

# Step 6: Deploy erp-services (core application services)
echo -e "\n[6/8] Deploying erp-services..."
deploy_service "erp-services" "kvs-storage"
deploy_service "erp-services" "bpe-processes"
deploy_service "erp-services" "rest-api"
deploy_service "erp-services" "n2o-connections"
deploy_service "erp-services" "nitro-ui"

# Step 7: Deploy erp-apps (business logic applications)
echo -e "\n[7/8] Deploying erp-apps..."
deploy_service "erp-apps" "crm-documents"
deploy_service "erp-apps" "wms-warehouse"
deploy_service "erp-apps" "itsm-incidents"
deploy_service "erp-apps" "chat-messenger"
deploy_service "erp-apps" "ias-auth"

# Step 8: Summary
echo -e "\n[8/8] Deployment Summary"
echo "    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for ns in erp-infra erp-telemetry erp-security erp-ai erp-services erp-apps; do
  pod_count=$(kubectl get pods -n $ns --no-headers 2>/dev/null | wc -l | xargs)
  running=$(kubectl get pods -n $ns --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | xargs)
  n=$(printf %\ 20s $ns)
  echo "    $n: $running/$pod_count pods running"
done

echo
echo "╔════════════════════════════════════════════════════════╗"
echo "║           Multi-Namespace Deployment Done ✓            ║"
echo "╚════════════════════════════════════════════════════════╝"

echo
echo "📊 Check Status:\n"
echo "   All pods: kubectl get pods -A"
echo "   All namespaces: kubectl get ns"

echo
echo "🌐 Access Services:\n"
echo "   UI (Nitro): kubectl port-forward -n erp-services svc/nitro-portal 8510:8510"
echo "   Prometheus: kubectl port-forward -n erp-telemetry svc/prometheus 9090:9090"
echo "   Grafana: kubectl port-forward -n erp-telemetry svc/grafana 3000:3000"
echo "   Registry: kubectl port-forward -n erp-infra svc/docker-registry 5000:5000"

echo
echo "📁 Namespace Organization:\n"
echo "       erp-infra: ns-dns, docker-registry"
echo "   erp-telemetry: prometheus, grafana, otel-collector"
echo "    erp-security: ca-pki, vpn-wireguard, ias-auth, ldap-directory"
echo "          erp-ai: ai-generation"
echo "    erp-services: kvs-storage, bpe-processes, rest-api, n2o-connections, nitro-ui"
echo "        erp-apps: lms-education, hl7-health, acc-accounting, wms-warehouse, cart-registers"
echo "        erp-apps: crm-documents, pm-projects, itsm-incidents, chat-messenger"

echo ""
