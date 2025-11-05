# Network Configuration for Metal3 Dev Environment

This document explains the network architecture and configuration for connecting your existing Rancher cluster to the OpenStack VM running libvirt VMs.

## 🏗️ Network Architecture

```
┌─────────────────────────────────────────┐
│  Rancher Cluster (3-node RKE2)          │
│  Network: 10.0.0.0/8 (example)          │
│  ├── Metal3/Ironic (BMC Client)        │
│  └── BareMetalHost Controller           │
└─────────────────────────────────────────┘
              ↓ Network Access
              ├─→ IPMI: VM_IP:6230-6232
              └─→ Redfish: VM_IP:8000-8002
┌─────────────────────────────────────────┐
│  OpenStack VM (External IP)             │
│  ├── libvirt network: 192.168.111.0/24 │
│  ├── node-0 (192.168.111.20)           │
│  │   └── BMC: IPMI :6230                │
│  ├── node-1 (192.168.111.21)           │
│  │   └── BMC: IPMI :6231                │
│  └── node-2 (192.168.111.22)           │
│      └── BMC: IPMI :6232                │
└─────────────────────────────────────────┘
```

## 🔌 Network Components

### 1. Internal Network (libvirt)

**Current Setup: NAT Network** (default)

The libvirt VMs run on an internal NAT network:

- **Network Name**: `metal3`
- **Network Mode**: NAT (isolated network with gateway)
- **Network CIDR**: `192.168.111.0/24`
- **Gateway**: `192.168.111.1` (VM's libvirt bridge)
- **DHCP Range**: `192.168.111.20-192.168.111.60`
- **VM IPs**: 
  - node-0: `192.168.111.20`
  - node-1: `192.168.111.21`
  - node-2: `192.168.111.22`
- **Bridge Interface**: `metal3` (created by libvirt)

**Alternative: Bridge Network** (for direct network access)

If you want libvirt VMs to be on the same network as the OpenStack VM:

- **Network Mode**: Bridge (connects to VM's physical interface)
- **Bridge Interface**: Uses existing bridge or creates new one
- **VM IPs**: Directly on OpenStack network (via DHCP or static)
- **Access**: Direct network access without NAT/port forwarding

### 2. BMC Access

BMC simulators are exposed on the OpenStack VM's external IP:

- **IPMI**: 
  - node-0: `VM_IP:6230`
  - node-1: `VM_IP:6231`
  - node-2: `VM_IP:6232`
- **Redfish**: 
  - node-0: `VM_IP:8000`
  - node-1: `VM_IP:8001`
  - node-2: `VM_IP:8002`

### 3. External Access (Rancher → VM)

Rancher cluster needs access to:
- **BMC Ports**: 6230-6232 (IPMI) or 8000-8002 (Redfish)
- **VM External IP**: The OpenStack VM's floating IP

## 📋 Network Configuration Steps

### Step 1: Create libvirt Network

#### Option A: NAT Network (Default - Isolated)

This creates an isolated network with NAT. Libvirt VMs are on a private network (192.168.111.0/24) and access the outside via NAT.

```bash
# On OpenStack VM
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

sudo virsh net-define /tmp/metal3-network.xml
sudo virsh net-start metal3
sudo virsh net-autostart metal3

# Verify bridge was created
ip addr show metal3
# Should show: 192.168.111.1/24
```

#### Option B: Bridge Network (Direct Network Access)

This connects libvirt VMs directly to the OpenStack VM's network. VMs get IPs from your OpenStack network's DHCP.

**Prerequisites:**
- OpenStack VM must have a bridge interface (or you'll create one)
- OpenStack network must allow bridge mode (some clouds disable this)

```bash
# On OpenStack VM, first check your network interface
ip addr show
# Note the interface name (e.g., eth0, ens3, etc.)

# Get the bridge name from OpenStack (if using bridge)
# Or create a bridge yourself

# Option B1: Use existing bridge (if OpenStack provides one)
# Find the bridge interface
brctl show
# or
ip link show type bridge

# Option B2: Create bridge network in libvirt (connects to physical interface)
cat > /tmp/metal3-bridge-network.xml <<'EOF'
<network>
  <name>metal3-bridge</name>
  <uuid>d9d9d9d9-d9d9-d9d9-d9d9-d9d9d9d9d9d9</uuid>
  <forward mode='bridge'/>
  <bridge name='br0'/>
</network>
EOF

# Replace 'br0' with your actual bridge name
# If no bridge exists, you need to create one first (see below)

sudo virsh net-define /tmp/metal3-bridge-network.xml
sudo virsh net-start metal3-bridge
sudo virsh net-autostart metal3-bridge
```

**Creating a Bridge Manually (if needed):**

```bash
# On OpenStack VM
# 1. Get your physical interface name
PHYSICAL_IF=$(ip route | grep default | awk '{print $5}' | head -1)
echo "Physical interface: $PHYSICAL_IF"

# 2. Create bridge
sudo brctl addbr br0
sudo ip link set br0 up

# 3. Move IP from physical interface to bridge
CURRENT_IP=$(ip addr show $PHYSICAL_IF | grep "inet " | awk '{print $2}')
sudo ip addr del $CURRENT_IP dev $PHYSICAL_IF
sudo ip addr add $CURRENT_IP dev br0

# 4. Add physical interface to bridge
sudo brctl addif br0 $PHYSICAL_IF

# 5. Update routing (if needed)
sudo ip route del default
sudo ip route add default via $(ip route | grep default | awk '{print $3}') dev br0

# 6. Make bridge persistent (add to /etc/network/interfaces or netplan)
# For netplan (Ubuntu 18.04+):
sudo tee /etc/netplan/99-bridge-config.yaml <<EOF
network:
  version: 2
  ethernets:
    $PHYSICAL_IF:
      dhcp4: false
  bridges:
    br0:
      interfaces: [$PHYSICAL_IF]
      dhcp4: true
EOF

sudo netplan apply
```

**Note**: Bridge networks may not work in all OpenStack environments due to security restrictions. NAT network is more portable.

### Step 2: Configure Security Groups

```bash
# From your local machine (with OpenStack CLI)
export VM_IP="192.168.1.100"  # Your VM external IP
export RANCHER_NETWORK="10.0.0.0/8"  # Your Rancher cluster network

# Allow IPMI ports
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
```

### Step 3: Configure Port Forwarding (if needed)

If libvirt VMs are on internal network and need external access:

```bash
# On OpenStack VM
# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf

# Forward IPMI ports to libvirt VMs
sudo iptables -t nat -A PREROUTING -p tcp --dport 6230 -j DNAT --to-destination 192.168.111.20:6230
sudo iptables -t nat -A PREROUTING -p tcp --dport 6231 -j DNAT --to-destination 192.168.111.21:6231
sudo iptables -t nat -A PREROUTING -p tcp --dport 6232 -j DNAT --to-destination 192.168.111.22:6232

# Allow forwarding
sudo iptables -A FORWARD -p tcp -d 192.168.111.0/24 -j ACCEPT
sudo iptables -A FORWARD -p tcp -s 192.168.111.0/24 -j ACCEPT

# Save rules
sudo iptables-save | sudo tee /etc/iptables/rules.v4
```

### Step 4: Verify Network Connectivity

```bash
# From Rancher cluster, test connectivity
export VM_IP="192.168.1.100"

# Test IPMI
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

## 🔍 Network Troubleshooting

### Cannot Access BMC from Rancher

```bash
# Check security groups
openstack security group rule list default | grep -E '6230|6231|6232'

# Check ports are listening on VM
ssh ubuntu@${VM_IP} "sudo netstat -tlnp | grep -E '6230|6231|6232'"

# Check firewall
ssh ubuntu@${VM_IP} "sudo ufw status"

# Test from VM itself
ssh ubuntu@${VM_IP} "ipmitool -I lanplus -U admin -P password -H localhost -p 6230 power status"
```

### libvirt VMs Cannot Access Internet

```bash
# Check libvirt network
sudo virsh net-info metal3

# Check NAT forwarding
sudo iptables -t nat -L -n -v

# Check DNS
sudo virsh net-dumpxml metal3 | grep -A 5 '<ip'
```

### Port Forwarding Not Working

```bash
# Check iptables rules
sudo iptables -t nat -L -n -v

# Check forwarding is enabled
cat /proc/sys/net/ipv4/ip_forward

# Test connectivity from VM
curl http://localhost:6230
```

## 📝 Summary

**Network Configuration:**

1. **Internal Network**: libvirt VMs on `192.168.111.0/24`
2. **BMC Access**: Via OpenStack VM external IP on ports 6230-6232 (IPMI)
3. **Security Groups**: Allow Rancher cluster network → VM BMC ports
4. **Port Forwarding**: Optional, if needed for internal VM access

**BMC Addresses for BareMetalHost:**

- node-0: `ipmi://${VM_IP}:6230`
- node-1: `ipmi://${VM_IP}:6231`
- node-2: `ipmi://${VM_IP}:6232`

Or using Redfish:
- node-0: `redfish+http://${VM_IP}:8000/redfish/v1/Systems/<system-id>`

