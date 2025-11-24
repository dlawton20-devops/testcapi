#!/bin/bash
set -e

echo "🌉 Simple Bridge Network Setup"
echo "==============================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BRIDGE_NETWORK="metal3-net"
BRIDGE_IP="192.168.124.1"
IRONIC_BRIDGE_PORT="6385"

# Check if network is active
echo ""
echo "Checking bridge network status..."
if virsh net-list --name 2>/dev/null | grep -q "^${BRIDGE_NETWORK}$"; then
    echo -e "${GREEN}✅ Bridge network is active${NC}"
else
    echo -e "${YELLOW}⚠️  Bridge network is not active${NC}"
    echo ""
    echo "Please start it manually:"
    echo "  sudo virsh net-start $BRIDGE_NETWORK"
    echo ""
    echo "Or if that doesn't work, use the default network:"
    echo "  sudo virsh net-start default"
    echo "  (Then update BRIDGE_NETWORK='default' and BRIDGE_IP='192.168.122.1')"
    echo ""
    read -p "Press Enter after starting the network, or Ctrl+C to cancel..."
    
    # Check again
    if virsh net-list --name 2>/dev/null | grep -q "^${BRIDGE_NETWORK}$"; then
        echo -e "${GREEN}✅ Bridge network is now active${NC}"
    else
        echo -e "${RED}❌ Bridge network is still not active${NC}"
        exit 1
    fi
fi

# Get NodePort
echo ""
echo "Getting Ironic NodePort..."
NODE_PORT=$(kubectl get svc metal3-metal3-ironic -n metal3-system -o jsonpath='{.spec.ports[?(@.port==6185)].nodePort}')
if [ -z "$NODE_PORT" ]; then
    NODE_PORT=$(kubectl get svc metal3-metal3-ironic -n metal3-system -o jsonpath='{.spec.ports[0].nodePort}')
fi

if [ -z "$NODE_PORT" ]; then
    echo -e "${RED}❌ Could not determine NodePort${NC}"
    exit 1
fi

echo -e "${GREEN}✅ NodePort: $NODE_PORT${NC}"

# Kill existing socat
echo ""
echo "Cleaning up existing port forwarding..."
pkill -f "socat.*${IRONIC_BRIDGE_PORT}" || true
sleep 1

# Check socat
if ! command -v socat &> /dev/null; then
    echo "Installing socat..."
    brew install socat
fi

# Start port forwarding
echo ""
echo "Starting port forwarding: ${BRIDGE_IP}:${IRONIC_BRIDGE_PORT} -> localhost:${NODE_PORT}"
sudo socat TCP-LISTEN:${IRONIC_BRIDGE_PORT},bind=${BRIDGE_IP},fork,reuseaddr TCP:localhost:${NODE_PORT} > /tmp/socat-ironic-bridge.log 2>&1 &
SOCAT_PID=$!
sleep 2

if kill -0 $SOCAT_PID 2>/dev/null; then
    echo -e "${GREEN}✅ Port forwarding started (PID: $SOCAT_PID)${NC}"
    echo $SOCAT_PID > /tmp/socat-ironic-bridge.pid
else
    echo -e "${RED}❌ Port forwarding failed${NC}"
    cat /tmp/socat-ironic-bridge.log
    exit 1
fi

# Update Ironic URL
echo ""
echo "Updating Ironic external URL..."
kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_EXTERNAL_HTTP_URL\":\"https://${BRIDGE_IP}:${IRONIC_BRIDGE_PORT}\"}}"
echo -e "${GREEN}✅ Ironic URL updated${NC}"

# Restart Ironic
echo ""
echo "Restarting Ironic pod..."
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic --wait=false
sleep 3

echo ""
echo -e "${GREEN}✅ Setup complete!${NC}"
echo ""
echo "Bridge Network: ${BRIDGE_NETWORK}"
echo "Bridge IP: ${BRIDGE_IP}"
echo "Ironic URL: https://${BRIDGE_IP}:${IRONIC_BRIDGE_PORT}"
echo "Port Forwarding PID: $SOCAT_PID"
echo ""

