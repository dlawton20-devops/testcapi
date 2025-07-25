#!/bin/bash

# Rook Ceph Sub-Chart Deployment Script
# This script deploys Rook Ceph using the new sub-chart structure

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

# Function to deploy CRDs first
deploy_crds() {
    local values_file=${1:-""}
    
    print_status "Step 1: Deploying CRDs..."
    
    if [ -n "$values_file" ] && [ -f "$values_file" ]; then
        helm install rook-crds ./charts/rook-crds -f "$values_file" --wait --timeout=5m
    else
        helm install rook-crds ./charts/rook-crds --wait --timeout=5m
    fi
    
    print_success "CRDs deployed successfully"
    
    # Wait for CRDs to be established
    print_status "Waiting for CRDs to be established..."
    kubectl wait --for=condition=established --timeout=60s crd/cephclusters.ceph.rook.io
    kubectl wait --for=condition=established --timeout=60s crd/cephfilesystems.ceph.rook.io
    
    print_success "CRDs are ready"
}

# Function to deploy operator
deploy_operator() {
    local values_file=${1:-""}
    
    print_status "Step 2: Deploying Rook Operator..."
    
    if [ -n "$values_file" ] && [ -f "$values_file" ]; then
        helm install rook-operator ./charts/rook-operator -f "$values_file" --wait --timeout=10m
    else
        helm install rook-operator ./charts/rook-operator --wait --timeout=10m
    fi
    
    print_success "Operator deployed successfully"
    
    # Wait for operator to be ready
    print_status "Waiting for operator to be ready..."
    kubectl wait --for=condition=ready pod -l app=rook-ceph-operator -n rook-ceph --timeout=300s
    
    print_success "Operator is ready"
}

# Function to deploy cluster
deploy_cluster() {
    local values_file=${1:-""}
    
    print_status "Step 3: Deploying Ceph Cluster..."
    
    if [ -n "$values_file" ] && [ -f "$values_file" ]; then
        helm install rook-cluster ./charts/rook-cluster -f "$values_file" --wait --timeout=15m
    else
        helm install rook-cluster ./charts/rook-cluster --wait --timeout=15m
    fi
    
    print_success "Cluster deployed successfully"
}

# Function to verify deployment
verify_deployment() {
    print_status "Verifying deployment..."
    
    # Wait for cluster to be ready
    print_status "Waiting for Ceph cluster to be ready..."
    kubectl wait --for=condition=ready cephcluster -n rook-ceph --timeout=600s
    
    # Wait for filesystem to be ready
    print_status "Waiting for CephFS filesystem to be ready..."
    kubectl wait --for=condition=ready cephfilesystem -n rook-ceph --timeout=300s
    
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

# Function to deploy all at once (using main chart)
deploy_all() {
    local values_file=${1:-""}
    
    print_status "Deploying all components using main chart..."
    
    if [ -n "$values_file" ] && [ -f "$values_file" ]; then
        helm install rook-ceph . -f "$values_file" --wait --timeout=20m
    else
        helm install rook-ceph . --wait --timeout=20m
    fi
    
    print_success "All components deployed successfully"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --values-file FILE     Custom values file"
    echo "  -s, --step-by-step        Deploy step by step (CRDs -> Operator -> Cluster)"
    echo "  -a, --all-at-once         Deploy all components at once (default)"
    echo "  -h, --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy all at once with default values"
    echo "  $0 -f custom-values.yaml              # Deploy all at once with custom values"
    echo "  $0 -s -f custom-values.yaml           # Deploy step by step with custom values"
    echo "  $0 -a -f custom-values.yaml           # Deploy all at once with custom values"
}

# Main script
main() {
    local values_file=""
    local step_by_step=false
    local all_at_once=true
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--values-file)
                values_file="$2"
                shift 2
                ;;
            -s|--step-by-step)
                step_by_step=true
                all_at_once=false
                shift
                ;;
            -a|--all-at-once)
                all_at_once=true
                step_by_step=false
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
    
    if [ "$step_by_step" = true ]; then
        print_status "Deploying Rook Ceph step by step..."
        
        # Step 1: Deploy CRDs
        deploy_crds "$values_file"
        
        # Step 2: Deploy Operator
        deploy_operator "$values_file"
        
        # Step 3: Deploy Cluster
        deploy_cluster "$values_file"
        
        # Verify deployment
        verify_deployment
        
    else
        print_status "Deploying Rook Ceph all at once..."
        deploy_all "$values_file"
        verify_deployment
    fi
    
    print_success "Rook Ceph deployment completed successfully!"
    echo ""
    print_status "Next steps:"
    echo "1. Check Ceph status: kubectl exec -it -n rook-ceph deploy/rook-ceph-toolbox -- ceph status"
    echo "2. Test storage: kubectl get pvc -n rook-ceph"
    echo "3. Access dashboard: kubectl port-forward -n rook-ceph svc/rook-ceph-mgr-dashboard 8443:8443"
}

# Run main function
main "$@" 