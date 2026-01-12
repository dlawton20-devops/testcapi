#!/bin/bash
# Fixed VM launcher - compatible CPU model for SL-Micro on M1 Mac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
IMAGES_DIR="$PROJECT_ROOT/images"

# Try to use raw image directly if available (more compatible)
RAW_IMAGE=$(find "$IMAGES_DIR" -name "SL-Micro*.raw" -type f 2>/dev/null | head -1)
QCOW2_IMAGE=$(find "$IMAGES_DIR" -name "SL-Micro*.qcow2" -type f 2>/dev/null | head -1)

if [ -n "$RAW_IMAGE" ]; then
    IMAGE_FILE="$RAW_IMAGE"
    IMAGE_FORMAT="raw"
    echo "Using raw image: $IMAGE_FILE"
elif [ -n "$QCOW2_IMAGE" ]; then
    IMAGE_FILE="$QCOW2_IMAGE"
    IMAGE_FORMAT="qcow2"
    echo "Using qcow2 image: $IMAGE_FILE"
else
    echo "Error: Could not find SL-Micro image"
    exit 1
fi

echo "Starting SL-Micro VM..."
echo "Using $IMAGE_FORMAT format"
echo ""
echo "A QEMU window will open - you can interact with the VM there"
echo "SSH will be available on: ssh root@localhost -p 2222"
echo ""

# Use pc-q35-7.2 machine type (more compatible)
# Use Haswell CPU model (well-supported x86_64 CPU)
# TCG emulation with proper x86_64 support
exec qemu-system-x86_64 \
    -name sl-micro-vm \
    -machine pc-q35-7.2 \
    -accel tcg,thread=multi \
    -cpu Haswell-v4,+ssse3,+sse4.1,+sse4.2,+x2apic \
    -smp 2,cores=2,threads=1,sockets=1 \
    -m 2048 \
    -drive file="$IMAGE_FILE",format=$IMAGE_FORMAT,if=virtio,cache=writeback \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -device virtio-net,netdev=net0 \
    -display cocoa \
    -vga virtio \
    -usb -device usb-tablet \
    -rtc base=utc,clock=host \
    -global ICH9-LPC.disable_s3=1 \
    -global ICH9-LPC.disable_s4=1


