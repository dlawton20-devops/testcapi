#!/bin/bash

echo "🔍 Metal3 Troubleshooting Helper"
echo "================================="
echo ""
echo "Based on: https://documentation.suse.com/suse-edge/3.3/html/edge/troubleshooting-directed-network-provisioning.html"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check cluster connectivity
echo "1. Checking Kubernetes cluster connectivity..."
if kubectl cluster-info &>/dev/null; then
    echo -e "${GREEN}✅ Cluster is accessible${NC}"
    kubectl cluster-info | head -1
else
    echo -e "${RED}❌ Cannot connect to cluster${NC}"
    exit 1
fi

echo ""
echo "2. Checking Metal3 pods..."
kubectl get pods -n metal3-system 2>/dev/null || {
    echo -e "${RED}❌ metal3-system namespace not found or no pods${NC}"
    exit 1
}

echo ""
echo "3. Checking BareMetalHosts..."
BMH_COUNT=$(kubectl get bmh -n metal3-system --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$BMH_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✅ Found $BMH_COUNT BareMetalHost(s)${NC}"
    kubectl get bmh -n metal3-system
    echo ""
    echo "BareMetalHost details:"
    for bmh in $(kubectl get bmh -n metal3-system -o name); do
        echo ""
        echo "--- $bmh ---"
        kubectl get $bmh -n metal3-system -o jsonpath='{.status}' | python3 -m json.tool 2>/dev/null || kubectl get $bmh -n metal3-system -o yaml | grep -A 20 "status:"
    done
else
    echo -e "${YELLOW}⚠️  No BareMetalHosts found${NC}"
fi

echo ""
echo "4. Checking sushy-tools..."
if curl -s -u admin:admin http://localhost:8000/redfish/v1 &>/dev/null; then
    echo -e "${GREEN}✅ sushy-tools is running${NC}"
    echo "Available systems:"
    curl -s -u admin:admin http://localhost:8000/redfish/v1/Systems | python3 -m json.tool 2>/dev/null | grep -E "(Members|@odata)" || echo "  (checking...)"
else
    echo -e "${RED}❌ sushy-tools is not running or not accessible${NC}"
    echo "   Start it with: ~/metal3-sushy/start-sushy.sh"
    echo "   Or: launchctl load ~/Library/LaunchAgents/com.metal3.sushy-emulator.plist"
fi

echo ""
echo "5. Checking Ironic service..."
IRONIC_SVC=$(kubectl get svc -n metal3-system -l app.kubernetes.io/component=ironic -o name 2>/dev/null | head -1)
if [ -n "$IRONIC_SVC" ]; then
    echo -e "${GREEN}✅ Ironic service found: $IRONIC_SVC${NC}"
    kubectl get $IRONIC_SVC -n metal3-system
    IRONIC_IP=$(kubectl get $IRONIC_SVC -n metal3-system -o jsonpath='{.spec.clusterIP}')
    IRONIC_PORT=$(kubectl get $IRONIC_SVC -n metal3-system -o jsonpath='{.spec.ports[0].port}')
    echo "   Ironic endpoint: http://${IRONIC_IP}:${IRONIC_PORT}"
else
    echo -e "${RED}❌ Ironic service not found${NC}"
fi

echo ""
echo "6. Checking libvirt VMs..."
if virsh list --all &>/dev/null; then
    VM_COUNT=$(virsh list --all | grep -c "metal3-" || echo "0")
    if [ "$VM_COUNT" -gt 0 ]; then
        echo -e "${GREEN}✅ Found Metal3 VMs${NC}"
        virsh list --all | grep -E "Id|Name|metal3-"
    else
        echo -e "${YELLOW}⚠️  No Metal3 VMs found${NC}"
    fi
else
    echo -e "${RED}❌ Cannot access libvirt${NC}"
fi

echo ""
echo "7. Recent Metal3 events..."
echo "Baremetal operator events:"
kubectl get events -n metal3-system --sort-by='.lastTimestamp' | grep -i baremetal | tail -5 || echo "  (no recent events)"

echo ""
echo "8. Pod status summary..."
kubectl get pods -n metal3-system -o wide

echo ""
echo "9. Common troubleshooting commands:"
echo ""
echo "Check BareMetalHost status:"
echo "  kubectl get bmh -n metal3-system -o wide"
echo "  kubectl describe bmh <name> -n metal3-system"
echo ""
echo "Check Metal3 logs:"
echo "  kubectl logs -n metal3-system -l app.kubernetes.io/component=baremetal-operator"
echo "  kubectl logs -n metal3-system -l app.kubernetes.io/component=ironic -c ironic"
echo ""
echo "Retrigger inspection:"
echo "  kubectl annotate bmh/<name> -n metal3-system inspect.metal3.io=\"\""
echo ""
echo "Check sushy-tools:"
echo "  curl -u admin:admin http://localhost:8000/redfish/v1/Systems"
echo ""
echo "For more details, see:"
echo "  https://documentation.suse.com/suse-edge/3.3/html/edge/troubleshooting-directed-network-provisioning.html"

