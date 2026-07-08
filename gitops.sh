#!/bin/bash
# gitops.sh - Local Gitea setup and GitHub repository migration script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/compose/gitea.yaml"
GITEA_URL="http://localhost:3000"
ADMIN_USER="root"
ADMIN_PASS="ErpUnoGitea2026"
ADMIN_EMAIL="root@erp.uno"
ORG_NAME="synrc"
REPOS=("ca" "ns" "ldap")

# Print banner
echo "================================================================="
echo "        ERP/1 GitOps Migration: GitHub -> Local Gitea"
echo "================================================================="

show_help() {
  echo "Usage: $0 [setup|migrate|all|status|stop]"
  echo "  setup    - Start Gitea container and provision admin/org/repos"
  echo "  migrate  - Mirror repositories from GitHub to Gitea"
  echo "  all      - Do both setup and migrate"
  echo "  status   - Check Gitea container and migration status"
  echo "  stop     - Stop Gitea container"
  exit 1
}

if [ $# -lt 1 ]; then
  show_help
fi

ACTION="$1"

wait_for_gitea() {
  echo "⏳ Waiting for Gitea to start and respond on $GITEA_URL..."
  local retries=30
  local count=0
  until curl -s --fail "$GITEA_URL/api/v1/swagger" > /dev/null; do
    sleep 2
    count=$((count + 1))
    if [ "$count" -ge "$retries" ]; then
      echo "❌ Timeout waiting for Gitea. Please check container logs: docker compose -f $COMPOSE_FILE logs"
      exit 1
    fi
  done
  echo "✅ Gitea is up and running!"
}

setup_gitea() {
  echo "🚀 Starting Gitea container..."
  docker compose -f "$COMPOSE_FILE" up -d
  
  wait_for_gitea

  # Create admin user if not exists
  echo "👤 Checking Gitea admin user..."
  # Gitea admin user list will contain username if it exists
  if docker exec -u 1000 gitea gitea admin user list 2>/dev/null | grep -qw "$ADMIN_USER"; then
    echo "    ✓ Admin user '$ADMIN_USER' already exists."
  else
    echo "    Creating admin user '$ADMIN_USER'..."
    docker exec -u 1000 gitea gitea admin user create \
      --username "$ADMIN_USER" \
      --password "$ADMIN_PASS" \
      --email "$ADMIN_EMAIL" \
      --admin \
      --must-change-password=false
    echo "    ✓ Admin user created successfully."
  fi

  # Create Organization if not exists
  echo "🏢 Checking Gitea organization '$ORG_NAME'..."
  local org_status
  org_status=$(curl -s -o /dev/null -w "%{http_code}" -u "$ADMIN_USER:$ADMIN_PASS" "$GITEA_URL/api/v1/orgs/$ORG_NAME" || echo "failed")
  
  if [ "$org_status" = "200" ]; then
    echo "    ✓ Organization '$ORG_NAME' already exists."
  else
    echo "    Creating organization '$ORG_NAME'..."
    curl -s -X POST "$GITEA_URL/api/v1/orgs" \
      -H "Content-Type: application/json" \
      -u "$ADMIN_USER:$ADMIN_PASS" \
      -d "{\"username\": \"$ORG_NAME\", \"visibility\": \"public\"}" > /dev/null
    echo "    ✓ Organization '$ORG_NAME' created."
  fi

  # Create repositories if they don't exist
  for repo in "${REPOS[@]}"; do
    echo "📁 Checking repository '$ORG_NAME/$repo'..."
    local repo_status
    repo_status=$(curl -s -o /dev/null -w "%{http_code}" -u "$ADMIN_USER:$ADMIN_PASS" "$GITEA_URL/api/v1/repos/$ORG_NAME/$repo" || echo "failed")
    
    if [ "$repo_status" = "200" ]; then
      echo "    ✓ Repository '$ORG_NAME/$repo' already exists."
    else
      echo "    Creating repository '$ORG_NAME/$repo'..."
      curl -s -X POST "$GITEA_URL/api/v1/org/$ORG_NAME/repos" \
        -H "Content-Type: application/json" \
        -u "$ADMIN_USER:$ADMIN_PASS" \
        -d "{\"name\": \"$repo\", \"private\": false}" > /dev/null
      echo "    ✓ Repository '$ORG_NAME/$repo' created."
    fi
  done

  echo "🎉 Gitea configuration completed successfully!"
}

migrate_repos() {
  echo "🔄 Starting repo migration from GitHub to Gitea..."
  local temp_dir="/tmp/gitea_migration"
  rm -rf "$temp_dir"
  mkdir -p "$temp_dir"

  for repo in "${REPOS[@]}"; do
    echo "-----------------------------------------------------------------"
    echo "📦 Migrating '$repo'..."
    
    local github_url="https://github.com/synrc/${repo}.git"
    local gitea_push_url="http://${ADMIN_USER}:${ADMIN_PASS}@localhost:3000/${ORG_NAME}/${repo}.git"
    local clone_path="$temp_dir/${repo}.git"

    # Clone from GitHub
    echo "    Cloning bare repository from GitHub: $github_url..."
    if [ "$repo" = "ca" ]; then
      # The original repo for ca did not end with .git in Dockerfile: https://github.com/synrc/ca
      github_url="https://github.com/synrc/ca"
    fi
    git clone --bare "$github_url" "$clone_path"

    # Push to Gitea
    echo "    Mirroring repository to local Gitea..."
    (
      cd "$clone_path"
      git push --mirror "$gitea_push_url"
    )
    
    echo "    Cleaning up local temp files..."
    rm -rf "$clone_path"
    echo "    ✓ Migration of '$repo' completed successfully."
  done

  rm -rf "$temp_dir"
  echo "================================================================="
  echo "🎉 All repositories successfully migrated to Gitea!"
  echo "   Gitea URL: http://localhost:3000/org/synrc/dashboard"
  echo "================================================================="
}

status_gitea() {
  echo "ℹ️ Checking Gitea Container Status..."
  docker compose -f "$COMPOSE_FILE" ps
  
  echo -e "\nℹ️ Checking Repository Status in Gitea:"
  for repo in "${REPOS[@]}"; do
    local repo_status
    repo_status=$(curl -s -o /dev/null -w "%{http_code}" -u "$ADMIN_USER:$ADMIN_PASS" "$GITEA_URL/api/v1/repos/$ORG_NAME/$repo" || echo "offline")
    if [ "$repo_status" = "200" ]; then
      echo "  - $ORG_NAME/$repo: [READY]"
    elif [ "$repo_status" = "offline" ]; then
      echo "  - $ORG_NAME/$repo: [GITEA OFFLINE]"
    else
      echo "  - $ORG_NAME/$repo: [NOT FOUND] (HTTP $repo_status)"
    fi
  done
}

stop_gitea() {
  echo "🛑 Stopping Gitea container..."
  docker compose -f "$COMPOSE_FILE" down
  echo "✅ Gitea container stopped."
}

case "$ACTION" in
  setup)
    setup_gitea
    ;;
  migrate)
    migrate_repos
    ;;
  all)
    setup_gitea
    migrate_repos
    ;;
  status)
    status_gitea
    ;;
  stop)
    stop_gitea
    ;;
  *)
    show_help
    ;;
esac
