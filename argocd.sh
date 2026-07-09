#!/usr/bin/env bash
# argocd.sh - Automated local ArgoCD setup for erp-uno cluster
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITEA_URL="http://localhost:3000"
ADMIN_USER="root"
ADMIN_PASS="ErpUnoGitea2026"
ORG_NAME="synrc"
REPO_NAME="cd"

echo "╔════════════════════════════════════════════════════════╗"
echo "║          ERP/1: ArgoCD Local Setup & GitOps            ║"
echo "╚════════════════════════════════════════════════════════╝"

# 1. Check Gitea is running
echo -e "\n[1/6] Checking Gitea local server status..."
if ! curl -s --fail "$GITEA_URL/api/v1/swagger" > /dev/null; then
  echo "❌ Gitea is not running on $GITEA_URL."
  echo "   Please start Gitea first using: ./gitops.sh setup (or './gitops.sh all')"
  exit 1
fi
echo "    ✓ Gitea is running"

# 2. Ensure CD repository exists in Gitea
echo -e "\n[2/6] Ensuring repository '$ORG_NAME/$REPO_NAME' exists in Gitea..."
REPO_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u "$ADMIN_USER:$ADMIN_PASS" "$GITEA_URL/api/v1/repos/$ORG_NAME/$REPO_NAME" || echo "failed")

if [ "$REPO_STATUS" = "200" ]; then
  echo "    ✓ Repository '$ORG_NAME/$REPO_NAME' already exists in Gitea"
else
  echo "    Creating repository '$ORG_NAME/$REPO_NAME' in Gitea..."
  curl -s -X POST "$GITEA_URL/api/v1/org/$ORG_NAME/repos" \
    -H "Content-Type: application/json" \
    -u "$ADMIN_USER:$ADMIN_PASS" \
    -d "{\"name\": \"$REPO_NAME\", \"private\": false}" > /dev/null
  echo "    ✓ Repository '$ORG_NAME/$REPO_NAME' created successfully"
fi

# 2.5 Generate helm/values.yaml from active configuration
echo -e "\n[2.5/6] Generating helm/values.yaml from active services..."
ruby "$SCRIPT_DIR/values.rb" --force
HAD_DIFF=false
if ! git diff --quiet; then
  echo "    Creating temporary commit for Gitea push (changes will be reset locally afterwards)..."
  git add -u
  git commit -m "temp: local fixes and auto-generated helm/values.yaml"
  HAD_DIFF=true
fi

# 3. Push current branch to Gitea
echo -e "\n[3/6] Pushing local codebase to Gitea..."
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")
if [ -z "$CURRENT_BRANCH" ]; then
  CURRENT_BRANCH="main"
fi

PUSH_URL="http://${ADMIN_USER}:${ADMIN_PASS}@localhost:3000/${ORG_NAME}/${REPO_NAME}.git"
echo "    Pushing branch '$CURRENT_BRANCH' to Gitea 'main'..."
git push -f "$PUSH_URL" "${CURRENT_BRANCH}:main"
echo "    ✓ Pushed local code successfully"

# Reset the temporary commit if one was created, so working copy has unstaged changes
if [ "$HAD_DIFF" = true ]; then
  echo "    Resetting temporary commit (keeping changes in working tree for review)..."
  git reset HEAD~1
fi

# 4. Check Kubernetes cluster access
echo -e "\n[4/6] Checking Kubernetes cluster status..."
if ! kubectl cluster-info &>/dev/null; then
  echo "❌ Kubernetes cluster is not accessible."
  echo "   Please create it using: ./kind.sh create synrc"
  exit 1
fi
echo "    ✓ Cluster is accessible"

# 5. Install ArgoCD
echo -e "\n[5/6] Deploying ArgoCD components..."

# Clean up namespace if it is stuck in Terminating phase
if kubectl get namespace argocd &>/dev/null; then
  PHASE=$(kubectl get namespace argocd -o jsonpath='{.status.phase}')
  if [ "$PHASE" = "Terminating" ]; then
    echo "⚠️ Namespace 'argocd' is stuck in Terminating state. Cleaning finalizers..."
    # Remove finalizers from applications in the namespace to allow deletion
    kubectl get applications.argoproj.io -n argocd -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | xargs -n 1 -I{} kubectl patch applications.argoproj.io -n argocd {} -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true

    echo "⏳ Waiting for namespace 'argocd' to terminate..."
    until ! kubectl get namespace argocd &>/dev/null; do
      sleep 2
    done
    echo "    ✓ Namespace 'argocd' terminated successfully"
  fi
fi

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
echo "    Applying community ArgoCD manifests..."
kubectl apply --server-side=true --force-conflicts -n argocd -f "$SCRIPT_DIR/argocd/install.yaml"

echo "    Configuring ArgoCD server in insecure (HTTP) mode..."
kubectl -n argocd patch deploy argocd-server --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--insecure"}]'

echo "    Waiting for ArgoCD server deployment rollout..."
kubectl rollout status deployment argocd-server -n argocd --timeout=150s

# 5.5 Clean up manual deployments/services/hpas/pvcs to avoid GitOps conflicts
echo -e "\n[5.5/7] Cleaning up manual deployments/services to avoid GitOps conflicts..."
for ns in erp-infra erp-security erp-telemetry erp-ai erp-services erp-apps; do
  if kubectl get ns "$ns" &>/dev/null; then
    echo "    Cleaning namespace $ns..."
    kubectl delete deployments,services,statefulsets,hpa,pvc --all -n "$ns" --ignore-not-found --grace-period=0 --force 2>/dev/null || true
  fi
done

# 6. Apply Ingress and Application
echo -e "\n[6/7] Applying ArgoCD Application & Ingress manifests..."
kubectl apply -f "$SCRIPT_DIR/argocd/ingress.yaml"
kubectl apply -f "$SCRIPT_DIR/argocd/application.yaml"

# 7. Create permanent background port-forward via macOS launchd agent
echo -e "\n[7/7] Creating permanent background port-forward (localhost:8080)..."
PLIST_NAME="uno.erp.argocd-portforward.plist"
PLIST_PATH="$HOME/Library/LaunchAgents/$PLIST_NAME"

mkdir -p "$HOME/Library/LaunchAgents"
cp "$SCRIPT_DIR/argocd/$PLIST_NAME" "$PLIST_PATH"

# Load and launch the agent
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"
echo "    ✓ macOS launchd agent configured and loaded"

echo -e "\n🎉 ArgoCD Local GitOps Setup Completed!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 ArgoCD Console (via Ingress): http://argocd.erp-uno.local"
echo "🌐 ArgoCD Console (via permanent Port-Forward): http://localhost:8080"
echo "👤 Username: admin"
echo -n "🔑 Password: "
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
