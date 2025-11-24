#!/bin/bash
set -e

echo "🌉 Setting up Bridge Network Port Forwarding"
echo "=============================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

BRIDGE_NETWORK="metal3-net"
BRIDGE_IP="192.168.124.1"
IRONIC_BRIDGE_PORT="6385"

# Get NodePort
echo "Getting Ironic NodePort..."
NODE_PORT=$(kubectl get svc metal3-metal3-ironic -n metal3-system -o jsonpath='{.spec.ports[?(@.port==6185)].nodePort}')
if [ -z "$NODE_PORT" ]; then
    NODE_PORT=$(kubectl get svc metal3-metal3-ironic -n metal3-system -o jsonpath='{.spec.ports[0].nodePort}')
fi

if [ -z "$NODE_PORT" ]; then
    echo -e "${RED}❌ Could not determine NodePort. Is Ironic service configured as NodePort?${NC}"
    exit 1
fi

echo -e "${GREEN}✅ NodePort: $NODE_PORT${NC}"

# Start bridge network
echo ""
echo "Starting bridge network..."
if virsh net-list --name | grep -q "^${BRIDGE_NETWORK}$"; then
    echo -e "${GREEN}✅ Bridge network is already active${NC}"
else
    if virsh net-start "$BRIDGE_NETWORK" 2>/dev/null; then
        echo -e "${GREEN}✅ Bridge network started${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not start bridge network without sudo.${NC}"
        echo "Please run: sudo virsh net-start $BRIDGE_NETWORK"
        echo ""
        read -p "Press Enter after starting the network, or Ctrl+C to cancel..."
    fi
fi

# Kill existing socat processes
echo ""
echo "Cleaning up existing port forwarding..."
pkill -f "socat.*${IRONIC_BRIDGE_PORT}" || true
sleep 1

# Check if socat is installed
if ! command -v socat &> /dev/null; then
    echo -e "${YELLOW}⚠️  socat is not installed. Installing...${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install socat || {
            echo -e "${RED}❌ Failed to install socat. Please install manually: brew install socat${NC}"
            exit 1
        }
    else
        sudo apt-get update && sudo apt-get install -y socat || {
            echo -e "${RED}❌ Failed to install socat. Please install manually${NC}"
            exit 1
        }
    fi
fi

# Start socat to forward from bridge network to NodePort
echo ""
echo "Setting up port forwarding from bridge network to NodePort..."
echo "  Bridge IP: ${BRIDGE_IP}:${IRONIC_BRIDGE_PORT}"
echo "  Forwarding to: localhost:${NODE_PORT}"

# Check if we can bind to the bridge IP (requires root)
if sudo socat TCP-LISTEN:${IRONIC_BRIDGE_PORT},bind=${BRIDGE_IP},fork,reuseaddr TCP:localhost:${NODE_PORT} > /tmp/socat-ironic-bridge.log 2>&1 &
then
    SOCAT_PID=$!
    sleep 2
    
    if kill -0 $SOCAT_PID 2>/dev/null; then
        echo -e "${GREEN}✅ Port forwarding started (PID: $SOCAT_PID)${NC}"
        echo ""
        echo "Port forwarding is running. To stop it, run:"
        echo "  sudo kill $SOCAT_PID"
        echo ""
        echo "Or save the PID:"
        echo "  echo $SOCAT_PID > /tmp/socat-ironic-bridge.pid"
        echo $SOCAT_PID > /tmp/socat-ironic-bridge.pid
    else
        echo -e "${RED}❌ Port forwarding failed to start. Check /tmp/socat-ironic-bridge.log${NC}"
        exit 1
    fi
else
    echo -e "${RED}❌ Failed to start port forwarding${NC}"
    exit 1
fi

# Update Ironic external URL
echo ""
echo "Updating Ironic external URL to use bridge network IP..."
kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_EXTERNAL_HTTP_URL\":\"https://${BRIDGE_IP}:${IRONIC_BRIDGE_PORT}\"}}"

# Restart Ironic pod to apply changes
echo "Restarting Ironic pod to apply URL change..."
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic --wait=false
sleep 3

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Bridge Network Port Forwarding Setup Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Bridge Network: ${BRIDGE_NETWORK} (192.168.124.0/24)"
echo "Bridge Gateway: ${BRIDGE_IP}"
echo "Ironic URL (from VM): https://${BRIDGE_IP}:${IRONIC_BRIDGE_PORT}"
echo "Ironic NodePort: ${NODE_PORT}"
echo "Port Forwarding PID: $SOCAT_PID (saved to /tmp/socat-ironic-bridge.pid)"
echo ""
echo "Test from host:"
echo "  curl -k https://${BRIDGE_IP}:${IRONIC_BRIDGE_PORT}/"
echo ""
echo "Test from VM (if VM is on bridge network):"
echo "  curl -k https://${BRIDGE_IP}:${IRONIC_BRIDGE_PORT}/"
echo ""

