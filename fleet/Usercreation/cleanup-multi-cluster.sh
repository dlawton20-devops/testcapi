#!/bin/bash

# Multi-Cluster Cleanup Script
# This script removes user permissions from all clusters and projects

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
USERNAME="${1:-lma-user}"
CONFIRM="${2:-false}"

echo -e "${GREEN}=== Multi-Cluster Cleanup Script ===${NC}"
echo -e "${BLUE}Removing permissions for user: ${USERNAME}${NC}"

# Function to get user ID
get_user_id() {
    echo -e "${YELLOW}Finding user ID for: ${USERNAME}${NC}"
    
    USER_ID=$(kubectl get users.management.cattle.io -o jsonpath="{.items[?(@.username=='${USERNAME}')].metadata.name}" 2>/dev/null || echo "")
    
    if [ -z "$USER_ID" ]; then
        echo -e "${RED}User '${USERNAME}' not found${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Found user ID: ${USER_ID}${NC}"
}

# Function to remove cluster permissions
remove_cluster_permissions() {
    echo -e "${YELLOW}Removing cluster permissions...${NC}"
    
    # Remove cluster role template bindings
    CLUSTER_BINDINGS=$(kubectl get clusterroletemplatebindings.management.cattle.io -o jsonpath="{.items[?(@.userId=='${USER_ID}')].metadata.name}" 2>/dev/null || echo "")
    
    if [ -n "$CLUSTER_BINDINGS" ]; then
        IFS=' ' read -ra BINDING_ARRAY <<< "$CLUSTER_BINDINGS"
        
        for binding in "${BINDING_ARRAY[@]}"; do
            echo -e "${BLUE}Removing cluster binding: ${binding}${NC}"
            if kubectl delete clusterroletemplatebindings.management.cattle.io "$binding" 2>/dev/null; then
                echo -e "${GREEN}✓ Removed: ${binding}${NC}"
            else
                echo -e "${RED}✗ Failed to remove: ${binding}${NC}"
            fi
        done
    else
        echo -e "${YELLOW}No cluster permissions found${NC}"
    fi
}

# Function to remove project permissions
remove_project_permissions() {
    echo -e "${YELLOW}Removing project permissions...${NC}"
    
    # Remove project role template bindings
    PROJECT_BINDINGS=$(kubectl get projectroletemplatebindings.management.cattle.io -o jsonpath="{.items[?(@.userId=='${USER_ID}')].metadata.name}" 2>/dev/null || echo "")
    
    if [ -n "$PROJECT_BINDINGS" ]; then
        IFS=' ' read -ra BINDING_ARRAY <<< "$PROJECT_BINDINGS"
        
        for binding in "${BINDING_ARRAY[@]}"; do
            echo -e "${BLUE}Removing project binding: ${binding}${NC}"
            if kubectl delete projectroletemplatebindings.management.cattle.io "$binding" 2>/dev/null; then
                echo -e "${GREEN}✓ Removed: ${binding}${NC}"
            else
                echo -e "${RED}✗ Failed to remove: ${binding}${NC}"
            fi
        done
    else
        echo -e "${YELLOW}No project permissions found${NC}"
    fi
}

# Function to remove global permissions
remove_global_permissions() {
    echo -e "${YELLOW}Removing global permissions...${NC}"
    
    # Remove global role bindings
    GLOBAL_BINDINGS=$(kubectl get globalrolebindings.management.cattle.io -o jsonpath="{.items[?(@.userId=='${USER_ID}')].metadata.name}" 2>/dev/null || echo "")
    
    if [ -n "$GLOBAL_BINDINGS" ]; then
        IFS=' ' read -ra BINDING_ARRAY <<< "$GLOBAL_BINDINGS"
        
        for binding in "${BINDING_ARRAY[@]}"; do
            echo -e "${BLUE}Removing global binding: ${binding}${NC}"
            if kubectl delete globalrolebindings.management.cattle.io "$binding" 2>/dev/null; then
                echo -e "${GREEN}✓ Removed: ${binding}${NC}"
            else
                echo -e "${RED}✗ Failed to remove: ${binding}${NC}"
            fi
        done
    else
        echo -e "${YELLOW}No global permissions found${NC}"
    fi
}

# Function to confirm deletion
confirm_deletion() {
    if [ "$CONFIRM" != "true" ]; then
        echo -e "${RED}WARNING: This will remove ALL permissions for user '${USERNAME}'${NC}"
        echo -e "${YELLOW}This includes:${NC}"
        echo "- Global role bindings"
        echo "- Cluster role bindings (all clusters)"
        echo "- Project role bindings (all projects)"
        echo ""
        read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
        
        if [ "$confirmation" != "yes" ]; then
            echo -e "${YELLOW}Cleanup cancelled${NC}"
            exit 0
        fi
    fi
}

# Function to show summary
show_summary() {
    echo -e "${GREEN}=== Cleanup Summary ===${NC}"
    echo -e "${BLUE}User: ${USERNAME} (${USER_ID})${NC}"
    echo -e "${GREEN}Cleanup completed!${NC}"
}

# Main execution
main() {
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${RED}Error: kubectl is not connected to a cluster${NC}"
        exit 1
    fi
    
    get_user_id
    confirm_deletion
    remove_global_permissions
    remove_cluster_permissions
    remove_project_permissions
    show_summary
}

# Run main function
main "$@"