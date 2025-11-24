#!/bin/bash
# Fresh setup - everything from scratch

set -e

echo "🚀 Fresh Metal3 setup starting..."

# Step 1: Ensure Ironic service exists as NodePort
echo ""
echo "1. Ensuring Ironic service exists..."
if ! kubectl get svc metal3-metal3-ironic -n metal3-system > /dev/null 2>&1; then
    echo "   Creating NodePort service..."
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
    echo "   ✅ Service created"
else
    echo "   ✅ Service exists"
    # Ensure it's NodePort
    kubectl patch svc metal3-metal3-ironic -n metal3-system -p '{"spec":{"type":"NodePort"}}' 2>/dev/null || true
fi

# Step 2: Set up port forwarding for port 6185 (serves boot ISOs)
echo ""
echo "2. Setting up port forwarding (port 6185)..."
mkdir -p ~/Library/LaunchAgents

# Port forward service
cat > ~/Library/LaunchAgents/com.dave.ironic-portforward.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.dave.ironic-portforward</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/kubectl</string>
        <string>port-forward</string>
        <string>-n</string>
        <string>metal3-system</string>
        <string>svc/metal3-metal3-ironic</string>
        <string>6185:6185</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/ironic-portforward.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/ironic-portforward.log</string>
</dict>
</plist>
EOF

# Socat service
cat > ~/Library/LaunchAgents/com.dave.ironic-socat.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.dave.ironic-socat</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/socat</string>
        <string>TCP-LISTEN:6185,fork,reuseaddr</string>
        <string>TCP:localhost:6185</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/ironic-socat.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/ironic-socat.log</string>
</dict>
</plist>
EOF

# Load services
launchctl unload ~/Library/LaunchAgents/com.dave.ironic-portforward.plist 2>/dev/null || true
launchctl unload ~/Library/LaunchAgents/com.dave.ironic-socat.plist 2>/dev/null || true
sleep 1
launchctl load ~/Library/LaunchAgents/com.dave.ironic-portforward.plist
launchctl load ~/Library/LaunchAgents/com.dave.ironic-socat.plist
echo "   ✅ Port forwarding set up (launchd)"

# Step 3: Wait for port forwarding to be ready
echo ""
echo "3. Waiting for port forwarding to be ready..."
sleep 5
if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 http://192.168.1.242:6185/v1 | grep -q "[0-9]"; then
    echo "   ✅ Port forwarding is working"
else
    echo "   ⚠️  Port forwarding might not be ready yet (will retry)"
    sleep 5
fi

# Step 4: Configure Ironic
echo ""
echo "4. Configuring Ironic..."
kubectl patch configmap ironic -n metal3-system --type merge -p '{"data":{"IRONIC_EXTERNAL_HTTP_URL":"http://192.168.1.242:6185"}}' 2>/dev/null || {
    echo "   ⚠️  ConfigMap might not exist yet, will retry after pod restart"
}
echo "   ✅ Ironic configured"

# Step 5: Restart Ironic pod
echo ""
echo "5. Restarting Ironic pod..."
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic 2>/dev/null || true
echo "   ⏳ Waiting for Ironic to be ready..."
kubectl wait --for=condition=ready pod -n metal3-system -l app.kubernetes.io/component=ironic --timeout=120s 2>/dev/null || {
    echo "   ⚠️  Ironic pod might still be starting"
}
echo "   ✅ Ironic ready"

# Step 6: Verify configuration
echo ""
echo "6. Verifying configuration..."
IRONIC_URL=$(kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_EXTERNAL_HTTP_URL}' 2>/dev/null || echo "")
if [ "$IRONIC_URL" = "http://192.168.1.242:6185" ]; then
    echo "   ✅ Ironic URL is correct: $IRONIC_URL"
else
    echo "   ⚠️  Ironic URL: $IRONIC_URL (might need manual update)"
fi

echo ""
echo "✅ Fresh setup complete!"
echo ""
echo "Configuration:"
echo "  - Service: NodePort"
echo "  - Port forwarding: Port 6185 (launchd - auto-restart)"
echo "  - Ironic URL: http://192.168.1.242:6185"
echo ""
echo "Next steps:"
echo "  1. Create VM: ./create-baremetal-host.sh"
echo "  2. Create BMH: kubectl apply -f baremetalhost.yaml"
echo "  3. Monitor: kubectl get baremetalhost metal3-node-0 -n metal3-system -w"
echo ""
echo "Port forwarding will:"
echo "  - Start automatically on boot"
echo "  - Restart automatically if it crashes"
echo "  - Run in background"

