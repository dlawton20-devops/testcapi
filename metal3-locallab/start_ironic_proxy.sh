#!/bin/bash
# Start Ironic boot ISO proxy server

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROXY_PORT=8080
BIND_ADDRESS="192.168.1.242"  # Host's external IP

echo "🔧 Starting Ironic Boot ISO Proxy Server..."

# Check if kubectl port-forward is running
if ! ps aux | grep -q "[k]ubectl port-forward.*ironic"; then
    echo "⚠️  kubectl port-forward not running. Starting it..."
    kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6385:6185 > /tmp/ironic-port-forward.log 2>&1 &
    sleep 2
    echo "✅ kubectl port-forward started"
fi

# Kill any existing proxy server
pkill -f "ironic_boot_iso_proxy.py" 2>/dev/null || true
sleep 1

# Start proxy server
echo "Starting proxy server on http://${BIND_ADDRESS}:${PROXY_PORT}..."
cd "$SCRIPT_DIR"
python3 ironic_boot_iso_proxy.py --port $PROXY_PORT --bind $BIND_ADDRESS > /tmp/ironic-proxy.log 2>&1 &
PROXY_PID=$!

sleep 2

# Verify proxy is running
if ps -p $PROXY_PID > /dev/null 2>&1; then
    echo "✅ Proxy server started (PID: $PROXY_PID)"
    echo "   URL: http://${BIND_ADDRESS}:${PROXY_PORT}"
    echo "   Backend: https://localhost:6385 (via kubectl port-forward)"
    echo ""
    echo "Test with: curl http://${BIND_ADDRESS}:${PROXY_PORT}/v1"
    echo ""
    echo "⚠️  Now update Ironic ConfigMap to use: http://${BIND_ADDRESS}:${PROXY_PORT}"
else
    echo "❌ Failed to start proxy server"
    exit 1
fi

