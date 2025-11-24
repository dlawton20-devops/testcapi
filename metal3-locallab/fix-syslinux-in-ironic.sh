#!/bin/bash
set -e

echo "🔧 Installing syslinux in Ironic Container"
echo "==========================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

IRONIC_POD=$(kubectl get pods -n metal3-system -l app.kubernetes.io/component=ironic -o jsonpath='{.items[0].metadata.name}')

if [ -z "$IRONIC_POD" ]; then
    echo -e "${RED}❌ Ironic pod not found${NC}"
    exit 1
fi

echo "Ironic pod: $IRONIC_POD"
echo ""

# Check if syslinux is already installed
echo "Checking if syslinux is installed..."
if kubectl exec -n metal3-system "$IRONIC_POD" -c ironic -- test -f /usr/share/syslinux/isolinux.bin 2>/dev/null; then
    echo -e "${GREEN}✅ syslinux is already installed${NC}"
    exit 0
fi

# Try to install syslinux
echo "Attempting to install syslinux..."
echo "Note: This requires the container to have package manager access"

# Check OS
OS_INFO=$(kubectl exec -n metal3-system "$IRONIC_POD" -c ironic -- cat /etc/os-release 2>/dev/null | grep "^ID=" | cut -d= -f2 | tr -d '"')

echo "Detected OS: $OS_INFO"

if [ "$OS_INFO" = "sles" ] || [ "$OS_INFO" = "opensuse" ]; then
    echo "Installing syslinux via zypper..."
    kubectl exec -n metal3-system "$IRONIC_POD" -c ironic -- zypper --non-interactive install syslinux 2>&1 || {
        echo -e "${YELLOW}⚠️  zypper install failed. Container may be read-only or need different approach.${NC}"
        echo ""
        echo "Alternative: Configure Ironic to use UEFI boot mode instead of BIOS"
        echo "  This avoids the syslinux requirement"
        exit 1
    }
elif [ "$OS_INFO" = "ubuntu" ] || [ "$OS_INFO" = "debian" ]; then
    echo "Installing syslinux via apt..."
    kubectl exec -n metal3-system "$IRONIC_POD" -c ironic -- apt-get update && \
    kubectl exec -n metal3-system "$IRONIC_POD" -c ironic -- apt-get install -y syslinux-common 2>&1 || {
        echo -e "${YELLOW}⚠️  apt install failed${NC}"
        exit 1
    }
else
    echo -e "${RED}❌ Unknown OS: $OS_INFO${NC}"
    exit 1
fi

# Verify installation
if kubectl exec -n metal3-system "$IRONIC_POD" -c ironic -- test -f /usr/share/syslinux/isolinux.bin 2>/dev/null; then
    echo -e "${GREEN}✅ syslinux installed successfully${NC}"
    echo ""
    echo "Restarting Ironic pod to ensure changes persist..."
    kubectl delete pod -n metal3-system "$IRONIC_POD"
    echo -e "${GREEN}✅ Ironic pod restarted${NC}"
else
    echo -e "${RED}❌ syslinux installation failed or file not found${NC}"
    exit 1
fi

echo ""
echo "Note: If the container is read-only, you may need to:"
echo "  1. Use UEFI boot mode instead (requires OVMF on host)"
echo "  2. Or modify the Ironic container image to include syslinux"
echo ""

