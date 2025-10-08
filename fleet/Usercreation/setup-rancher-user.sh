#!/bin/bash

# Rancher User Setup Helper Script
# This script helps you get the required IDs and apply the manifests

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Rancher Local User Setup Helper ===${NC}"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Check if rancher CLI is available
if ! command -v rancher &> /dev/null; then
    echo -e "${YELLOW}Warning: rancher CLI is not installed. You'll need it to get user IDs.${NC}"
    echo "Install it from: https://github.com/rancher/cli/releases"
fi

echo -e "\n${YELLOW}Step 1: Get your local user ID${NC}"
echo "You can get your user ID using one of these methods:"
echo "1. Rancher UI: Go to Users & Authentication > Users, click on your user, copy the ID from URL"
echo "2. Rancher CLI: rancher users ls"
echo "3. kubectl: kubectl get users.management.cattle.io -o wide"

echo -e "\n${YELLOW}Step 2: Get cluster and project IDs${NC}"
echo "Get cluster ID:"
echo "kubectl get clusters.management.cattle.io -o wide"
echo ""
echo "Get project ID (after creating the project):"
echo "kubectl get projects.management.cattle.io -o wide"

echo -e "\n${YELLOW}Step 3: Update the manifest file${NC}"
echo "Edit rancher-user-setup.yaml and replace:"
echo "- 'your-local-user-id' with your actual user ID"
echo "- 'c-xxxxx:p-xxxxx' with actual cluster:project IDs"
echo "- 'your-cluster-name' with your actual cluster name"

echo -e "\n${YELLOW}Step 4: Apply the manifests${NC}"
echo "kubectl apply -f rancher-user-setup.yaml"

echo -e "\n${GREEN}=== Quick Commands ===${NC}"
echo ""
echo "# Get current user ID (if you're logged in as the user):"
echo "kubectl get users.management.cattle.io -o jsonpath='{.items[?(@.username==\"'$(whoami)'\")].metadata.name}'"
echo ""
echo "# Get all users:"
echo "kubectl get users.management.cattle.io -o wide"
echo ""
echo "# Get clusters:"
echo "kubectl get clusters.management.cattle.io -o wide"
echo ""
echo "# Get projects:"
echo "kubectl get projects.management.cattle.io -o wide"

echo -e "\n${YELLOW}Note: You may need to apply the manifests in a specific order:${NC}"
echo "1. First create the project"
echo "2. Then create the namespaces with project labels"
echo "3. Finally create the role bindings"