# Libvirt Network Fix for macOS

## Issue
On macOS, libvirt bridge networks require elevated permissions that aren't easily available in session mode.

## Solution Options

### Option 1: Use NAT Network (Recommended for testing)
The network is already defined. Try starting it with proper permissions:

```bash
# The network exists but needs to be started
# On macOS, you may need to allow libvirt to create network interfaces
virsh net-start metal3-net
```

If it fails with "Operation not permitted", you may need to:
1. Allow libvirt in System Settings > Privacy & Security
2. Or use a different network approach

### Option 2: Modify VM to Use Different Network
Update the VM to use a network that doesn't require bridge creation:

```bash
# Edit VM network configuration
virsh edit metal3-node-0

# Change from:
#   <source network='metal3-net'/>
# To use a simpler network or direct connection
```

### Option 3: Use Default Network
Create and use the default libvirt network:

```bash
# Create default network
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
virsh net-start default
```

Then update the VM to use 'default' network instead of 'metal3-net'.

### Option 4: Run VM Without Network (for testing sushy-tools)
For now, you can test if sushy-tools works by starting the VM without network (it will fail to get IP, but sushy-tools might still see it):

```bash
# Temporarily remove network requirement
virsh edit metal3-node-0
# Comment out or remove the <interface> section temporarily
```

## Current Status
- Network `metal3-net` is defined but inactive
- VM `metal3-node-0` is configured to use `metal3-net`
- Network can't start due to bridge creation permissions

## Quick Test
Try starting the network again - sometimes it works after libvirt services restart:

```bash
virsh net-start metal3-net
```

If successful, then:
```bash
virsh start metal3-node-0
```

