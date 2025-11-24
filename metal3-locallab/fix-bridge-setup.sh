#!/bin/bash
set -e

echo "🔧 Fixing Bridge Network Setup"
echo "==============================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 1. Start libvirt service
echo ""
echo "1. Starting libvirt service..."
# Check if libvirt is actually accessible
if virsh list &>/dev/null 2>&1; then
    echo -e "${GREEN}✅ libvirt is already running and accessible${NC}"
else
    echo "Starting libvirt..."
    brew services start libvirt
    sleep 5
    # Check if libvirt is now accessible
    if virsh list &>/dev/null 2>&1; then
        echo -e "${GREEN}✅ libvirt started and accessible${NC}"
    else
        echo -e "${YELLOW}⚠️  libvirt service started but may need a moment to be fully ready${NC}"
        echo "Waiting a bit more..."
        sleep 3
        if virsh list &>/dev/null 2>&1; then
            echo -e "${GREEN}✅ libvirt is now accessible${NC}"
        else
            echo -e "${YELLOW}⚠️  libvirt may still be starting. Continuing anyway...${NC}"
        fi
    fi
fi

# 2. Start bridge network
echo ""
echo "2. Starting bridge network..."
BRIDGE_NETWORK="metal3-net"

if virsh net-list --name 2>/dev/null | grep -q "^${BRIDGE_NETWORK}$"; then
    echo -e "${GREEN}✅ Bridge network is already active${NC}"
else
    echo "Attempting to start bridge network..."
    # Try without sudo first (run in background with timeout simulation)
    (virsh net-start "$BRIDGE_NETWORK" 2>&1) &
    NET_PID=$!
    sleep 3
    if kill -0 $NET_PID 2>/dev/null; then
        # Still running, kill it and try sudo
        kill $NET_PID 2>/dev/null || true
        wait $NET_PID 2>/dev/null || true
        echo -e "${YELLOW}⚠️  Network start is taking too long, trying with sudo...${NC}"
    else
        # Command finished, check result
        wait $NET_PID
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ Bridge network started${NC}"
        else
            echo -e "${YELLOW}⚠️  Could not start bridge network without sudo.${NC}"
        fi
    fi
    
    # Check if network is now active
    if ! virsh net-list --name 2>/dev/null | grep -q "^${BRIDGE_NETWORK}$"; then
        echo "Trying with sudo..."
        (sudo virsh net-start "$BRIDGE_NETWORK" 2>&1) &
        SUDO_PID=$!
        sleep 3
        if kill -0 $SUDO_PID 2>/dev/null; then
            kill $SUDO_PID 2>/dev/null || true
            wait $SUDO_PID 2>/dev/null || true
            echo -e "${RED}❌ Network start is hanging even with sudo${NC}"
            echo ""
            echo -e "${YELLOW}⚠️  On macOS, bridge networks often have issues.${NC}"
            echo "Trying alternative: using default network instead..."
            BRIDGE_NETWORK="default"
        else
            wait $SUDO_PID
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✅ Bridge network started with sudo${NC}"
            fi
        fi
    fi
    
    # If still not active, try default network
    if ! virsh net-list --name 2>/dev/null | grep -q "^${BRIDGE_NETWORK}$"; then
        if [ "$BRIDGE_NETWORK" != "default" ]; then
            echo -e "${YELLOW}⚠️  metal3-net failed to start. Trying default network...${NC}"
            BRIDGE_NETWORK="default"
        fi
        
        if virsh net-list --name 2>/dev/null | grep -q "^${BRIDGE_NETWORK}$"; then
            echo -e "${GREEN}✅ Default network is already active${NC}"
        else
            echo "Starting default network..."
            (virsh net-start "$BRIDGE_NETWORK" 2>/dev/null || sudo virsh net-start "$BRIDGE_NETWORK" 2>/dev/null) &
            DEF_PID=$!
            sleep 3
            if kill -0 $DEF_PID 2>/dev/null; then
                kill $DEF_PID 2>/dev/null || true
                wait $DEF_PID 2>/dev/null || true
                echo -e "${RED}❌ Could not start default network either${NC}"
                echo "Please check libvirt permissions or network configuration"
                echo ""
                echo "You can try manually:"
                echo "  sudo virsh net-start default"
                exit 1
            else
                wait $DEF_PID
                if [ $? -eq 0 ]; then
                    echo -e "${GREEN}✅ Default network started${NC}"
                fi
            fi
        fi
    fi
fi

# Wait a moment for network to be fully up
sleep 2

# Set bridge IP based on network
if [ "$BRIDGE_NETWORK" = "default" ]; then
    BRIDGE_IP="192.168.122.1"
    VM_STATIC_IP="192.168.122.100"
else
    BRIDGE_IP="192.168.124.1"
    VM_STATIC_IP="192.168.124.100"
fi

# 3. Verify bridge interface exists
echo ""
echo "3. Checking bridge interface..."
if ip addr show metal3-bridge 2>/dev/null | grep -q "$BRIDGE_IP"; then
    echo -e "${GREEN}✅ Bridge interface has IP $BRIDGE_IP${NC}"
elif ifconfig metal3-bridge 2>/dev/null | grep -q "$BRIDGE_IP"; then
    echo -e "${GREEN}✅ Bridge interface has IP $BRIDGE_IP${NC}"
else
    echo -e "${YELLOW}⚠️  Bridge interface may not have IP yet. This is OK if network just started.${NC}"
fi

# 4. Get NodePort
echo ""
echo "4. Getting Ironic NodePort..."
NODE_PORT=$(kubectl get svc metal3-metal3-ironic -n metal3-system -o jsonpath='{.spec.ports[?(@.port==6185)].nodePort}')
if [ -z "$NODE_PORT" ]; then
    NODE_PORT=$(kubectl get svc metal3-metal3-ironic -n metal3-system -o jsonpath='{.spec.ports[0].nodePort}')
fi

if [ -z "$NODE_PORT" ]; then
    echo -e "${RED}❌ Could not determine NodePort. Is Ironic service configured as NodePort?${NC}"
    exit 1
fi

echo -e "${GREEN}✅ NodePort: $NODE_PORT${NC}"

# 5. Kill existing socat processes
echo ""
echo "5. Cleaning up existing port forwarding..."
pkill -f "socat.*6385" || true
sleep 1

# 6. Set up port forwarding
echo ""
echo "6. Setting up port forwarding from bridge network to NodePort..."
IRONIC_BRIDGE_PORT="6385"

# Check if socat is installed
if ! command -v socat &> /dev/null; then
    echo -e "${YELLOW}⚠️  socat is not installed. Installing...${NC}"
    brew install socat || {
        echo -e "${RED}❌ Failed to install socat. Please install manually: brew install socat${NC}"
        exit 1
    }
fi

# Try to bind to bridge IP (requires root)
echo "Starting socat: ${BRIDGE_IP}:${IRONIC_BRIDGE_PORT} -> localhost:${NODE_PORT}"
if sudo socat TCP-LISTEN:${IRONIC_BRIDGE_PORT},bind=${BRIDGE_IP},fork,reuseaddr TCP:localhost:${NODE_PORT} > /tmp/socat-ironic-bridge.log 2>&1 &
then
    SOCAT_PID=$!
    sleep 2
    
    if kill -0 $SOCAT_PID 2>/dev/null; then
        echo -e "${GREEN}✅ Port forwarding started (PID: $SOCAT_PID)${NC}"
        echo $SOCAT_PID > /tmp/socat-ironic-bridge.pid
    else
        echo -e "${RED}❌ Port forwarding failed to start${NC}"
        echo "Check /tmp/socat-ironic-bridge.log for errors"
        cat /tmp/socat-ironic-bridge.log
        exit 1
    fi
else
    echo -e "${RED}❌ Failed to start port forwarding${NC}"
    exit 1
fi

# 7. Update Ironic external URL
echo ""
echo "7. Updating Ironic external URL..."
kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_EXTERNAL_HTTP_URL\":\"https://${BRIDGE_IP}:${IRONIC_BRIDGE_PORT}\"}}"
echo -e "${GREEN}✅ Ironic URL updated to https://${BRIDGE_IP}:${IRONIC_BRIDGE_PORT}${NC}"

# 8. Restart Ironic pod
echo ""
echo "8. Restarting Ironic pod to apply URL change..."
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic --wait=false
sleep 3

# 9. Test connectivity
echo ""
echo "9. Testing connectivity..."
sleep 2
if curl -k -s https://${BRIDGE_IP}:${IRONIC_BRIDGE_PORT}/ > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Ironic is accessible from bridge network!${NC}"
else
    echo -e "${YELLOW}⚠️  Ironic may not be accessible yet (pod may still be starting)${NC}"
fi

# Summary
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Bridge Network Setup Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Bridge Network: ${BRIDGE_NETWORK}"
if [ "$BRIDGE_NETWORK" = "default" ]; then
    echo "Network Range: 192.168.122.0/24"
else
    echo "Network Range: 192.168.124.0/24"
fi
echo "Bridge Gateway: ${BRIDGE_IP}"
echo "VM Static IP: ${VM_STATIC_IP}"
echo "Ironic URL (from VM): https://${BRIDGE_IP}:${IRONIC_BRIDGE_PORT}"
echo "Ironic NodePort: ${NODE_PORT}"
echo "Port Forwarding PID: $SOCAT_PID (saved to /tmp/socat-ironic-bridge.pid)"
echo ""
echo "Next steps:"
echo "  1. Make sure VM is on bridge network (metal3-net)"
echo "  2. VM should have static IP: 192.168.124.100"
echo "  3. Check BareMetalHost status: kubectl get baremetalhost -n metal3-system -w"
echo ""

