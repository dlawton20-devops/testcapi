#!/bin/bash

# Fleet + Kustomize Deployment Example
# This script shows how to deploy Rancher monitoring using Fleet with Kustomize overlays

set -e

ENVIRONMENT=${1:-staging}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🚀 Fleet + Kustomize Deployment Example"
echo "Environment: $ENVIRONMENT"
echo ""

# Step 1: Show the directory structure
echo "📁 Directory Structure:"
echo "fleet/bundles/monitoring/"
echo "├── base/"
echo "│   ├── kustomization.yaml"
echo "│   ├── fleet.yaml"
echo "│   ├── values.yaml"
echo "│   ├── namespace.yaml"
echo "│   └── helmrepository.yaml"
echo "└── overlays/"
echo "    ├── dev/"
echo "    │   └── kustomization.yaml"
echo "    ├── staging/"
echo "    │   └── kustomization.yaml"
echo "    └── prod/"
echo "        └── kustomization.yaml"
echo ""

# Step 2: Show the base Fleet bundle
echo "📦 Base Fleet Bundle (fleet/bundles/monitoring/base/fleet.yaml):"
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
        env: ${ENVIRONMENT}
    clusterGroup: ${ENVIRONMENT}-clusters
    values:
      global:
        cattle:
          systemDefaultRegistry: ""
        rke2Enabled: true
      prometheus:
        prometheusSpec:
          retention: ${PROMETHEUS_RETENTION}
          storageSpec:
            volumeClaimTemplate:
              spec:
                resources:
                  requests:
                    storage: ${PROMETHEUS_STORAGE_SIZE}
                storageClassName: ${STORAGE_CLASS}
          resources:
            requests:
              memory: ${PROMETHEUS_MEMORY_REQUEST}
              cpu: ${PROMETHEUS_CPU_REQUEST}
            limits:
              memory: ${PROMETHEUS_MEMORY_LIMIT}
              cpu: ${PROMETHEUS_CPU_LIMIT}
      grafana:
        persistence:
          enabled: true
          size: ${GRAFANA_PERSISTENCE_SIZE}
          storageClassName: ${STORAGE_CLASS}
        resources:
          requests:
            memory: ${GRAFANA_MEMORY_REQUEST}
            cpu: ${GRAFANA_CPU_REQUEST}
          limits:
            memory: ${GRAFANA_MEMORY_LIMIT}
            cpu: ${GRAFANA_CPU_LIMIT}
        adminPassword: ${GRAFANA_ADMIN_PASSWORD}
      alertmanager:
        alertmanagerSpec:
          retention: ${ALERTMANAGER_RETENTION}
          storage:
            volumeClaimTemplate:
              spec:
                resources:
                  requests:
                    storage: ${ALERTMANAGER_STORAGE_SIZE}
                storageClassName: ${STORAGE_CLASS}
          resources:
            requests:
              memory: ${ALERTMANAGER_MEMORY_REQUEST}
              cpu: ${ALERTMANAGER_CPU_REQUEST}
            limits:
              memory: ${ALERTMANAGER_MEMORY_LIMIT}
              cpu: ${ALERTMANAGER_CPU_LIMIT}
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

# Step 3: Show the production overlay
echo "🔧 Production Overlay (fleet/bundles/monitoring/overlays/prod/kustomization.yaml):"
cat << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
metadata:
  name: monitoring-prod
resources:
  - ../../base
configMapGenerator:
  - name: monitoring-config
    literals:
      - ENVIRONMENT=production
      - PROMETHEUS_RETENTION=30d
      - PROMETHEUS_STORAGE_SIZE=100Gi
      - PROMETHEUS_MEMORY_REQUEST=2Gi
      - PROMETHEUS_MEMORY_LIMIT=4Gi
      - PROMETHEUS_CPU_REQUEST=500m
      - PROMETHEUS_CPU_LIMIT=1000m
      - GRAFANA_PERSISTENCE_SIZE=10Gi
      - GRAFANA_MEMORY_REQUEST=512Mi
      - GRAFANA_MEMORY_LIMIT=1Gi
      - GRAFANA_CPU_REQUEST=250m
      - GRAFANA_CPU_LIMIT=500m
      - ALERTMANAGER_RETENTION=120h
      - ALERTMANAGER_STORAGE_SIZE=10Gi
      - ALERTMANAGER_MEMORY_REQUEST=256Mi
      - ALERTMANAGER_MEMORY_LIMIT=512Mi
      - ALERTMANAGER_CPU_REQUEST=100m
      - ALERTMANAGER_CPU_LIMIT=200m
      - STORAGE_CLASS=fast-ssd
secretGenerator:
  - name: monitoring-secrets
    envs:
      - ../../../examples/env.prod
EOF
echo ""

# Step 4: Show how to deploy
echo "🚀 Deployment Commands:"
echo ""
echo "# 1. Create namespaces"
echo "kubectl create namespace fleet-local --dry-run=client -o yaml | kubectl apply -f -"
echo "kubectl create namespace cattle-monitoring-system --dry-run=client -o yaml | kubectl apply -f -"
echo ""
echo "# 2. Create secrets (manually - don't commit to Git)"
echo "kubectl create secret generic monitoring-secrets \\"
echo "  --namespace=cattle-monitoring-system \\"
echo "  --from-literal=grafana-admin-password=\"your-secure-password\" \\"
echo "  --dry-run=client -o yaml | kubectl apply -f -"
echo ""
echo "# 3. Apply Kustomize overlay"
echo "cd fleet/bundles/monitoring/overlays/$ENVIRONMENT"
echo "kubectl apply -k ."
echo ""
echo "# 4. Create Fleet GitRepo"
echo "kubectl apply -f - <<EOF"
echo "apiVersion: fleet.cattle.io/v1alpha1"
echo "kind: GitRepo"
echo "metadata:"
echo "  name: rancher-monitoring-$ENVIRONMENT"
echo "  namespace: fleet-local"
echo "spec:"
echo "  branch: main"
echo "  repo: https://github.com/YOUR-ORG/YOUR-GITOPS-REPO"
echo "  paths:"
echo "  - fleet/bundles/monitoring/overlays/$ENVIRONMENT"
echo "  refreshInterval: 60s"
echo "  targetsNamespace: cattle-monitoring-system"
echo "EOF"
echo ""

# Step 5: Show the benefits
echo "✅ Benefits of Fleet + Kustomize:"
echo ""
echo "1. 🔄 Variable Substitution: Kustomize replaces \${VARIABLE} with actual values"
echo "2. 🌍 Environment Separation: Different overlays for dev/staging/prod"
echo "3. 🔒 Secret Management: Secrets stored externally, not in Git"
echo "4. 📦 Helm Integration: Fleet handles Helm chart deployment"
echo "5. 🎯 GitOps Workflow: Changes in Git trigger deployments"
echo "6. 🔧 Minimal Setup: No additional tools needed beyond Fleet"
echo ""

# Step 6: Show how to check status
echo "📊 Status Commands:"
echo ""
echo "# Check Fleet GitRepo status"
echo "kubectl get gitrepo -n fleet-local"
echo ""
echo "# Check Fleet Bundle status"
echo "kubectl get bundle -n fleet-local"
echo ""
echo "# Check monitoring pods"
echo "kubectl get pods -n cattle-monitoring-system"
echo ""
echo "# Check Helm releases"
echo "kubectl get helmrelease -n cattle-monitoring-system"
echo ""
echo "# Access Grafana"
echo "kubectl port-forward svc/rancher-monitoring-grafana 3000:80 -n cattle-monitoring-system"
echo ""

echo "🎉 Fleet + Kustomize setup complete!"
echo ""
echo "💡 Tips:"
echo "- Use 'kubectl apply -k .' to apply Kustomize overlays"
echo "- Use 'kubectl diff -k .' to see what will change"
echo "- Use 'kubectl get kustomization' to check Kustomize status"
echo "- Use 'fleet get bundles' to check Fleet bundle status" 