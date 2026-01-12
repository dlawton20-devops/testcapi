#!/bin/bash
# Diagnose VM issues

echo "=== SL-Micro VM Diagnostics ==="
echo ""

echo "1. Checking QEMU process..."
if ps aux | grep -q "qemu.*sl-micro" | grep -v grep; then
    echo "✓ QEMU process is running"
    ps aux | grep "qemu.*sl-micro" | grep -v grep | head -1
else
    echo "✗ QEMU process not found"
fi
echo ""

echo "2. Checking SSH port..."
if lsof -i :2222 2>/dev/null | grep -q LISTEN; then
    echo "✓ Port 2222 is listening"
    lsof -i :2222
else
    echo "✗ Port 2222 not listening (VM may still be booting)"
fi
echo ""

echo "3. Testing SSH connection..."
if ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no root@localhost -p 2222 "echo 'Connected'" 2>/dev/null; then
    echo "✓ SSH connection successful"
else
    echo "✗ SSH connection failed"
    echo "  This could mean:"
    echo "  - VM is still booting (wait 30-60 seconds)"
    echo "  - SSH service not started in VM"
    echo "  - Wrong credentials"
fi
echo ""

echo "4. Checking image file..."
if [ -f "images/SL-Micro.x86_64-6.2-Default-GM.qcow2" ]; then
    echo "✓ Image file exists"
    ls -lh images/SL-Micro.x86_64-6.2-Default-GM.qcow2
else
    echo "✗ Image file not found"
fi
echo ""

echo "5. Checking QEMU version..."
qemu-system-x86_64 --version | head -1
echo ""

echo "6. Checking for QEMU windows..."
echo "Look for a QEMU window on your screen. If you don't see one:"
echo "  - The display backend might not be working"
echo "  - Try running: ./scripts/start-vm.sh in a terminal"
echo ""

echo "=== Common Issues ==="
echo ""
echo "If VM is slow: Using TCG (software emulation) instead of hardware acceleration"
echo "If no window appears: Display backend issue - try running in terminal"
echo "If SSH fails: VM may still be booting or SSH not configured"
echo ""
echo "To see VM output, check the terminal where you ran start-vm.sh"


