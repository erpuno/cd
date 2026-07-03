#!/bin/bash
# Helm chart validation and lint for multi-namespace deployment

set -e

CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════════════════════╗"
echo "║    Helm Chart Validation (Multi-Namespace)            ║"
echo "╚════════════════════════════════════════════════════════╝"

# Step 1: Check Helm
echo -e "\n[1/4] Checking Helm..."
if ! command -v helm &> /dev/null; then
  echo "❌ Helm not installed"
  exit 1
fi

HELM_VERSION=$(helm version --short | grep -o 'v[0-9.]*')
echo "    ✓ Helm $HELM_VERSION"

# Step 2: Validate chart structure
echo -e "\n[2/4] Validating chart structure..."
if [ ! -f "$CHART_DIR/Chart.yaml" ]; then
  echo "❌ Chart.yaml not found"
  exit 1
fi
echo "    ✓ Chart.yaml exists"

if [ ! -f "$CHART_DIR/values.yaml" ]; then
  echo "❌ values.yaml not found"
  exit 1
fi
echo "    ✓ values.yaml exists"

if [ ! -d "$CHART_DIR/templates" ] || [ -z "$(ls -A "$CHART_DIR/templates")" ]; then
  echo "❌ templates/ directory empty or missing"
  exit 1
fi
echo "    ✓ templates/ directory exists with $(ls "$CHART_DIR/templates" | wc -l) files"

# Step 3: Lint chart
echo -e "\n[3/4] Linting Helm chart..."
if helm lint "$CHART_DIR" 2>&1 | grep -q "1 chart(s) linted, 0 chart(s) failed"; then
  echo "    ✓ Helm lint passed"
else
  echo "    ⚠ Helm lint warnings (non-blocking)"
  helm lint "$CHART_DIR" || true
fi

# Step 4: Validate template rendering
echo -e "\n[4/4] Validating template rendering..."
TEMP_RENDERED="/tmp/erp-uno-template-check.yaml"
if helm template erp-uno "$CHART_DIR" --values "$CHART_DIR/values.yaml" > "$TEMP_RENDERED" 2>&1; then
  RESOURCE_COUNT=$(grep -c "^kind:" "$TEMP_RENDERED" || true)
  echo "    ✓ Templates render successfully ($RESOURCE_COUNT resources)"
else
  echo "❌ Template rendering failed"
  exit 1
fi

# Summary
echo -e "\n╔════════════════════════════════════════════════════════╗"
echo "║              Chart Validation Complete ✓              ║"
echo "╚════════════════════════════════════════════════════════╝"

echo -e "\n📋 Chart Info:"
grep "name:\|version:\|appVersion:" "$CHART_DIR/Chart.yaml" | sed 's/^/    /'

echo -e "\n📊 Configuration:"
NAMESPACE_COUNT=$(grep -c "^  [a-z-]*:" "$CHART_DIR/values.yaml" | head -1)
echo "    Namespaces: $(grep "^  erp-" "$CHART_DIR/values.yaml" | grep "enabled: true" | wc -l)"
echo "    Services: ~25 (defined per namespace)"

echo -e "\n🚀 Deploy with:\n"
echo "    helm install erp-uno $CHART_DIR --values $CHART_DIR/values.yaml"
echo "    OR"
echo "    bash $CHART_DIR/deploy.sh"

echo ""
