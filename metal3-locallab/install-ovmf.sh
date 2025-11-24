#!/bin/bash
set -e

echo "📦 Installing OVMF for UEFI Boot"
echo "================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if OVMF files exist
OVMF_CODE=""
OVMF_VARS=""

# Check common locations
for path in \
    "/opt/homebrew/share/qemu/edk2-x86_64-code.fd" \
    "/opt/homebrew/share/qemu/edk2-x86_64-vars.fd" \
    "/usr/local/share/qemu/edk2-x86_64-code.fd" \
    "/usr/local/share/qemu/edk2-x86_64-vars.fd" \
    "/opt/homebrew/Cellar/qemu/*/share/qemu/edk2-x86_64-code.fd" \
    "/opt/homebrew/Cellar/qemu/*/share/qemu/edk2-x86_64-vars.fd"; do
    
    if ls $path 2>/dev/null | head -1; then
        if [[ "$path" == *"code"* ]]; then
            OVMF_CODE=$(ls $path 2>/dev/null | head -1)
        elif [[ "$path" == *"vars"* ]]; then
            OVMF_VARS=$(ls $path 2>/dev/null | head -1)
        fi
    fi
done

if [ -n "$OVMF_CODE" ] && [ -n "$OVMF_VARS" ]; then
    echo -e "${GREEN}✅ OVMF files found:${NC}"
    echo "  CODE: $OVMF_CODE"
    echo "  VARS: $OVMF_VARS"
    
    # Create symlinks in expected location
    echo ""
    echo "Creating symlinks in /usr/share/OVMF/..."
    sudo mkdir -p /usr/share/OVMF
    sudo ln -sf "$OVMF_CODE" /usr/share/OVMF/OVMF_CODE.secboot.fd 2>/dev/null || true
    sudo ln -sf "$OVMF_VARS" /usr/share/OVMF/OVMF_VARS.fd 2>/dev/null || true
    
    echo -e "${GREEN}✅ OVMF symlinks created${NC}"
    exit 0
fi

# Try to find via qemu package
echo "Searching for OVMF in QEMU installation..."
QEMU_DIR=$(dirname $(dirname $(which qemu-system-x86_64 2>/dev/null || echo "")))
if [ -n "$QEMU_DIR" ]; then
    OVMF_CODE=$(find "$QEMU_DIR" -name "*edk2*x86_64*code*.fd" 2>/dev/null | head -1)
    OVMF_VARS=$(find "$QEMU_DIR" -name "*edk2*x86_64*vars*.fd" 2>/dev/null | head -1)
    
    if [ -n "$OVMF_CODE" ] && [ -n "$OVMF_VARS" ]; then
        echo -e "${GREEN}✅ Found OVMF files:${NC}"
        echo "  CODE: $OVMF_CODE"
        echo "  VARS: $OVMF_VARS"
        
        sudo mkdir -p /usr/share/OVMF
        sudo ln -sf "$OVMF_CODE" /usr/share/OVMF/OVMF_CODE.secboot.fd
        sudo ln -sf "$OVMF_VARS" /usr/share/OVMF/OVMF_VARS.fd
        
        echo -e "${GREEN}✅ OVMF symlinks created${NC}"
        exit 0
    fi
fi

echo -e "${RED}❌ OVMF files not found${NC}"
echo ""
echo "OVMF is typically included with QEMU. Try:"
echo "  1. Reinstall QEMU: brew reinstall qemu"
echo "  2. Or download OVMF manually and place in /usr/share/OVMF/"
echo ""
echo "Alternatively, we can try to work around the syslinux issue for BIOS boot."
exit 1

