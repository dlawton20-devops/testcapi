#!/bin/bash

# Kustomize + Fleet Demo
# This shows the actual implementation step by step

set -e

ENVIRONMENT=${1:-staging}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🎯 Kustomize + Fleet Implementation Demo"
echo "Environment: $ENVIRONMENT"
echo ""

# Step 1: Show the base configuration
echo "📁 Step 1: Base Configuration"
echo "File: fleet/bundles/monitoring/base/fleet.yaml"
echo ""

# Show the actual base fleet.yaml content
echo "Base Fleet Bundle (with variables):"
grep -A 5 -B 5 "\\${" "$ROOT_DIR/fleet/bundles/monitoring/base/fleet.yaml" || echo "No variables found in base fleet.yaml"
echo ""

# Step 2: Show the overlay configuration
echo "🔧 Step 2: Kustomize Overlay"
echo "File: fleet/bundles/monitoring/overlays/$ENVIRONMENT/kustomization.yaml"
echo ""

if [ -f "$ROOT_DIR/fleet/bundles/monitoring/overlays/$ENVIRONMENT/kustomization.yaml" ]; then
    cat "$ROOT_DIR/fleet/bundles/monitoring/overlays/$ENVIRONMENT/kustomization.yaml"
else
    echo "❌ Overlay not found for environment: $ENVIRONMENT"
    echo "Available overlays:"
    ls -la "$ROOT_DIR/fleet/bundles/monitoring/overlays/"
    exit 1
fi
echo ""

# Step 3: Show Kustomize processing
echo "⚙️  Step 3: Kustomize Processing"
echo "Command: kubectl kustomize fleet/bundles/monitoring/overlays/$ENVIRONMENT/"
echo ""

# Actually run kustomize to show the output
echo "Kustomize Output (what gets generated):"
cd "$ROOT_DIR/fleet/bundles/monitoring/overlays/$ENVIRONMENT"
kubectl kustomize . 2>/dev/null || echo "Kustomize processing failed - check your overlay configuration"
echo ""

# Step 4: Show the workflow
echo "🔄 Step 4: Complete Workflow"
echo ""

echo "Here's exactly how Kustomize and Fleet work together:"
echo ""
echo "1. 📝 You have base configuration with \${VARIABLE} placeholders"
echo "2. 🔧 You run: kubectl apply -k fleet/bundles/monitoring/overlays/$ENVIRONMENT/"
echo "3. ⚙️  Kustomize:"
echo "   - Reads base configuration"
echo "   - Applies overlay patches"
echo "   - Substitutes \${VARIABLE} with actual values"
echo "   - Generates final Kubernetes manifests"
echo "4. 📦 Fleet:"
echo "   - Reads the processed manifests"
echo "   - Deploys the Rancher monitoring chart"
echo "   - Uses the substituted values"
echo ""

# Step 5: Show practical implementation
echo "🛠️  Step 5: Practical Implementation"
echo ""

echo "To implement this in your workflow:"
echo ""
echo "# 1. Create your base configuration"
echo "mkdir -p fleet/bundles/monitoring/base"
echo "cp fleet.yaml values.yaml namespace.yaml fleet/bundles/monitoring/base/"
echo ""
echo "# 2. Create environment overlays"
echo "mkdir -p fleet/bundles/monitoring/overlays/{dev,staging,prod}"
echo ""
echo "# 3. Create kustomization.yaml for each environment"
echo "cat > fleet/bundles/monitoring/overlays/$ENVIRONMENT/kustomization.yaml <<EOF"
echo "apiVersion: kustomize.config.k8s.io/v1beta1"
echo "kind: Kustomization"
echo "resources:"
echo "  - ../../base"
echo "configMapGenerator:"
echo "  - name: monitoring-config"
echo "    literals:"
echo "      - ENVIRONMENT=$ENVIRONMENT"
echo "      - PROMETHEUS_RETENTION=7d"
echo "      - STORAGE_CLASS=standard"
echo "EOF"
echo ""
echo "# 4. Apply the overlay"
echo "kubectl apply -k fleet/bundles/monitoring/overlays/$ENVIRONMENT/"
echo ""
echo "# 5. Create Fleet GitRepo"
echo "kubectl apply -f - <<EOF"
echo "apiVersion: fleet.cattle.io/v1alpha1"
echo "kind: GitRepo"
echo "metadata:"
echo "  name: rancher-monitoring-$ENVIRONMENT"
echo "  namespace: fleet-local"
echo "spec:"
echo "  repo: https://github.com/YOUR-ORG/YOUR-GITOPS-REPO"
echo "  paths:"
echo "  - fleet/bundles/monitoring/overlays/$ENVIRONMENT"
echo "EOF"
echo ""

# Step 6: Show the key files
echo "📋 Step 6: Key Files in the Implementation"
echo ""

echo "Base Files (fleet/bundles/monitoring/base/):"
echo "├── kustomization.yaml  # References all base resources"
echo "├── fleet.yaml          # Fleet bundle with \${VARIABLE} syntax"
echo "├── values.yaml         # Helm values with \${VARIABLE} syntax"
echo "├── namespace.yaml      # Namespace definition"
echo "└── helmrepository.yaml # Helm repository reference"
echo ""

echo "Overlay Files (fleet/bundles/monitoring/overlays/$ENVIRONMENT/):"
echo "└── kustomization.yaml  # Environment-specific configuration"
echo ""

echo "Environment Files:"
echo "├── examples/env.dev     # Development variables"
echo "├── examples/env.staging # Staging variables"
echo "└── examples/env.prod    # Production variables"
echo ""

echo "🎉 That's the complete Kustomize + Fleet implementation!"
echo ""
echo "💡 Key Points:"
echo "- Kustomize processes templates BEFORE Fleet sees them"
echo "- Fleet deploys the processed manifests"
echo "- Variables are substituted at the Kustomize level"
echo "- Each environment has its own overlay"
echo "- Secrets are managed externally (not in Git)" 