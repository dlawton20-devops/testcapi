#!/bin/bash

# Multi-Cluster Rancher User Setup
# This script adds cluster and project permissions to a user across ALL clusters in Rancher

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
USERNAME="${1:-lma-user}"
DRY_RUN="${2:-false}"  # Set to "true" for dry run
MANIFEST_DIR="multi-cluster-manifests"

echo -e "${GREEN}=== Multi-Cluster Rancher User Setup ===${NC}"
echo -e "${BLUE}Setting up user: ${USERNAME}${NC}"
echo -e "${BLUE}Dry run mode: ${DRY_RUN}${NC}"

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}Error: kubectl is not installed${NC}"
        exit 1
    fi
    
    if ! kubectl cluster-info >/dev/null 2>&1; then
        echo -e "${RED}Error: kubectl is not connected to a cluster${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Prerequisites check passed${NC}"
}

# Function to get user ID
get_user_id() {
    echo -e "${YELLOW}Finding user ID for: ${USERNAME}${NC}"
    
    USER_ID=$(kubectl get users.management.cattle.io -o jsonpath="{.items[?(@.username=='${USERNAME}')].metadata.name}" 2>/dev/null || echo "")
    
    if [ -z "$USER_ID" ]; then
        echo -e "${RED}User '${USERNAME}' not found${NC}"
        echo "Available users:"
        kubectl get users.management.cattle.io -o custom-columns="USERNAME:.username,ID:.metadata.name,DISPLAY:.displayName" 2>/dev/null
        exit 1
    fi
    
    echo -e "${GREEN}✓ Found user ID: ${USER_ID}${NC}"
}

# Function to discover all clusters
discover_clusters() {
    echo -e "${YELLOW}Discovering all clusters...${NC}"
    
    # Get all clusters (both local and downstream)
    CLUSTERS=$(kubectl get clusters.management.cattle.io -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$CLUSTERS" ]; then
        echo -e "${RED}No clusters found${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Found clusters: ${CLUSTERS}${NC}"
    
    # Convert to array
    IFS=' ' read -ra CLUSTER_ARRAY <<< "$CLUSTERS"
    echo -e "${BLUE}Total clusters: ${#CLUSTER_ARRAY[@]}${NC}"
}

# Function to create cluster role bindings for all clusters
create_cluster_permissions() {
    echo -e "${YELLOW}Creating cluster permissions for all clusters...${NC}"
    
    mkdir -p "$MANIFEST_DIR"
    
    for cluster in "${CLUSTER_ARRAY[@]}"; do
        echo -e "${PURPLE}Processing cluster: ${cluster}${NC}"
        
        # Get cluster display name
        CLUSTER_NAME=$(kubectl get clusters.management.cattle.io "$cluster" -o jsonpath='{.spec.displayName}' 2>/dev/null || echo "$cluster")
        
        # Create cluster member role binding
        cat > "$MANIFEST_DIR/cluster-member-${cluster}.yaml" << EOF
apiVersion: management.cattle.io/v3
kind: ClusterRoleTemplateBinding
metadata:
  name: ${USERNAME}-cluster-member-${cluster}
  namespace: "cattle-global-data"
clusterRoleTemplateId: "cluster-member"
userId: "${USER_ID}"
clusterId: "${cluster}"
EOF
        
        # Create cluster viewer role binding
        cat > "$MANIFEST_DIR/cluster-viewer-${cluster}.yaml" << EOF
apiVersion: management.cattle.io/v3
kind: ClusterRoleTemplateBinding
metadata:
  name: ${USERNAME}-cluster-viewer-${cluster}
  namespace: "cattle-global-data"
clusterRoleTemplateId: "cluster-view"
userId: "${USER_ID}"
clusterId: "${cluster}"
EOF
        
        echo -e "${GREEN}✓ Created manifests for cluster: ${CLUSTER_NAME} (${cluster})${NC}"
    done
}

# Function to discover and create project permissions
create_project_permissions() {
    echo -e "${YELLOW}Creating project permissions for all clusters...${NC}"
    
    for cluster in "${CLUSTER_ARRAY[@]}"; do
        echo -e "${PURPLE}Processing projects in cluster: ${cluster}${NC}"
        
        # Get all projects in this cluster
        PROJECTS=$(kubectl get projects.management.cattle.io -o jsonpath="{.items[?(@.spec.clusterName=='${cluster}')].metadata.name}" 2>/dev/null || echo "")
        
        if [ -n "$PROJECTS" ]; then
            IFS=' ' read -ra PROJECT_ARRAY <<< "$PROJECTS"
            
            for project in "${PROJECT_ARRAY[@]}"; do
                # Get project display name
                PROJECT_NAME=$(kubectl get projects.management.cattle.io "$project" -o jsonpath='{.spec.displayName}' 2>/dev/null || echo "$project")
                
                # Create project member role binding
                cat > "$MANIFEST_DIR/project-member-${project}.yaml" << EOF
apiVersion: management.cattle.io/v3
kind: ProjectRoleTemplateBinding
metadata:
  name: ${USERNAME}-project-member-${project}
  namespace: "cattle-global-data"
projectId: "${project}"
roleTemplateId: "project-member"
userId: "${USER_ID}"
EOF
                
                # Create project viewer role binding
                cat > "$MANIFEST_DIR/project-viewer-${project}.yaml" << EOF
apiVersion: management.cattle.io/v3
kind: ProjectRoleTemplateBinding
metadata:
  name: ${USERNAME}-project-viewer-${project}
  namespace: "cattle-global-data"
projectId: "${project}"
roleTemplateId: "project-view"
userId: "${USER_ID}"
EOF
                
                echo -e "${GREEN}✓ Created project permissions for: ${PROJECT_NAME} (${project})${NC}"
            done
        else
            echo -e "${YELLOW}⚠ No projects found in cluster: ${cluster}${NC}"
        fi
    done
}

# Function to apply manifests
apply_manifests() {
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}DRY RUN: Would apply the following manifests:${NC}"
        ls -la "$MANIFEST_DIR"/*.yaml 2>/dev/null || echo "No manifests found"
        echo -e "${BLUE}To apply for real, run: ${NC}./multi-cluster-setup.sh ${USERNAME} false"
        return
    fi
    
    echo -e "${YELLOW}Applying manifests...${NC}"
    
    # Apply cluster permissions
    for cluster in "${CLUSTER_ARRAY[@]}"; do
        echo -e "${PURPLE}Applying cluster permissions for: ${cluster}${NC}"
        
        if kubectl apply -f "$MANIFEST_DIR/cluster-member-${cluster}.yaml" 2>/dev/null; then
            echo -e "${GREEN}✓ Applied cluster member role for: ${cluster}${NC}"
        else
            echo -e "${RED}✗ Failed to apply cluster member role for: ${cluster}${NC}"
        fi
        
        if kubectl apply -f "$MANIFEST_DIR/cluster-viewer-${cluster}.yaml" 2>/dev/null; then
            echo -e "${GREEN}✓ Applied cluster viewer role for: ${cluster}${NC}"
        else
            echo -e "${RED}✗ Failed to apply cluster viewer role for: ${cluster}${NC}"
        fi
    done
    
    # Apply project permissions
    for manifest in "$MANIFEST_DIR"/project-*.yaml; do
        if [ -f "$manifest" ]; then
            if kubectl apply -f "$manifest" 2>/dev/null; then
                echo -e "${GREEN}✓ Applied project permission: $(basename "$manifest")${NC}"
            else
                echo -e "${RED}✗ Failed to apply project permission: $(basename "$manifest")${NC}"
            fi
        fi
    done
}

# Function to verify setup
verify_setup() {
    echo -e "${YELLOW}Verifying setup...${NC}"
    
    echo -e "${BLUE}Cluster permissions:${NC}"
    kubectl get clusterroletemplatebindings.management.cattle.io | grep "$USERNAME" || echo "No cluster permissions found"
    
    echo -e "${BLUE}Project permissions:${NC}"
    kubectl get projectroletemplatebindings.management.cattle.io | grep "$USERNAME" || echo "No project permissions found"
    
    echo -e "${BLUE}Total manifests created:${NC}"
    ls -1 "$MANIFEST_DIR"/*.yaml 2>/dev/null | wc -l || echo "0"
}

# Function to show summary
show_summary() {
    echo -e "${GREEN}=== Setup Summary ===${NC}"
    echo -e "${BLUE}User: ${USERNAME} (${USER_ID})${NC}"
    echo -e "${BLUE}Clusters processed: ${#CLUSTER_ARRAY[@]}${NC}"
    echo -e "${BLUE}Manifests created: $(ls -1 "$MANIFEST_DIR"/*.yaml 2>/dev/null | wc -l)${NC}"
    echo -e "${BLUE}Manifest directory: ${MANIFEST_DIR}/${NC}"
    
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}This was a dry run. No changes were applied.${NC}"
    else
        echo -e "${GREEN}Setup completed successfully!${NC}"
    fi
}

# Main execution
main() {
    check_prerequisites
    get_user_id
    discover_clusters
    create_cluster_permissions
    create_project_permissions
    apply_manifests
    verify_setup
    show_summary
}

# Run main function
main "$@"