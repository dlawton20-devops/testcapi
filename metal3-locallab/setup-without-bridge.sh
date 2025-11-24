#!/bin/bash
set -e

echo "🌉 Setting up Metal3 without Bridge Network (macOS Compatible)"
echo "=============================================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# On macOS, libvirt user mode can't create bridges
# We'll use user-mode networking and port forwarding from host IP
HOST_IP=$(ifconfig | grep -E "inet.*broadcast" | grep -v "127.0.0.1" | awk '{print $2}' | head -1)
if [ -z "$HOST_IP" ]; then
    HOST_IP="192.168.1.242"
fi

IRONIC_PORT="6385"

echo ""
echo "Using host IP: $HOST_IP"
echo "Note: VM will use user-mode networking (10.0.2.0/24)"
echo "      VM can reach host at 10.0.2.2"
echo ""

# Get NodePort
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

# Kill existing port forwarding
echo ""
echo "Cleaning up existing port forwarding..."
pkill -f "kubectl port-forward.*metal3-metal3-ironic" || true
pkill -f "socat.*${IRONIC_PORT}" || true
sleep 1

# Check socat
if ! command -v socat &> /dev/null; then
    echo "Installing socat..."
    brew install socat
fi

# Set up two-stage port forwarding:
# 1. kubectl port-forward: NodePort -> localhost:6385
# 2. socat: host IP:6385 -> localhost:6385

echo ""
echo "Setting up port forwarding..."

# Stage 1: kubectl port-forward
echo "  Stage 1: kubectl port-forward (NodePort -> localhost:${IRONIC_PORT})..."
nohup kubectl port-forward -n metal3-system svc/metal3-metal3-ironic ${IRONIC_PORT}:6185 > /tmp/ironic-port-forward.log 2>&1 &
PF_PID=$!
sleep 2

if ! kill -0 $PF_PID 2>/dev/null; then
    echo -e "${RED}❌ kubectl port-forward failed${NC}"
    exit 1
fi
echo -e "${GREEN}✅ kubectl port-forward running (PID: $PF_PID)${NC}"

# Stage 2: socat (host IP -> localhost)
echo "  Stage 2: socat (${HOST_IP}:${IRONIC_PORT} -> localhost:${IRONIC_PORT})..."
nohup socat TCP-LISTEN:${IRONIC_PORT},bind=${HOST_IP},fork,reuseaddr TCP:localhost:${IRONIC_PORT} > /tmp/socat-ironic.log 2>&1 &
SOCAT_PID=$!
sleep 2

if ! kill -0 $SOCAT_PID 2>/dev/null; then
    echo -e "${YELLOW}⚠️  socat may have failed. Check /tmp/socat-ironic.log${NC}"
    echo "You may need to run manually:"
    echo "  socat TCP-LISTEN:${IRONIC_PORT},bind=${HOST_IP},fork,reuseaddr TCP:localhost:${IRONIC_PORT} &"
else
    echo -e "${GREEN}✅ socat running (PID: $SOCAT_PID)${NC}"
fi

# Update Ironic URL to use host IP
echo ""
echo "Updating Ironic external URL to use host IP..."
kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_EXTERNAL_HTTP_URL\":\"https://${HOST_IP}:${IRONIC_PORT}\"}}"
echo -e "${GREEN}✅ Ironic URL updated to https://${HOST_IP}:${IRONIC_PORT}${NC}"

# Update NetworkData secret for user-mode network
echo ""
echo "Updating NetworkData secret for user-mode network..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: provisioning-networkdata
  namespace: metal3-system
type: Opaque
stringData:
  networkData: |
    version: 2
    ethernets:
      eth0:
        dhcp4: false
        addresses:
          - 10.0.2.100/24
        gateway4: 10.0.2.2
        nameservers:
          addresses:
            - 8.8.8.8
            - 8.8.4.4
EOF
echo -e "${GREEN}✅ NetworkData secret updated${NC}"

# Restart Ironic pod
echo ""
echo "Restarting Ironic pod..."
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic --wait=false
sleep 3

# Test connectivity
echo ""
echo "Testing connectivity..."
sleep 2
if curl -k -s https://${HOST_IP}:${IRONIC_PORT}/ > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Ironic is accessible from host!${NC}"
else
    echo -e "${YELLOW}⚠️  Ironic may not be accessible yet (pod may still be starting)${NC}"
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Setup Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Network Configuration:"
echo "  VM Network: User-mode (10.0.2.0/24)"
echo "  VM IP: 10.0.2.100"
echo "  VM Gateway: 10.0.2.2 (host)"
echo "  Host IP: ${HOST_IP}"
echo ""
echo "Ironic Configuration:"
echo "  Ironic URL (from VM): https://${HOST_IP}:${IRONIC_PORT}"
echo "  NodePort: ${NODE_PORT}"
echo ""
echo "Port Forwarding:"
echo "  kubectl port-forward PID: $PF_PID"
echo "  socat PID: $SOCAT_PID"
echo ""
echo "Next steps:"
echo "  1. Make sure VM uses user-mode networking (type='user')"
echo "  2. VM should have static IP 10.0.2.100"
echo "  3. Check BareMetalHost: kubectl get baremetalhost -n metal3-system -w"
echo ""

