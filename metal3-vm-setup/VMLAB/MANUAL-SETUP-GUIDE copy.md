# Manual Setup Guide: Metal3 Dev Environment on OpenStack VM

This guide provides **completely manual** step-by-step instructions for setting up a Metal3 development environment on an OpenStack VM, integrated with your existing 3-node RKE2 Rancher cluster.

**No scripts required** - all commands are run manually.

## 🎯 Overview

This manual guide will help you:
1. Create and configure an OpenStack VM
2. Install libvirt and dependencies manually
3. Create libvirt network with NAT bridge (default setup)
4. Create libvirt VMs (simulated bare metal hosts)
5. Setup BMC simulators (IPMI/Redfish)
6. Configure network access from your Rancher cluster
7. Create BareMetalHost resources in Rancher

**Network Setup**: Uses NAT network with libvirt-managed bridge interface (`metal3`). This is the default and recommended setup. For bridge network alternative, see `BRIDGE-NETWORK-SETUP.md`.

## 📋 Prerequisites

- **Existing Rancher cluster** (3-node RKE2) with Metal3 and Turtles installed
- **OpenStack access** to create VMs
- **OpenStack CLI** installed locally
- **SSH access** to OpenStack VMs
- **Network connectivity** between Rancher cluster and OpenStack VM

## 🚀 Step-by-Step Manual Setup

### Step 1: Create OpenStack VM

#### 1.1 Create VM

```bash
# Create VM with adequate resources for nested virtualization
openstack server create \
  --flavor m1.xlarge \
  --image ubuntu-22.04 \
  --key-name your-ssh-key \
  --network private \
  --security-group default \
  --tag metal3-dev-env \
  metal3-dev-vm

# Wait for VM to be created
sleep 10

# Assign floating IP
FLOATING_IP=$(openstack floating ip create public -f value -c floating_ip_address)
openstack server add floating ip metal3-dev-vm $FLOATING_IP

# Get VM IP
VM_IP=$(openstack server show metal3-dev-vm -f value -c addresses | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
echo "VM IP: $VM_IP"
export VM_IP
```

#### 1.2 Configure Security Groups

```bash
# Allow SSH access
openstack security group rule create default \
  --protocol tcp --dst-port 22 --remote-ip 0.0.0.0/0

# Allow IPMI ports (for BMC access)
for port in 6230 6231 6232; do
    openstack security group rule create default \
      --protocol tcp --dst-port $port --remote-ip 0.0.0.0/0 \
      --description "IPMI port for node-$((port-6230))"
done

# Allow Redfish ports (optional, if using Redfish)
for port in 8000 8001 8002; do
    openstack security group rule create default \
      --protocol tcp --dst-port $port --remote-ip 0.0.0.0/0 \
      --description "Redfish port for node-$((port-8000))"
done
```

### Step 2: SSH to VM and Install Dependencies

#### 2.1 SSH to VM

```bash
# Wait for VM to be ready
sleep 30

# SSH to VM
ssh ubuntu@${VM_IP}
```

#### 2.2 Update System

```bash
# Update package list
sudo apt-get update

# Upgrade system
sudo apt-get upgrade -y

# Install basic tools
sudo apt-get install -y \
    curl \
    wget \
    git \
    vim \
    make \
    build-essential
```

#### 2.3 Install libvirt and Dependencies

```bash
# Install libvirt and virtualization tools
sudo apt-get install -y \
    qemu-kvm \
    libvirt-daemon-system \
    libvirt-clients \
    virt-manager \
    bridge-utils \
    virtinst \
    libvirt-dev \
    python3-libvirt \
    python3-pip \
    ipmitool \
    qemu-utils

# Add user to libvirt and kvm groups
sudo usermod -aG libvirt $USER
sudo usermod -aG kvm $USER

# Verify groups
groups
```

#### 2.4 Log Out and Back In

```bash
# Log out to apply group changes
exit

# SSH back in
ssh ubuntu@${VM_IP}

# Verify libvirt is accessible
virsh list --all
```

#### 2.5 Enable and Start libvirt

```bash
# Enable libvirt service
sudo systemctl enable libvirtd
sudo systemctl start libvirtd

# Verify libvirt is running
sudo systemctl status libvirtd

# Check libvirt version
virsh version
```

### Step 3: Enable Nested Virtualization

#### 3.1 Check Current Status

```bash
# Check if nested virtualization is enabled
cat /sys/module/kvm_intel/parameters/nested 2>/dev/null || \
cat /sys/module/kvm_amd/parameters/nested 2>/dev/null

# Should show: N (disabled) or Y (enabled)
```

#### 3.2 Enable Nested Virtualization

```bash
# Check CPU type
lscpu | grep "Model name"

# For Intel CPU
if grep -q "Intel" <<< "$(lscpu | grep 'Model name')"; then
    echo "Detected Intel CPU"
    
    # Create/modify kvm configuration
    sudo mkdir -p /etc/modprobe.d
    echo "options kvm_intel nested=1" | sudo tee /etc/modprobe.d/kvm.conf
    
    # Reload module
    sudo modprobe -r kvm_intel
    sudo modprobe kvm_intel
    
    # Verify
    cat /sys/module/kvm_intel/parameters/nested
    # Should show: Y
fi

# For AMD CPU
if grep -q "AMD" <<< "$(lscpu | grep 'Model name')"; then
    echo "Detected AMD CPU"
    
    # Create/modify kvm configuration
    sudo mkdir -p /etc/modprobe.d
    echo "options kvm_amd nested=1" | sudo tee /etc/modprobe.d/kvm.conf
    
    # Reload module
    sudo modprobe -r kvm_amd
    sudo modprobe kvm_amd
    
    # Verify
    cat /sys/module/kvm_amd/parameters/nested
    # Should show: Y
fi
```

**Note**: If nested virtualization doesn't enable, you may need to reboot the VM:
```bash
sudo reboot
# Wait for reboot, then SSH back in
ssh ubuntu@${VM_IP}
```

### Step 4: Configure Passwordless Sudo

```bash
# Edit sudoers file
sudo visudo

# Add this line at the end (replace 'ubuntu' with your username):
ubuntu ALL=(ALL) NOPASSWD: ALL

# Save and exit (Ctrl+X, then Y, then Enter in nano)
# Or in vi: :wq
```

### Step 5: Create libvirt Network (NAT Network - Default)

This creates a NAT network with a libvirt-managed bridge interface. The bridge `metal3` is automatically created by libvirt.

#### 5.1 Create Network Configuration

```bash
# Create network XML file
# This creates a NAT network with bridge interface 'metal3'
cat > /tmp/metal3-network.xml <<'EOF'
<network>
  <name>metal3</name>
  <uuid>c8c8c8c8-c8c8-c8c8-c8c8-c8c8c8c8c8c8</uuid>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='metal3' stp='on' delay='0'/>
  <ip address='192.168.111.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.111.20' end='192.168.111.60'/>
    </dhcp>
  </ip>
</network>
EOF
```

**Note**: This creates:
- A bridge interface named `metal3` (automatically by libvirt)
- NAT network on 192.168.111.0/24
- Libvirt VMs will be on this isolated network
- Bridge is accessible via `ip addr show metal3`

#### 5.2 Define and Start Network

```bash
# Define network
sudo virsh net-define /tmp/metal3-network.xml

# Start network (this creates the bridge interface automatically)
sudo virsh net-start metal3

# Enable autostart
sudo virsh net-autostart metal3

# Verify network
sudo virsh net-list --all

# Check network details
sudo virsh net-info metal3

# Verify bridge interface was created
ip addr show metal3
# Should show: 192.168.111.1/24

# Check bridge interface details
brctl show metal3
# or
ip link show metal3
```

### Step 6: Download Base Image for libvirt VMs

#### 6.1 Create Images Directory

```bash
# Create directory for images
sudo mkdir -p /opt/metal3-dev-env/ironic/html/images
cd /opt/metal3-dev-env/ironic/html/images
```

#### 6.2 Download Ubuntu Cloud Image

```bash
# Download Ubuntu 22.04 cloud image
wget https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img -O ubuntu-22.04.img

# Or use Ubuntu 22.04
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img -O ubuntu-22.04.img

# Verify download
ls -lh ubuntu-22.04.img
```

#### 6.3 (Optional) Use Custom Image

If you have a custom image:

```bash
# Copy your custom image to the images directory
# sudo cp /path/to/your/image.raw /opt/metal3-dev-env/ironic/html/images/ubuntu-22.04.img
```

### Step 7: Create libvirt VMs

#### 7.1 Create VM Disk Images

```bash
# Create disk images directory
sudo mkdir -p /var/lib/libvirt/images

# Create disk image for node-0
sudo qemu-img create -f qcow2 -F qcow2 \
  -b /opt/metal3-dev-env/ironic/html/images/ubuntu-22.04.img \
  /var/lib/libvirt/images/node-0.qcow2 50G

# Create disk image for node-1
sudo qemu-img create -f qcow2 -F qcow2 \
  -b /opt/metal3-dev-env/ironic/html/images/ubuntu-22.04.img \
  /var/lib/libvirt/images/node-1.qcow2 50G

# Create disk image for node-2
sudo qemu-img create -f qcow2 -F qcow2 \
  -b /opt/metal3-dev-env/ironic/html/images/ubuntu-22.04.img \
  /var/lib/libvirt/images/node-2.qcow2 50G

# Verify disk images
ls -lh /var/lib/libvirt/images/
```

#### 7.2 Create VM (node-0)

```bash
# Create node-0 VM
sudo virt-install \
  --name node-0 \
  --ram 4096 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/node-0.qcow2,format=qcow2 \
  --network network=metal3,model=virtio \
  --os-type linux \
  --os-variant ubuntu22.04 \
  --import \
  --noautoconsole \
  --graphics none \
  --console pty,target_type=serial

# Verify VM was created
sudo virsh list --all
```

#### 7.3 Create VM (node-1)

```bash
# Create node-1 VM
sudo virt-install \
  --name node-1 \
  --ram 4096 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/node-1.qcow2,format=qcow2 \
  --network network=metal3,model=virtio \
  --os-type linux \
  --os-variant ubuntu22.04 \
  --import \
  --noautoconsole \
  --graphics none \
  --console pty,target_type=serial

# Verify
sudo virsh list --all
```

#### 7.4 Create VM (node-2)

```bash
# Create node-2 VM
sudo virt-install \
  --name node-2 \
  --ram 4096 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/node-2.qcow2,format=qcow2 \
  --network network=metal3,model=virtio \
  --os-type linux \
  --os-variant ubuntu22.04 \
  --import \
  --noautoconsole \
  --graphics none \
  --console pty,target_type=serial

# Verify all VMs
sudo virsh list --all
```

#### 7.5 Get VM MAC Addresses

```bash
# Get MAC address for node-0
sudo virsh domiflist node-0

# Get MAC address for node-1
sudo virsh domiflist node-1

# Get MAC address for node-2
sudo virsh domiflist node-2

# Save MAC addresses (you'll need these for BareMetalHost)
# Example output:
# node-0 MAC: 52:54:00:xx:xx:xx
# node-1 MAC: 52:54:00:yy:yy:yy
# node-2 MAC: 52:54:00:zz:zz:zz
```

#### 7.6 Get VM IPs (Optional - Not Required for BMC Access)

> **Important**: VM IPs are NOT needed for BMC access or BareMetalHost creation. BMC simulators run on the OpenStack VM itself, so you access them via the OpenStack VM's IP (e.g., `192.168.1.100:6230`), not the libvirt VM IPs. You only need MAC addresses (from Step 7.5).

**If using DHCP** (default NAT network setup):
```bash
# Wait a moment for VMs to get IPs
sleep 10

# Check DHCP leases
sudo virsh net-dhcp-leases metal3

# Should show IPs like:
# 192.168.111.20 for node-0
# 192.168.111.21 for node-1
# 192.168.111.22 for node-2
```

**If NOT using DHCP** (static IPs or no IPs assigned):
```bash
# VMs may not have IPs yet - that's OK!
# You only need MAC addresses for BareMetalHost (from Step 7.5)

# To check if VMs have IPs:
for vm in node-0 node-1 node-2; do
    VM_IP=$(sudo virsh domifaddr $vm 2>/dev/null | grep -oE '192\.168\.111\.[0-9]+' | head -1 || echo "No IP assigned")
    echo "$vm IP: $VM_IP"
done

# If VMs don't have IPs and you need them:
# See docs/STATIC-IP-CONFIGURATION.md for how to configure static IPs
```

**What You Actually Need for Metal3:**
- ✅ **MAC addresses** (from Step 7.5) - for BareMetalHost `bootMACAddress`
- ✅ **OpenStack VM IP** - for BMC address (e.g., `ipmi://192.168.1.100:6230`)
- ❌ **Libvirt VM IPs** - NOT needed for BMC access

### Step 8: Install and Setup BMC Simulators

#### 8.1 Install virtualbmc (IPMI Simulator)

```bash
# Install virtualbmc
sudo pip3 install virtualbmc

# Verify installation
vbmc --version
```

#### 8.2 Create Virtual BMC for Each VM

```bash
# Create virtual BMC for node-0 (port 6230)
vbmc add node-0 --port 6230 --username admin --password password

# Create virtual BMC for node-1 (port 6231)
vbmc add node-1 --port 6231 --username admin --password password

# Create virtual BMC for node-2 (port 6232)
vbmc add node-2 --port 6232 --username admin --password password

# Start virtual BMCs
vbmc start node-0
vbmc start node-1
vbmc start node-2

# Verify virtual BMCs
vbmc list

# Should show all three VMs with status "running"
```

#### 8.3 (Optional) Install and Setup Redfish Simulator

```bash
# Install sushy-tools (Redfish simulator)
sudo pip3 install sushy-tools

# Or install from package
sudo apt-get install -y sushy-tools

# Create systemd service for sushy
sudo tee /etc/systemd/system/sushy-emulator.service <<'EOF'
[Unit]
Description=Sushy Redfish Emulator
After=network.target libvirtd.service

[Service]
Type=simple
User=ubuntu
Environment="SUSHY_EMULATOR_LISTEN_IP=0.0.0.0"
Environment="SUSHY_EMULATOR_LISTEN_PORT=8000"
Environment="SUSHY_EMULATOR_OS_CLOUD=metal3"
Environment="SUSHY_EMULATOR_LIBVIRT_URI=qemu:///system"
ExecStart=/usr/local/bin/sushy-emulator
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Start sushy service
sudo systemctl daemon-reload
sudo systemctl enable sushy-emulator
sudo systemctl start sushy-emulator

# Verify sushy is running
sudo systemctl status sushy-emulator

# Test Redfish endpoint
curl http://localhost:8000/redfish/v1/
```

### Step 9: Configure Network Access from Rancher Cluster

#### 9.1 Get Rancher Cluster Network

```bash
# From your Rancher cluster, get the network CIDR
# Example: 10.0.0.0/8 or 192.168.0.0/16
# Set this variable
export RANCHER_NETWORK="10.0.0.0/8"  # Replace with your actual network
```

#### 9.2 Configure Security Groups (from Local Machine)

```bash
# From your local machine (with OpenStack CLI)
export VM_IP="192.168.1.100"  # Your OpenStack VM IP
export RANCHER_NETWORK="10.0.0.0/8"  # Your Rancher cluster network

# Allow IPMI ports from Rancher cluster
for port in 6230 6231 6232; do
    openstack security group rule create default \
      --protocol tcp \
      --dst-port $port \
      --remote-ip "$RANCHER_NETWORK" \
      --description "IPMI for node-$((port-6230))"
done

# Allow Redfish ports (if using Redfish)
for port in 8000 8001 8002; do
    openstack security group rule create default \
      --protocol tcp \
      --dst-port $port \
      --remote-ip "$RANCHER_NETWORK" \
      --description "Redfish for node-$((port-8000))"
done

# Verify security group rules
openstack security group rule list default -f table
```

#### 9.3 Test BMC Access from Rancher Cluster

```bash
# From your Rancher cluster, test IPMI access
# Install ipmitool in a pod
kubectl run -it --rm test-ipmi \
  --image=quay.io/metalkube/vbmc:latest \
  --restart=Never \
  -- ipmitool -I lanplus -U admin -P password -H ${VM_IP} -p 6230 power status

# Test network connectivity
kubectl run -it --rm test-net \
  --image=nicolaka/netshoot \
  --restart=Never \
  -- nc -zv ${VM_IP} 6230
```

### Step 9.5: Setup Image Server (HTTP Server)

Metal3/Ironic needs to download images via HTTP. Set up an HTTP server on the OpenStack VM to serve the images.

```bash
# On OpenStack VM
cd /opt/metal3-dev-env/ironic/html/images

# Generate checksum file
sha256sum ubuntu-22.04.img > ubuntu-22.04.img.sha256

# Start simple HTTP server on port 8080
# Option 1: Run in background
nohup python3 -m http.server 8080 > /tmp/image-server.log 2>&1 &

# Option 2: Create systemd service (recommended for persistence)
sudo tee /etc/systemd/system/image-server.service <<'EOF'
[Unit]
Description=Image Server for Metal3
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/metal3-dev-env/ironic/html/images
ExecStart=/usr/bin/python3 -m http.server 8080
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable image-server
sudo systemctl start image-server

# Verify server is running
curl http://localhost:8080/ubuntu-22.04.img.sha256

# Configure security group to allow access from Rancher cluster
# (From your local machine with OpenStack CLI)
export VM_IP="192.168.1.100"
export RANCHER_NETWORK="10.0.0.0/8"
openstack security group rule create default \
  --protocol tcp \
  --dst-port 8080 \
  --remote-ip "$RANCHER_NETWORK" \
  --description "Image server for Metal3"
```

**Image URLs for BareMetalHost:**
- Image URL: `http://${VM_IP}:8080/ubuntu-22.04.img`
- Checksum URL: `http://${VM_IP}:8080/ubuntu-22.04.img.sha256`

See `docs/IMAGE-SERVER-SETUP.md` for more details and alternative setups (Nginx, etc.).

### Step 10: Create BareMetalHost Resources in Rancher

#### 10.1 Get Required Information

From the OpenStack VM, collect:
- **VM External IP**: `${VM_IP}` (your OpenStack VM floating IP)
- **MAC Addresses**: From Step 7.5
- **BMC Ports**: 6230, 6231, 6232

#### 10.2 Create BMC Credentials Secret

```bash
# From your Rancher cluster
kubectl create secret generic bmc-credentials \
  --from-literal=username=admin \
  --from-literal=password=password \
  --namespace default

# Verify
kubectl get secret bmc-credentials -n default
```

#### 10.3 Create BareMetalHost for node-0

```bash
# From your Rancher cluster
export VM_IP="192.168.1.100"  # Your OpenStack VM IP
export NODE_0_MAC="52:54:00:xx:xx:xx"  # Replace with actual MAC from Step 7.5

kubectl apply -f - <<EOF
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-0
  namespace: default
spec:
  online: true
  bootMACAddress: ${NODE_0_MAC}
  bmc:
    address: ipmi://${VM_IP}:6230
    credentialsName: bmc-credentials
    disableCertificateVerification: true
  bootMode: legacy
  automatedCleaningMode: metadata
  image:
    url: http://${VM_IP}:8080/ubuntu-22.04.img
    checksum: http://${VM_IP}:8080/ubuntu-22.04.img.sha256
    checksumType: sha256
    format: raw
EOF
```

#### 10.4 Create BareMetalHost for node-1

```bash
# From your Rancher cluster
export VM_IP="192.168.1.100"  # Your OpenStack VM IP
export NODE_1_MAC="52:54:00:yy:yy:yy"  # Replace with actual MAC from Step 7.5

kubectl apply -f - <<EOF
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-1
  namespace: default
spec:
  online: true
  bootMACAddress: ${NODE_1_MAC}
  bmc:
    address: ipmi://${VM_IP}:6231
    credentialsName: bmc-credentials
    disableCertificateVerification: true
  bootMode: legacy
  automatedCleaningMode: metadata
  image:
    url: http://${VM_IP}:8080/ubuntu-22.04.img
    checksum: http://${VM_IP}:8080/ubuntu-22.04.img.sha256
    checksumType: sha256
    format: raw
EOF
```

#### 10.5 Create BareMetalHost for node-2

```bash
# From your Rancher cluster
export VM_IP="192.168.1.100"  # Your OpenStack VM IP
export NODE_2_MAC="52:54:00:zz:zz:zz"  # Replace with actual MAC from Step 7.5

kubectl apply -f - <<EOF
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-2
  namespace: default
spec:
  online: true
  bootMACAddress: ${NODE_2_MAC}
  bmc:
    address: ipmi://${VM_IP}:6232
    credentialsName: bmc-credentials
    disableCertificateVerification: true
  bootMode: legacy
  automatedCleaningMode: metadata
  image:
    url: http://${VM_IP}:8080/ubuntu-22.04.img
    checksum: http://${VM_IP}:8080/ubuntu-22.04.img.sha256
    checksumType: sha256
    format: raw
EOF
```

### Step 11: Monitor BareMetalHost Status

```bash
# From your Rancher cluster
# Watch BareMetalHost status
kubectl get bmh -w

# Check detailed status
kubectl describe bmh node-0

# Check Metal3 operator logs
kubectl logs -n metal3-system -l app.kubernetes.io/name=metal3-baremetal-operator | tail -50

# Check Ironic logs
kubectl logs -n metal3-system -l app.kubernetes.io/name=metal3-ironic | tail -50
```

## 🔍 Verification

### Verify libvirt VMs

```bash
# On OpenStack VM
sudo virsh list --all

# Check VM details
sudo virsh dominfo node-0
sudo virsh domiflist node-0
```

### Verify Virtual BMC

```bash
# On OpenStack VM
vbmc list

# Test IPMI locally
ipmitool -I lanplus -U admin -P password -H localhost -p 6230 power status
```

### Verify Network

```bash
# On OpenStack VM
sudo virsh net-info metal3
sudo virsh net-dhcp-leases metal3

# Check ports are listening
sudo netstat -tlnp | grep -E '6230|6231|6232'
```

### Verify BareMetalHosts

```bash
# From Rancher cluster
kubectl get bmh

# Should show:
# NAME     STATUS   STATE       CONSUMER   BMC                    ONLINE   ERROR
# node-0   OK       available              ipmi://...:6230        true     
# node-1   OK       available              ipmi://...:6231        true     
# node-2   OK       available              ipmi://...:6232         true     
```

## 🔧 Troubleshooting

### libvirt VMs Not Starting

```bash
# Check libvirt status
sudo systemctl status libvirtd

# Check VM logs
sudo virsh dominfo node-0
sudo journalctl -u libvirtd | tail -50

# Check nested virtualization
cat /sys/module/kvm_intel/parameters/nested
# Should show: Y
```

### Virtual BMC Not Working

```bash
# Check virtual BMC status
vbmc list

# Check virtual BMC details
vbmc show node-0

# Restart virtual BMC
vbmc stop node-0
vbmc start node-0

# Check ports
sudo netstat -tlnp | grep 6230
```

### BareMetalHost Stuck in Registering

```bash
# Check BMC connectivity from Rancher cluster
kubectl run -it --rm test-bmc \
  --image=nicolaka/netshoot \
  --restart=Never \
  -- nc -zv ${VM_IP} 6230

# Check Metal3 operator logs
kubectl logs -n metal3-system -l app.kubernetes.io/name=metal3-baremetal-operator | grep node-0

# Check BareMetalHost events
kubectl describe bmh node-0 | grep -A 10 Events
```

### Network Issues

```bash
# Check libvirt network
sudo virsh net-info metal3

# Check firewall
sudo ufw status

# Check security groups (from local machine)
openstack security group rule list default | grep -E '6230|6231|6232'
```

## 📝 Summary

After completing this manual setup:

- ✅ **OpenStack VM** created and configured
- ✅ **libvirt** installed and configured
- ✅ **3 libvirt VMs** created (node-0, node-1, node-2)
- ✅ **Virtual BMC** configured for each VM
- ✅ **Network access** configured from Rancher cluster
- ✅ **BareMetalHost resources** created in Rancher cluster

Your Rancher cluster can now manage these simulated bare metal hosts via Metal3!

## 📚 Additional Resources

- **Complete Setup Guide**: See `docs/COMPLETE-SETUP-GUIDE.md` (with scripts)
- **Network Configuration**: See `docs/NETWORK-CONFIGURATION.md`
- **Rancher Integration**: See `docs/RANCHER-INTEGRATION.md`
- **Official Metal3 dev-env**: https://book.metal3.io/developer_environment/tryit

