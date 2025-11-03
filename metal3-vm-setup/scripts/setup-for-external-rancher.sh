#!/bin/bash

# Setup Script for External Rancher Cluster Integration
# Configures Kind cluster on VM to be managed by external Rancher cluster

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[RANCHER-INTEGRATION]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[RANCHER-INTEGRATION]${NC} $1"
}

print_error() {
    echo -e "${RED}[RANCHER-INTEGRATION]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[RANCHER-INTEGRATION]${NC} $1"
}

# Configuration
VM_IP="${VM_IP:-}"
VM_USER="${VM_USER:-ubuntu}"
SSH_KEY="${SSH_KEY:-~/.ssh/id_rsa}"
RANCHER_NETWORK="${RANCHER_NETWORK:-}"  # CIDR of Rancher cluster network (e.g., 10.0.0.0/8)

# Check prerequisites
if [ -z "$VM_IP" ]; then
    print_error "VM_IP not set. Please set it:"
    print_error "  export VM_IP=192.168.1.100"
    exit 1
fi

if [ -z "$RANCHER_NETWORK" ]; then
    print_warning "RANCHER_NETWORK not set. Will allow from all IPs (0.0.0.0/0)"
    print_warning "For production, set: export RANCHER_NETWORK=10.0.0.0/8"
    RANCHER_NETWORK="0.0.0.0/0"
fi

print_status "═══════════════════════════════════════════════════"
print_status "Configuring Kind Cluster for External Rancher"
print_status "═══════════════════════════════════════════════════"
print_status "VM IP: $VM_IP"
print_status "Rancher Network: $RANCHER_NETWORK"
print_status ""

# Verify kind-config.yaml is configured correctly
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

API_ADDRESS=$(grep "apiServerAddress" "$BASE_DIR/kind-config.yaml" | grep -oE '"[^"]+"' | tr -d '"' || echo "")
if [ "$API_ADDRESS" != "0.0.0.0" ]; then
    print_error "kind-config.yaml must have apiServerAddress: \"0.0.0.0\""
    print_error "Please update kind-config.yaml before running this script"
    exit 1
fi

# Configure security group
print_status "Configuring OpenStack security group..."
print_status "Adding rules to allow:"
print_status "  - Kubernetes API (6443) from Rancher cluster"
print_status "  - Redfish Simulators (8000-8002) from Rancher cluster (for Metal3/Ironic)"

# Note: This assumes you have OpenStack CLI configured
# If not, you'll need to do this manually
if command -v openstack &> /dev/null; then
    # Kubernetes API port (6443)
    if openstack security group rule list default -f value -c "IP Protocol" -c "Port Range" -c "Remote IP Prefix" | grep -q "tcp.*6443.*$RANCHER_NETWORK"; then
        print_status "✓ Security group rule for Kubernetes API (6443) already exists"
    else
        print_status "Creating security group rule for Kubernetes API (6443)..."
        openstack security group rule create default \
            --protocol tcp \
            --dst-port 6443 \
            --remote-ip "$RANCHER_NETWORK" || {
            print_warning "Failed to create security group rule for port 6443"
            print_warning "Please create it manually:"
            print_warning "  openstack security group rule create default \\"
            print_warning "    --protocol tcp --dst-port 6443 --remote-ip $RANCHER_NETWORK"
        }
    fi
    
    # Redfish simulator ports (8000, 8001, 8002)
    for port in 8000 8001 8002; do
        if openstack security group rule list default -f value -c "IP Protocol" -c "Port Range" -c "Remote IP Prefix" | grep -q "tcp.*$port.*$RANCHER_NETWORK"; then
            print_status "✓ Security group rule for Redfish simulator (port $port) already exists"
        else
            print_status "Creating security group rule for Redfish simulator (port $port)..."
            openstack security group rule create default \
                --protocol tcp \
                --dst-port $port \
                --remote-ip "$RANCHER_NETWORK" || {
                print_warning "Failed to create security group rule for port $port"
                print_warning "Please create it manually:"
                print_warning "  openstack security group rule create default \\"
                print_warning "    --protocol tcp --dst-port $port --remote-ip $RANCHER_NETWORK"
            }
        fi
    done
else
    print_warning "OpenStack CLI not found. Please create security group rules manually:"
    print_warning "  # Kubernetes API"
    print_warning "  openstack security group rule create default \\"
    print_warning "    --protocol tcp --dst-port 6443 --remote-ip $RANCHER_NETWORK"
    print_warning ""
    print_warning "  # Redfish Simulators (for Metal3/Ironic)"
    for port in 8000 8001 8002; do
        print_warning "  openstack security group rule create default \\"
        print_warning "    --protocol tcp --dst-port $port --remote-ip $RANCHER_NETWORK"
    done
fi

# Get kubeconfig
print_status "Getting Kind cluster kubeconfig..."
ssh -i "$SSH_KEY" "$VM_USER@$VM_IP" "kind get kubeconfig --name metal3-management" > "/tmp/kind-metal3-management-kubeconfig.yaml"

# Update kubeconfig server URL to use VM IP
print_status "Updating kubeconfig to use VM external IP..."
sed -i.bak "s|server: https://.*:6443|server: https://${VM_IP}:6443|" "/tmp/kind-metal3-management-kubeconfig.yaml"

# Verify connectivity
print_status "Testing connectivity to Kind cluster..."
if kubectl --kubeconfig=/tmp/kind-metal3-management-kubeconfig.yaml get nodes &>/dev/null; then
    print_success "✓ Successfully connected to Kind cluster"
    kubectl --kubeconfig=/tmp/kind-metal3-management-kubeconfig.yaml get nodes
else
    print_error "✗ Cannot connect to Kind cluster"
    print_error "Please verify:"
    print_error "  1. Kind cluster is running on VM"
    print_error "  2. Security group allows port 6443 from your network"
    print_error "  3. VM IP is correct: $VM_IP"
    exit 1
fi

# Verify simulator accessibility from Rancher network perspective
print_status ""
print_status "Verifying simulator endpoints..."
SIMULATOR_PORTS=(8000 8001 8002)
for port in "${SIMULATOR_PORTS[@]}"; do
    if curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${VM_IP}:${port}/redfish/v1/" | grep -q "200"; then
        print_success "✓ Simulator on port $port is accessible"
    else
        print_warning "⚠ Simulator on port $port may not be accessible from this network"
        print_warning "  Verify security group rules allow port $port from Rancher cluster"
    fi
done

print_success "═══════════════════════════════════════════════════"
print_success "Kind Cluster Ready for Rancher Integration"
print_success "═══════════════════════════════════════════════════"
print_status ""
print_status "Kubeconfig saved to: /tmp/kind-metal3-management-kubeconfig.yaml"
print_status ""
print_status "Network Access Configured:"
print_status "  ✓ Kubernetes API: ${VM_IP}:6443 (for Rancher cluster management)"
print_status "  ✓ Redfish Simulators: ${VM_IP}:8000-8002 (for Metal3/Ironic provisioning)"
print_status ""
print_status "BMC Addresses for BareMetalHost (use from Rancher cluster):"
print_status "  Control Plane: redfish-virtualmedia://${VM_IP}:8000/redfish/v1/Systems/1"
print_status "  Worker 0:      redfish-virtualmedia://${VM_IP}:8001/redfish/v1/Systems/1"
print_status "  Worker 1:      redfish-virtualmedia://${VM_IP}:8002/redfish/v1/Systems/1"
print_status ""
print_status "Next steps to import into Rancher:"
print_status ""
print_status "1. Access Rancher UI:"
print_status "   - Go to Clusters → Import Existing"
print_status "   - Copy the import command provided"
print_status ""
print_status "2. Run import command:"
print_status "   kubectl --kubeconfig=/tmp/kind-metal3-management-kubeconfig.yaml apply -f - <<EOF"
print_status "   # ... (paste import manifest from Rancher UI)"
print_status "   EOF"
print_status ""
print_status "3. Alternative: Use Rancher API:"
print_status "   curl -X POST \\"
print_status "     -H \"Authorization: Bearer \$RANCHER_TOKEN\" \\"
print_status "     -H \"Content-Type: application/json\" \\"
print_status "     -d '{\"type\":\"cluster\",\"name\":\"kind-metal3\",\"kubeconfig\":\"'$(base64 -w 0 /tmp/kind-metal3-management-kubeconfig.yaml)'\"}' \\"
print_status "     \"\$RANCHER_URL/v3/clusters\""
print_status ""
print_status "4. Verify in Rancher:"
print_status "   - Navigate to Clusters → kind-metal3-management"
print_status "   - Cluster should appear and be managed by Rancher"
print_status ""
print_status "For detailed instructions, see: docs/RANCHER-INTEGRATION.md"

