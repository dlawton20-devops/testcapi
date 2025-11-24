#!/bin/bash
# Start local HTTP server for boot ISOs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT=8080
BIND_ADDRESS="192.168.1.242"

echo "🔧 Starting Boot ISO HTTP Server..."

# Kill any existing server
pkill -f "serve_boot_isos.py" 2>/dev/null || true
sleep 1

# Start server
echo "Starting server on http://${BIND_ADDRESS}:${PORT}..."
cd "$SCRIPT_DIR"
python3 serve_boot_isos.py --port $PORT --bind $BIND_ADDRESS > /tmp/boot-iso-server.log 2>&1 &
SERVER_PID=$!

sleep 2

# Verify server is running
if ps -p $SERVER_PID > /dev/null 2>&1; then
    echo "✅ Boot ISO server started (PID: $SERVER_PID)"
    echo "   URL: http://${BIND_ADDRESS}:${PORT}"
    echo "   Directory: ~/metal3-images/boot-isos"
    echo ""
    echo "⚠️  Now update Ironic ConfigMap to use: http://${BIND_ADDRESS}:${PORT}"
    echo ""
    echo "To sync ISOs manually:"
    echo "  kubectl cp metal3-system/<ironic-pod>:/shared/html/redfish ~/metal3-images/boot-isos -c ironic"
else
    echo "❌ Failed to start server"
    tail -20 /tmp/boot-iso-server.log
    exit 1
fi

