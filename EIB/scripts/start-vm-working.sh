#!/bin/bash
# Working VM launcher - uses TCG emulation which works on all Macs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
IMAGES_DIR="$PROJECT_ROOT/images"

QCOW2_IMAGE=$(find "$IMAGES_DIR" -name "SL-Micro*.qcow2" -type f 2>/dev/null | head -1)

if [ -z "$QCOW2_IMAGE" ]; then
    echo "Error: Could not find SL-Micro qcow2 image in $IMAGES_DIR"
    exit 1
fi

echo "Starting SL-Micro VM (using software emulation)..."
echo "Image: $QCOW2_IMAGE"
echo "Note: This uses TCG emulation which is slower but works on all systems"
echo ""
echo "A QEMU window should appear. If not, check the terminal for errors."
echo "SSH will be available on: ssh root@localhost -p 2222"
echo ""
echo "Press Ctrl+C in this terminal to stop the VM"
echo ""

# Use TCG (software emulation) - works everywhere but slower
exec qemu-system-x86_64 \
    -name sl-micro-vm \
    -machine q35 \
    -accel tcg,thread=multi \
    -cpu qemu64 \
    -smp 2,cores=2,threads=1,sockets=1 \
    -m 2048 \
    -drive file="$QCOW2_IMAGE",format=qcow2,if=virtio,cache=writeback \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net,netdev=net0 \
    -display cocoa \
    -vga virtio \
    -usb -device usb-tablet \
    -rtc base=utc,clock=host


