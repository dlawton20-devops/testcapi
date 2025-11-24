#!/bin/bash
set -e

echo "🔧 Fixing VM for PXE Boot (IPA)"
echo "=================================="

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

# Check if default network exists and is active
if virsh net-info default &>/dev/null; then
    if virsh net-is-active default; then
        echo -e "${GREEN}✅ Default network is active${NC}"
        NETWORK_NAME="default"
    else
        echo -e "${YELLOW}⚠️  Default network exists but is not active. Attempting to start...${NC}"
        if virsh net-start default 2>/dev/null; then
            echo -e "${GREEN}✅ Default network started${NC}"
            NETWORK_NAME="default"
        else
            echo -e "${RED}❌ Could not start default network. You may need to run: virsh net-start default${NC}"
            exit 1
        fi
    fi
else
    echo -e "${YELLOW}⚠️  Default network not found. Creating it...${NC}"
    cat > /tmp/default-net.xml <<EOF
<network>
  <name>default</name>
  <uuid>$(uuidgen)</uuid>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='virbr0' stp='on' delay='0'/>
  <mac address='52:54:00:00:00:01'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
EOF
    virsh net-define /tmp/default-net.xml
    virsh net-autostart default
    if virsh net-start default 2>/dev/null; then
        echo -e "${GREEN}✅ Default network created and started${NC}"
        NETWORK_NAME="default"
    else
        echo -e "${RED}❌ Could not start default network. You may need sudo: sudo virsh net-start default${NC}"
        exit 1
    fi
fi

# Stop VM if running
if virsh dominfo "$VM_NAME" | grep -q "State:.*running"; then
    echo "Stopping VM..."
    virsh destroy "$VM_NAME"
    sleep 2
fi

# Get current VM XML
echo "Backing up current VM configuration..."
virsh dumpxml "$VM_NAME" > "/tmp/${VM_NAME}-backup-$(date +%s).xml"

# Get MAC address from current VM
MAC_ADDRESS=$(virsh dumpxml "$VM_NAME" | grep -oP "mac address='\K[^']+" | head -1)
if [ -z "$MAC_ADDRESS" ]; then
    echo -e "${YELLOW}⚠️  Could not find MAC address, generating new one...${NC}"
    MAC_ADDRESS="52:54:00:$(openssl rand -hex 3 | sed 's/\(..\)/\1:/g; s/.$//')"
fi

echo "MAC Address: $MAC_ADDRESS"

# Create updated VM XML with PXE boot support
echo "Updating VM configuration for PXE boot..."
cat > /tmp/${VM_NAME}-updated.xml <<EOF
<domain type='qemu'>
  <name>$VM_NAME</name>
  <uuid>721bcaa7-be3d-4d62-99a9-958bb212f2b7</uuid>
  <memory unit='KiB'>4194304</memory>
  <vcpu placement='static'>2</vcpu>
  <os>
    <type arch='x86_64' machine='pc-q35-7.2'>hvm</type>
    <boot dev='network'/>
    <boot dev='hd'/>
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
    <emulator>/opt/homebrew/bin/qemu-system-x86_64</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='$HOME/metal3-images/metal3-node-0.qcow2'/>
      <target dev='vda' bus='virtio'/>
      <boot order='2'/>
    </disk>
    <interface type='network'>
      <source network='$NETWORK_NAME'/>
      <mac address='$MAC_ADDRESS'/>
      <model type='virtio'/>
      <boot order='1'/>
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

# Undefine and redefine VM
echo "Updating VM definition..."
virsh undefine "$VM_NAME" --keep-nvram 2>/dev/null || virsh undefine "$VM_NAME"
virsh define /tmp/${VM_NAME}-updated.xml

echo -e "${GREEN}✅ VM updated for PXE boot${NC}"
echo ""
echo "Changes made:"
echo "  - Boot order: Network first, then hard disk"
echo "  - Network: Changed from user-mode to bridge network ($NETWORK_NAME)"
echo "  - Boot menu: Enabled (can press F12 to select boot device)"
echo ""
echo "Next steps:"
echo "  1. Start the VM: virsh start $VM_NAME"
echo "  2. The VM should now boot from network (PXE) when Ironic triggers inspection"
echo "  3. Recreate the BareMetalHost: kubectl apply -f baremetalhost.yaml"
echo ""
echo -e "${YELLOW}Note: If the network requires sudo to start, you may need to:${NC}"
echo "  sudo virsh net-start $NETWORK_NAME"

