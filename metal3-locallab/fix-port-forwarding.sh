#!/bin/bash
set -e

echo "🔌 Fixing Port Forwarding for Ironic"
echo "======================================"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

HOST_IP=$(ifconfig | grep -E "inet.*broadcast" | grep -v "127.0.0.1" | awk '{print $2}' | head -1)
if [ -z "$HOST_IP" ]; then
    HOST_IP="192.168.1.242"
fi

IRONIC_PORT="6385"

echo "Host IP: $HOST_IP"
echo ""

# Kill existing processes
echo "1. Cleaning up existing port forwarding..."
pkill -f "kubectl port-forward.*metal3-metal3-ironic" || true
pkill -f "socat.*${IRONIC_PORT}" || true
sleep 2

# Get service port
SVC_PORT=$(kubectl get svc metal3-metal3-ironic -n metal3-system -o jsonpath='{.spec.ports[0].port}')
if [ -z "$SVC_PORT" ]; then
    SVC_PORT="6185"
fi

echo "2. Setting up two-stage port forwarding..."
echo "   Stage 1: kubectl port-forward (service -> localhost:${IRONIC_PORT})"
echo "   Stage 2: socat (localhost:${IRONIC_PORT} -> ${HOST_IP}:${IRONIC_PORT})"
echo ""

# Stage 1: kubectl port-forward
echo "Starting kubectl port-forward..."
nohup kubectl port-forward -n metal3-system svc/metal3-metal3-ironic ${IRONIC_PORT}:${SVC_PORT} > /tmp/ironic-port-forward.log 2>&1 &
PF_PID=$!
sleep 3

if ! kill -0 $PF_PID 2>/dev/null; then
    echo -e "${RED}❌ kubectl port-forward failed${NC}"
    cat /tmp/ironic-port-forward.log
    exit 1
fi
echo -e "${GREEN}✅ kubectl port-forward running (PID: $PF_PID)${NC}"

# Test localhost connection
sleep 1
if curl -k -s https://localhost:${IRONIC_PORT}/ > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Ironic accessible on localhost:${IRONIC_PORT}${NC}"
else
    echo -e "${YELLOW}⚠️  Ironic may not be ready yet on localhost${NC}"
fi

# Stage 2: socat
echo ""
echo "Starting socat forwarder..."
nohup socat TCP-LISTEN:${IRONIC_PORT},bind=${HOST_IP},fork,reuseaddr TCP:localhost:${IRONIC_PORT} > /tmp/socat-ironic.log 2>&1 &
SOCAT_PID=$!
sleep 2

if ! kill -0 $SOCAT_PID 2>/dev/null; then
    echo -e "${RED}❌ socat failed to start${NC}"
    cat /tmp/socat-ironic.log
    exit 1
fi
echo -e "${GREEN}✅ socat running (PID: $SOCAT_PID)${NC}"

# Test host IP connection
sleep 1
if curl -k -s https://${HOST_IP}:${IRONIC_PORT}/ > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Ironic accessible on ${HOST_IP}:${IRONIC_PORT}${NC}"
else
    echo -e "${YELLOW}⚠️  Ironic may not be accessible yet on ${HOST_IP}${NC}"
fi

# Save PIDs
echo $PF_PID > /tmp/ironic-port-forward.pid
echo $SOCAT_PID > /tmp/socat-ironic.pid

echo ""
echo -e "${GREEN}✅ Port forwarding configured!${NC}"
echo ""
echo "PIDs saved to:"
echo "  /tmp/ironic-port-forward.pid: $PF_PID"
echo "  /tmp/socat-ironic.pid: $SOCAT_PID"
echo ""
echo "To stop:"
echo "  kill \$(cat /tmp/ironic-port-forward.pid) \$(cat /tmp/socat-ironic.pid)"
echo ""

