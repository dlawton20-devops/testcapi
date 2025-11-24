#!/bin/bash
# Complete wipe - remove everything Metal3 related

set -e

echo "🧹 Wiping everything Metal3 related..."

# Stop all launchd services
echo "1. Stopping launchd services..."
launchctl unload ~/Library/LaunchAgents/com.dave.ironic-portforward.plist 2>/dev/null || true
launchctl unload ~/Library/LaunchAgents/com.dave.ironic-socat.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.dave.ironic-*.plist 2>/dev/null || true

# Kill all processes
echo "2. Killing all port forwarding processes..."
pkill -9 -f "kubectl port-forward.*ironic" 2>/dev/null || true
pkill -9 -f "socat.*6185" 2>/dev/null || true
pkill -9 -f "socat.*6385" 2>/dev/null || true
pkill -9 -f "serve_boot_isos" 2>/dev/null || true
pkill -9 -f "http.server.*6185" 2>/dev/null || true
pkill -9 -f "http.server.*6385" 2>/dev/null || true

# Delete BareMetalHost
echo "3. Deleting BareMetalHost..."
kubectl delete baremetalhost metal3-node-0 -n metal3-system 2>/dev/null || true

# Delete VM
echo "4. Deleting VM..."
virsh destroy metal3-node-0 2>/dev/null || true
virsh undefine metal3-node-0 --nvram 2>/dev/null || true

# Clean up log files
echo "5. Cleaning up logs..."
rm -f /tmp/ironic-*.log /tmp/socat-*.log /tmp/boot-iso-*.log /tmp/simple-*.log 2>/dev/null || true

# Clean up boot ISO directory (optional - comment out if you want to keep them)
# echo "6. Cleaning up boot ISOs..."
# rm -rf ~/metal3-images/boot-isos/* 2>/dev/null || true

# Delete Kind cluster
echo "6. Deleting Kind cluster..."
kind delete cluster --name metal3-management 2>/dev/null || {
    echo "   ⚠️  Cluster might not exist or have different name"
    # Try to find and delete any Kind cluster
    kind get clusters 2>/dev/null | while read cluster; do
        echo "   Deleting cluster: $cluster"
        kind delete cluster --name "$cluster" 2>/dev/null || true
    done
}

# Stop Docker containers (if any Metal3 related)
echo "7. Stopping Docker containers..."
docker ps -a --filter "name=metal3" --format "{{.ID}}" | xargs -r docker rm -f 2>/dev/null || true

# Clean up Docker networks (optional - be careful)
# echo "8. Cleaning up Docker networks..."
# docker network prune -f 2>/dev/null || true

echo ""
echo "✅ Everything wiped!"
echo ""
echo "What was removed:"
echo "  - Launchd services"
echo "  - All port forwarding processes"
echo "  - BareMetalHost"
echo "  - VM"
echo "  - Log files"
echo "  - Kind cluster"
echo "  - Docker containers"
echo ""
echo "Ready for completely fresh setup!"
echo ""
echo "Next: Recreate cluster and install Metal3 from scratch"

