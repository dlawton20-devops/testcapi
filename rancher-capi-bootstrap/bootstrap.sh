#!/bin/bash

# Rancher CAPI Bootstrap Script - Sylva-Style
# This script creates a complete Cluster API environment for Rancher management

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if environment values directory is provided
if [ $# -eq 0 ]; then
    print_error "Usage: $0 <environment-values-directory>"
    print_error "Example: $0 environment-values/default"
    exit 1
fi

ENVIRONMENT_VALUES_DIR="$1"

# Check if environment values directory exists
if [ ! -d "$ENVIRONMENT_VALUES_DIR" ]; then
    print_error "Environment values directory '$ENVIRONMENT_VALUES_DIR' does not exist"
    exit 1
fi

# Load environment values
VALUES_FILE="$ENVIRONMENT_VALUES_DIR/values.yaml"
if [ ! -f "$VALUES_FILE" ]; then
    print_error "Values file '$VALUES_FILE' does not exist"
    exit 1
fi

print_status "Loading configuration from $VALUES_FILE"

# Extract values from YAML (requires yq)
if ! command -v yq &> /dev/null; then
    print_error "yq is required but not installed. Please install yq first."
    print_status "Install with: brew install yq (macOS) or apt install yq (Ubuntu)"
    exit 1
fi

CLUSTER_NAME=$(yq eval '.cluster.name' "$VALUES_FILE")
CLUSTER_NODES=$(yq eval '.cluster.nodes' "$VALUES_FILE")
CAPI_VERSION=$(yq eval '.capi.version' "$VALUES_FILE")
FLUX_VERSION=$(yq eval '.flux.version' "$VALUES_FILE")

print_status "Configuration loaded:"
print_status "  Cluster Name: $CLUSTER_NAME"
print_status "  Cluster Nodes: $CLUSTER_NODES"
print_status "  CAPI Version: $CAPI_VERSION"
print_status "  Flux Version: $FLUX_VERSION"

# Check prerequisites
print_status "Checking prerequisites..."

# Check if Docker is running
if ! docker info &> /dev/null; then
    print_error "Docker is not running. Please start Docker first."
    exit 1
fi

# Check if kind is installed
if ! command -v kind &> /dev/null; then
    print_error "kind is not installed. Please install kind first."
    print_status "Install with: brew install kind (macOS) or go install sigs.k8s.io/kind@v0.20.0"
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please install kubectl first."
    exit 1
fi

# Check if clusterctl is installed
if ! command -v clusterctl &> /dev/null; then
    print_error "clusterctl is not installed. Please install clusterctl first."
    print_status "Install with: go install sigs.k8s.io/cluster-api/cmd/clusterctl@latest"
    exit 1
fi

# Check if flux is installed
if ! command -v flux &> /dev/null; then
    print_warning "flux CLI is not installed. Installing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install fluxcd/tap/flux
    else
        curl -s https://fluxcd.io/install.sh | sudo bash
    fi
fi

print_success "Prerequisites check completed"

# Create kind cluster
print_status "Creating kind cluster '$CLUSTER_NAME'..."

# Check if cluster already exists
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
    print_warning "Cluster '$CLUSTER_NAME' already exists. Deleting..."
    kind delete cluster --name "$CLUSTER_NAME"
fi

# Create cluster with configuration
kind create cluster --name "$CLUSTER_NAME" --config kind-config.yaml --wait 5m

# Set kubectl context
kubectl cluster-info --context "kind-$CLUSTER_NAME"

print_success "Kind cluster created successfully"

# Set up networking
print_status "Setting up networking..."
if ! docker network inspect kind > /dev/null 2>&1; then
    print_status "Creating Docker network 'kind'..."
    docker network create kind
fi

# Get cluster IP for configuration
KIND_PREFIX=$(docker network inspect kind -f '{{ (index .IPAM.Config 0).Subnet }}')
CLUSTER_IP=$(echo $KIND_PREFIX | awk -F"." '{print $1"."$2"."$3".100"}')
print_status "Cluster virtual IP: $CLUSTER_IP"

# Update values with cluster IP
yq eval -i ".cluster.virtual_ip = \"$CLUSTER_IP\"" "$VALUES_FILE"

print_success "Networking setup completed"

# Install Flux
print_status "Installing Flux..."
./scripts/install-flux.sh "$VALUES_FILE"

# Initialize Cluster API
print_status "Initializing Cluster API..."
./scripts/install-capi.sh "$VALUES_FILE"

# Install Rancher Operator
print_status "Installing Rancher Operator..."
./scripts/install-rancher-operator.sh "$VALUES_FILE"

# Deploy GitOps resources
print_status "Deploying GitOps resources..."
kubectl apply -f gitops/sources/
kubectl apply -f gitops/clusters/
kubectl apply -f gitops/rancher-resources/

# Wait for resources to be ready
print_status "Waiting for resources to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=source-controller -n flux-system --timeout=300s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=capi-controller -n capi-system --timeout=300s

# Validate deployment
print_status "Validating deployment..."
./scripts/validate-deployment.sh

print_success "CAPI Bootstrap completed successfully!"
print_status ""
print_status "🎉 Rancher CAPI Bootstrap Environment is ready!"
print_status ""
print_status "Next steps:"
print_status "1. Configure your Git repository in gitops/sources/git-repository.yaml"
print_status "2. Update cluster templates in clusters/templates/"
print_status "3. Commit your CAPI resources to the Git repository"
print_status "4. Monitor with: kubectl get clusters -A"
print_status ""
print_status "Useful commands:"
print_status "  kubectl get clusters -A                    # View CAPI clusters"
print_status "  kubectl get machines -A                    # View CAPI machines"
print_status "  kubectl get rancherusers -A                # View Rancher users"
print_status "  clusterctl describe cluster <name>         # Describe cluster"
print_status "  ./cleanup.sh                               # Clean up everything"
print_status ""
print_status "For more information, see README.md"
