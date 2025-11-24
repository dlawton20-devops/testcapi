#!/bin/bash
# Complete cleanup script - tear down everything

set -e

echo "🧹 Cleaning up everything..."

# Kill all port forwarding processes
echo "1. Stopping port forwarding processes..."
pkill -f "kubectl port-forward.*ironic" 2>/dev/null || true
pkill -f "socat.*6385" 2>/dev/null || true
pkill -f "socat.*8081" 2>/dev/null || true

# Kill all HTTP servers
echo "2. Stopping HTTP servers..."
pkill -f "serve_boot_isos" 2>/dev/null || true
pkill -f "http.server.*8081" 2>/dev/null || true
pkill -f "http.server.*8080" 2>/dev/null || true
pkill -f "python.*8081" 2>/dev/null || true
pkill -f "simple_boot_iso_server" 2>/dev/null || true

# Kill proxy servers
echo "3. Stopping proxy servers..."
pkill -f "ironic_boot_iso_proxy" 2>/dev/null || true

# Clean up temporary directories (keep boot-isos in case user wants to keep them)
echo "4. Cleaning up temporary files..."
rm -rf ~/metal3-images/boot-isos-temp 2>/dev/null || true

# Clean up log files
echo "5. Cleaning up log files..."
rm -f /tmp/ironic-port-forward.log /tmp/socat-ironic.log /tmp/boot-iso-server.log /tmp/simple-http-server.log /tmp/simple-boot-server.log /tmp/ironic-proxy.log 2>/dev/null || true

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "What was cleaned:"
echo "  - Port forwarding processes (kubectl, socat)"
echo "  - HTTP servers (boot ISO servers)"
echo "  - Proxy servers"
echo "  - Temporary files and logs"
echo ""
echo "What was kept:"
echo "  - ~/metal3-images/boot-isos/ (boot ISO files)"
echo "  - Kubernetes resources (BMH, Ironic, etc.)"
echo "  - VM (metal3-node-0)"
echo ""
echo "To clean Kubernetes resources too, run:"
echo "  kubectl delete baremetalhost metal3-node-0 -n metal3-system"
echo "  virsh destroy metal3-node-0"
echo "  virsh undefine metal3-node-0 --nvram"

