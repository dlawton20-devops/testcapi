#!/bin/bash

# Tenant Deployment Script
# Usage: ./deploy-tenant.sh <tenant-name> <gitlab-repo-url> <gitlab-username> <gitlab-token>

set -e

TENANT_NAME=${1:-"tenant1"}
GITLAB_REPO_URL=${2:-"https://gitlab.com/your-org/tenant1-gitops.git"}
GITLAB_USERNAME=${3:-"flux-bot"}
GITLAB_TOKEN=${4:-""}

if [ -z "$GITLAB_TOKEN" ]; then
    echo "Error: GitLab token is required"
    echo "Usage: $0 <tenant-name> <gitlab-repo-url> <gitlab-username> <gitlab-token>"
    exit 1
fi

echo "Deploying tenant: $TENANT_NAME"
echo "GitLab Repo: $GITLAB_REPO_URL"

# Deploy to dev cluster
echo "Deploying to dev cluster..."
./install-flux.sh "dev-cluster" "$TENANT_NAME" "dev" "$GITLAB_REPO_URL" "$GITLAB_USERNAME" "$GITLAB_TOKEN"

# Deploy to preprod cluster
echo "Deploying to preprod cluster..."
./install-flux.sh "preprod-cluster" "$TENANT_NAME" "preprod" "$GITLAB_REPO_URL" "$GITLAB_USERNAME" "$GITLAB_TOKEN"

# Deploy to prod cluster
echo "Deploying to prod cluster..."
./install-flux.sh "prod-cluster" "$TENANT_NAME" "prod" "$GITLAB_REPO_URL" "$GITLAB_USERNAME" "$GITLAB_TOKEN"

echo "Tenant deployment completed!"
echo "Check status with:"
echo "  kubectl get gitrepositories,kustomizations -n flux-system"
echo "  kubectl get helmreleases -A" 