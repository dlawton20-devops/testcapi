#!/bin/bash

# Authentication Setup Script for Fleet with Harbor and GitLab
# Update the variables below with your actual values

# Harbor Configuration
HARBOR_URL="harbor.your-domain.com"
HARBOR_USERNAME="robot$project-name$fleet-robot"
HARBOR_PASSWORD="your-robot-token"
HARBOR_EMAIL="robot@your-domain.com"

# GitLab Configuration
GITLAB_USERNAME="your-gitlab-username"
GITLAB_TOKEN="your-gitlab-token"

echo "🚀 Setting up Fleet authentication for Harbor and GitLab..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed or not in PATH"
    exit 1
fi

# Check if we can connect to cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "✅ Kubernetes cluster connection verified"

# Create Harbor secret
echo "📦 Creating Harbor secret..."
kubectl create secret docker-registry harbor-secret \
  --docker-server=$HARBOR_URL \
  --docker-username=$HARBOR_USERNAME \
  --docker-password=$HARBOR_PASSWORD \
  --docker-email=$HARBOR_EMAIL \
  -n fleet-local

if [ $? -eq 0 ]; then
    echo "✅ Harbor secret created successfully"
else
    echo "❌ Failed to create Harbor secret"
    exit 1
fi

# Create GitLab secret
echo "🔑 Creating GitLab secret..."
kubectl create secret generic gitlab-secret \
  --from-literal=username=$GITLAB_USERNAME \
  --from-literal=password=$GITLAB_TOKEN \
  -n fleet-local

if [ $? -eq 0 ]; then
    echo "✅ GitLab secret created successfully"
else
    echo "❌ Failed to create GitLab secret"
    exit 1
fi

# Verify secrets
echo "🔍 Verifying secrets..."
echo "Harbor secret:"
kubectl get secret harbor-secret -n fleet-local
echo ""
echo "GitLab secret:"
kubectl get secret gitlab-secret -n fleet-local

# Test Harbor connection
echo "🧪 Testing Harbor connection..."
if docker login $HARBOR_URL -u $HARBOR_USERNAME -p $HARBOR_PASSWORD &> /dev/null; then
    echo "✅ Harbor connection successful"
else
    echo "⚠️  Harbor connection failed - check credentials"
fi

# Test GitLab connection
echo "🧪 Testing GitLab connection..."
if curl -s -H "Authorization: Bearer $GITLAB_TOKEN" \
  "https://gitlab.com/api/v4/user" &> /dev/null; then
    echo "✅ GitLab connection successful"
else
    echo "⚠️  GitLab connection failed - check token"
fi

echo ""
echo "🎉 Authentication setup complete!"
echo ""
echo "Next steps:"
echo "1. Update your fleet.yaml with your actual repository URL"
echo "2. Update your Harbor repository URL in bundle configurations"
echo "3. Apply your Fleet configuration: kubectl apply -f fleet.yaml"
echo "4. Verify deployment: kubectl get gitrepo -A"
echo ""
echo "Troubleshooting commands:"
echo "- Check secrets: kubectl get secrets -n fleet-local"
echo "- Check Fleet status: kubectl get gitrepo -A"
echo "- Check Fleet logs: kubectl logs -n fleet-system deployment/fleet-controller" 