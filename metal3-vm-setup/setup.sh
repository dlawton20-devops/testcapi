#!/bin/bash

# Main Setup Script Wrapper
# This is the entry point for setting up Metal3 on an OpenStack VM

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Check if VM_IP is set
if [ -z "$VM_IP" ]; then
    echo "Error: VM_IP not set"
    echo ""
    echo "Usage:"
    echo "  export VM_IP=\"192.168.1.100\""
    echo "  export VM_USER=\"ubuntu\"          # Optional, default: ubuntu"
    echo "  export SSH_KEY=\"~/.ssh/id_rsa\"   # Optional, default: ~/.ssh/id_rsa"
    echo "  export CLUSTER_NAME=\"metal3-management\"  # Optional"
    echo "  ./setup.sh"
    echo ""
    echo "Note: This setup configures the Kind cluster for external Rancher management."
    echo "      The API server will be exposed on the VM's external IP."
    echo ""
    exit 1
fi

# Run the main setup script
exec "$SCRIPT_DIR/scripts/setup-vm-with-kind-and-simulators.sh" "$@"

