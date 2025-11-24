#!/bin/bash
set -e

echo "🔧 Fixing VM Boot Mode (UEFI -> BIOS)"
echo "======================================"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

VM_NAME="metal3-node-0"

# Check if VM exists
if ! virsh dominfo "$VM_NAME" &>/dev/null; then
    echo -e "${RED}❌ VM $VM_NAME not found${NC}"
    exit 1
fi

# Stop VM if running
if virsh list --name | grep -q "^${VM_NAME}$"; then
    echo "Stopping VM..."
    virsh destroy "$VM_NAME"
    sleep 2
fi

# Get current XML
echo "Updating VM boot mode to BIOS..."
virsh dumpxml "$VM_NAME" > /tmp/${VM_NAME}.xml

# Remove UEFI/OVMF configuration and set to BIOS
# Replace <loader> and <nvram> sections, change machine type if needed
sed -i.bak \
    -e '/<loader>/d' \
    -e '/<nvram>/d' \
    -e 's/<type arch="x86_64" machine="pc-q35-[^"]*">/<type arch="x86_64" machine="pc-i440fx-7.2">/' \
    /tmp/${VM_NAME}.xml

# Redefine VM
virsh undefine "$VM_NAME"
virsh define /tmp/${VM_NAME}.xml

echo -e "${GREEN}✅ VM boot mode changed to BIOS${NC}"

# Update BareMetalHost
echo ""
echo "Updating BareMetalHost boot mode to legacy..."
kubectl patch baremetalhost "$VM_NAME" -n metal3-system --type merge -p '{"spec":{"bootMode":"legacy"}}'
echo -e "${GREEN}✅ BareMetalHost boot mode updated${NC}"

# Start VM
echo ""
echo "Starting VM..."
virsh start "$VM_NAME"
sleep 2

echo ""
echo -e "${GREEN}✅ VM updated and started${NC}"
echo ""
echo "VM is now configured for BIOS/legacy boot mode"
echo "Check status: virsh list --all"
echo ""

