#!/bin/bash

# Fleet Deployment Script for Rancher Monitoring and Logging
# Usage: ./deploy-fleet.sh [environment]

set -e

ENVIRONMENT=${1:-staging}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "Deploying Rancher Monitoring and Logging via Fleet for environment: $ENVIRONMENT"

# Load environment variables
if [ -f "$ROOT_DIR/examples/env.$ENVIRONMENT" ]; then
    echo "Loading environment variables from examples/env.$ENVIRONMENT"
    export $(cat "$ROOT_DIR/examples/env.$ENVIRONMENT" | grep -v '^#' | xargs)
else
    echo "Environment file examples/env.$ENVIRONMENT not found"
    exit 1
fi

# Validate required variables
required_vars=("ENVIRONMENT" "PROMETHEUS_RETENTION" "STORAGE_CLASS")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: Required variable $var is not set"
        exit 1
    fi
done

echo "Environment: $ENVIRONMENT"
echo "Prometheus Retention: $PROMETHEUS_RETENTION"
echo "Storage Class: $STORAGE_CLASS"

# Create namespaces if they don't exist
echo "Creating namespaces..."
kubectl create namespace fleet-local --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace cattle-monitoring-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace cattle-logging-system --dry-run=client -o yaml | kubectl apply -f -

# Create secrets for Git access (if needed)
echo "Creating Git access secrets..."
kubectl create secret generic monitoring-git-secret \
    --namespace=fleet-local \
    --from-literal=username=git \
    --from-literal=password=your-git-token \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic logging-git-secret \
    --namespace=fleet-local \
    --from-literal=username=git \
    --from-literal=password=your-git-token \
    --dry-run=client -o yaml | kubectl apply -f -

# Create monitoring secrets
echo "Creating monitoring secrets..."
kubectl create secret generic monitoring-secrets \
    --namespace=cattle-monitoring-system \
    --from-literal=grafana-admin-password="$GRAFANA_ADMIN_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -

# Create logging secrets
echo "Creating logging secrets..."
kubectl create secret generic logging-secrets \
    --namespace=cattle-logging-system \
    --from-literal=external-logging-api-key="$EXTERNAL_LOGGING_API_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -

# Apply Fleet GitRepos
echo "Applying Fleet GitRepos..."
kubectl apply -f "$ROOT_DIR/fleet/gitrepos/monitoring-gitrepo.yaml"
kubectl apply -f "$ROOT_DIR/fleet/gitrepos/logging-gitrepo.yaml"

# Wait for GitRepos to be ready
echo "Waiting for GitRepos to be ready..."
kubectl wait --for=condition=Ready gitrepo/rancher-monitoring -n fleet-local --timeout=300s
kubectl wait --for=condition=Ready gitrepo/rancher-logging -n fleet-local --timeout=300s

# Wait for bundles to be ready
echo "Waiting for bundles to be ready..."
kubectl wait --for=condition=Ready bundle/rancher-monitoring -n fleet-local --timeout=600s
kubectl wait --for=condition=Ready bundle/rancher-logging -n fleet-local --timeout=600s

echo "Deployment completed successfully!"
echo ""
echo "To check the status:"
echo "  kubectl get gitrepo -n fleet-local"
echo "  kubectl get bundle -n fleet-local"
echo "  kubectl get pods -n cattle-monitoring-system"
echo "  kubectl get pods -n cattle-logging-system" 