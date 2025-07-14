#!/bin/bash

# Simple Fleet + Kustomize Deployment Script
# Usage: ./deploy-simple.sh [environment]
# Environments: dev, staging, prod

set -e

ENVIRONMENT=${1:-staging}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🚀 Deploying Rancher Monitoring via Fleet + Kustomize"
echo "Environment: $ENVIRONMENT"

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    echo "❌ Error: Environment must be dev, staging, or prod"
    exit 1
fi

# Create namespaces
echo "📁 Creating namespaces..."
kubectl create namespace fleet-local --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace cattle-monitoring-system --dry-run=client -o yaml | kubectl apply -f -

# Create secrets from environment file
echo "🔐 Creating secrets..."
if [ -f "$ROOT_DIR/examples/env.$ENVIRONMENT" ]; then
    kubectl create secret generic monitoring-secrets \
        --namespace=cattle-monitoring-system \
        --from-env-file="$ROOT_DIR/examples/env.$ENVIRONMENT" \
        --dry-run=client -o yaml | kubectl apply -f -
else
    echo "⚠️  Warning: Environment file examples/env.$ENVIRONMENT not found"
fi

# Apply Kustomize overlay
echo "🔧 Applying Kustomize overlay for $ENVIRONMENT..."
cd "$ROOT_DIR/fleet/bundles/monitoring/overlays/$ENVIRONMENT"
kubectl apply -k .

# Create Fleet GitRepo (if not exists)
echo "📦 Creating Fleet GitRepo..."
kubectl apply -f - <<EOF
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: rancher-monitoring-$ENVIRONMENT
  namespace: fleet-local
spec:
  branch: main
  repo: https://github.com/YOUR-ORG/YOUR-GITOPS-REPO
  paths:
  - fleet/bundles/monitoring/overlays/$ENVIRONMENT
  refreshInterval: 60s
  targetsNamespace: cattle-monitoring-system
EOF

echo "✅ Deployment initiated!"
echo ""
echo "📊 To check status:"
echo "  kubectl get gitrepo -n fleet-local"
echo "  kubectl get bundle -n fleet-local"
echo "  kubectl get pods -n cattle-monitoring-system"
echo ""
echo "🌐 To access Grafana:"
echo "  kubectl port-forward svc/rancher-monitoring-grafana 3000:80 -n cattle-monitoring-system"
echo ""
echo "📈 To check logs:"
echo "  kubectl logs -n cattle-monitoring-system -l app=prometheus" 