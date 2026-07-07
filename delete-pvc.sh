#!/bin/bash
set -euo pipefail

echo "Scaling down deployments using PVCs..."
kubectl scale deployment ca-pki ldap-directory -n erp-security --replicas=0 || true

echo "Waiting for pods to terminate completely..."
kubectl wait --for=delete pod -l app=ca-pki -n erp-security --timeout=30s || true
kubectl wait --for=delete pod -l app=ldap-directory -n erp-security --timeout=30s || true

echo "Deleting PVCs..."
kubectl delete pvc ca-pki-data ldap-directory-data -n erp-security --ignore-not-found

echo "Waiting for PVCs to be fully removed..."
for pvc in ca-pki-data ldap-directory-data; do
  while kubectl get pvc "$pvc" -n erp-security &>/dev/null 2>&1; do
    echo "  Waiting for $pvc to be deleted..."
    sleep 1
  done
done

echo "✓ PVCs deleted successfully"
