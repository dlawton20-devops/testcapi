#!/bin/bash

# Rook Ceph Helm Chart Deployment Script
# This script helps deploy the Rook Ceph chart with proper setup

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
    
    # Check if helm is installed
    if ! command -v helm &> /dev/null; then
        print_error "helm is not installed. Please install helm first."
        exit 1
    fi
    
    # Check if we can connect to the cluster
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Function to add Rook Helm repository
add_rook_repo() {
    print_status "Adding Rook Helm repository..."
    
    if helm repo add rook-release https://charts.rook.io/release 2>/dev/null; then
        print_success "Rook repository added"
    else
        print_warning "Rook repository might already exist"
    fi
    
    helm repo update
    print_success "Helm repositories updated"
}

# Function to get node information
get_node_info() {
    print_status "Getting cluster node information..."
    
    echo "Available nodes in your cluster:"
    kubectl get nodes -o wide
    
    echo ""
    print_warning "Please note the hostnames of your nodes for configuration"
}

# Function to deploy the chart
deploy_chart() {
    local release_name=${1:-"rook-ceph"}
    local values_file=${2:-""}
    
    print_status "Deploying Rook Ceph chart..."
    
    if [ -n "$values_file" ] && [ -f "$values_file" ]; then
        print_status "Using custom values file: $values_file"
        helm install "$release_name" . -f "$values_file" --wait --timeout=10m
    else
        print_status "Using default values"
        helm install "$release_name" . --wait --timeout=10m
    fi
    
    print_success "Chart deployed successfully"
}

# Function to verify deployment
verify_deployment() {
    local release_name=${1:-"rook-ceph"}
    
    print_status "Verifying deployment..."
    
    # Wait for CRDs to be created
    print_status "Waiting for CRDs to be created..."
    kubectl wait --for=condition=established --timeout=60s crd/cephclusters.ceph.rook.io
    
    # Wait for operator to be ready
    print_status "Waiting for Rook operator to be ready..."
    kubectl wait --for=condition=ready pod -l app=rook-ceph-operator -n rook-ceph --timeout=300s
    
    # Wait for operator to be fully functional
    print_status "Waiting for operator to be fully functional..."
    sleep 30
    
    # Check if cluster is created
    if kubectl get cephcluster -n rook-ceph &>/dev/null; then
        print_status "Waiting for Ceph cluster to be ready..."
        kubectl wait --for=condition=ready cephcluster -n rook-ceph --timeout=600s
    fi
    
    # Wait for filesystem to be ready
    if kubectl get cephfilesystem -n rook-ceph &>/dev/null; then
        print_status "Waiting for CephFS filesystem to be ready..."
        kubectl wait --for=condition=ready cephfilesystem -n rook-ceph --timeout=300s
    fi
    
    # Wait for toolbox to be ready
    print_status "Waiting for toolbox to be ready..."
    kubectl wait --for=condition=ready pod -l app=rook-ceph-toolbox -n rook-ceph --timeout=300s
    
    # Wait for test PVC to be ready
    if kubectl get pvc test-cephfs-pvc -n rook-ceph &>/dev/null; then
        print_status "Waiting for test PVC to be ready..."
        kubectl wait --for=condition=bound pvc/test-cephfs-pvc -n rook-ceph --timeout=300s
    fi
    
    # Wait for test pod to be ready
    if kubectl get pod test-cephfs-pod -n rook-ceph &>/dev/null; then
        print_status "Waiting for test pod to be ready..."
        kubectl wait --for=condition=ready pod/test-cephfs-pod -n rook-ceph --timeout=300s
    fi
    
    # Show pod status
    print_status "Pod status:"
    kubectl get pods -n rook-ceph
    
    # Show storage classes
    print_status "Storage classes:"
    kubectl get storageclass
    
    # Show PVCs
    print_status "PVCs:"
    kubectl get pvc -n rook-ceph
    
    print_success "Deployment verification completed"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -r, --release-name NAME    Release name (default: rook-ceph)"
    echo "  -f, --values-file FILE     Custom values file"
    echo "  -n, --nodes-only           Only show node information"
    echo "  -h, --help                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy with default values"
    echo "  $0 -f custom-values.yaml              # Deploy with custom values"
    echo "  $0 -r my-rook -f 3-nodes-example.yaml # Deploy with custom release name and values"
    echo "  $0 -n                                 # Only show node information"
}

# Main script
main() {
    local release_name="rook-ceph"
    local values_file=""
    local nodes_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--release-name)
                release_name="$2"
                shift 2
                ;;
            -f|--values-file)
                values_file="$2"
                shift 2
                ;;
            -n|--nodes-only)
                nodes_only=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Check prerequisites
    check_prerequisites
    
    # Show node information
    get_node_info
    
    if [ "$nodes_only" = true ]; then
        print_status "Node information displayed. Exiting."
        exit 0
    fi
    
    # Add Rook repository
    add_rook_repo
    
    # Deploy the chart
    deploy_chart "$release_name" "$values_file"
    
    # Verify deployment
    verify_deployment "$release_name"
    
    print_success "Rook Ceph deployment completed successfully!"
    echo ""
    print_status "Next steps:"
    echo "1. Check cluster health: kubectl -n rook-ceph get cephcluster -o yaml"
    echo "2. Access dashboard: kubectl -n rook-ceph get service rook-ceph-mgr-dashboard"
    echo "3. Use CephFS storage class: kubectl get storageclass"
    echo "4. Test CephFS: kubectl logs test-cephfs-pod -n rook-ceph"
    echo "5. Use toolbox: kubectl -n rook-ceph exec -it deploy/rook-ceph-toolbox -- ceph status"
    echo ""
    print_status "For more information, see the README.md file"
}

# Run main function
main "$@" 