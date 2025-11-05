# Bridge Network Setup for libvirt VMs

This guide explains how to configure a bridge network for libvirt VMs instead of the default NAT network. A bridge network allows libvirt VMs to be directly on the same network as the OpenStack VM.

## 🎯 When to Use Bridge Network

**Use Bridge Network when:**
- You want libvirt VMs directly accessible from your network
- You need libvirt VMs to get IPs from your OpenStack network's DHCP
- You want simpler network configuration (no NAT/port forwarding)
- Your OpenStack environment supports bridge mode

**Use NAT Network when:**
- You want isolated network for libvirt VMs
- Your OpenStack environment doesn't allow bridge mode
- You prefer the default setup (more portable)

## 🔍 Check Current Network Setup

```bash
# On OpenStack VM, check current network
ip addr show

# Check if bridge already exists
brctl show
ip link show type bridge

# Check libvirt networks
sudo virsh net-list --all
```

## 🏗️ Bridge Network Architecture

### NAT Network (Current Default)
```
OpenStack Network
    ↓
OpenStack VM (eth0: 192.168.1.100)
    ↓
libvirt bridge (metal3: 192.168.111.1)
    ↓ (NAT)
libvirt VMs (192.168.111.20-22)
```

### Bridge Network (Alternative)
```
OpenStack Network
    ↓
OpenStack VM (br0: 192.168.1.100)
    ├── libvirt VMs (192.168.1.101-103) ← Direct access
    └── Physical interface (eth0) → br0
```

## 📋 Step-by-Step Bridge Network Setup

### Step 1: Check OpenStack VM Network

```bash
# SSH to OpenStack VM
ssh ubuntu@${VM_IP}

# Check current network interface
ip addr show

# Check if using NetworkManager or netplan
if command -v nmcli &> /dev/null; then
    echo "Using NetworkManager"
    nmcli connection show
elif [ -d /etc/netplan ]; then
    echo "Using netplan"
    ls /etc/netplan/
else
    echo "Using traditional /etc/network/interfaces"
fi
```

### Step 2: Create Bridge Interface

#### Option A: Using netplan (Ubuntu 18.04+)

```bash
# Backup current config
sudo cp /etc/netplan/*.yaml /etc/netplan/backup-$(date +%Y%m%d).yaml

# Get current interface name
PHYSICAL_IF=$(ip route | grep default | awk '{print $5}' | head -1)
echo "Physical interface: $PHYSICAL_IF"

# Get current IP configuration
ip addr show $PHYSICAL_IF

# Create bridge configuration
sudo tee /etc/netplan/99-bridge-config.yaml <<EOF
network:
  version: 2
  ethernets:
    ${PHYSICAL_IF}:
      dhcp4: false
  bridges:
    br0:
      interfaces: [${PHYSICAL_IF}]
      dhcp4: true
      parameters:
        stp: true
        forward-delay: 4
EOF

# Apply configuration
sudo netplan apply

# Verify bridge
ip addr show br0
brctl show
```

#### Option B: Using NetworkManager

```bash
# Create bridge connection
sudo nmcli connection add type bridge ifname br0 con-name br0

# Add physical interface to bridge
PHYSICAL_IF=$(ip route | grep default | awk '{print $5}' | head -1)
sudo nmcli connection add type bridge-slave ifname ${PHYSICAL_IF} master br0

# Configure bridge for DHCP
sudo nmcli connection modify br0 ipv4.method auto
sudo nmcli connection up br0

# Verify
ip addr show br0
```

#### Option C: Manual Bridge Setup (Traditional)

```bash
# Install bridge utils (if not installed)
sudo apt-get install -y bridge-utils

# Get physical interface
PHYSICAL_IF=$(ip route | grep default | awk '{print $5}' | head -1)

# Get current IP
CURRENT_IP=$(ip addr show $PHYSICAL_IF | grep "inet " | awk '{print $2}')
GATEWAY=$(ip route | grep default | awk '{print $3}')

# Create bridge
sudo brctl addbr br0
sudo ip link set br0 up

# Add physical interface to bridge
sudo brctl addif br0 $PHYSICAL_IF

# Move IP to bridge
sudo ip addr del $CURRENT_IP dev $PHYSICAL_IF
sudo ip addr add $CURRENT_IP dev br0

# Update routing
sudo ip route del default
sudo ip route add default via $GATEWAY dev br0

# Make persistent (edit /etc/network/interfaces)
sudo tee -a /etc/network/interfaces <<EOF

# Bridge configuration
auto br0
iface br0 inet dhcp
    bridge_ports ${PHYSICAL_IF}
    bridge_stp off
    bridge_fd 0
    bridge_maxwait 0
EOF
```

### Step 3: Create libvirt Bridge Network

```bash
# Create bridge network XML
cat > /tmp/metal3-bridge-network.xml <<'EOF'
<network>
  <name>metal3-bridge</name>
  <uuid>d9d9d9d9-d9d9-d9d9-d9d9-d9d9d9d9d9d9</uuid>
  <forward mode='bridge'/>
  <bridge name='br0'/>
</network>
EOF

# Replace 'br0' with your actual bridge name if different
# Edit the file if needed:
# sed -i 's/br0/your-bridge-name/g' /tmp/metal3-bridge-network.xml

# Define and start network
sudo virsh net-define /tmp/metal3-bridge-network.xml
sudo virsh net-start metal3-bridge
sudo virsh net-autostart metal3-bridge

# Verify
sudo virsh net-list --all
sudo virsh net-info metal3-bridge
```

### Step 4: Update Existing libvirt VMs to Use Bridge

If you already created VMs with NAT network, update them:

```bash
# Stop VMs
sudo virsh shutdown node-0
sudo virsh shutdown node-1
sudo virsh shutdown node-2

# Wait for shutdown
sleep 10

# Update network interface for each VM
for vm in node-0 node-1 node-2; do
    # Remove old interface
    sudo virsh detach-interface $vm --type network --config
    
    # Add new interface on bridge
    sudo virsh attach-interface $vm \
        --type network \
        --source metal3-bridge \
        --model virtio \
        --config
done

# Start VMs
sudo virsh start node-0
sudo virsh start node-1
sudo virsh start node-2

# Wait for VMs to get IPs
sleep 20

# Check VM IPs (now on your network)
sudo virsh domifaddr node-0
sudo virsh domifaddr node-1
sudo virsh domifaddr node-2
```

### Step 5: Create New VMs with Bridge Network

If creating new VMs:

```bash
# Create VM with bridge network
sudo virt-install \
  --name node-0 \
  --ram 4096 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/node-0.qcow2,format=qcow2 \
  --network network=metal3-bridge,model=virtio \
  --os-type linux \
  --os-variant ubuntu22.04 \
  --import \
  --noautoconsole \
  --graphics none \
  --console pty,target_type=serial

# VMs will get IPs from your OpenStack network's DHCP
```

### Step 6: Update BMC Configuration

With bridge network, libvirt VMs are directly accessible:

```bash
# Get VM IPs (now on your network, not 192.168.111.x)
NODE_0_IP=$(sudo virsh domifaddr node-0 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
NODE_1_IP=$(sudo virsh domifaddr node-1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
NODE_2_IP=$(sudo virsh domifaddr node-2 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)

echo "Node-0 IP: $NODE_0_IP"
echo "Node-1 IP: $NODE_1_IP"
echo "Node-2 IP: $NODE_2_IP"

# Option 1: Use VM IPs directly for BMC (if BMC is on each VM)
# Option 2: Keep using OpenStack VM IP with port forwarding (current setup)
# Option 3: Use OpenStack VM IP if virtual BMC is still on the VM
```

**If using virtual BMC on OpenStack VM (current setup):**
- BMC addresses remain the same: `ipmi://${VM_IP}:6230-6232`
- No changes needed to BareMetalHost resources

**If BMC is on each libvirt VM:**
- Update BareMetalHost BMC addresses to use libvirt VM IPs:
  - `ipmi://${NODE_0_IP}:6230`
  - `ipmi://${NODE_1_IP}:6231`
  - `ipmi://${NODE_2_IP}:6232`

### Step 7: Update Security Groups

```bash
# From local machine, update security groups
# If libvirt VMs are directly accessible, you may need to allow their IPs

# Or if still using OpenStack VM IP for BMC, no changes needed
```

## 🔍 Verification

### Verify Bridge

```bash
# On OpenStack VM
ip addr show br0
brctl show

# Check libvirt network
sudo virsh net-info metal3-bridge
```

### Verify VM Network Access

```bash
# Check VM IPs
sudo virsh domifaddr node-0
sudo virsh domifaddr node-1
sudo virsh domifaddr node-2

# Test connectivity from Rancher cluster
# VMs should now be directly accessible (if on same network)
kubectl run -it --rm test-net \
  --image=nicolaka/netshoot \
  --restart=Never \
  -- ping -c 3 ${NODE_0_IP}
```

### Verify BMC Access

```bash
# Test BMC (if using OpenStack VM IP, unchanged)
ipmitool -I lanplus -U admin -P password -H ${VM_IP} -p 6230 power status

# Or test from Rancher cluster
kubectl run -it --rm test-ipmi \
  --image=quay.io/metalkube/vbmc:latest \
  --restart=Never \
  -- ipmitool -I lanplus -U admin -P password -H ${VM_IP} -p 6230 power status
```

## 🔧 Troubleshooting

### Bridge Not Working

```bash
# Check bridge status
ip link show br0

# Check bridge ports
brctl show br0

# Check libvirt network
sudo virsh net-info metal3-bridge
```

### VMs Not Getting IPs

```bash
# Check DHCP on your network
# Verify bridge is on correct network

# Check VM network interface
sudo virsh domiflist node-0

# Check network connectivity
sudo virsh domifaddr node-0
```

### OpenStack Network Restrictions

Some OpenStack environments don't allow bridge mode:
- Check OpenStack security groups
- Check if bridge mode is enabled in OpenStack
- May need to use NAT network instead

## 📝 Summary

**Bridge Network Benefits:**
- ✅ Direct network access to libvirt VMs
- ✅ VMs get IPs from your network's DHCP
- ✅ Simpler network topology (no NAT)
- ✅ Direct access from Rancher cluster (if on same network)

**Bridge Network Considerations:**
- ⚠️ May not work in all OpenStack environments
- ⚠️ Requires bridge configuration on OpenStack VM
- ⚠️ More complex setup than NAT
- ⚠️ Security groups may need updates

**Recommendation:**
- Start with **NAT network** (default) - simpler and more portable
- Use **Bridge network** only if you need direct VM access or OpenStack supports it

