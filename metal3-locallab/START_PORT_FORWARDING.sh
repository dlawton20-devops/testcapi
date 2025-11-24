#!/bin/bash
# Script to start and maintain port forwarding for Ironic

set -e

echo "🔧 Starting port forwarding for Ironic..."

# Kill any existing processes
pkill -f "kubectl port-forward.*ironic" 2>/dev/null || true
pkill -f "socat.*6385" 2>/dev/null || true
sleep 1

# Start kubectl port-forward
echo "Starting kubectl port-forward..."
kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6385:6185 > /tmp/ironic-port-forward.log 2>&1 &
KUBECTL_PID=$!
sleep 2

# Start socat
echo "Starting socat..."
socat TCP-LISTEN:6385,fork,reuseaddr TCP:localhost:6385 > /tmp/socat-ironic.log 2>&1 &
SOCAT_PID=$!
sleep 2

# Verify
echo "Verifying connection..."
if curl -k -s -o /dev/null -w "%{http_code}" https://192.168.1.242:6385/v1 | grep -q "200\|404"; then
    echo "✅ Port forwarding is working!"
    echo "   kubectl port-forward PID: $KUBECTL_PID"
    echo "   socat PID: $SOCAT_PID"
    echo ""
    echo "Keep this script running or run it before provisioning."
else
    echo "⚠️  Connection test failed"
    exit 1
fi

