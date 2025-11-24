#!/bin/bash
set -e

echo "🔄 Continuing Metal3 Setup from VM Creation"
echo "============================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
VM_NAME="metal3-node-0"
VM_IMAGE_DIR="$HOME/metal3-images"
FOCAL_IMAGE="focal-server-cloudimg-amd64.img"
FOCAL_URL="https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"
VM_DISK_SIZE="20G"
VM_MEMORY="4096"
VM_CPUS="2"
HOST_IP=$(ifconfig | grep -E "inet.*broadcast" | grep -v "127.0.0.1" | awk '{print $2}' | head -1)
if [ -z "$HOST_IP" ]; then
    HOST_IP="192.168.1.242"
fi

# Get NodePort
echo "Getting Ironic NodePort..."
NODE_PORT=$(kubectl get svc metal3-metal3-ironic -n metal3-system -o jsonpath='{.spec.ports[?(@.port==6185)].nodePort}')
if [ -z "$NODE_PORT" ]; then
    NODE_PORT=$(kubectl get svc metal3-metal3-ironic -n metal3-system -o jsonpath='{.spec.ports[0].nodePort}')
fi

if [ -z "$NODE_PORT" ]; then
    echo -e "${RED}❌ Could not determine NodePort. Is Ironic service configured as NodePort?${NC}"
    exit 1
fi

echo -e "${GREEN}✅ NodePort: $NODE_PORT${NC}"

# Create libvirt VM
echo ""
echo -e "${BLUE}🖥️  Creating libvirt VM...${NC}"

# Note: We're using user-mode networking, so no libvirt network is needed
echo -e "${GREEN}✅ Using user-mode networking (no libvirt network required)${NC}"

# Create image directory
mkdir -p "$VM_IMAGE_DIR"

# Download Ubuntu Focal image if not exists
if [ ! -f "$VM_IMAGE_DIR/$FOCAL_IMAGE" ]; then
    echo "Downloading Ubuntu Focal (20.04) cloud image..."
    curl -L -o "$VM_IMAGE_DIR/$FOCAL_IMAGE" "$FOCAL_URL"
    echo -e "${GREEN}✅ Image downloaded${NC}"
else
    echo -e "${GREEN}✅ Image already exists${NC}"
fi

# Create a qcow2 disk from the image
VM_DISK="$VM_IMAGE_DIR/${VM_NAME}.qcow2"
if [ ! -f "$VM_DISK" ]; then
    echo "Creating VM disk..."
    qemu-img create -f qcow2 -F qcow2 -b "$VM_IMAGE_DIR/$FOCAL_IMAGE" "$VM_DISK" "$VM_DISK_SIZE"
    echo -e "${GREEN}✅ VM disk created${NC}"
else
    echo -e "${GREEN}✅ VM disk already exists${NC}"
fi

# Check if VM already exists
if virsh dominfo "$VM_NAME" &>/dev/null; then
    echo -e "${YELLOW}⚠️  VM $VM_NAME already exists. Destroying and removing...${NC}"
    virsh destroy "$VM_NAME" 2>/dev/null || true
    virsh undefine "$VM_NAME" 2>/dev/null || true
fi

# Generate cloud-init user-data
CLOUD_INIT_DIR="$VM_IMAGE_DIR/cloud-init"
mkdir -p "$CLOUD_INIT_DIR"

cat > "$CLOUD_INIT_DIR/user-data" <<EOF
#cloud-config
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo, docker
    shell: /bin/bash
    ssh_authorized_keys:
      - $(cat ~/.ssh/id_rsa.pub 2>/dev/null || echo "# Add your SSH key here")
password: ubuntu
chpasswd:
  expire: false
ssh_pwauth: true
package_update: true
packages:
  - qemu-guest-agent
  - cloud-init
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
# Network configuration - static IP for user-mode network
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses:
        - 10.0.2.100/24
      gateway4: 10.0.2.2
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
EOF

cat > "$CLOUD_INIT_DIR/meta-data" <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

# Create cloud-init ISO
CLOUD_INIT_ISO="$VM_IMAGE_DIR/${VM_NAME}-cloud-init.iso"
if [ -f "$CLOUD_INIT_ISO" ]; then
    rm "$CLOUD_INIT_ISO"
fi

# Create cloud-init ISO
if command -v genisoimage &> /dev/null; then
    genisoimage -output "$CLOUD_INIT_ISO" -volid cidata -joliet -rock "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"
elif command -v mkisofs &> /dev/null; then
    mkisofs -output "$CLOUD_INIT_ISO" -volid cidata -joliet -rock "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"
elif [ -f "/opt/homebrew/bin/genisoimage" ]; then
    /opt/homebrew/bin/genisoimage -output "$CLOUD_INIT_ISO" -volid cidata -joliet -rock "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"
elif [ -f "/opt/homebrew/bin/mkisofs" ]; then
    /opt/homebrew/bin/mkisofs -output "$CLOUD_INIT_ISO" -volid cidata -joliet -rock "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"
else
    echo -e "${YELLOW}⚠️  genisoimage or mkisofs not found. Installing...${NC}"
    brew install cdrtools || {
        echo -e "${RED}❌ Failed to install cdrtools. Please install manually: brew install cdrtools${NC}"
        exit 1
    }
    if [ -f "/opt/homebrew/bin/genisoimage" ]; then
        /opt/homebrew/bin/genisoimage -output "$CLOUD_INIT_ISO" -volid cidata -joliet -rock "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"
    elif [ -f "/opt/homebrew/bin/mkisofs" ]; then
        /opt/homebrew/bin/mkisofs -output "$CLOUD_INIT_ISO" -volid cidata -joliet -rock "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"
    else
        echo -e "${RED}❌ genisoimage/mkisofs still not found after installation${NC}"
        exit 1
    fi
fi

# Find qemu path
QEMU_PATH=$(which qemu-system-x86_64 2>/dev/null || echo "/opt/homebrew/bin/qemu-system-x86_64")
if [ ! -f "$QEMU_PATH" ]; then
    if [ -f "/opt/homebrew/bin/qemu-system-x86_64" ]; then
        QEMU_PATH="/opt/homebrew/bin/qemu-system-x86_64"
    elif [ -f "/usr/local/bin/qemu-system-x86_64" ]; then
        QEMU_PATH="/usr/local/bin/qemu-system-x86_64"
    else
        echo -e "${RED}❌ qemu-system-x86_64 not found${NC}"
        exit 1
    fi
fi
echo "Using QEMU: $QEMU_PATH"

# Generate MAC address
MAC_ADDRESS="52:54:00:$(openssl rand -hex 3 | sed 's/\(..\)/\1:/g; s/.$//')"
echo "Generated MAC address: $MAC_ADDRESS"

# Create libvirt VM definition with user-mode networking
echo "Creating libvirt VM with user-mode networking..."
cat > /tmp/${VM_NAME}.xml <<EOF
<domain type='qemu'>
  <name>$VM_NAME</name>
  <memory unit='KiB'>$((VM_MEMORY * 1024))</memory>
  <vcpu placement='static'>$VM_CPUS</vcpu>
  <os>
    <type arch='x86_64' machine='pc-q35-7.2'>hvm</type>
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

# Define and start the VM
virsh define /tmp/${VM_NAME}.xml
virsh start "$VM_NAME"

echo -e "${GREEN}✅ VM $VM_NAME created and started${NC}"

# Wait a bit for VM to initialize
echo "Waiting for VM to initialize..."
sleep 10

# Get VM IP
VM_IP=""
for i in {1..30}; do
    VM_IP=$(virsh domifaddr "$VM_NAME" 2>/dev/null | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" | head -1 || echo "")
    if [ -n "$VM_IP" ]; then
        break
    fi
    sleep 2
done

if [ -z "$VM_IP" ]; then
    echo -e "${YELLOW}⚠️  Could not get VM IP automatically. It should be 10.0.2.100${NC}"
    VM_IP="10.0.2.100"
else
    echo -e "${GREEN}✅ VM IP: $VM_IP${NC}"
fi

# Get system ID from sushy
echo ""
echo -e "${BLUE}🔍 Getting system ID from sushy-tools...${NC}"
SUSHY_PORT=8000
SUSHY_SYSTEM_ID=$(curl -s -u admin:admin "http://localhost:${SUSHY_PORT}/redfish/v1/Systems" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('Members', [{}])[0].get('@odata.id', '').split('/')[-1])" 2>/dev/null || echo "")

if [ -z "$SUSHY_SYSTEM_ID" ] || [ "$SUSHY_SYSTEM_ID" == "None" ]; then
    echo -e "${YELLOW}⚠️  Could not determine system ID from sushy. Using VM name.${NC}"
    SUSHY_SYSTEM_ID="$VM_NAME"
fi

echo "System ID: $SUSHY_SYSTEM_ID"

# Get MAC address from VM
BOOT_MAC=$(virsh domiflist "$VM_NAME" | grep -oE "([0-9a-f]{2}:){5}[0-9a-f]{2}" | head -1)
if [ -z "$BOOT_MAC" ]; then
    BOOT_MAC="$MAC_ADDRESS"
fi

# Create BareMetalHost
echo ""
echo -e "${BLUE}📝 Creating BareMetalHost...${NC}"
kubectl apply -f - <<EOF
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: $VM_NAME
  namespace: metal3-system
  annotations:
    inspect.metal3.io: "disabled"
spec:
  online: true
  bootMACAddress: "$BOOT_MAC"
  bmc:
    address: "redfish-virtualmedia+http://${HOST_IP}:${SUSHY_PORT}/redfish/v1/Systems/${SUSHY_SYSTEM_ID}"
    credentialsName: $VM_NAME-bmc-secret
  bootMode: "UEFI"
  automatedCleaningMode: "disabled"
  preprovisioningNetworkDataName: "provisioning-networkdata"
  image:
    url: "https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"
    checksum: "https://cloud-images.ubuntu.com/focal/current/SHA256SUMS"
    checksumType: "auto"
---
apiVersion: v1
kind: Secret
metadata:
  name: $VM_NAME-bmc-secret
  namespace: metal3-system
type: Opaque
data:
  username: YWRtaW4=  # admin
  password: YWRtaW4=  # admin
EOF

echo -e "${GREEN}✅ BareMetalHost created${NC}"

# Summary
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Setup Complete!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""
echo "VM: $VM_NAME"
echo "VM IP: $VM_IP"
echo "Host IP: $HOST_IP"
echo "Ironic NodePort: $NODE_PORT"
echo "Ironic URL: https://${HOST_IP}:${NODE_PORT}"
echo ""
echo "Check BareMetalHost status:"
echo "  kubectl get baremetalhost -n metal3-system -w"
echo ""
echo "Check VM console:"
echo "  virsh console $VM_NAME"
echo ""
echo "Access VM via SSH:"
echo "  ssh ubuntu@$VM_IP (password: ubuntu)"
echo ""
echo "Test Ironic connectivity:"
echo "  curl -k https://${HOST_IP}:${NODE_PORT}/"
echo ""

