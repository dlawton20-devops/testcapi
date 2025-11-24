#!/bin/bash
set -e

echo "🔍 Finding Ironic External URL for OpenStack Environment"
echo "========================================================"
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="${NAMESPACE:-metal3-system}"

echo "Step 1: Check MetalLB VIP (LoadBalancer IP)"
echo "-------------------------------------------"
IRONIC_LB_IP=$(kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/component=ironic -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [ -n "$IRONIC_LB_IP" ]; then
    echo -e "${GREEN}✅ Found MetalLB VIP: ${IRONIC_LB_IP}${NC}"
    echo ""
    echo "⚠️  IMPORTANT: Can your KVM VMs (bare metal hosts) reach this IP?"
    echo "   - If KVM VMs are on the same network as the Rancher cluster: YES"
    echo "   - If KVM VMs are on a different network: NO (use option 2 or 3)"
    echo ""
    read -p "Can KVM VMs reach ${IRONIC_LB_IP}? (y/n): " USE_LB_IP
    
    if [ "$USE_LB_IP" = "y" ] || [ "$USE_LB_IP" = "Y" ]; then
        IRONIC_URL="https://${IRONIC_LB_IP}:6385"
        echo -e "${GREEN}✅ Using MetalLB VIP: ${IRONIC_URL}${NC}"
    else
        IRONIC_LB_IP=""
    fi
else
    echo -e "${YELLOW}⚠️  No LoadBalancer IP found${NC}"
fi

echo ""
echo "Step 2: Check OpenStack VM IP (where Rancher runs)"
echo "--------------------------------------------------"
if [ -z "$IRONIC_LB_IP" ]; then
    echo "What is the IP address of your OpenStack VM (where Rancher cluster runs)?"
    echo "This IP should be reachable from your KVM VMs."
    read -p "OpenStack VM IP: " OPENSTACK_VM_IP
    
    if [ -n "$OPENSTACK_VM_IP" ]; then
        IRONIC_URL="https://${OPENSTACK_VM_IP}:6385"
        echo -e "${GREEN}✅ Using OpenStack VM IP: ${IRONIC_URL}${NC}"
        echo ""
        echo "⚠️  You'll need to set up port forwarding or NodePort to expose Ironic:"
        echo "   kubectl get svc -n $NAMESPACE -l app.kubernetes.io/component=ironic"
        echo "   Then forward port 6385 from OpenStack VM to Ironic service"
    fi
fi

echo ""
echo "Step 3: Check OpenStack Controller IP"
echo "--------------------------------------"
if [ -z "$IRONIC_LB_IP" ] && [ -z "$OPENSTACK_VM_IP" ]; then
    echo "What is the OpenStack controller IP that KVM VMs can reach?"
    read -p "OpenStack Controller IP: " OPENSTACK_CTRL_IP
    
    if [ -n "$OPENSTACK_CTRL_IP" ]; then
        IRONIC_URL="https://${OPENSTACK_CTRL_IP}:6385"
        echo -e "${GREEN}✅ Using OpenStack Controller IP: ${IRONIC_URL}${NC}"
    fi
fi

echo ""
echo "Step 4: Check Ironic Service Port"
echo "----------------------------------"
IRONIC_PORT=$(kubectl get svc -n "$NAMESPACE" -l app.kubernetes.io/component=ironic -o jsonpath='{.items[0].spec.ports[?(@.name=="http")].port}' 2>/dev/null || echo "6385")

if [ -z "$IRONIC_PORT" ]; then
    IRONIC_PORT="6385"
fi

echo "Ironic service port: $IRONIC_PORT"

echo ""
echo "=========================================="
echo "Configuration Summary"
echo "=========================================="
echo ""

if [ -z "$IRONIC_URL" ]; then
    echo -e "${RED}❌ Could not determine Ironic URL${NC}"
    echo ""
    echo "Please manually set:"
    echo "  kubectl patch configmap ironic -n $NAMESPACE --type merge -p '{\"data\":{\"IRONIC_EXTERNAL_HTTP_URL\":\"https://<ip>:<port>\"}}'"
    exit 1
fi

# Extract IP and port from URL
IRONIC_IP=$(echo "$IRONIC_URL" | sed -E 's|https?://([^:]+):.*|\1|')
IRONIC_PORT_FROM_URL=$(echo "$IRONIC_URL" | sed -E 's|https?://[^:]+:([0-9]+)|\1|')

if [ -n "$IRONIC_PORT_FROM_URL" ]; then
    IRONIC_PORT="$IRONIC_PORT_FROM_URL"
fi

echo -e "${BLUE}Ironic External URL: ${IRONIC_URL}${NC}"
echo -e "${BLUE}IP: ${IRONIC_IP}${NC}"
echo -e "${BLUE}Port: ${IRONIC_PORT}${NC}"
echo ""

read -p "Apply this configuration? (y/n): " APPLY

if [ "$APPLY" != "y" ] && [ "$APPLY" != "Y" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Applying configuration..."
kubectl patch configmap ironic -n "$NAMESPACE" --type merge -p "{\"data\":{\"IRONIC_EXTERNAL_HTTP_URL\":\"${IRONIC_URL}\"}}"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Configuration applied${NC}"
    echo ""
    echo "Restarting Ironic pod..."
    kubectl delete pod -n "$NAMESPACE" -l app.kubernetes.io/component=ironic
    
    echo ""
    echo -e "${GREEN}✅ Done!${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Reprovision your BareMetalHost to regenerate boot ISO with new URL"
    echo "2. Verify IPA can connect: check BareMetalHost status"
    echo ""
    echo "To verify configuration:"
    echo "  kubectl get configmap ironic -n $NAMESPACE -o jsonpath='{.data.IRONIC_EXTERNAL_HTTP_URL}'"
else
    echo -e "${RED}❌ Failed to apply configuration${NC}"
    exit 1
fi
