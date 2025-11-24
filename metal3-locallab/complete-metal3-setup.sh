#!/bin/bash
set -e

echo "🚀 Complete Metal3 Setup with Kind Cluster and KVM Node"
echo "========================================================"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CLUSTER_NAME="metal3-management"
VM_NAME="metal3-node-0"
VM_IMAGE_DIR="$HOME/metal3-images"
FOCAL_IMAGE="focal-server-cloudimg-amd64.img"
FOCAL_URL="https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"
VM_DISK_SIZE="20G"
VM_MEMORY="4096"
VM_CPUS="2"
STATIC_IRONIC_IP="172.18.255.200"
IRONIC_PORT="6385"
SUSHY_PORT="8000"

# Get host IP address (for Ironic external URL)
get_host_ip() {
    # Try to get the primary network interface IP
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        HOST_IP=$(ifconfig | grep -E "inet.*broadcast" | grep -v "127.0.0.1" | awk '{print $2}' | head -1)
    else
        # Linux
        HOST_IP=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $7; exit}' || hostname -I | awk '{print $1}')
    fi
    
    if [ -z "$HOST_IP" ]; then
        echo -e "${YELLOW}⚠️  Could not determine host IP. Using 192.168.1.242 as default.${NC}"
        HOST_IP="192.168.1.242"
    fi
    
    echo "$HOST_IP"
}

HOST_IP=$(get_host_ip)
echo -e "${BLUE}📡 Using host IP: $HOST_IP${NC}"

# Check prerequisites
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}❌ $1 is not installed${NC}"
        exit 1
    else
        echo -e "${GREEN}✅ $1 is installed${NC}"
    fi
}

echo ""
echo "Checking prerequisites..."
check_command kubectl
check_command helm
check_command kind
check_command virsh
check_command qemu-system-x86_64

# Check if Docker is running
if ! docker ps &>/dev/null; then
    echo -e "${RED}❌ Docker is not running. Please start Docker Desktop or Rancher Desktop first.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Docker is running${NC}"

# Clean up old cluster if it exists
echo ""
echo -e "${BLUE}🧹 Cleaning up old cluster if it exists...${NC}"
if kind get clusters 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    echo "Deleting old $CLUSTER_NAME cluster..."
    kind delete cluster --name "$CLUSTER_NAME" 2>/dev/null || true
fi

# Create kind cluster
echo ""
echo -e "${BLUE}📦 Creating kind cluster...${NC}"
cat <<EOF | kind create cluster --name "$CLUSTER_NAME" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  podSubnet: "192.168.0.0/16"
  serviceSubnet: "10.96.0.0/12"
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 8080
    protocol: TCP
  - containerPort: 443
    hostPort: 8443
    protocol: TCP
EOF

# Set kubectl context
kubectl config use-context "kind-$CLUSTER_NAME"

# Wait for cluster to be ready
echo "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Install MetalLB
echo ""
echo -e "${BLUE}📡 Installing MetalLB...${NC}"
helm install metallb oci://registry.suse.com/edge/charts/metallb \
    --namespace metallb-system \
    --create-namespace \
    --wait \
    --timeout 5m || {
    echo -e "${YELLOW}⚠️  MetalLB install may have timed out. Checking status...${NC}"
    kubectl get pods -n metallb-system
}

# Wait for MetalLB to be ready
kubectl wait --namespace metallb-system \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/name=metallb \
    --timeout=300s || true

# Configure MetalLB IP pool
echo "Configuring MetalLB IP pool..."
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - ${STATIC_IRONIC_IP}-172.18.255.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
EOF

echo -e "${GREEN}✅ MetalLB installed and configured${NC}"

# Install cert-manager
echo ""
echo -e "${BLUE}🔐 Installing cert-manager...${NC}"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --namespace cert-manager \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/instance=cert-manager \
    --timeout=300s || {
    echo -e "${YELLOW}⚠️  Waiting for cert-manager pods...${NC}"
    kubectl get pods -n cert-manager
}

echo -e "${GREEN}✅ cert-manager installed${NC}"

# Install Metal3 from SUSE Edge
echo ""
echo -e "${BLUE}⚙️  Installing Metal3 from SUSE Edge...${NC}"
helm install metal3 oci://registry.suse.com/edge/charts/metal3 \
    --namespace metal3-system \
    --create-namespace \
    --wait \
    --timeout 10m \
    --set global.ironicIP="$STATIC_IRONIC_IP" \
    --set global.ironicKernelParams="console=ttyS0" \
    --set ironic.service.type=LoadBalancer \
    --set ironic.service.loadBalancerIP="$STATIC_IRONIC_IP" \
    || {
        echo -e "${YELLOW}⚠️  Helm install may have timed out. Checking status...${NC}"
        kubectl get pods -n metal3-system
    }

# Wait for Metal3 pods to be ready
echo "Waiting for Metal3 pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n metal3-system --timeout=600s || {
    echo -e "${YELLOW}⚠️  Some pods may not be ready yet. Current status:${NC}"
    kubectl get pods -n metal3-system
}

echo -e "${GREEN}✅ Metal3 installed${NC}"

# Configure IPA fixes
echo ""
echo -e "${BLUE}🔧 Configuring IPA fixes...${NC}"

# Fix 1: Disable certificate verification
echo "Setting IPA_INSECURE=1..."
kubectl patch configmap ironic -n metal3-system --type merge -p '{"data":{"IPA_INSECURE":"1"}}'

# Fix 2: Ironic external URL will be set after NodePort is configured
echo "Ironic external URL will be configured after NodePort setup..."

# Fix 3: Enable console autologin for debugging
CURRENT_PARAMS=$(kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_KERNEL_PARAMS}' 2>/dev/null || echo "console=ttyS0")
if [[ ! "$CURRENT_PARAMS" =~ "suse.autologin" ]]; then
    NEW_PARAMS="$CURRENT_PARAMS suse.autologin=ttyS0"
    kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_KERNEL_PARAMS\":\"$NEW_PARAMS\"}}"
fi

# Restart Ironic pod to apply changes
echo "Restarting Ironic pod to apply changes..."
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic --wait=false

# Wait for Ironic pod to be ready again
echo "Waiting for Ironic pod to be ready..."
kubectl wait --for=condition=Ready pod -n metal3-system -l app.kubernetes.io/component=ironic --timeout=300s || true

echo -e "${GREEN}✅ IPA fixes configured${NC}"

# Create NetworkData secret for IPA
echo ""
echo -e "${BLUE}🌐 Creating NetworkData secret for IPA...${NC}"
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: provisioning-networkdata
  namespace: metal3-system
type: Opaque
stringData:
  networkData: |
    version: 2
    ethernets:
      eth0:
        dhcp4: false
        addresses:
          - 192.168.124.100/24
        gateway4: 192.168.124.1
        nameservers:
          addresses:
            - 8.8.8.8
            - 8.8.4.4
EOF

echo -e "${GREEN}✅ NetworkData secret created${NC}"

# Configure Ironic service to use NodePort
echo ""
echo -e "${BLUE}🔌 Configuring Ironic service to use NodePort...${NC}"

# Bridge network configuration (defined here for use in NodePort setup)
BRIDGE_IP="192.168.124.1"
IRONIC_BRIDGE_PORT="6385"

# Change Ironic service to NodePort
echo "Changing Ironic service to NodePort..."
kubectl patch svc metal3-metal3-ironic -n metal3-system -p '{"spec":{"type":"NodePort"}}'

# Get the NodePort number
echo "Getting NodePort number..."
NODE_PORT=$(kubectl get svc metal3-metal3-ironic -n metal3-system -o jsonpath='{.spec.ports[?(@.port==6185)].nodePort}')
if [ -z "$NODE_PORT" ]; then
    # Try alternative port
    NODE_PORT=$(kubectl get svc metal3-metal3-ironic -n metal3-system -o jsonpath='{.spec.ports[0].nodePort}')
fi

if [ -z "$NODE_PORT" ]; then
    echo -e "${RED}❌ Could not determine NodePort. Using default port 6385${NC}"
    NODE_PORT="6385"
else
    echo -e "${GREEN}✅ NodePort: $NODE_PORT${NC}"
fi

# Set up port forwarding from bridge network to NodePort
echo "Setting up port forwarding from bridge network to NodePort..."

# Kill existing socat processes
pkill -f "socat.*${IRONIC_BRIDGE_PORT}" || true

# Check if socat is installed
if ! command -v socat &> /dev/null; then
    echo -e "${YELLOW}⚠️  socat is not installed. Installing...${NC}"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install socat || {
            echo -e "${RED}❌ Failed to install socat. Please install manually: brew install socat${NC}"
            exit 1
        }
    else
        sudo apt-get update && sudo apt-get install -y socat || {
            echo -e "${RED}❌ Failed to install socat. Please install manually${NC}"
            exit 1
        }
    fi
fi

# Start socat to forward from bridge network to NodePort
echo "Starting socat forwarder from bridge network to NodePort..."
nohup sudo socat TCP-LISTEN:${IRONIC_BRIDGE_PORT},bind=${BRIDGE_IP},fork,reuseaddr TCP:localhost:${NODE_PORT} > /tmp/socat-ironic-bridge.log 2>&1 &
SOCAT_PID=$!
sleep 2

# Check if socat is running
if ! kill -0 $SOCAT_PID 2>/dev/null; then
    echo -e "${YELLOW}⚠️  socat may have failed to start. Check /tmp/socat-ironic-bridge.log${NC}"
    echo -e "${YELLOW}⚠️  You may need to run manually: sudo socat TCP-LISTEN:${IRONIC_BRIDGE_PORT},bind=${BRIDGE_IP},fork,reuseaddr TCP:localhost:${NODE_PORT}${NC}"
else
    echo -e "${GREEN}✅ Port forwarding configured (socat PID: $SOCAT_PID)${NC}"
fi

# Update Ironic external URL to use bridge network IP
echo "Updating Ironic external URL to use bridge network IP..."
kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_EXTERNAL_HTTP_URL\":\"https://${BRIDGE_IP}:${IRONIC_BRIDGE_PORT}\"}}"

# Restart Ironic pod to apply changes
echo "Restarting Ironic pod to apply NodePort URL..."
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic --wait=false
sleep 5

# Wait for Ironic pod to be ready
kubectl wait --for=condition=Ready pod -n metal3-system -l app.kubernetes.io/component=ironic --timeout=300s || true

echo -e "${GREEN}✅ NodePort configured${NC}"
echo "   Ironic NodePort: $NODE_PORT"
echo "   Ironic URL: https://${HOST_IP}:${NODE_PORT}"

# Check/install sushy-tools
echo ""
echo -e "${BLUE}🔧 Checking sushy-tools...${NC}"
if ! curl -s -u admin:admin "http://localhost:${SUSHY_PORT}/redfish/v1" &>/dev/null; then
    echo "sushy-tools is not running. Setting it up..."
    if [ -f "./setup-sushy-tools.sh" ]; then
        ./setup-sushy-tools.sh
    else
        echo -e "${YELLOW}⚠️  setup-sushy-tools.sh not found. Please set up sushy-tools manually.${NC}"
    fi
    
    # Try to start sushy-tools
    if [ -f "$HOME/metal3-sushy/start-sushy.sh" ]; then
        echo "Starting sushy-tools..."
        nohup "$HOME/metal3-sushy/start-sushy.sh" > "$HOME/metal3-sushy/sushy.log" 2>&1 &
        sleep 5
    fi
fi

if curl -s -u admin:admin "http://localhost:${SUSHY_PORT}/redfish/v1" &>/dev/null; then
    echo -e "${GREEN}✅ sushy-tools is running${NC}"
else
    echo -e "${YELLOW}⚠️  sushy-tools is not accessible. You may need to start it manually.${NC}"
fi

# Create libvirt VM
echo ""
echo -e "${BLUE}🖥️  Creating libvirt VM...${NC}"

# Set up bridge network for shared address space
BRIDGE_NETWORK="metal3-net"
VM_STATIC_IP="192.168.124.100"

echo "Setting up bridge network for shared address space..."
if ! virsh net-info "$BRIDGE_NETWORK" &>/dev/null; then
    echo "Creating bridge network $BRIDGE_NETWORK..."
    cat > /tmp/${BRIDGE_NETWORK}.xml <<EOF
<network>
  <name>${BRIDGE_NETWORK}</name>
  <uuid>$(uuidgen)</uuid>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='metal3-bridge' stp='on' delay='0'/>
  <mac address='52:54:00:00:00:01'/>
  <ip address='${BRIDGE_IP}' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.124.101' end='192.168.124.200'/>
    </dhcp>
  </ip>
</network>
EOF
    virsh net-define /tmp/${BRIDGE_NETWORK}.xml
    virsh net-autostart "$BRIDGE_NETWORK"
    if virsh net-start "$BRIDGE_NETWORK" 2>/dev/null; then
        echo -e "${GREEN}✅ Bridge network created and started${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not start bridge network without sudo. Trying with sudo...${NC}"
        if sudo virsh net-start "$BRIDGE_NETWORK" 2>/dev/null; then
            echo -e "${GREEN}✅ Bridge network started with sudo${NC}"
        else
            echo -e "${RED}❌ Failed to start bridge network. Please run manually: sudo virsh net-start $BRIDGE_NETWORK${NC}"
            exit 1
        fi
    fi
else
    echo -e "${GREEN}✅ Bridge network $BRIDGE_NETWORK already exists${NC}"
fi

# Ensure network is active
if ! virsh net-list --name | grep -q "^${BRIDGE_NETWORK}$"; then
    echo "Starting bridge network $BRIDGE_NETWORK..."
    if virsh net-start "$BRIDGE_NETWORK" 2>/dev/null; then
        echo -e "${GREEN}✅ Network started${NC}"
    else
        if sudo virsh net-start "$BRIDGE_NETWORK" 2>/dev/null; then
            echo -e "${GREEN}✅ Network started with sudo${NC}"
        else
            echo -e "${RED}❌ Failed to start network. Please run manually: sudo virsh net-start $BRIDGE_NETWORK${NC}"
            exit 1
        fi
    fi
else
    echo -e "${GREEN}✅ Bridge network $BRIDGE_NETWORK is active${NC}"
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
        - ${VM_STATIC_IP}/24
      gateway4: ${BRIDGE_IP}
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
    # Try alternative paths
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

# Create libvirt VM definition with network boot support
echo "Creating libvirt VM with network boot support..."
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
    <interface type='network'>
      <source network='$BRIDGE_NETWORK'/>
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
    echo -e "${YELLOW}⚠️  Could not get VM IP automatically. It should be ${VM_STATIC_IP}${NC}"
    VM_IP="${VM_STATIC_IP}"
else
    echo -e "${GREEN}✅ VM IP: $VM_IP${NC}"
fi

# Get system ID from sushy
echo ""
echo -e "${BLUE}🔍 Getting system ID from sushy-tools...${NC}"
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
echo "Cluster: $CLUSTER_NAME"
echo "VM: $VM_NAME"
echo "VM IP: $VM_IP (on bridge network 192.168.124.0/24)"
echo "Bridge Network: metal3-net (192.168.124.0/24)"
echo "Bridge Gateway: 192.168.124.1"
echo "Host IP: $HOST_IP"
echo "Ironic NodePort: $NODE_PORT"
echo "Ironic URL (from VM): https://${BRIDGE_IP}:${IRONIC_BRIDGE_PORT}"
echo "Ironic URL (from host): https://localhost:${NODE_PORT}"
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

