#!/bin/bash
# Start SL-Micro VM - this version runs in foreground for GUI display

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
IMAGES_DIR="$PROJECT_ROOT/images"

# Find qcow2 image
QCOW2_IMAGE=$(find "$IMAGES_DIR" -name "SL-Micro*.qcow2" -type f 2>/dev/null | head -1)

if [ -z "$QCOW2_IMAGE" ]; then
    echo "Error: Could not find SL-Micro qcow2 image in $IMAGES_DIR"
    echo "Please run: ./scripts/extract-image.sh"
    exit 1
fi

echo "Starting SL-Micro VM..."
echo "Image: $QCOW2_IMAGE"
echo "A QEMU window will open - you can interact with the VM there"
echo ""
echo "SSH will be available on: ssh root@localhost -p 2222"
echo "Press Cmd+Option to release mouse/keyboard from QEMU window (macOS)"
echo ""

# Run QEMU in foreground (required for GUI)
# Use Cocoa display backend on macOS for better compatibility
# Try hardware acceleration (hvf) first, fall back to TCG
exec qemu-system-x86_64 \
    -name sl-micro-vm \
    -machine q35 \
    -accel hvf:tcg \
    -cpu host \
    -smp 2 \
    -m 2048 \
    -drive file="$QCOW2_IMAGE",format=qcow2,if=virtio,cache=writeback \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net,netdev=net0 \
    -display cocoa \
    -vga virtio \
    -usb -device usb-tablet \
    -device virtio-rng-pci
