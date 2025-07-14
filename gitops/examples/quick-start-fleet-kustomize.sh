#!/bin/bash

# Quick Start: Fleet + Kustomize for Rancher Monitoring
# This script actually deploys the monitoring stack

set -e

ENVIRONMENT=${1:-staging}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🚀 Quick Start: Fleet + Kustomize Deployment"
echo "Environment: $ENVIRONMENT"
echo ""

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    echo "❌ Error: Environment must be dev, staging, or prod"
    exit 1
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ Error: kubectl is not installed"
    exit 1
fi

# Check if we can connect to cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Error: Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "✅ Prerequisites check passed"
echo ""

# Step 1: Create namespaces
echo "📁 Creating namespaces..."
kubectl create namespace fleet-local --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace cattle-monitoring-system --dry-run=client -o yaml | kubectl apply -f -

# Step 2: Create secrets (if environment file exists)
echo "🔐 Creating secrets..."
if [ -f "$ROOT_DIR/examples/env.$ENVIRONMENT" ]; then
    echo "Using environment file: examples/env.$ENVIRONMENT"
    kubectl create secret generic monitoring-secrets \
        --namespace=cattle-monitoring-system \
        --from-env-file="$ROOT_DIR/examples/env.$ENVIRONMENT" \
        --dry-run=client -o yaml | kubectl apply -f -
else
    echo "⚠️  Warning: Environment file examples/env.$ENVIRONMENT not found"
    echo "Creating default secret (you should update this with real values)"
    kubectl create secret generic monitoring-secrets \
        --namespace=cattle-monitoring-system \
        --from-literal=grafana-admin-password="admin" \
        --from-literal=GRAFANA_ADMIN_PASSWORD="admin" \
        --dry-run=client -o yaml | kubectl apply -f -
fi

# Step 3: Apply Kustomize overlay
echo "🔧 Applying Kustomize overlay for $ENVIRONMENT..."
cd "$ROOT_DIR/fleet/bundles/monitoring/overlays/$ENVIRONMENT"

# Check if overlay exists
if [ ! -f "kustomization.yaml" ]; then
    echo "❌ Error: Overlay for environment $ENVIRONMENT not found"
    echo "Available overlays:"
    ls -la "$ROOT_DIR/fleet/bundles/monitoring/overlays/"
    exit 1
fi

echo "Applying overlay from: $(pwd)"
kubectl apply -k .

# Step 4: Create Fleet GitRepo
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

# Step 5: Wait for deployment
echo "⏳ Waiting for deployment to complete..."
echo "This may take a few minutes..."

# Wait for GitRepo to be ready
echo "Waiting for GitRepo to be ready..."
kubectl wait --for=condition=Ready gitrepo/rancher-monitoring-$ENVIRONMENT -n fleet-local --timeout=300s || echo "GitRepo not ready yet, continuing..."

# Wait for Bundle to be created
echo "Waiting for Bundle to be created..."
sleep 30

# Check status
echo ""
echo "📊 Deployment Status:"
echo ""

echo "Fleet GitRepo:"
kubectl get gitrepo -n fleet-local -o wide

echo ""
echo "Fleet Bundles:"
kubectl get bundle -n fleet-local -o wide

echo ""
echo "Monitoring Pods:"
kubectl get pods -n cattle-monitoring-system

echo ""
echo "Helm Releases:"
kubectl get helmrelease -n cattle-monitoring-system 2>/dev/null || echo "No HelmReleases found yet"

echo ""
echo "🎉 Deployment initiated!"
echo ""
echo "📈 Next Steps:"
echo "1. Monitor deployment: kubectl get pods -n cattle-monitoring-system -w"
echo "2. Check Fleet status: kubectl get gitrepo,bundle -n fleet-local"
echo "3. Access Grafana: kubectl port-forward svc/rancher-monitoring-grafana 3000:80 -n cattle-monitoring-system"
echo "4. Access Prometheus: kubectl port-forward svc/rancher-monitoring-prometheus 9090:9090 -n cattle-monitoring-system"
echo ""
echo "🔧 Troubleshooting:"
echo "- Check Fleet logs: kubectl logs -n fleet-system -l app=fleet-controller"
echo "- Check bundle status: kubectl describe bundle rancher-monitoring -n fleet-local"
echo "- Check GitRepo status: kubectl describe gitrepo rancher-monitoring-$ENVIRONMENT -n fleet-local" 