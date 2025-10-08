#!/bin/bash

# Simple script to find Rancher IDs
# Usage: ./find-ids.sh [username]

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

USERNAME="${1:-}"

echo -e "${BLUE}=== Rancher ID Finder ===${NC}"

# Check kubectl connection
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo -e "${RED}Error: kubectl is not connected to a cluster${NC}"
    exit 1
fi

echo -e "${YELLOW}1. Finding Cluster ID...${NC}"
CLUSTER_ID=$(kubectl get clusters.management.cattle.io -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "Not found")
echo -e "${GREEN}Cluster ID: ${CLUSTER_ID}${NC}"

echo -e "${YELLOW}2. Finding Cluster Name...${NC}"
CLUSTER_NAME=$(kubectl get clusters.management.cattle.io "$CLUSTER_ID" -o jsonpath='{.spec.displayName}' 2>/dev/null || echo "$CLUSTER_ID")
echo -e "${GREEN}Cluster Name: ${CLUSTER_NAME}${NC}"

if [ -n "$USERNAME" ]; then
    echo -e "${YELLOW}3. Finding User ID for: ${USERNAME}...${NC}"
    USER_ID=$(kubectl get users.management.cattle.io -o jsonpath="{.items[?(@.username=='${USERNAME}')].metadata.name}" 2>/dev/null || echo "Not found")
    echo -e "${GREEN}User ID: ${USER_ID}${NC}"
else
    echo -e "${YELLOW}3. Available Users:${NC}"
    kubectl get users.management.cattle.io -o custom-columns="USERNAME:.username,ID:.metadata.name,DISPLAY:.displayName" 2>/dev/null || echo "No users found"
fi

echo -e "${YELLOW}4. Available Projects:${NC}"
kubectl get projects.management.cattle.io -o custom-columns="NAME:.metadata.name,DISPLAY:.spec.displayName,CLUSTER:.spec.clusterName" 2>/dev/null || echo "No projects found"

echo -e "${YELLOW}5. Available Namespaces:${NC}"
kubectl get namespaces -o custom-columns="NAME:.metadata.name,PROJECT:.metadata.labels.field\.cattle\.io/projectId" 2>/dev/null | head -10

echo -e "${BLUE}=== Copy these values to your manifest ===${NC}"
echo "USER_ID: ${USER_ID:-'your-local-user-id'}"
echo "CLUSTER_ID: ${CLUSTER_ID}"
echo "CLUSTER_NAME: ${CLUSTER_NAME}"
echo "PROJECT_ID: c-${CLUSTER_ID#c-}:p-xxxxx (replace xxxxx with actual project ID)"