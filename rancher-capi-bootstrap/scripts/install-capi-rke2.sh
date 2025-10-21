#!/bin/bash

# Install Cluster API with RKE2 Provider Script
# Part of the Rancher CAPI Bootstrap environment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[CAPI-RKE2]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[CAPI-RKE2]${NC} $1"
}

print_error() {
    echo -e "${RED}[CAPI-RKE2]${NC} $1"
}

# Check if values file is provided
if [ $# -eq 0 ]; then
    print_error "Usage: $0 <values-file>"
    exit 1
fi

VALUES_FILE="$1"

# Extract CAPI configuration
CAPI_VERSION=$(yq eval '.capi.version' "$VALUES_FILE")
RKE2_VERSION=$(yq eval '.rke2.version' "$VALUES_FILE")
OPENSTACK_CLOUD=$(yq eval '.openstack.cloud_name' "$VALUES_FILE")

print_status "Installing Cluster API with RKE2 provider"
print_status "CAPI Version: $CAPI_VERSION"
print_status "RKE2 Version: $RKE2_VERSION"
print_status "OpenStack Cloud: $OPENSTACK_CLOUD"

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

# Initialize Cluster API with RKE2 and OpenStack providers
print_status "Initializing Cluster API with RKE2 and OpenStack providers..."

# Initialize CAPI with RKE2 and OpenStack
clusterctl init \
    --core cluster-api:${CAPI_VERSION} \
    --bootstrap rke2-bootstrap:${RKE2_VERSION} \
    --control-plane rke2-control-plane:${RKE2_VERSION} \
    --infrastructure openstack:latest

# Wait for CAPI components to be ready
print_status "Waiting for CAPI components to be ready..."

# Wait for core CAPI controller
kubectl wait --for=condition=ready pod -l control-plane=controller-manager -n capi-system --timeout=300s

# Wait for RKE2 bootstrap controller
kubectl wait --for=condition=ready pod -l control-plane=bootstrap-controller-manager -n capi-rke2-bootstrap-system --timeout=300s

# Wait for RKE2 control plane controller
kubectl wait --for=condition=ready pod -l control-plane=controller-manager -n capi-rke2-control-plane-system --timeout=300s

# Wait for OpenStack infrastructure controller
kubectl wait --for=condition=ready pod -l control-plane=controller-manager -n capo-system --timeout=300s

# Verify installation
print_status "Verifying CAPI with RKE2 installation..."

# Check if CAPI CRDs are installed
if kubectl get crd clusters.cluster.x-k8s.io &> /dev/null; then
    print_success "CAPI CRDs are installed"
else
    print_error "CAPI CRDs are not installed"
    exit 1
fi

# Check if RKE2 CRDs are installed
if kubectl get crd rke2clusters.infrastructure.cluster.x-k8s.io &> /dev/null; then
    print_success "RKE2 CRDs are installed"
else
    print_error "RKE2 CRDs are not installed"
    exit 1
fi

# Check if OpenStack CRDs are installed
if kubectl get crd openstackclusters.infrastructure.cluster.x-k8s.io &> /dev/null; then
    print_success "OpenStack CRDs are installed"
else
    print_error "OpenStack CRDs are not installed"
    exit 1
fi

# Create OpenStack credentials secret
print_status "Creating OpenStack credentials secret..."
cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: openstack-credentials
  namespace: capo-system
type: Opaque
stringData:
  cloud.yaml: |
    clouds:
      $OPENSTACK_CLOUD:
        auth:
          auth_url: "https://your-openstack.com:5000/v3"
          username: "your-username"
          password: "your-password"
          project_name: "your-project"
          domain_name: "your-domain"
        region_name: "RegionOne"
        verify: false
EOF

# Display CAPI status
print_status "CAPI with RKE2 installation status:"
kubectl get pods -n capi-system
kubectl get pods -n capi-rke2-bootstrap-system
kubectl get pods -n capi-rke2-control-plane-system
kubectl get pods -n capo-system

# Create cluster templates namespace
print_status "Creating cluster templates namespace..."
kubectl create namespace cluster-templates --dry-run=client -o yaml | kubectl apply -f -

print_success "CAPI with RKE2 installation completed successfully!"

# Display useful commands
print_status "Useful commands:"
print_status "  kubectl get clusters -A                    # View CAPI clusters"
print_status "  kubectl get rke2clusters -A                 # View RKE2 clusters"
print_status "  kubectl get openstackclusters -A           # View OpenStack clusters"
print_status "  clusterctl describe cluster <name>         # Describe cluster"
print_status "  clusterctl get kubeconfig <name>           # Get cluster kubeconfig"
print_status "  clusterctl delete cluster <name>           # Delete cluster"
