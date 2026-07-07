#!/bin/bash
set -euo pipefail

echo "Scaling down deployments using PVCs..."
kubectl scale deployment ca-pki ldap-directory -n erp-security --replicas=0 || true
sleep 2

echo "Deleting PVCs..."
kubectl delete pvc ca-pki-data ldap-directory-data -n erp-security --wait=false || true

echo "Waiting for PVCs to be fully removed..."
for pvc in ca-pki-data ldap-directory-data; do
  while kubectl get pvc "$pvc" -n erp-security &>/dev/null 2>&1; do
    echo "  Waiting for $pvc to be deleted..."
    sleep 1
  done
done

echo "✓ PVCs deleted successfully"
