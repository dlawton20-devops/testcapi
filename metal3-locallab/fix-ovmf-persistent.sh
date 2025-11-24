#!/bin/bash
set -e

echo "🔧 Setting Up OVMF Persistently"
echo "================================"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Find OVMF files
echo "Searching for OVMF files..."
OVMF_CODE=$(find /opt/homebrew -name "*edk2*x86_64*code*.fd" 2>/dev/null | head -1)
OVMF_VARS=$(find /opt/homebrew -name "*edk2*x86_64*vars*.fd" 2>/dev/null | head -1)

if [ -z "$OVMF_CODE" ] || [ -z "$OVMF_VARS" ]; then
    echo -e "${RED}❌ OVMF files not found${NC}"
    echo "Trying alternative search..."
    OVMF_CODE=$(find /opt/homebrew/share/qemu -name "*edk2*x86_64*code*.fd" 2>/dev/null | head -1)
    OVMF_VARS=$(find /opt/homebrew/share/qemu -name "*edk2*x86_64*vars*.fd" 2>/dev/null | head -1)
fi

if [ -z "$OVMF_CODE" ] || [ -z "$OVMF_VARS" ]; then
    echo -e "${RED}❌ Could not find OVMF files${NC}"
    echo "Please ensure QEMU is installed: brew install qemu"
    exit 1
fi

echo -e "${GREEN}✅ Found OVMF files:${NC}"
echo "  CODE: $OVMF_CODE"
echo "  VARS: $OVMF_VARS"

# Create directory and symlinks
echo ""
echo "Creating OVMF directory and symlinks..."
sudo mkdir -p /usr/share/OVMF
sudo ln -sf "$OVMF_CODE" /usr/share/OVMF/OVMF_CODE.secboot.fd
sudo ln -sf "$OVMF_VARS" /usr/share/OVMF/OVMF_VARS.fd

# Also create in user's libvirt nvram directory
USER_NVRAM_DIR="$HOME/.config/libvirt/qemu/nvram"
mkdir -p "$USER_NVRAM_DIR"

# Copy vars template if it doesn't exist
if [ ! -f "$USER_NVRAM_DIR/metal3-node-0_VARS.fd" ]; then
    echo "Creating NVRAM file for VM..."
    cp "$OVMF_VARS" "$USER_NVRAM_DIR/metal3-node-0_VARS.fd"
    echo -e "${GREEN}✅ NVRAM file created${NC}"
fi

echo -e "${GREEN}✅ OVMF symlinks created${NC}"

# Update VM XML to use correct OVMF paths
echo ""
echo "Updating VM configuration..."
VM_NAME="metal3-node-0"

if virsh dominfo "$VM_NAME" &>/dev/null; then
    # Stop VM if running
    if virsh list --name | grep -q "^${VM_NAME}$"; then
        echo "Stopping VM..."
        virsh destroy "$VM_NAME"
        sleep 2
    fi
    
    # Get current XML
    virsh dumpxml "$VM_NAME" > /tmp/${VM_NAME}-ovmf.xml
    
    # Update OVMF paths in XML
    sed -i.bak \
        -e "s|/usr/share/OVMF/OVMF_CODE.secboot.fd|$OVMF_CODE|g" \
        -e "s|/usr/share/OVMF/OVMF_VARS.fd|$OVMF_VARS|g" \
        -e "s|/Users/dave/.config/libvirt/qemu/nvram/metal3-node-0_VARS.fd|$USER_NVRAM_DIR/metal3-node-0_VARS.fd|g" \
        /tmp/${VM_NAME}-ovmf.xml
    
    # Redefine VM
    virsh undefine "$VM_NAME"
    virsh define /tmp/${VM_NAME}-ovmf.xml
    
    echo -e "${GREEN}✅ VM updated with correct OVMF paths${NC}"
    
    # Start VM
    echo "Starting VM..."
    virsh start "$VM_NAME"
    sleep 2
    
    if virsh list --name | grep -q "^${VM_NAME}$"; then
        echo -e "${GREEN}✅ VM started successfully${NC}"
    else
        echo -e "${YELLOW}⚠️  VM may not have started. Check: virsh list --all${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  VM $VM_NAME not found. OVMF symlinks are ready for when VM is created.${NC}"
fi

echo ""
echo -e "${GREEN}✅ OVMF setup complete!${NC}"
echo ""
echo "OVMF files are now available at:"
echo "  /usr/share/OVMF/OVMF_CODE.secboot.fd -> $OVMF_CODE"
echo "  /usr/share/OVMF/OVMF_VARS.fd -> $OVMF_VARS"
echo ""
echo "If VM fails to start, run this script again to update paths."
echo ""

