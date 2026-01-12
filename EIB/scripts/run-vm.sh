#!/bin/bash
# Run SL-Micro as a VM using QEMU on Mac

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
IMAGES_DIR="$PROJECT_ROOT/images"

# VM Configuration
VM_NAME="sl-micro-vm"
MEMORY="2048"  # 2GB RAM
CPUS="2"
DISK_SIZE="20G"  # Will create a qcow2 disk

# Find qcow2 image first (preferred), then raw image
QCOW2_IMAGE=$(find "$IMAGES_DIR" -name "SL-Micro*.qcow2" -type f 2>/dev/null | head -1)
RAW_IMAGE=$(find "$IMAGES_DIR" -name "SL-Micro*.raw" -type f 2>/dev/null | head -1)

# Use existing qcow2 or create from raw
if [ -n "$QCOW2_IMAGE" ]; then
    echo "Using existing qcow2 image: $QCOW2_IMAGE"
elif [ -n "$RAW_IMAGE" ]; then
    echo "Found raw image, converting to qcow2..."
    QCOW2_IMAGE="${RAW_IMAGE%.raw}.qcow2"
    qemu-img convert -f raw -O qcow2 "$RAW_IMAGE" "$QCOW2_IMAGE"
    # Expand disk to 20GB
    qemu-img resize "$QCOW2_IMAGE" "$DISK_SIZE"
else
    echo "Error: Could not find SL-Micro image in $IMAGES_DIR"
    echo "Please run ./scripts/extract-image.sh first or copy your image to $IMAGES_DIR"
    exit 1
fi

echo "Starting SL-Micro VM..."
echo "Image: $QCOW2_IMAGE"
echo "Memory: ${MEMORY}MB"
echo "CPUs: $CPUS"
echo ""
echo "To connect via SSH after boot:"
echo "  ssh root@localhost -p 2222"
echo ""
echo "Press Ctrl+C to stop the VM"
echo ""

# Run QEMU with network access
qemu-system-x86_64 \
    -name "$VM_NAME" \
    -machine q35,accel=hvf:tcg \
    -cpu host \
    -smp "$CPUS" \
    -m "$MEMORY" \
    -drive file="$QCOW2_IMAGE",format=qcow2,if=virtio \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net,netdev=net0 \
    -display default \
    -vga virtio \
    -usb -device usb-tablet \
    -enable-kvm

