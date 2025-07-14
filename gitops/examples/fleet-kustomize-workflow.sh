#!/bin/bash

# Fleet + Kustomize Workflow Example
# This shows exactly how Kustomize and Fleet work together

set -e

ENVIRONMENT=${1:-staging}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🔄 Fleet + Kustomize Workflow"
echo "Environment: $ENVIRONMENT"
echo ""

# Step 1: Show the base configuration
echo "📁 Step 1: Base Configuration"
echo "Location: fleet/bundles/monitoring/base/"
echo ""
echo "Base Fleet Bundle (fleet.yaml):"
echo "Uses \${VARIABLE} syntax for all configurable values"
echo ""

# Step 2: Show the overlay
echo "🔧 Step 2: Kustomize Overlay"
echo "Location: fleet/bundles/monitoring/overlays/$ENVIRONMENT/"
echo ""
echo "Overlay kustomization.yaml:"
echo "- References ../../base"
echo "- Generates ConfigMap with environment-specific values"
echo "- Generates Secret from environment file"
echo ""

# Step 3: Show Kustomize processing
echo "⚙️  Step 3: Kustomize Processing"
echo "Command: kubectl apply -k fleet/bundles/monitoring/overlays/$ENVIRONMENT/"
echo ""
echo "What Kustomize does:"
echo "1. Reads base configuration"
echo "2. Applies overlay patches"
echo "3. Substitutes \${VARIABLE} with actual values"
echo "4. Generates final Kubernetes manifests"
echo ""

# Step 4: Show what Fleet sees
echo "📦 Step 4: What Fleet Sees"
echo "After Kustomize processing, Fleet sees the final manifests:"
echo ""

# Show the processed output
echo "Processed Fleet Bundle (what Fleet actually sees):"
cat << 'EOF'
apiVersion: fleet.cattle.io/v1alpha1
kind: Bundle
metadata:
  name: rancher-monitoring
  namespace: fleet-local
spec:
  targets:
  - clusterSelector:
      matchLabels:
        env: production
    clusterGroup: production-clusters
    values:
      global:
        cattle:
          systemDefaultRegistry: ""
        rke2Enabled: true
      prometheus:
        prometheusSpec:
          retention: 30d                    # ← Substituted by Kustomize
          storageSpec:
            volumeClaimTemplate:
              spec:
                resources:
                  requests:
                    storage: 100Gi          # ← Substituted by Kustomize
                storageClassName: fast-ssd  # ← Substituted by Kustomize
          resources:
            requests:
              memory: 2Gi                   # ← Substituted by Kustomize
              cpu: 500m                     # ← Substituted by Kustomize
            limits:
              memory: 4Gi                   # ← Substituted by Kustomize
              cpu: 1000m                    # ← Substituted by Kustomize
      grafana:
        persistence:
          enabled: true
          size: 10Gi                        # ← Substituted by Kustomize
          storageClassName: fast-ssd        # ← Substituted by Kustomize
        resources:
          requests:
            memory: 512Mi                   # ← Substituted by Kustomize
            cpu: 250m                       # ← Substituted by Kustomize
          limits:
            memory: 1Gi                     # ← Substituted by Kustomize
            cpu: 500m                       # ← Substituted by Kustomize
        adminPassword: your-secure-password # ← Substituted by Kustomize
      alertmanager:
        alertmanagerSpec:
          retention: 120h                   # ← Substituted by Kustomize
          storage:
            volumeClaimTemplate:
              spec:
                resources:
                  requests:
                    storage: 10Gi           # ← Substituted by Kustomize
                storageClassName: fast-ssd  # ← Substituted by Kustomize
          resources:
            requests:
              memory: 256Mi                 # ← Substituted by Kustomize
              cpu: 100m                     # ← Substituted by Kustomize
            limits:
              memory: 512Mi                 # ← Substituted by Kustomize
              cpu: 200m                     # ← Substituted by Kustomize
  helm:
    chart: rancher-monitoring
    repo: https://releases.rancher.com/server-charts/stable
    version: 102.0.0+up40.1.2
    valuesFiles:
    - values.yaml
  resources:
  - helmrepository.yaml
EOF
echo ""

# Step 5: Show the complete workflow
echo "🔄 Complete Workflow:"
echo ""
echo "1. 📝 You edit: fleet/bundles/monitoring/overlays/$ENVIRONMENT/kustomization.yaml"
echo "2. 🔧 Kustomize processes: kubectl apply -k ."
echo "3. 📦 Fleet reads: The processed manifests"
echo "4. 🚀 Fleet deploys: Rancher monitoring chart with your values"
echo "5. 📊 Result: Monitoring stack running with environment-specific config"
echo ""

# Step 6: Show practical commands
echo "🛠️  Practical Commands:"
echo ""
echo "# See what Kustomize will generate (without applying)"
echo "kubectl kustomize fleet/bundles/monitoring/overlays/$ENVIRONMENT/"
echo ""
echo "# Apply Kustomize overlay (processes and applies to cluster)"
echo "kubectl apply -k fleet/bundles/monitoring/overlays/$ENVIRONMENT/"
echo ""
echo "# See what Fleet sees after Kustomize processing"
echo "kubectl get bundle rancher-monitoring -n fleet-local -o yaml"
echo ""
echo "# Check Fleet deployment status"
echo "kubectl get gitrepo,bundle -n fleet-local"
echo "kubectl get pods -n cattle-monitoring-system"
echo ""

echo "💡 Key Point: Fleet doesn't run Kustomize - YOU run Kustomize first!"
echo "Kustomize processes your templates, Fleet deploys the results." 