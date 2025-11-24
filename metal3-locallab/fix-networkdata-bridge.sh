#!/bin/bash
set -e

echo "🔧 Fixing NetworkData for Bridge Network"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="${NAMESPACE:-metal3-system}"

echo "Problem: NetworkData works with NAT but not with bridge network"
echo ""
echo "Common causes:"
echo "  1. Interface name mismatch (eth0 vs ens3/enp1s0)"
echo "  2. NetworkData format needs MAC address matching"
echo "  3. IPA not detecting the interface correctly"
echo ""

# Get BareMetalHost to find MAC address
echo "Step 1: Finding BareMetalHost MAC address..."
BMH_NAME=$(kubectl get baremetalhost -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$BMH_NAME" ]; then
    echo -e "${RED}❌ No BareMetalHost found${NC}"
    exit 1
fi

echo "Found BareMetalHost: $BMH_NAME"

BMH_MAC=$(kubectl get baremetalhost "$BMH_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.bootMACAddress}' 2>/dev/null || echo "")

if [ -z "$BMH_MAC" ]; then
    echo -e "${YELLOW}⚠️  No bootMACAddress found in BareMetalHost${NC}"
    echo "Please provide the VM's MAC address:"
    read -p "MAC address (e.g., 52:54:00:xx:xx:xx): " BMH_MAC
fi

echo "MAC address: $BMH_MAC"
echo ""

# Get network configuration
echo "Step 2: Network configuration"
echo "Please provide your bridge network details:"
read -p "VM static IP (e.g., 192.168.124.100): " VM_IP
read -p "Network mask (e.g., 24): " NETMASK
read -p "Gateway IP (e.g., 192.168.124.1): " GATEWAY

if [ -z "$VM_IP" ] || [ -z "$NETMASK" ] || [ -z "$GATEWAY" ]; then
    echo -e "${RED}❌ Missing network configuration${NC}"
    exit 1
fi

echo ""
echo "Step 3: Creating NetworkData with MAC address matching"
echo "------------------------------------------------------"

# Option 1: Match by MAC address (most reliable for bridge networks)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: provisioning-networkdata
  namespace: $NAMESPACE
type: Opaque
stringData:
  networkData: |
    version: 2
    ethernets:
      # Match by MAC address (most reliable for bridge networks)
      match_by_mac:
        match:
          macaddress: $BMH_MAC
        dhcp4: false
        addresses:
          - $VM_IP/$NETMASK
        gateway4: $GATEWAY
        nameservers:
          addresses:
            - 8.8.8.8
            - 8.8.4.4
EOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ NetworkData secret created with MAC address matching${NC}"
else
    echo -e "${RED}❌ Failed to create NetworkData secret${NC}"
    exit 1
fi

echo ""
echo "Step 4: Alternative - Try interface name matching"
echo "-------------------------------------------------"
echo "If MAC matching doesn't work, we can try common interface names:"
echo "  - eth0 (common in NAT/user-mode)"
echo "  - ens3 (common in bridge networks)"
echo "  - enp1s0 (common in some setups)"
echo ""

read -p "Create alternative NetworkData with interface name matching? (y/n): " CREATE_ALT

if [ "$CREATE_ALT" = "y" ] || [ "$CREATE_ALT" = "Y" ]; then
    read -p "Interface name (e.g., ens3, enp1s0, or eth0): " IFACE_NAME
    
    if [ -n "$IFACE_NAME" ]; then
        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: provisioning-networkdata-alt
  namespace: $NAMESPACE
type: Opaque
stringData:
  networkData: |
    version: 2
    ethernets:
      $IFACE_NAME:
        dhcp4: false
        addresses:
          - $VM_IP/$NETMASK
        gateway4: $GATEWAY
        nameservers:
          addresses:
            - 8.8.8.8
            - 8.8.4.4
EOF
        echo -e "${GREEN}✅ Alternative NetworkData created as 'provisioning-networkdata-alt'${NC}"
        echo "   You can test this by updating BareMetalHost:"
        echo "   kubectl patch baremetalhost $BMH_NAME -n $NAMESPACE --type merge -p '{\"spec\":{\"preprovisioningNetworkDataName\":\"provisioning-networkdata-alt\"}}'"
    fi
fi

echo ""
echo "Step 5: Verify NetworkData is referenced in BareMetalHost"
echo "----------------------------------------------------------"

CURRENT_NETDATA=$(kubectl get baremetalhost "$BMH_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.preprovisioningNetworkDataName}' 2>/dev/null || echo "")

if [ -z "$CURRENT_NETDATA" ]; then
    echo -e "${YELLOW}⚠️  BareMetalHost doesn't reference NetworkData secret${NC}"
    echo "Adding reference..."
    kubectl patch baremetalhost "$BMH_NAME" -n "$NAMESPACE" --type merge -p '{"spec":{"preprovisioningNetworkDataName":"provisioning-networkdata"}}'
    echo -e "${GREEN}✅ NetworkData reference added${NC}"
else
    echo "Current NetworkData reference: $CURRENT_NETDATA"
    if [ "$CURRENT_NETDATA" != "provisioning-networkdata" ]; then
        echo "Updating to use 'provisioning-networkdata'..."
        kubectl patch baremetalhost "$BMH_NAME" -n "$NAMESPACE" --type merge -p '{"spec":{"preprovisioningNetworkDataName":"provisioning-networkdata"}}'
        echo -e "${GREEN}✅ NetworkData reference updated${NC}"
    else
        echo -e "${GREEN}✅ NetworkData reference is correct${NC}"
    fi
fi

echo ""
echo "Step 6: Restart Ironic to regenerate boot ISO"
echo "----------------------------------------------"
echo "Restarting Ironic pod to ensure NetworkData is included in boot ISO..."
kubectl delete pod -n "$NAMESPACE" -l app.kubernetes.io/component=ironic --wait=false

echo ""
echo "=========================================="
echo -e "${BLUE}📋 Summary${NC}"
echo "=========================================="
echo "NetworkData secret created with:"
echo "  - MAC address matching: $BMH_MAC"
echo "  - Static IP: $VM_IP/$NETMASK"
echo "  - Gateway: $GATEWAY"
echo ""
echo "Next steps:"
echo "1. Wait for Ironic pod to restart"
echo "2. Reprovision BareMetalHost to regenerate boot ISO:"
echo "   kubectl patch baremetalhost $BMH_NAME -n $NAMESPACE --type merge -p '{\"spec\":{\"image\":null}}'"
echo "   kubectl patch baremetalhost $BMH_NAME -n $NAMESPACE --type merge -p '{\"spec\":{\"image\":{\"url\":\"...\"}}}'"
echo ""
echo "3. Check IPA console to verify network is configured:"
echo "   virsh console <vm-name>"
echo "   # Inside IPA, run: ip addr show"
echo ""
echo "4. If network still not configured, check:"
echo "   - Interface name in IPA: ip link show"
echo "   - NetworkData format: kubectl get secret provisioning-networkdata -n $NAMESPACE -o jsonpath='{.data.networkData}' | base64 -d"
echo ""

