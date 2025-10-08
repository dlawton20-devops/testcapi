#!/bin/bash

# Rancher User Auto-Setup Script
# This script automatically finds all required IDs and applies the manifests

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MANIFEST_FILE="rancher-user-setup.yaml"
TEMP_MANIFEST="rancher-user-setup-temp.yaml"
USERNAME="${1:-lma-user}"  # Default username or first argument

echo -e "${GREEN}=== Rancher User Auto-Setup Script ===${NC}"
echo -e "${BLUE}Setting up user: ${USERNAME}${NC}"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check kubectl connection
check_kubectl() {
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${RED}Error: kubectl is not connected to a cluster${NC}"
        echo "Please ensure kubectl is configured and connected to your Rancher cluster"
        exit 1
    fi
}

# Function to get user ID
get_user_id() {
    echo -e "${YELLOW}Finding user ID for: ${USERNAME}${NC}"
    
    # Try to find existing user
    USER_ID=$(kubectl get users.management.cattle.io -o jsonpath="{.items[?(@.username=='${USERNAME}')].metadata.name}" 2>/dev/null || echo "")
    
    if [ -z "$USER_ID" ]; then
        echo -e "${YELLOW}User '${USERNAME}' not found. Available users:${NC}"
        kubectl get users.management.cattle.io -o custom-columns="NAME:.metadata.name,USERNAME:.username,DISPLAY:.displayName" 2>/dev/null || echo "No users found"
        echo ""
        read -p "Enter the user ID manually (or press Enter to create a new user): " USER_ID
        
        if [ -z "$USER_ID" ]; then
            echo -e "${BLUE}Creating new user via Rancher API...${NC}"
            create_user_via_api
        fi
    else
        echo -e "${GREEN}Found user ID: ${USER_ID}${NC}"
    fi
}

# Function to create user via API (if Rancher CLI is available)
create_user_via_api() {
    if command_exists rancher; then
        echo -e "${BLUE}Creating user with Rancher CLI...${NC}"
        read -s -p "Enter password for new user: " PASSWORD
        echo ""
        
        # Create user via Rancher CLI
        USER_ID=$(rancher users create --username "$USERNAME" --password "$PASSWORD" --enabled 2>/dev/null | grep -o 'user-[a-z0-9]*' || echo "")
        
        if [ -n "$USER_ID" ]; then
            echo -e "${GREEN}User created successfully: ${USER_ID}${NC}"
        else
            echo -e "${RED}Failed to create user via Rancher CLI${NC}"
            echo "Please create the user manually in Rancher UI and run this script again"
            exit 1
        fi
    else
        echo -e "${RED}Rancher CLI not found. Please install it or create the user manually.${NC}"
        echo "Install from: https://github.com/rancher/cli/releases"
        exit 1
    fi
}

# Function to get cluster ID
get_cluster_id() {
    echo -e "${YELLOW}Finding cluster ID...${NC}"
    
    CLUSTER_ID=$(kubectl get clusters.management.cattle.io -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$CLUSTER_ID" ]; then
        echo -e "${YELLOW}No clusters found. Available clusters:${NC}"
        kubectl get clusters.management.cattle.io -o custom-columns="NAME:.metadata.name,DISPLAY:.spec.displayName" 2>/dev/null || echo "No clusters found"
        echo ""
        read -p "Enter the cluster ID manually: " CLUSTER_ID
        
        if [ -z "$CLUSTER_ID" ]; then
            echo -e "${RED}Cluster ID is required${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}Found cluster ID: ${CLUSTER_ID}${NC}"
    fi
}

# Function to get or create project ID
get_project_id() {
    echo -e "${YELLOW}Finding LMA project ID...${NC}"
    
    # Try to find existing LMA project
    PROJECT_ID=$(kubectl get projects.management.cattle.io -o jsonpath="{.items[?(@.spec.displayName=='LMA (Logging, Monitoring, Alerting)')].metadata.name}" 2>/dev/null || echo "")
    
    if [ -z "$PROJECT_ID" ]; then
        echo -e "${YELLOW}LMA project not found. Will create it...${NC}"
        PROJECT_ID="c-${CLUSTER_ID#c-}:p-$(openssl rand -hex 4)"
        echo -e "${BLUE}Generated project ID: ${PROJECT_ID}${NC}"
    else
        echo -e "${GREEN}Found existing LMA project: ${PROJECT_ID}${NC}"
    fi
}

# Function to get cluster name
get_cluster_name() {
    echo -e "${YELLOW}Finding cluster name...${NC}"
    
    CLUSTER_NAME=$(kubectl get clusters.management.cattle.io "$CLUSTER_ID" -o jsonpath='{.spec.displayName}' 2>/dev/null || echo "")
    
    if [ -z "$CLUSTER_NAME" ]; then
        CLUSTER_NAME="$CLUSTER_ID"
        echo -e "${YELLOW}Using cluster ID as name: ${CLUSTER_NAME}${NC}"
    else
        echo -e "${GREEN}Found cluster name: ${CLUSTER_NAME}${NC}"
    fi
}

# Function to update manifest with found IDs
update_manifest() {
    echo -e "${YELLOW}Updating manifest with found IDs...${NC}"
    
    # Create a copy of the manifest
    cp "$MANIFEST_FILE" "$TEMP_MANIFEST"
    
    # Replace placeholders with actual values
    sed -i.bak "s/your-local-user-id/${USER_ID}/g" "$TEMP_MANIFEST"
    sed -i.bak "s/c-xxxxx:p-xxxxx/${PROJECT_ID}/g" "$TEMP_MANIFEST"
    sed -i.bak "s/your-cluster-name/${CLUSTER_NAME}/g" "$TEMP_MANIFEST"
    
    # Clean up backup file
    rm -f "${TEMP_MANIFEST}.bak"
    
    echo -e "${GREEN}Manifest updated successfully${NC}"
}

# Function to apply manifests
apply_manifests() {
    echo -e "${YELLOW}Applying manifests...${NC}"
    
    if kubectl apply -f "$TEMP_MANIFEST"; then
        echo -e "${GREEN}Manifests applied successfully!${NC}"
    else
        echo -e "${RED}Failed to apply manifests${NC}"
        echo "Check the error messages above and try again"
        exit 1
    fi
}

# Function to verify setup
verify_setup() {
    echo -e "${YELLOW}Verifying setup...${NC}"
    
    echo "Checking user permissions..."
    kubectl auth can-i get pods --as="$USER_ID" 2>/dev/null && echo -e "${GREEN}✓ User can access pods${NC}" || echo -e "${RED}✗ User cannot access pods${NC}"
    
    echo "Checking project..."
    kubectl get projects.management.cattle.io | grep -i lma && echo -e "${GREEN}✓ LMA project exists${NC}" || echo -e "${RED}✗ LMA project not found${NC}"
    
    echo "Checking namespaces..."
    kubectl get namespaces | grep -E "(cattle-monitoring-system|cattle-logging-system)" && echo -e "${GREEN}✓ Monitoring/Logging namespaces exist${NC}" || echo -e "${YELLOW}⚠ Namespaces may not be created yet${NC}"
}

# Function to cleanup
cleanup() {
    echo -e "${YELLOW}Cleaning up temporary files...${NC}"
    rm -f "$TEMP_MANIFEST"
}

# Main execution
main() {
    echo -e "${BLUE}Starting Rancher user setup automation...${NC}"
    
    # Check prerequisites
    if ! command_exists kubectl; then
        echo -e "${RED}Error: kubectl is not installed${NC}"
        exit 1
    fi
    
    check_kubectl
    
    # Get all required IDs
    get_user_id
    get_cluster_id
    get_project_id
    get_cluster_name
    
    # Update and apply manifests
    update_manifest
    apply_manifests
    
    # Verify setup
    verify_setup
    
    # Cleanup
    cleanup
    
    echo -e "${GREEN}=== Setup Complete! ===${NC}"
    echo -e "${BLUE}User ID: ${USER_ID}${NC}"
    echo -e "${BLUE}Cluster ID: ${CLUSTER_ID}${NC}"
    echo -e "${BLUE}Project ID: ${PROJECT_ID}${NC}"
    echo -e "${BLUE}Cluster Name: ${CLUSTER_NAME}${NC}"
}

# Run main function
main "$@"