#!/bin/bash

# Install Cluster API Script
# Part of the Rancher CAPI Bootstrap environment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[CAPI]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[CAPI]${NC} $1"
}

print_error() {
    echo -e "${RED}[CAPI]${NC} $1"
}

# Check if values file is provided
if [ $# -eq 0 ]; then
    print_error "Usage: $0 <values-file>"
    exit 1
fi

VALUES_FILE="$1"

# Extract CAPI configuration
CAPI_VERSION=$(yq eval '.capi.version' "$VALUES_FILE")
CAPI_NAMESPACE=$(yq eval '.capi.namespace' "$VALUES_FILE")

print_status "Installing Cluster API version: $CAPI_VERSION"
print_status "Namespace: $CAPI_NAMESPACE"

# Check if clusterctl is installed
if ! command -v clusterctl &> /dev/null; then
    print_error "clusterctl is not installed. Please install it first."
    print_status "Install with: go install sigs.k8s.io/cluster-api/cmd/clusterctl@latest"
    exit 1
fi

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to cluster. Please ensure kubectl is configured."
    exit 1
fi

# Initialize Cluster API
print_status "Initializing Cluster API..."

# Initialize CAPI with Docker provider
clusterctl init \
    --core cluster-api:${CAPI_VERSION} \
    --bootstrap kubeadm-bootstrap:${CAPI_VERSION} \
    --control-plane kubeadm-control-plane:${CAPI_VERSION} \
    --infrastructure docker:${CAPI_VERSION}

# Wait for CAPI components to be ready
print_status "Waiting for CAPI components to be ready..."

# Wait for core CAPI controller
kubectl wait --for=condition=ready pod -l control-plane=controller-manager -n capi-system --timeout=300s

# Wait for bootstrap controller
kubectl wait --for=condition=ready pod -l control-plane=bootstrap-controller-manager -n capi-kubeadm-bootstrap-system --timeout=300s

# Wait for control plane controller
kubectl wait --for=condition=ready pod -l control-plane=controller-manager -n capi-kubeadm-control-plane-system --timeout=300s

# Wait for Docker infrastructure controller
kubectl wait --for=condition=ready pod -l control-plane=controller-manager -n capd-system --timeout=300s

# Verify installation
print_status "Verifying CAPI installation..."

# Check if CAPI CRDs are installed
if kubectl get crd clusters.cluster.x-k8s.io &> /dev/null; then
    print_success "CAPI CRDs are installed"
else
    print_error "CAPI CRDs are not installed"
    exit 1
fi

# Check if Docker provider CRDs are installed
if kubectl get crd dockerclusters.infrastructure.cluster.x-k8s.io &> /dev/null; then
    print_success "Docker provider CRDs are installed"
else
    print_error "Docker provider CRDs are not installed"
    exit 1
fi

# Display CAPI status
print_status "CAPI installation status:"
kubectl get pods -n capi-system
kubectl get pods -n capi-kubeadm-bootstrap-system
kubectl get pods -n capi-kubeadm-control-plane-system
kubectl get pods -n capd-system

# Create cluster templates namespace
print_status "Creating cluster templates namespace..."
kubectl create namespace cluster-templates --dry-run=client -o yaml | kubectl apply -f -

print_success "CAPI installation completed successfully!"

# Display useful commands
print_status "Useful commands:"
print_status "  kubectl get clusters -A                    # View CAPI clusters"
print_status "  kubectl get machines -A                    # View CAPI machines"
print_status "  clusterctl describe cluster <name>         # Describe cluster"
print_status "  clusterctl get kubeconfig <name>           # Get cluster kubeconfig"
print_status "  clusterctl delete cluster <name>           # Delete cluster"
