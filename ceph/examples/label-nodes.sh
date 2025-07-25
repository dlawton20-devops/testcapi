#!/bin/bash

# Script to label nodes for Rook Ceph deployment
# Usage: ./label-nodes.sh
# Automatically finds and labels all nodes with "platformworker" in the name

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

# Function to show usage
show_usage() {
    echo "Usage: $0"
    echo ""
    echo "This script will:"
    echo "  1. Find all nodes with 'platformworker' in the name"
    echo "  2. Label them with ceph-storage=true"
    echo "  3. Label them with node-role.caas.com/platform-worker=true"
    echo "  4. Verify the labels were applied correctly"
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if we can connect to the cluster
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi

# Find nodes with "platformworker" in the name
print_status "Finding nodes with 'platformworker' in the name..."
PLATFORM_WORKER_NODES=$(kubectl get nodes -o jsonpath='{.items[?(@.metadata.name contains "platformworker")].metadata.name}')

if [ -z "$PLATFORM_WORKER_NODES" ]; then
    print_error "No nodes found with 'platformworker' in the name."
    print_status "Available nodes:"
    kubectl get nodes
    exit 1
fi

# Convert to array
IFS=' ' read -ra NODES_ARRAY <<< "$PLATFORM_WORKER_NODES"

print_status "Found ${#NODES_ARRAY[@]} platform worker node(s):"
for node in "${NODES_ARRAY[@]}"; do
    echo "  - $node"
done

print_status "Starting node labeling process..."

# Label each node
for node in "${NODES_ARRAY[@]}"; do
    print_status "Labeling node: $node"
    
    # Label with ceph-storage=true
    if kubectl label nodes "$node" ceph-storage=true --overwrite; then
        print_success "Applied ceph-storage=true to $node"
    else
        print_error "Failed to apply ceph-storage=true to $node"
        exit 1
    fi
    
    # Label with platform worker role
    if kubectl label nodes "$node" node-role.caas.com/platform-worker=true --overwrite; then
        print_success "Applied node-role.caas.com/platform-worker=true to $node"
    else
        print_warning "Failed to apply node-role.caas.com/platform-worker=true to $node (may already exist)"
    fi
done

echo ""
print_status "Verifying labels..."

# Show all nodes with their labels
echo ""
print_status "All nodes and their labels:"
kubectl get nodes --show-labels

echo ""
print_status "Detailed node information:"
for node in "${NODES_ARRAY[@]}"; do
    echo ""
    print_status "Node: $node"
    kubectl describe node "$node" | grep -E "(Name:|Labels:|Taints:)" || true
done

echo ""
print_success "Node labeling completed!"
echo ""
print_status "Next steps:"
echo "1. Verify the labels are correct above"
echo "2. Deploy Rook Ceph: ./deploy.sh -f examples/values-ceph-storage.yaml"
echo "3. Or customize your own values file based on examples/values-ceph-storage.yaml" 