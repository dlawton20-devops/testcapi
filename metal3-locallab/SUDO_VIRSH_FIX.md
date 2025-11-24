# Fix: sudo virsh with Session Mode Networks

## The Issue
When you use `sudo virsh`, it defaults to connecting to `qemu:///system`, but your network was created in session mode (`qemu:///session`). This causes the "Cannot use direct socket mode" error.

## Solution

### Option 1: Specify Session URI with sudo
```bash
sudo virsh -c qemu:///session net-start metal3-net
```

### Option 2: Use Regular User (No sudo needed for session mode)
Since the network is in session mode, you don't need sudo:
```bash
virsh net-start metal3-net
```

However, if it fails with "Operation not permitted" for bridge creation, you have two choices:

### Option 3: Recreate Network in System Mode
If you need sudo for bridge permissions, recreate the network in system mode:

```bash
# Remove session network
virsh net-destroy metal3-net
virsh net-undefine metal3-net

# Create in system mode (requires sudo)
sudo virsh net-define /path/to/metal3-net.xml
sudo virsh net-autostart metal3-net
sudo virsh net-start metal3-net
```

Then update sushy-tools config to use `qemu:///system` instead of `qemu:///session`.

## Current Setup
- Network: `metal3-net` in session mode (`qemu:///session`)
- sushy-tools: Configured for `qemu:///session`
- VM: Configured to use `metal3-net`

## Recommended Approach
Try Option 1 first:
```bash
sudo virsh -c qemu:///session net-start metal3-net
```

If that works, then start the VM:
```bash
virsh start metal3-node-0
```

