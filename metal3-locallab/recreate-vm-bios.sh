#!/bin/bash
set -e

echo "🔧 Recreating VM with BIOS Boot Mode"
echo "===================================="

VM_NAME="metal3-node-0"
VM_IMAGE_DIR="$HOME/metal3-images"
VM_DISK="$VM_IMAGE_DIR/${VM_NAME}.qcow2"
VM_MEMORY="4096"
VM_CPUS="2"
MAC_ADDRESS="52:54:00:f5:26:5e"  # Use existing MAC

# Check if VM exists and destroy it
if virsh dominfo "$VM_NAME" &>/dev/null; then
    echo "Destroying existing VM..."
    virsh destroy "$VM_NAME" 2>/dev/null || true
    virsh undefine "$VM_NAME" 2>/dev/null || true
fi

# Find qemu path
QEMU_PATH=$(which qemu-system-x86_64 2>/dev/null || echo "/opt/homebrew/bin/qemu-system-x86_64")
if [ ! -f "$QEMU_PATH" ]; then
    if [ -f "/opt/homebrew/bin/qemu-system-x86_64" ]; then
        QEMU_PATH="/opt/homebrew/bin/qemu-system-x86_64"
    elif [ -f "/usr/local/bin/qemu-system-x86_64" ]; then
        QEMU_PATH="/usr/local/bin/qemu-system-x86_64"
    else
        echo "❌ qemu-system-x86_64 not found"
        exit 1
    fi
fi

# Get cloud-init ISO
CLOUD_INIT_ISO="$VM_IMAGE_DIR/${VM_NAME}-cloud-init.iso"

echo "Creating VM with BIOS boot mode..."
cat > /tmp/${VM_NAME}-bios.xml <<EOF
<domain type='qemu'>
  <name>$VM_NAME</name>
  <uuid>c9e14d08-1eac-4ec6-9088-f2966c8c46e8</uuid>
  <memory unit='KiB'>$((VM_MEMORY * 1024))</memory>
  <vcpu placement='static'>$VM_CPUS</vcpu>
  <os>
    <type arch='x86_64' machine='pc-i440fx-7.2'>hvm</type>
    <bootmenu enable='yes'/>
  </os>
  <features>
    <acpi/>
    <apic/>
  </features>
  <cpu mode='custom' match='exact'>
    <model fallback='allow'>qemu64</model>
  </cpu>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>destroy</on_crash>
  <devices>
    <emulator>$QEMU_PATH</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='$VM_DISK'/>
      <target dev='vda' bus='virtio'/>
      <boot order='2'/>
    </disk>
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='$CLOUD_INIT_ISO'/>
      <target dev='hda' bus='sata'/>
      <readonly/>
    </disk>
    <interface type='user'>
      <mac address='$MAC_ADDRESS'/>
      <model type='virtio'/>
    </interface>
    <serial type='pty'>
      <target port='0'/>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <graphics type='vnc' port='-1' autoport='yes'/>
    <video>
      <model type='cirrus' vram='16384' heads='1'/>
    </video>
  </devices>
</domain>
EOF

virsh define /tmp/${VM_NAME}-bios.xml
virsh start "$VM_NAME"

echo "✅ VM recreated with BIOS boot mode"
echo ""
echo "Check status: virsh list --all"
echo "Access console: virsh console $VM_NAME"
echo ""

