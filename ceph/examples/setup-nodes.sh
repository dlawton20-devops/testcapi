#!/bin/bash

# Node Setup Script for Rook Ceph Cluster
# This script helps prepare your nodes with the required labels and taints

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
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -n, --nodes NODES     Comma-separated list of node names"
    echo "  -l, --labels-only     Only add labels (no taints)"
    echo "  -t, --taints-only     Only add taints (no labels)"
    echo "  -r, --remove          Remove labels and taints instead of adding"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -n node1.example.com,node2.example.com,node3.example.com"
    echo "  $0 -n node1,node2,node3 -l"
    echo "  $0 -n node1,node2,node3 -r"
}

# Function to add labels to nodes
add_labels() {
    local nodes=$1
    print_status "Adding labels to nodes..."
    
    for node in ${nodes//,/ }; do
        print_status "Adding labels to node: $node"
        
        # Add storage role label
        kubectl label nodes "$node" node-role.kubernetes.io/storage=true --overwrite
        
        # Add storage type label
        kubectl label nodes "$node" storage-type=ceph --overwrite
        
        # Add node type label
        kubectl label nodes "$node" node-type=storage --overwrite
        
        print_success "Labels added to node: $node"
    done
}

# Function to add taints to nodes
add_taints() {
    local nodes=$1
    print_status "Adding taints to nodes..."
    
    for node in ${nodes//,/ }; do
        print_status "Adding taints to node: $node"
        
        # Add storage role taint
        kubectl taint nodes "$node" node-role.kubernetes.io/storage=true:NoSchedule --overwrite
        
        # Add dedicated taint
        kubectl taint nodes "$node" dedicated=ceph:NoSchedule --overwrite
        
        # Add storage taint
        kubectl taint nodes "$node" storage=ceph:NoExecute --overwrite
        
        print_success "Taints added to node: $node"
    done
}

# Function to remove labels from nodes
remove_labels() {
    local nodes=$1
    print_status "Removing labels from nodes..."
    
    for node in ${nodes//,/ }; do
        print_status "Removing labels from node: $node"
        
        # Remove storage role label
        kubectl label nodes "$node" node-role.kubernetes.io/storage- || true
        
        # Remove storage type label
        kubectl label nodes "$node" storage-type- || true
        
        # Remove node type label
        kubectl label nodes "$node" node-type- || true
        
        print_success "Labels removed from node: $node"
    done
}

# Function to remove taints from nodes
remove_taints() {
    local nodes=$1
    print_status "Removing taints from nodes..."
    
    for node in ${nodes//,/ }; do
        print_status "Removing taints from node: $node"
        
        # Remove storage role taint
        kubectl taint nodes "$node" node-role.kubernetes.io/storage=true:NoSchedule- || true
        
        # Remove dedicated taint
        kubectl taint nodes "$node" dedicated=ceph:NoSchedule- || true
        
        # Remove storage taint
        kubectl taint nodes "$node" storage=ceph:NoExecute- || true
        
        print_success "Taints removed from node: $node"
    done
}

# Function to show current node status
show_node_status() {
    local nodes=$1
    print_status "Current node status:"
    
    for node in ${nodes//,/ }; do
        echo ""
        print_status "Node: $node"
        echo "Labels:"
        kubectl get node "$node" -o jsonpath='{.metadata.labels}' | jq . 2>/dev/null || kubectl get node "$node" -o jsonpath='{.metadata.labels}'
        echo ""
        echo "Taints:"
        kubectl get node "$node" -o jsonpath='{.spec.taints}' | jq . 2>/dev/null || kubectl get node "$node" -o jsonpath='{.spec.taints}'
        echo ""
    done
}

# Main script
main() {
    local nodes=""
    local labels_only=false
    local taints_only=false
    local remove_mode=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -n|--nodes)
                nodes="$2"
                shift 2
                ;;
            -l|--labels-only)
                labels_only=true
                shift
                ;;
            -t|--taints-only)
                taints_only=true
                shift
                ;;
            -r|--remove)
                remove_mode=true
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
    
    # Check if nodes are provided
    if [ -z "$nodes" ]; then
        print_error "No nodes specified. Use -n option to specify nodes."
        show_usage
        exit 1
    fi
    
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
    
    print_status "Setting up nodes for Rook Ceph cluster..."
    print_status "Nodes: $nodes"
    
    if [ "$remove_mode" = true ]; then
        if [ "$labels_only" = true ]; then
            remove_labels "$nodes"
        elif [ "$taints_only" = true ]; then
            remove_taints "$nodes"
        else
            remove_labels "$nodes"
            remove_taints "$nodes"
        fi
    else
        if [ "$labels_only" = true ]; then
            add_labels "$nodes"
        elif [ "$taints_only" = true ]; then
            add_taints "$nodes"
        else
            add_labels "$nodes"
            add_taints "$nodes"
        fi
    fi
    
    echo ""
    show_node_status "$nodes"
    
    print_success "Node setup completed!"
    echo ""
    print_status "Next steps:"
    echo "1. Update your values.yaml with the correct node names"
    echo "2. Deploy Rook Ceph: ./deploy.sh -f your-values.yaml"
}

# Run main function
main "$@" 