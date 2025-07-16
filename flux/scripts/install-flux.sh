#!/bin/bash

# Flux Installation Script for Multi-Tenant GitOps
# Usage: ./install-flux.sh <cluster-name> <tenant-name> <environment> <gitlab-repo-url> <gitlab-username> <gitlab-token>

set -e

CLUSTER_NAME=${1:-"dev-cluster"}
TENANT_NAME=${2:-"tenant1"}
ENVIRONMENT=${3:-"dev"}
GITLAB_REPO_URL=${4:-"https://gitlab.com/your-org/tenant1-gitops.git"}
GITLAB_USERNAME=${5:-"flux-bot"}
GITLAB_TOKEN=${6:-""}

if [ -z "$GITLAB_TOKEN" ]; then
    echo "Error: GitLab token is required"
    echo "Usage: $0 <cluster-name> <tenant-name> <environment> <gitlab-repo-url> <gitlab-username> <gitlab-token>"
    exit 1
fi

echo "Installing Flux on cluster: $CLUSTER_NAME"
echo "Tenant: $TENANT_NAME"
echo "Environment: $ENVIRONMENT"
echo "GitLab Repo: $GITLAB_REPO_URL"

# Add Flux Helm repository
helm repo add flux https://fluxcd.github.io/helm-charts
helm repo update

# Create namespace for Flux
kubectl create namespace flux-system --dry-run=client -o yaml | kubectl apply -f -

# Install Flux via Helm
helm upgrade --install flux flux/flux2 \
    --namespace flux-system \
    --create-namespace \
    --set clusterDomain=cluster.local \
    --set image.repository=ghcr.io/fluxcd/flux2 \
    --set image.tag=v2.1.0 \
    --set image.pullPolicy=IfNotPresent \
    --set logLevel=info \
    --set resources.requests.cpu=100m \
    --set resources.requests.memory=128Mi \
    --set resources.limits.cpu=1000m \
    --set resources.limits.memory=512Mi \
    --wait --timeout=5m

# Create GitRepository with basic auth
cat <<EOF | kubectl apply -f -
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: ${TENANT_NAME}-${ENVIRONMENT}
  namespace: flux-system
spec:
  interval: 1m
  url: ${GITLAB_REPO_URL}
  ref:
    branch: ${ENVIRONMENT}
  secretRef:
    name: gitlab-auth-${TENANT_NAME}
EOF

# Create secret for GitLab basic auth
kubectl create secret generic gitlab-auth-${TENANT_NAME} \
    --namespace=flux-system \
    --from-literal=username=${GITLAB_USERNAME} \
    --from-literal=password=${GITLAB_TOKEN} \
    --dry-run=client -o yaml | kubectl apply -f -

# Create Kustomization for cluster-specific resources
cat <<EOF | kubectl apply -f -
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: ${TENANT_NAME}-${ENVIRONMENT}-cluster
  namespace: flux-system
spec:
  interval: 10m
  path: ./clusters/${TENANT_NAME}/${ENVIRONMENT}-cluster
  prune: true
  sourceRef:
    kind: GitRepository
    name: ${TENANT_NAME}-${ENVIRONMENT}
  targetNamespace: flux-system
EOF

# Create Kustomization for shared infrastructure
cat <<EOF | kubectl apply -f -
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: ${TENANT_NAME}-${ENVIRONMENT}-shared
  namespace: flux-system
spec:
  interval: 10m
  path: ./shared
  prune: true
  sourceRef:
    kind: GitRepository
    name: ${TENANT_NAME}-${ENVIRONMENT}
  targetNamespace: flux-system
EOF

# Create Kustomization for tenant-specific applications
cat <<EOF | kubectl apply -f -
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: ${TENANT_NAME}-${ENVIRONMENT}-apps
  namespace: flux-system
spec:
  interval: 10m
  path: ./tenants/${TENANT_NAME}
  prune: true
  sourceRef:
    kind: GitRepository
    name: ${TENANT_NAME}-${ENVIRONMENT}
  targetNamespace: default
EOF

echo "Flux installation completed successfully!"
echo "Check status with: kubectl get gitrepositories,kustomizations -n flux-system" 