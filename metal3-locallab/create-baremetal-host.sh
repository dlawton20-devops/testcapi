#!/bin/bash
set -e

echo "🔧 Creating libvirt VM and BareMetalHost for Metal3"
echo "==================================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

VM_NAME="metal3-node-0"
VM_IMAGE_DIR="$HOME/metal3-images"
FOCAL_IMAGE="focal-server-cloudimg-amd64.img"
FOCAL_URL="https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"
VM_DISK_SIZE="20G"
VM_MEMORY="4096"
VM_CPUS="2"
VM_NETWORK="metal3-net"  # Use bridge network

# Check if kubectl context is set
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}❌ No Kubernetes cluster found. Run setup-metal3.sh first.${NC}"
    exit 1
fi

# Check if bridge network exists, create if not
if ! virsh net-info "$VM_NETWORK" &>/dev/null; then
    echo -e "${YELLOW}⚠️  Bridge network $VM_NETWORK not found. Creating it...${NC}"
    if [ -f "./setup-libvirt-bridge.sh" ]; then
        ./setup-libvirt-bridge.sh
    else
        echo -e "${YELLOW}⚠️  setup-libvirt-bridge.sh not found. Using default network.${NC}"
        VM_NETWORK="default"
    fi
fi

# Ensure network is active
if ! virsh net-list --name | grep -q "^${VM_NETWORK}$"; then
    echo "Starting network $VM_NETWORK..."
    if virsh net-start "$VM_NETWORK" 2>/dev/null; then
        echo -e "${GREEN}✅ Network $VM_NETWORK started${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not start network $VM_NETWORK. You may need to run:${NC}"
        echo "   sudo virsh net-start $VM_NETWORK"
        echo -e "${YELLOW}⚠️  Falling back to default network...${NC}"
        VM_NETWORK="default"
        virsh net-start "$VM_NETWORK" 2>/dev/null || true
    fi
else
    echo -e "${GREEN}✅ Network $VM_NETWORK is active${NC}"
fi

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

# Static IP configuration
STATIC_IP="192.168.122.100"
GATEWAY="192.168.122.1"
NETMASK="255.255.255.0"
DNS="8.8.8.8"

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
# Network configuration - static IP for Redfish virtual media
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

# Create cloud-init ISO (requires genisoimage or mkisofs)
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
    # Try again after installation
    if [ -f "/opt/homebrew/bin/genisoimage" ]; then
        /opt/homebrew/bin/genisoimage -output "$CLOUD_INIT_ISO" -volid cidata -joliet -rock "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"
    elif [ -f "/opt/homebrew/bin/mkisofs" ]; then
        /opt/homebrew/bin/mkisofs -output "$CLOUD_INIT_ISO" -volid cidata -joliet -rock "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data"
    else
        echo -e "${RED}❌ genisoimage/mkisofs still not found after installation${NC}"
        exit 1
    fi
fi

# Generate MAC address (VM doesn't exist yet, so generate one)
MAC_ADDRESS="52:54:00:$(openssl rand -hex 3 | sed 's/\(..\)/\1:/g; s/.$//')"
echo "Generated MAC address: $MAC_ADDRESS"

# Create libvirt VM definition
echo "Creating libvirt VM..."
cat > /tmp/${VM_NAME}.xml <<EOF
<domain type='qemu'>
  <name>$VM_NAME</name>
  <memory unit='KiB'>$((VM_MEMORY * 1024))</memory>
  <vcpu placement='static'>$VM_CPUS</vcpu>
  <os>
    <type arch='x86_64' machine='pc-q35-7.2'>hvm</type>
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
          <source file='$VM_DISK'/>
          <target dev='vda' bus='virtio'/>
          <boot order='2'/>
        </disk>
        <disk type='file' device='cdrom'>
          <driver name='qemu' type='raw'/>
          <source file='$CLOUD_INIT_ISO'/>
          <target dev='hda' bus='sata'/>
          <readonly/>
          <boot order='1'/>
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

# Wait a bit for VM to get IP
echo "Waiting for VM to initialize..."
sleep 10

# Get VM IP (this may take a while)
echo "Getting VM IP address..."
VM_IP=""
for i in {1..30}; do
    VM_IP=$(virsh domifaddr "$VM_NAME" 2>/dev/null | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" | head -1 || echo "")
    if [ -n "$VM_IP" ]; then
        break
    fi
    sleep 2
done

if [ -z "$VM_IP" ]; then
    echo -e "${YELLOW}⚠️  Could not get VM IP automatically. You may need to check manually.${NC}"
    echo "   Run: virsh domifaddr $VM_NAME"
else
    echo -e "${GREEN}✅ VM IP: $VM_IP${NC}"
fi

# Check if sushy-tools is running
SUSHY_PORT=8000
SUSHY_HOST="localhost"
if ! curl -s -u admin:admin "http://${SUSHY_HOST}:${SUSHY_PORT}/redfish/v1" &>/dev/null; then
    echo -e "${YELLOW}⚠️  sushy-tools doesn't appear to be running.${NC}"
    echo "   Please start sushy-tools first:"
    echo "   - If using launchd: launchctl load ~/Library/LaunchAgents/com.metal3.sushy-emulator.plist"
    echo "   - Or run manually: ~/metal3-sushy/start-sushy.sh"
    echo ""
    read -p "Do you want to start sushy-tools now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [ -f "$HOME/metal3-sushy/start-sushy.sh" ]; then
            echo "Starting sushy-tools in background..."
            nohup "$HOME/metal3-sushy/start-sushy.sh" > "$HOME/metal3-sushy/sushy.log" 2>&1 &
            SUSHY_PID=$!
            echo "Waiting for sushy-tools to start..."
            sleep 5
            if ! kill -0 $SUSHY_PID 2>/dev/null; then
                echo -e "${RED}❌ sushy-tools failed to start. Check logs: $HOME/metal3-sushy/sushy.log${NC}"
                exit 1
            fi
        else
            echo -e "${RED}❌ sushy-tools not set up. Run setup-sushy-tools.sh first.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ Cannot proceed without sushy-tools. Exiting.${NC}"
        exit 1
    fi
fi

# Get the system ID from sushy (it should match the VM name)
echo "Checking sushy-tools for VM..."
SUSHY_SYSTEM_ID=$(curl -s -u admin:admin "http://${SUSHY_HOST}:${SUSHY_PORT}/redfish/v1/Systems" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('Members', [{}])[0].get('@odata.id', '').split('/')[-1])" 2>/dev/null || echo "")

if [ -z "$SUSHY_SYSTEM_ID" ] || [ "$SUSHY_SYSTEM_ID" == "None" ]; then
    # Try to get system ID by VM name
    SUSHY_SYSTEM_ID=$(curl -s -u admin:admin "http://${SUSHY_HOST}:${SUSHY_PORT}/redfish/v1/Systems" | python3 -c "import sys, json; data=json.load(sys.stdin); members=data.get('Members', []); print(members[0].get('@odata.id', '').split('/')[-1]) if members else ''" 2>/dev/null || echo "")
fi

# If still no system ID, use the VM name as fallback
if [ -z "$SUSHY_SYSTEM_ID" ] || [ "$SUSHY_SYSTEM_ID" == "None" ]; then
    echo -e "${YELLOW}⚠️  Could not determine system ID from sushy. Using VM name.${NC}"
    SUSHY_SYSTEM_ID="$VM_NAME"
fi

# Create BareMetalHost resource
echo ""
echo "Creating BareMetalHost resource..."

# Get MAC address from VM
BOOT_MAC=$(virsh domiflist "$VM_NAME" | grep -oE "([0-9a-f]{2}:){5}[0-9a-f]{2}" | head -1)

# Use localhost for sushy (it should be accessible from the cluster)
# For kind, we need to use host.docker.internal or the host IP
# Get the host IP that's accessible from the cluster
HOST_IP=$(ifconfig | grep -E "inet.*broadcast" | grep -v "127.0.0.1" | awk '{print $2}' | head -1)
if [ -z "$HOST_IP" ]; then
    HOST_IP="host.docker.internal"
fi

cat > /tmp/baremetalhost.yaml <<EOF
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: $VM_NAME
  namespace: metal3-system
spec:
  online: true
  bootMACAddress: "$BOOT_MAC"
  bmc:
    address: "redfish+http://${HOST_IP}:${SUSHY_PORT}/redfish/v1/Systems/${SUSHY_SYSTEM_ID}"
    credentialsName: $VM_NAME-bmc-secret
  bootMode: "UEFI"
  automatedCleaning: false
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

kubectl apply -f /tmp/baremetalhost.yaml

echo -e "${GREEN}✅ BareMetalHost resource created${NC}"
echo ""
echo "BareMetalHost status:"
kubectl get baremetalhost -n metal3-system

echo ""
echo -e "${GREEN}✅ Setup complete!${NC}"
echo ""
echo "To check VM status: virsh list"
echo "To check BareMetalHost: kubectl get baremetalhost -n metal3-system"
echo "To access VM: ssh ubuntu@$VM_IP (password: ubuntu)"

