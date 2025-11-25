# OpenStack VM Bridge Network Configuration Guide

## Overview

You have an OpenStack VM at **10.2.83.180** and want to:
- Create a bridge network for KVM VMs
- Use IPs **10.2.83.181, 182, 183** on the bridge
- Allow KVM VMs to reach gateway **10.2.83.1**

## Complete Manual Configuration Process

Follow these steps in order:

0. **Configure OpenStack** (Step 0)
   - Add allowed address pairs for bridge IPs (10.2.83.181, 182, 183)
   - Verify OpenStack port configuration

1. **Identify Components** (Step 1)
   - Find your physical network interface name
   - Verify host can reach gateway (10.2.83.1)
   - Check if bridge already exists

2. **Create Bridge** (Step 2)
   - Create netplan configuration file
   - Configure bridge with IPs 181, 182, 183
   - Apply netplan configuration

3. **Verify Bridge** (Step 3)
   - Check bridge is UP
   - Verify bridge has correct IPs
   - Test gateway connectivity from bridge

4. **Enable IP Forwarding** (Step 4)
   - Check current status
   - Enable temporarily
   - Enable permanently in sysctl.conf

5. **Configure NAT Rules** (Step 5)
   - Check existing iptables rules
   - Add NAT masquerade rule
   - Add forwarding rules
   - Save rules permanently

6. **Configure Firewall** (Step 6)
   - Check if UFW or firewalld is active
   - Allow bridge traffic

7. **Configure KVM** (Step 7)
   - Create libvirt bridge network
   - Configure VMs to use bridge

8. **Test Everything** (Diagnostic Commands section)
   - Test from host
   - Test from KVM VM
   - Troubleshoot any issues

## Step 0: Configure OpenStack Allowed Address Pairs

**Important**: Before configuring the bridge, ensure OpenStack allows the bridge IPs to be used.

### What Are Allowed Address Pairs?

OpenStack by default only allows a VM to send traffic with its assigned IP address. When you create a bridge with additional IPs (10.2.83.181, 182, 183), OpenStack needs to be told these IPs are allowed, otherwise traffic from these IPs will be dropped at the OpenStack network level.

### Check Current Allowed Address Pairs

1. **Find your VM's port ID**:
   ```bash
   # From OpenStack control node or with OpenStack CLI access
   openstack port list --server <vm-name>
   # Or
   openstack port list | grep "10.2.83.180"
   ```

2. **Check current allowed address pairs**:
   ```bash
   openstack port show <port-id> -c allowed_address_pairs
   ```

### Add Allowed Address Pairs

1. **Add the bridge IPs as allowed address pairs**:
   ```bash
   openstack port set <port-id> \
     --allowed-address ip-address=10.2.83.181 \
     --allowed-address ip-address=10.2.83.182 \
     --allowed-address ip-address=10.2.83.183
   ```

   Or add all at once:
   ```bash
   openstack port set <port-id> \
     --allowed-address ip-address=10.2.83.181 \
     --allowed-address ip-address=10.2.83.182 \
     --allowed-address ip-address=10.2.83.183
   ```

2. **Verify they were added**:
   ```bash
   openstack port show <port-id> -c allowed_address_pairs -f json
   ```

   Should show:
   ```json
   {
     "allowed_address_pairs": [
       {"ip_address": "10.2.83.180"},
       {"ip_address": "10.2.83.181"},
       {"ip_address": "10.2.83.182"},
       {"ip_address": "10.2.83.183"}
     ]
   }
   ```

### Alternative: Via OpenStack Dashboard

1. Navigate to **Network** → **Ports**
2. Find the port for your VM (the one with 10.2.83.180)
3. Click **Edit Port**
4. Scroll to **Allowed Address Pairs**
5. Click **+ Add Allowed Address Pair**
6. Add each IP: 10.2.83.181, 10.2.83.182, 10.2.83.183
7. Click **Save**

### Why This Matters

Without allowed address pairs:
- Bridge IPs may be configured on the VM
- Traffic from bridge IPs will be dropped by OpenStack
- KVM VMs using bridge IPs won't be able to communicate
- Gateway connectivity will fail even if everything else is correct

**This is often the root cause of "can't reach gateway" issues when bridge IPs are involved.**

## Step 1: Identify Your Network Components

### Find Your Physical Interface

```bash
# List all network interfaces
ip link show

# Or
ip addr show

# Common interface names:
# - eth0, eth1 (traditional)
# - ens3, ens4 (systemd predictable naming)
# - enp1s0, enp2s0 (PCI-based naming)
```

**What to look for**: The interface that has your current IP (10.2.83.180)

### Check Current Network Configuration

```bash
# See current IP configuration
ip addr show

# See current routes
ip route show

# Check if you can reach the gateway
ping -c 3 10.2.83.1
```

**Important**: If you can't ping the gateway from the host, the bridge won't help - fix the host network first.

### Check if Bridge Already Exists

```bash
# List all bridges
ip link show type bridge

# Or check for specific bridge
ip link show br0

# See what's connected to bridges
bridge link show
```

## Step 2: Create Netplan Bridge Configuration

### Step 2.1: Create Netplan Configuration File

1. **Create the file**:
   ```bash
   sudo nano /etc/netplan/99-kvm-bridge.yaml
   ```

2. **Write the configuration** (replace `eth0` with your interface name from Step 1):
   ```yaml
   network:
     version: 2
     renderer: networkd
     ethernets:
       eth0:  # REPLACE with your actual interface name from Step 1
         dhcp4: false
         dhcp6: false
         addresses:
           - 10.2.83.180/24
         gateway4: 10.2.83.1
         nameservers:
           addresses:
             - 8.8.8.8
             - 8.8.4.4

     bridges:
       br0:
         dhcp4: false
         dhcp6: false
         interfaces:
           - eth0  # Same interface name as above
         addresses:
           - 10.2.83.181/24
           - 10.2.83.182/24
           - 10.2.83.183/24
         gateway4: 10.2.83.1
         nameservers:
           addresses:
             - 8.8.8.8
             - 8.8.4.4
         parameters:
           stp: false
           forward-delay: 0
   ```

3. **Save the file** (Ctrl+O, Enter, Ctrl+X in nano)

### Step 2.2: Validate Configuration

```bash
# Check for syntax errors
sudo netplan generate
```

**If errors appear**: Fix the YAML syntax (check indentation, spacing, interface name)

### Step 2.3: Apply Configuration

**Option A - Test first (recommended)**:
```bash
# This will apply and revert after 120 seconds if you don't confirm
sudo netplan try
# If everything works, press Enter to keep the configuration
```

**Option B - Apply directly**:
```bash
sudo netplan apply
```

## Step 3: Verify Bridge Configuration

### Check Bridge Status

```bash
# Is bridge created?
ip link show br0

# Is bridge UP?
ip link show br0 | grep "state UP"

# See bridge IPs
ip addr show br0

# Should show: 10.2.83.181, 182, 183
```

### Check Physical Interface is in Bridge

```bash
# See what's connected to the bridge
bridge link show

# Or
ip link show br0

# Should show your physical interface (eth0, etc.) as a slave
```

### Test Gateway from Bridge

```bash
# Ping gateway from the bridge IP
ping -I 10.2.83.181 -c 3 10.2.83.1
```

## Step 4: Enable IP Forwarding

### Check Current Status

```bash
# Check if forwarding is enabled
sysctl net.ipv4.ip_forward

# Should output: net.ipv4.ip_forward = 1
# If it shows 0, it's disabled
```

### Enable Temporarily

```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

### Enable Permanently

1. **Edit sysctl.conf**:
   ```bash
   sudo nano /etc/sysctl.conf
   ```

2. **Add or uncomment this line**:
   ```
   net.ipv4.ip_forward=1
   ```

3. **Save the file** (Ctrl+O, Enter, Ctrl+X)

4. **Apply the change**:
   ```bash
   sudo sysctl -p
   ```

5. **Verify it's enabled**:
   ```bash
   sysctl net.ipv4.ip_forward
   # Should output: net.ipv4.ip_forward = 1
   ```

## Step 5: Configure NAT/Forwarding Rules

### Check Current iptables Rules

```bash
# Check NAT rules
sudo iptables -t nat -L POSTROUTING -n -v

# Check forwarding rules
sudo iptables -L FORWARD -n -v

# See all rules
sudo iptables -L -n -v
```

### Find Your Physical Interface Name

```bash
# From earlier step - the interface that connects to gateway
# Usually the one with 10.2.83.180
ip addr show | grep "10.2.83.180"
```

### Add NAT Masquerade Rule

```bash
# Replace 'eth0' with your physical interface name
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
```

### Add Forwarding Rules

```bash
# Allow forwarding from bridge to physical interface
sudo iptables -A FORWARD -i br0 -o eth0 -j ACCEPT

# Allow forwarding from physical interface back to bridge
sudo iptables -A FORWARD -i eth0 -o br0 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

### Save iptables Rules (Ubuntu/Debian)

1. **Install iptables-persistent** (if not already installed):
   ```bash
   sudo apt-get update
   sudo apt-get install iptables-persistent
   ```

2. **Save the current rules**:
   ```bash
   sudo iptables-save | sudo tee /etc/iptables/rules.v4
   ```

3. **Verify rules are saved**:
   ```bash
   sudo cat /etc/iptables/rules.v4
   ```

## Step 6: Check Firewall

### If Using UFW

1. **Check if UFW is active**:
   ```bash
   sudo ufw status
   ```

2. **If active, allow bridge traffic**:
   ```bash
   sudo ufw allow in on br0
   sudo ufw allow forward
   ```

3. **Verify rules**:
   ```bash
   sudo ufw status verbose
   ```

### If Using firewalld

1. **Check if firewalld is running**:
   ```bash
   sudo firewall-cmd --state
   ```

2. **Add bridge to trusted zone**:
   ```bash
   sudo firewall-cmd --permanent --zone=trusted --add-interface=br0
   ```

3. **Reload firewall**:
   ```bash
   sudo firewall-cmd --reload
   ```

4. **Verify**:
   ```bash
   sudo firewall-cmd --zone=trusted --list-interfaces
   # Should show br0
   ```

## Step 7: Configure KVM to Use Bridge

### Check Libvirt Networks

```bash
# List all networks
virsh net-list --all

# Get network details
virsh net-info default
```

### Create Libvirt Bridge Network

1. **Create the XML file**:
   ```bash
   sudo nano /tmp/kvm-bridge.xml
   ```

2. **Write the configuration**:
   ```xml
   <network>
     <name>kvm-bridge</name>
     <uuid>$(uuidgen)</uuid>
     <forward mode="bridge"/>
     <bridge name="br0"/>
   </network>
   ```
   Note: Replace `$(uuidgen)` with actual UUID by running `uuidgen` command first, or remove the uuid line.

3. **Save the file** (Ctrl+O, Enter, Ctrl+X)

4. **Define the network**:
   ```bash
   sudo virsh net-define /tmp/kvm-bridge.xml
   ```

5. **Start the network**:
   ```bash
   sudo virsh net-start kvm-bridge
   ```

6. **Enable autostart**:
   ```bash
   sudo virsh net-autostart kvm-bridge
   ```

7. **Verify it's active**:
   ```bash
   virsh net-list --all
   # Should show kvm-bridge as active
   ```

### Configure VM to Use Bridge

1. **List your VMs**:
   ```bash
   virsh list --all
   ```

2. **Edit the VM configuration**:
   ```bash
   sudo virsh edit <vm-name>
   ```

3. **Find the interface section** (look for `<interface type='...'>`)

4. **Replace it with**:
   ```xml
   <interface type='bridge'>
     <source bridge='br0'/>
     <model type='virtio'/>
   </interface>
   ```

5. **Save and exit** (in vi/vim: press Esc, type `:wq`, press Enter)

6. **Restart the VM**:
   ```bash
   sudo virsh shutdown <vm-name>
   sudo virsh start <vm-name>
   ```

## Diagnostic Commands - Finding What's Wrong

### Problem: KVM VMs Can't Reach Gateway (10.2.83.1)

#### 0. Check OpenStack Allowed Address Pairs (CRITICAL)

**This is often the root cause!** If bridge IPs aren't in allowed address pairs, OpenStack will drop the traffic.

1. **Find your VM's port**:
   ```bash
   openstack port list | grep "10.2.83.180"
   ```

2. **Check allowed address pairs**:
   ```bash
   openstack port show <port-id> -c allowed_address_pairs
   ```

3. **Verify bridge IPs are listed**:
   - Should include: 10.2.83.181, 182, 183
   - If missing, add them (see Step 0 above)

4. **Test if traffic is being dropped**:
   ```bash
   # From the VM, try to ping gateway using bridge IP as source
   ping -I 10.2.83.181 -c 3 10.2.83.1
   
   # If this fails but ping without -I works, it's likely allowed address pairs
   ping -c 3 10.2.83.1
   ```

**If allowed address pairs are missing**: Add them immediately - this is usually the issue.

#### 1. Check Host Can Reach Gateway

```bash
# From OpenStack VM host
ping -c 3 10.2.83.1
```

**If this fails**: Problem is with OpenStack VM network, not bridge. Check:
- OpenStack security groups
- OpenStack network configuration
- Physical network connectivity

#### 2. Check Bridge is Up

```bash
ip link show br0
```

**Look for**: `state UP`

**If DOWN**: 
```bash
sudo ip link set br0 up
```

**Verify it's up**:
```bash
ip link show br0 | grep "state UP"
```

#### 3. Check Bridge Has IPs

```bash
ip addr show br0
```

**Should show**: 10.2.83.181, 182, 183

**If missing**: 
1. Check netplan configuration file exists and is correct
2. Apply configuration:
   ```bash
   sudo netplan apply
   ```
3. Verify again:
   ```bash
   ip addr show br0
   ```

#### 4. Check IP Forwarding

```bash
sysctl net.ipv4.ip_forward
```

**Should be**: `net.ipv4.ip_forward = 1`

**If 0**: 
1. Enable temporarily: `sudo sysctl -w net.ipv4.ip_forward=1`
2. Enable permanently: Edit `/etc/sysctl.conf` and add `net.ipv4.ip_forward=1`
3. Apply: `sudo sysctl -p`
4. Verify: `sysctl net.ipv4.ip_forward` (should show 1)

#### 5. Check NAT Rules

```bash
sudo iptables -t nat -L POSTROUTING -n -v
```

**Look for**: Rule with `MASQUERADE` and your physical interface

**If missing**: 
1. Find your physical interface name: `ip addr show | grep "10.2.83.180"`
2. Add NAT rule: `sudo iptables -t nat -A POSTROUTING -o <interface> -j MASQUERADE`
3. Replace `<interface>` with your actual interface name (e.g., eth0)
4. Verify: `sudo iptables -t nat -L POSTROUTING -n -v`

#### 6. Check Forwarding Rules

```bash
sudo iptables -L FORWARD -n -v
```

**Look for**: Rules allowing traffic between br0 and physical interface

**If missing**: 
1. Find your physical interface name: `ip addr show | grep "10.2.83.180"`
2. Add forwarding rules:
   ```bash
   sudo iptables -A FORWARD -i br0 -o <interface> -j ACCEPT
   sudo iptables -A FORWARD -i <interface> -o br0 -m state --state RELATED,ESTABLISHED -j ACCEPT
   ```
3. Replace `<interface>` with your actual interface name (e.g., eth0)
4. Verify: `sudo iptables -L FORWARD -n -v`

#### 7. Check Routing

```bash
# From host
ip route show

# Should show default route via 10.2.83.1
```

#### 8. Test from Bridge IP

```bash
# Ping gateway using bridge IP as source
ping -I 10.2.83.181 -c 3 10.2.83.1
```

**If this works but VM can't**: Problem is with VM configuration or libvirt network

#### 9. Check VM Network Configuration

```bash
# See VM interfaces
virsh domiflist <vm-name>

# Check VM is on bridge network
virsh domiflist <vm-name> | grep br0
```

#### 10. Check VM IP Configuration

Inside the VM:

```bash
# See interfaces
ip addr show

# See routes
ip route show

# Check gateway
ip route | grep default

# Should show: default via 10.2.83.1
```

### Problem: Bridge Not Created

#### Check Netplan Configuration

1. **Validate syntax**:
   ```bash
   sudo netplan generate
   ```

2. **Check for detailed errors**:
   ```bash
   sudo netplan --debug generate
   ```

3. **Review the configuration file**:
   ```bash
   sudo cat /etc/netplan/99-kvm-bridge.yaml
   ```
   Check for:
   - Correct YAML indentation (spaces, not tabs)
   - Correct interface name
   - Valid IP addresses and netmask format

#### Check for Conflicting Configs

1. **List all netplan files**:
   ```bash
   ls -la /etc/netplan/
   ```

2. **Check for conflicts**:
   ```bash
   sudo netplan generate
   ```
   Look for warnings about multiple configurations for the same interface

3. **If conflicts exist**: Remove or rename conflicting files, or merge configurations

#### Check System Logs

1. **Check networkd logs**:
   ```bash
   journalctl -u systemd-networkd -n 50
   ```

2. **Check for errors**:
   ```bash
   journalctl -u systemd-networkd | grep -i error
   ```

3. **Check recent logs**:
   ```bash
   journalctl -u systemd-networkd --since "10 minutes ago"
   ```

### Problem: Physical Interface Loses Connectivity

**Cause**: When interface moves to bridge, IP moves to bridge

**Solution**: 
- Bridge should have the IPs (181, 182, 183)
- Physical interface doesn't need its own IP if bridge handles it
- OR keep IP on physical interface and add bridge IPs separately

**Check**:
```bash
# Physical interface should be in bridge
bridge link show | grep br0

# Bridge should have IPs
ip addr show br0
```

### Problem: Netplan Apply Fails

#### Check YAML Syntax

1. **Validate the configuration**:
   ```bash
   sudo netplan generate
   ```

2. **Common errors to check**:
   - Wrong indentation (must use spaces, not tabs)
   - Interface name mismatch (interface doesn't exist)
   - Invalid IP format (should be like `10.2.83.181/24`)
   - Missing colons after keys
   - Incorrect nesting levels

3. **Fix errors**:
   ```bash
   sudo nano /etc/netplan/99-kvm-bridge.yaml
   ```
   Make corrections and save

#### Check Interface Names

1. **Verify the interface exists**:
   ```bash
   ip link show eth0  # or whatever name you used in netplan
   ```

2. **If it doesn't exist, find the correct name**:
   ```bash
   ip link show
   ```

3. **Update netplan with correct interface name**:
   ```bash
   sudo nano /etc/netplan/99-kvm-bridge.yaml
   ```
   Replace the interface name in both the `ethernets:` and `interfaces:` sections

4. **Apply the corrected configuration**:
   ```bash
   sudo netplan apply
   ```

## Quick Reference: All Diagnostic Commands

```bash
# OpenStack Allowed Address Pairs (CRITICAL - check this first!)
openstack port list | grep "10.2.83.180"
openstack port show <port-id> -c allowed_address_pairs

# Network interfaces
ip link show
ip addr show

# Bridge status
ip link show br0
bridge link show
ip addr show br0

# Routing
ip route show
ip route get 10.2.83.1

# IP forwarding
sysctl net.ipv4.ip_forward

# iptables
sudo iptables -t nat -L -n -v
sudo iptables -L FORWARD -n -v

# Connectivity tests
ping -c 3 10.2.83.1
ping -I 10.2.83.181 -c 3 10.2.83.1  # Test with bridge IP as source
ping -c 3 8.8.8.8

# DNS
nslookup google.com
cat /etc/resolv.conf

# Netplan
sudo netplan generate
sudo netplan --debug generate
ls -la /etc/netplan/

# Libvirt
virsh net-list --all
virsh net-info kvm-bridge
virsh domiflist <vm-name>

# Logs
journalctl -u systemd-networkd -n 50
journalctl -u systemd-networkd | grep -i error
```

## Common Issues Summary

| Issue | Diagnostic Command | Fix |
|-------|-------------------|-----|
| **OpenStack dropping traffic** | `openstack port show <port-id> -c allowed_address_pairs` | **Add bridge IPs to allowed address pairs** |
| Can't ping gateway from host | `ping 10.2.83.1` | Fix OpenStack network/security groups |
| Bridge not created | `ip link show br0` | Check netplan config, run `netplan apply` |
| Bridge DOWN | `ip link show br0` | `ip link set br0 up` |
| No IPs on bridge | `ip addr show br0` | Check netplan, apply config |
| IP forwarding disabled | `sysctl net.ipv4.ip_forward` | Enable in `/etc/sysctl.conf` |
| No NAT rule | `iptables -t nat -L POSTROUTING` | Add MASQUERADE rule |
| No forward rules | `iptables -L FORWARD` | Add FORWARD rules |
| Firewall blocking | `ufw status` or `firewall-cmd --state` | Allow bridge traffic |
| VM not on bridge | `virsh domiflist <vm>` | Configure VM network interface |

## Network Architecture

```
Internet
   |
   v
10.2.83.1 (Gateway)
   |
   v
OpenStack VM (10.2.83.180)
   |
   |-- eth0 (physical interface) 
   |     |
   |     v
   |-- br0 (bridge)
         |
         |-- 10.2.83.181
         |-- 10.2.83.182  
         |-- 10.2.83.183
         |
         v
    KVM VMs (connected to br0)
```

## Important Notes

1. **OpenStack Allowed Address Pairs**: **CRITICAL** - Must be configured first. Without this, OpenStack will drop traffic from bridge IPs even if everything else is correct. This is the #1 cause of "can't reach gateway" issues with bridge networks.

2. **Interface Name**: Always verify your physical interface name with `ip link show` - it may not be `eth0`

3. **IP Forwarding**: Critical for VMs to reach gateway - must be enabled

4. **NAT Rules**: Required for VMs to access external networks through the gateway

5. **OpenStack Security Groups**: Ensure they allow necessary traffic (different from allowed address pairs)

6. **Order Matters**: 
   - Configure OpenStack allowed address pairs FIRST
   - Create bridge
   - Enable IP forwarding
   - Add NAT rules
   - Then configure KVM

7. **Testing**: Always test from host first, then from VM. If ping works without `-I` but fails with `-I 10.2.83.181`, check allowed address pairs.

