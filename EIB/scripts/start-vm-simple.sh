#!/bin/bash
# Simple VM launcher with better error handling

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
IMAGES_DIR="$PROJECT_ROOT/images"

QCOW2_IMAGE=$(find "$IMAGES_DIR" -name "SL-Micro*.qcow2" -type f 2>/dev/null | head -1)

if [ -z "$QCOW2_IMAGE" ]; then
    echo "Error: Could not find SL-Micro qcow2 image"
    exit 1
fi

echo "Starting SL-Micro VM..."
echo "Image: $QCOW2_IMAGE"
echo ""

# Try different configurations in order of preference
# Configuration 1: Try with hardware acceleration and Cocoa display
echo "Attempting to start with hardware acceleration..."
qemu-system-x86_64 \
    -name sl-micro-vm \
    -machine q35 \
    -accel hvf \
    -cpu host \
    -smp 2 \
    -m 2048 \
    -drive file="$QCOW2_IMAGE",format=qcow2,if=virtio \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net,netdev=net0 \
    -display cocoa \
    -vga virtio \
    -usb -device usb-tablet 2>&1 | tee /tmp/qemu-output.log

EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "Hardware acceleration failed, trying software emulation..."
    echo "Last error output:"
    tail -10 /tmp/qemu-output.log
    echo ""
    echo "Trying with TCG emulation..."
    
    qemu-system-x86_64 \
        -name sl-micro-vm \
        -machine q35 \
        -accel tcg \
        -cpu qemu64 \
        -smp 2 \
        -m 2048 \
        -drive file="$QCOW2_IMAGE",format=qcow2,if=virtio \
        -netdev user,id=net0,hostfwd=tcp::2222-:22 \
        -device virtio-net,netdev=net0 \
        -display cocoa \
        -vga virtio \
        -usb -device usb-tablet
fi


