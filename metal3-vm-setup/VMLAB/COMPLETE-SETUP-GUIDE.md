# Complete Setup Guide: Metal3 Dev Environment on OpenStack VM

This guide provides step-by-step instructions for setting up a Metal3 development environment on an OpenStack VM, integrated with your existing 3-node RKE2 Rancher cluster.

Based on [Metal3 dev-env documentation](https://book.metal3.io/developer_environment/tryit).

## 🎯 Overview

This setup creates libvirt VMs on an OpenStack VM to simulate bare metal hosts, which your existing 3-node RKE2 Rancher cluster (with Metal3) will manage directly.

**No Kind cluster needed** - this integrates directly with your existing Rancher cluster.

## 📋 Prerequisites

### OpenStack VM Requirements

- **OS**: Ubuntu 22.04+ or CentOS 9 Stream
- **Resources**: Minimum 8 vCPU, 32GB RAM, 100GB disk (recommended: 16 vCPU, 64GB RAM)
- **Nested Virtualization**: Must be enabled (for libvirt VMs)
- **Access**: Passwordless sudo, SSH access

### Your Existing Setup

- ✅ 3-node RKE2 Rancher cluster
- ✅ Metal3 installed
- ✅ Rancher Turtles installed
- ✅ Network access to OpenStack VM

## 🚀 Step-by-Step Setup

### Step 1: Create OpenStack VM

#### 1.1 Create VM

```bash
# Create VM with adequate resources
openstack server create \
  --flavor m1.xlarge \
  --image ubuntu-22.04 \
  --key-name your-ssh-key \
  --network private \
  --security-group default \
  --tag metal3-dev-env \
  metal3-dev-vm

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
# Allow SSH
openstack security group rule create default \
  --protocol tcp --dst-port 22 --remote-ip 0.0.0.0/0

# Allow libvirt VM management ports (if needed)
# IPMI: 6230, Redfish: 8000, etc.
for port in 6230 8000 8001 8002; do
    openstack security group rule create default \
      --protocol tcp --dst-port $port --remote-ip 0.0.0.0/0
done
```

### Step 2: Setup VM for libvirt

#### 2.1 SSH to VM and Install Dependencies

```bash
# SSH to VM
ssh ubuntu@${VM_IP}

# Update system
sudo apt-get update
sudo apt-get upgrade -y

# Install libvirt and tools
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
    curl \
    wget \
    git \
    make

# Add user to libvirt group
sudo usermod -aG libvirt $USER
sudo usermod -aG kvm $USER

# Log out and back in
exit
ssh ubuntu@${VM_IP}
```

#### 2.2 Enable Nested Virtualization

```bash
# On VM, check current nested virtualization status
sudo cat /sys/module/kvm_intel/parameters/nested
# Should show: N (disabled) or Y (enabled)

# For Intel CPU
sudo vi /etc/modprobe.d/kvm.conf
# Add or uncomment:
options kvm_intel nested=1

# For AMD CPU
# options kvm_amd nested=1

# Reload module
sudo modprobe -r kvm_intel
sudo modprobe kvm_intel

# Verify
sudo cat /sys/module/kvm_intel/parameters/nested
# Should show: Y
```

#### 2.3 Configure Passwordless Sudo

```bash
# On VM
sudo visudo

# Add this line (replace 'ubuntu' with your username)
ubuntu ALL=(ALL) NOPASSWD: ALL

# Save and exit
```

#### 2.4 Start libvirt

```bash
# Start and enable libvirt
sudo systemctl enable libvirtd
sudo systemctl start libvirtd

# Verify
sudo systemctl status libvirtd
virsh list --all
```

### Step 3: Create Internal Network for libvirt VMs

#### 3.1 Create libvirt Network

```bash
# On VM, create network configuration
cat > /tmp/metallb-network.xml <<'EOF'
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

# Create and start network
sudo virsh net-define /tmp/metallb-network.xml
sudo virsh net-start metal3
sudo virsh net-autostart metal3

# Verify
sudo virsh net-list --all
```

#### 3.2 Verify Network

```bash
# Check network interface
ip addr show metal3

# Should show:
# 192.168.111.1/24
```

### Step 4: Setup BMC Simulators (IPMI/Redfish)

#### 4.1 Install BMC Simulators

```bash
# On VM, install sushy-tools (Redfish simulator)
sudo pip3 install sushy-tools

# Or install from package
sudo apt-get install -y sushy-tools

# Install virtualbmc (IPMI simulator)
sudo pip3 install virtualbmc
```

#### 4.2 Create Redfish Simulator Service

```bash
# Create systemd service for Redfish simulator
sudo tee /etc/systemd/system/sushy-emulator.service <<'EOF'
[Unit]
Description=Sushy Redfish Emulator
After=network.target

[Service]
Type=simple
User=ubuntu
ExecStart=/usr/local/bin/sushy-emulator --port 8000 --host 0.0.0.0
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Start service
sudo systemctl daemon-reload
sudo systemctl enable sushy-emulator
sudo systemctl start sushy-emulator

# Verify
sudo systemctl status sushy-emulator
curl http://localhost:8000/redfish/v1/
```

### Step 5: Create libvirt VMs (Simulated Bare Metal Hosts)

#### 5.1 Download Base Image

```bash
# On VM, create images directory
sudo mkdir -p /opt/metal3-dev-env/ironic/html/images
cd /opt/metal3-dev-env/ironic/html/images

# Download Ubuntu 22.04 cloud image (example)
wget https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img -O ubuntu-22.04.img

# Or use your custom image
# Copy your image to this directory
```

#### 5.2 Create First VM (node-0)

```bash
# On VM
sudo virt-install \
  --name node-0 \
  --ram 4096 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/node-0.qcow2,size=50,format=qcow2 \
  --network network=metal3,model=virtio \
  --os-type linux \
  --os-variant ubuntu22.04 \
  --import \
  --noautoconsole \
  --graphics vnc,listen=0.0.0.0 \
  --console pty,target_type=serial

# Or create from existing image
sudo virt-install \
  --name node-0 \
  --ram 4096 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/node-0.qcow2,size=50,format=qcow2 \
  --network network=metal3,model=virtio \
  --os-type linux \
  --os-variant ubuntu22.04 \
  --import \
  --noautoconsole \
  --disk /opt/metal3-dev-env/ironic/html/images/ubuntu-22.04.img,format=qcow2

# Verify VM created
sudo virsh list --all
```

#### 5.3 Create Additional VMs (node-1, node-2)

```bash
# Create node-1
sudo virt-install \
  --name node-1 \
  --ram 4096 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/node-1.qcow2,size=50,format=qcow2 \
  --network network=metal3,model=virtio \
  --os-type linux \
  --os-variant ubuntu22.04 \
  --import \
  --noautoconsole

# Create node-2
sudo virt-install \
  --name node-2 \
  --ram 4096 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/node-2.qcow2,size=50,format=qcow2 \
  --network network=metal3,model=virtio \
  --os-type linux \
  --os-variant ubuntu22.04 \
  --import \
  --noautoconsole

# Verify all VMs
sudo virsh list --all
```

#### 5.4 Get VM MAC Addresses

```bash
# On VM, get MAC addresses for each libvirt VM
for vm in node-0 node-1 node-2; do
    MAC=$(sudo virsh domiflist $vm | grep metal3 | awk '{print $5}')
    echo "$vm MAC: $MAC"
done
```

### Step 6: Setup BMC for libvirt VMs

#### 6.1 Setup Virtual BMC (IPMI)

```bash
# On VM, create virtual BMC for each node
# Using virtualbmc

# For node-0 (IPMI on port 6230)
vbmc add node-0 --port 6230 --username admin --password password
vbmc start node-0

# For node-1 (IPMI on port 6231)
vbmc add node-1 --port 6231 --username admin --password password
vbmc start node-1

# For node-2 (IPMI on port 6232)
vbmc add node-2 --port 6232 --username admin --password password
vbmc start node-2

# Verify
vbmc list
```

#### 6.2 Setup Redfish Simulator (Alternative)

If using Redfish instead of IPMI:

```bash
# Sushy emulator is already running on port 8000
# Configure it to manage libvirt VMs

# Create sushy config
sudo tee /etc/sushy/sushy.conf <<'EOF'
SUSHY_EMULATOR_LISTEN_IP = '0.0.0.0'
SUSHY_EMULATOR_LISTEN_PORT = 8000
SUSHY_EMULATOR_OS_CLOUD = 'metal3'
SUSHY_EMULATOR_LIBVIRT_URI = 'qemu:///system'
EOF

# Restart sushy
sudo systemctl restart sushy-emulator

# Test Redfish endpoint
curl http://localhost:8000/redfish/v1/
```

### Step 7: Configure Network Access from Rancher Cluster

#### 7.1 Get Network Information

```bash
# On OpenStack VM, get network details
VM_INTERNAL_IP=$(ip addr show | grep -E 'inet.*192\.168\.111' | awk '{print $2}' | cut -d/ -f1 || echo "192.168.111.1")
VM_EXTERNAL_IP="${VM_IP}"  # From Step 1

echo "VM Internal IP (metal3 network): $VM_INTERNAL_IP"
echo "VM External IP: $VM_EXTERNAL_IP"

# Get libvirt VM IPs
for vm in node-0 node-1 node-2; do
    VM_IP=$(sudo virsh domifaddr $vm | grep -oE '192\.168\.111\.[0-9]+' | head -1 || echo "N/A")
    echo "$vm IP: $VM_IP"
done
```

#### 7.2 Configure Security Groups

From your local machine (with OpenStack CLI):

```bash
# Set your Rancher cluster network
export RANCHER_NETWORK="10.0.0.0/8"  # Your Rancher cluster network CIDR

# Allow IPMI ports (if using IPMI)
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

# Verify rules
openstack security group rule list default -f table
```

#### 7.3 Configure Port Forwarding (If Needed)

If libvirt VMs are on internal network (192.168.111.0/24) and need to be accessible from Rancher cluster:

```bash
# On OpenStack VM, setup port forwarding
# Option 1: Use iptables (if VM has public IP)

# Forward IPMI ports
sudo iptables -t nat -A PREROUTING -p tcp --dport 6230 -j DNAT --to-destination 192.168.111.20:6230
sudo iptables -t nat -A PREROUTING -p tcp --dport 6231 -j DNAT --to-destination 192.168.111.21:6231
sudo iptables -t nat -A PREROUTING -p tcp --dport 6232 -j DNAT --to-destination 192.168.111.22:6232

# Save iptables rules
sudo iptables-save | sudo tee /etc/iptables/rules.v4
```

### Step 8: Create BareMetalHost Resources in Rancher

#### 8.1 Get BMC Information

```bash
# On OpenStack VM, get BMC addresses
VM_EXTERNAL_IP="${VM_IP}"  # Your VM's external IP

echo "BMC Addresses for BareMetalHost:"
echo ""
echo "node-0 (IPMI):"
echo "  address: ipmi://${VM_EXTERNAL_IP}:6230"
echo ""
echo "node-1 (IPMI):"
echo "  address: ipmi://${VM_EXTERNAL_IP}:6231"
echo ""
echo "node-2 (IPMI):"
echo "  address: ipmi://${VM_EXTERNAL_IP}:6232"
echo ""
echo "Or using Redfish:"
echo "  address: redfish+http://${VM_EXTERNAL_IP}:8000/redfish/v1/Systems/<system-id>"
```

#### 8.2 Create BMC Credentials in Rancher

From your Rancher cluster:

```bash
# Create BMC credentials secret
kubectl create secret generic bmc-credentials \
  --from-literal=username=admin \
  --from-literal=password=password \
  --namespace default
```

#### 8.3 Create BareMetalHost Resources

From your Rancher cluster:

```bash
# Set VM external IP
export VM_IP="192.168.1.100"  # Your OpenStack VM external IP

# Create BareMetalHost for node-0
kubectl apply -f - <<EOF
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-0
  namespace: default
spec:
  online: true
  bootMACAddress: $(ssh ubuntu@${VM_IP} "sudo virsh domiflist node-0 | grep metal3 | awk '{print \$5}'")
  bmc:
    address: ipmi://${VM_IP}:6230
    credentialsName: bmc-credentials
    disableCertificateVerification: true
  bootMode: legacy
  automatedCleaningMode: metadata
  image:
    url: http://imagecache.example.com/ubuntu-22.04.raw
    checksum: http://imagecache.example.com/ubuntu-22.04.raw.sha256
    checksumType: sha256
    format: raw
EOF

# Create BareMetalHost for node-1
kubectl apply -f - <<EOF
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-1
  namespace: default
spec:
  online: true
  bootMACAddress: $(ssh ubuntu@${VM_IP} "sudo virsh domiflist node-1 | grep metal3 | awk '{print \$5}'")
  bmc:
    address: ipmi://${VM_IP}:6231
    credentialsName: bmc-credentials
    disableCertificateVerification: true
  bootMode: legacy
  automatedCleaningMode: metadata
  image:
    url: http://imagecache.example.com/ubuntu-22.04.raw
    checksum: http://imagecache.example.com/ubuntu-22.04.raw.sha256
    checksumType: sha256
    format: raw
EOF

# Create BareMetalHost for node-2
kubectl apply -f - <<EOF
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-2
  namespace: default
spec:
  online: true
  bootMACAddress: $(ssh ubuntu@${VM_IP} "sudo virsh domiflist node-2 | grep metal3 | awk '{print \$5}'")
  bmc:
    address: ipmi://${VM_IP}:6232
    credentialsName: bmc-credentials
    disableCertificateVerification: true
  bootMode: legacy
  automatedCleaningMode: metadata
  image:
    url: http://imagecache.example.com/ubuntu-22.04.raw
    checksum: http://imagecache.example.com/ubuntu-22.04.raw.sha256
    checksumType: sha256
    format: raw
EOF
```

#### 8.4 Monitor BareMetalHosts

```bash
# From Rancher cluster
kubectl get bmh -w

# Check status
kubectl describe bmh node-0
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

### Verify BMC Access

```bash
# Test IPMI from Rancher cluster
# Install ipmitool in a pod
kubectl run -it --rm test-ipmi \
  --image=quay.io/metalkube/vbmc:latest \
  --restart=Never \
  -- ipmitool -I lanplus -U admin -P password -H ${VM_IP} -p 6230 power status

# Test Redfish
curl http://${VM_IP}:8000/redfish/v1/
```

### Verify Network Connectivity

```bash
# From Rancher cluster, test connectivity to VM
kubectl run -it --rm test-net \
  --image=nicolaka/netshoot \
  --restart=Never \
  -- nc -zv ${VM_IP} 6230
```

## 🔧 Troubleshooting

### libvirt VMs Not Starting

```bash
# Check libvirt status
sudo systemctl status libvirtd

# Check nested virtualization
cat /sys/module/kvm_intel/parameters/nested

# Check VM logs
sudo virsh dominfo node-0
sudo journalctl -u libvirtd
```

### BMC Not Accessible

```bash
# Check virtual BMC
vbmc list
vbmc show node-0

# Check ports
sudo netstat -tlnp | grep -E '6230|6231|6232|8000'

# Check firewall
sudo ufw status
```

### Network Issues

```bash
# Check libvirt network
sudo virsh net-info metal3
sudo virsh net-dhcp-leases metal3

# Check VM network
sudo virsh domiflist node-0
```

## 📊 Summary

After setup, you have:

- ✅ **OpenStack VM** with libvirt installed
- ✅ **3 libvirt VMs** (node-0, node-1, node-2) simulating bare metal
- ✅ **BMC access** via IPMI or Redfish
- ✅ **BareMetalHost resources** in Rancher cluster
- ✅ **Network connectivity** between Rancher and OpenStack VM

Your Rancher cluster can now manage these simulated bare metal hosts via Metal3!

## 📚 Additional Resources

- **Official Metal3 dev-env**: https://book.metal3.io/developer_environment/tryit
- **Network Configuration**: See `docs/NETWORK-CONFIGURATION.md`
- **Rancher Integration**: See `docs/RANCHER-INTEGRATION.md`

