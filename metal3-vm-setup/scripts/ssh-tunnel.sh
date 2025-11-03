#!/bin/bash

# SSH Tunnel Script for Kind Cluster Access
# Creates an SSH tunnel to access the Kind cluster API server from your local machine

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[TUNNEL]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[TUNNEL]${NC} $1"
}

print_error() {
    echo -e "${RED}[TUNNEL]${NC} $1"
}

# Configuration
VM_IP="${VM_IP:-}"
VM_USER="${VM_USER:-ubuntu}"
SSH_KEY="${SSH_KEY:-~/.ssh/id_rsa}"
LOCAL_PORT="${LOCAL_PORT:-6443}"
REMOTE_PORT="${REMOTE_PORT:-6443}"

# Check if VM_IP is set
if [ -z "$VM_IP" ]; then
    print_error "VM_IP not set. Please set it:"
    print_error "  export VM_IP=192.168.1.100"
    exit 1
fi

print_status "Setting up SSH tunnel to Kind cluster..."
print_status "VM: $VM_USER@$VM_IP"
print_status "Local port: $LOCAL_PORT -> Remote port: $REMOTE_PORT"
print_status ""
print_status "Keep this terminal open while using kubectl."
print_status "In another terminal, run:"
print_status "  export KUBECONFIG=/tmp/metal3-management-kubeconfig.yaml"
print_status "  kubectl --server=https://localhost:$LOCAL_PORT get nodes"
print_status ""
print_warning "Press Ctrl+C to stop the tunnel"
print_status ""

# Create SSH tunnel
ssh -i "$SSH_KEY" \
    -L ${LOCAL_PORT}:localhost:${REMOTE_PORT} \
    -N \
    -o ServerAliveInterval=60 \
    -o ServerAliveCountMax=3 \
    "$VM_USER@$VM_IP"

