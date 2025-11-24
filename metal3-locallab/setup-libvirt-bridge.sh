#!/bin/bash
set -e

echo "🌉 Setting up libvirt bridge network for Metal3"
echo "================================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BRIDGE_NAME="metal3-bridge"
BRIDGE_NETWORK="metal3-net"
BRIDGE_IP="192.168.124.1"
BRIDGE_NETMASK="255.255.255.0"
BRIDGE_DHCP_START="192.168.124.100"
BRIDGE_DHCP_END="192.168.124.200"

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${YELLOW}⚠️  This script is optimized for macOS. Linux may need different setup.${NC}"
fi

# Check if bridge network already exists
if virsh net-info "$BRIDGE_NETWORK" &>/dev/null; then
    echo -e "${GREEN}✅ Bridge network $BRIDGE_NETWORK already exists${NC}"
    virsh net-info "$BRIDGE_NETWORK"
    
    # Check if it's active
    if virsh net-list --name | grep -q "^${BRIDGE_NETWORK}$"; then
        echo -e "${GREEN}✅ Bridge network is active${NC}"
        exit 0
    else
        echo "Starting bridge network..."
        virsh net-start "$BRIDGE_NETWORK" || true
        virsh net-autostart "$BRIDGE_NETWORK" || true
        exit 0
    fi
fi

echo "Creating bridge network configuration..."

# Create bridge network XML
cat > /tmp/${BRIDGE_NETWORK}.xml <<EOF
<network>
  <name>${BRIDGE_NETWORK}</name>
  <forward mode='bridge'/>
  <bridge name='${BRIDGE_NAME}'/>
</network>
EOF

# For macOS, we'll use a routed network that can reach the Docker network
# This is more compatible than a true bridge on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    # Get Docker bridge network info
    DOCKER_BRIDGE=$(docker network inspect bridge 2>/dev/null | python3 -c "import sys, json; data=json.load(sys.stdin); print(data[0].get('IPAM', {}).get('Config', [{}])[0].get('Subnet', '172.17.0.0/16'))" 2>/dev/null || echo "172.17.0.0/16")
    
    echo "Creating routed network for macOS (compatible with Docker/kind)..."
    cat > /tmp/${BRIDGE_NETWORK}.xml <<EOF
<network>
  <name>${BRIDGE_NETWORK}</name>
  <uuid>$(uuidgen)</uuid>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='${BRIDGE_NAME}' stp='on' delay='0'/>
  <mac address='52:54:00:$(openssl rand -hex 3 | sed 's/\(..\)/\1:/g; s/.$//')'/>
  <ip address='${BRIDGE_IP}' netmask='${BRIDGE_NETMASK}'>
    <dhcp>
      <range start='${BRIDGE_DHCP_START}' end='${BRIDGE_DHCP_END}'/>
    </dhcp>
  </ip>
</network>
EOF
fi

# Define the network
virsh net-define /tmp/${BRIDGE_NETWORK}.xml
virsh net-autostart "$BRIDGE_NETWORK"

# Start the network (may require sudo on macOS)
if virsh net-start "$BRIDGE_NETWORK" 2>/dev/null; then
    echo -e "${GREEN}✅ Network started${NC}"
else
    echo -e "${YELLOW}⚠️  Failed to start network. You may need to run with sudo:${NC}"
    echo "   sudo virsh net-start $BRIDGE_NETWORK"
    echo "   Or ensure your user is in the libvirt group"
fi

echo -e "${GREEN}✅ Bridge network $BRIDGE_NETWORK created and started${NC}"

# Show network info
echo ""
echo "Network information:"
virsh net-info "$BRIDGE_NETWORK"

echo ""
echo -e "${GREEN}✅ Bridge network setup complete!${NC}"
echo ""
echo "Network details:"
echo "  Name: $BRIDGE_NETWORK"
echo "  Bridge: $BRIDGE_NAME"
echo "  IP Range: ${BRIDGE_DHCP_START}-${BRIDGE_DHCP_END}"
echo ""
echo "VMs using this network will be able to communicate with:"
echo "  - The Kubernetes cluster (via routing)"
echo "  - The host machine"
echo "  - Other VMs on the same network"

