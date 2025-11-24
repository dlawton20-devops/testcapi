#!/bin/bash
# Setup reliable port forwarding using launchd (macOS system service)

set -e

echo "🔧 Setting up reliable port forwarding for Ironic..."

# First, ensure the service exists
if ! kubectl get svc metal3-metal3-ironic -n metal3-system > /dev/null 2>&1; then
    echo "⚠️  Ironic service doesn't exist. Creating NodePort service..."
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: metal3-metal3-ironic
  namespace: metal3-system
spec:
  type: NodePort
  ports:
  - name: httpd-tls
    port: 6185
    targetPort: 6185
    protocol: TCP
  - name: api
    port: 6385
    targetPort: 6385
    protocol: TCP
  selector:
    app.kubernetes.io/component: ironic
EOF
    echo "✅ Service created"
fi

# Stop any existing services
echo "Stopping existing launchd services..."
launchctl unload ~/Library/LaunchAgents/com.dave.ironic-portforward.plist 2>/dev/null || true
launchctl unload ~/Library/LaunchAgents/com.dave.ironic-socat.plist 2>/dev/null || true

# Copy plist files
echo "Installing launchd services..."
mkdir -p ~/Library/LaunchAgents
cp "$(dirname "$0")/com.dave.ironic-portforward.plist" ~/Library/LaunchAgents/
cp "$(dirname "$0")/com.dave.ironic-socat.plist" ~/Library/LaunchAgents/

# Load services
launchctl load ~/Library/LaunchAgents/com.dave.ironic-portforward.plist
launchctl load ~/Library/LaunchAgents/com.dave.ironic-socat.plist

echo "✅ Launchd services installed and started"
echo ""
echo "Port forwarding is now managed by macOS and will:"
echo "  - Start automatically on boot"
echo "  - Restart automatically if it crashes"
echo "  - Run in the background"
echo ""
echo "Configure Ironic:"
echo "  kubectl patch configmap ironic -n metal3-system --type merge -p '{\"data\":{\"IRONIC_EXTERNAL_HTTP_URL\":\"http://192.168.1.242:6385\"}}'"
echo ""
echo "Check status:"
echo "  launchctl list | grep ironic"
echo "  tail -f /tmp/ironic-portforward.log"
echo "  tail -f /tmp/ironic-socat.log"

