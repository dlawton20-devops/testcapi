# Fix: IPA Not Booting in libvirt VM

## Problem
The Ironic Python Agent (IPA) is not booting correctly within the libvirt VM, causing the BareMetalHost to be stuck in `preparing` state with Ironic node in `inspect wait`.

## Root Cause
1. **User-mode networking doesn't support PXE boot** - The VM was configured with `<interface type='user'>` which doesn't support TFTP/PXE required for IPA to boot
2. **Boot order** - VM was configured to boot from hard disk first (`<boot dev='hd'/>`), not network
3. **Network connectivity** - IPA needs to reach Ironic's PXE/TFTP server to download and boot

## Solution Applied

### 1. Changed Network Type
- **Before**: `<interface type='user'>` (user-mode networking, no PXE support)
- **After**: `<interface type='network'>` with `source network='default'` (bridge network with PXE support)

### 2. Updated Boot Order
- **Before**: `<boot dev='hd'/>` (hard disk first)
- **After**: 
  ```xml
  <boot dev='network'/>
  <boot dev='hd'/>
  <bootmenu enable='yes'/>
  ```
  - Network boot first (for IPA)
  - Hard disk second (for normal OS)

### 3. Network Requirements
For PXE boot to work, the VM needs:
- A bridge network (not user-mode)
- The network must be active
- The network must support DHCP and TFTP

## Current Status

The VM has been updated with:
- ✅ Network boot enabled (first priority)
- ✅ Interface changed to bridge network
- ⚠️  Network may need to be started: `virsh net-start default` (may require sudo on macOS)

## Next Steps

1. **Start the network** (if not already running):
   ```bash
   # Try without sudo first
   virsh net-start default
   
   # If that fails, try with sudo
   sudo virsh net-start default
   ```

2. **Start the VM**:
   ```bash
   virsh start metal3-node-0
   ```

3. **Recreate the BareMetalHost** (since we deleted it earlier):
   ```bash
   kubectl apply -f baremetalhost.yaml
   ```

4. **Monitor the inspection**:
   ```bash
   kubectl get bmh -n metal3-system -w
   ```

## Expected Behavior

When Ironic triggers inspection:
1. Ironic will power cycle the VM via sushy-tools
2. VM will boot from network (PXE)
3. IPA will download from Ironic's TFTP server
4. IPA will boot and report hardware information
5. Inspection will complete
6. BareMetalHost will move to `available` state

## Troubleshooting

If IPA still doesn't boot:

1. **Check VM console** to see boot process:
   ```bash
   virsh console metal3-node-0
   # Press Enter to activate console
   # Look for PXE boot messages
   ```

2. **Check network connectivity**:
   ```bash
   # From inside the VM (after it boots)
   # Should be able to reach Ironic at 172.18.255.200
   ```

3. **Check Ironic logs** for PXE/TFTP errors:
   ```bash
   kubectl logs -n metal3-system -l app.kubernetes.io/component=ironic -c ironic | grep -i "pxe\|tftp\|boot"
   ```

4. **Verify network is active**:
   ```bash
   virsh net-list --all
   # Should show 'default' as active
   ```

## Alternative: Use metal3-net Bridge

If the default network doesn't work, you can use the metal3-net bridge we created earlier:

```bash
# Start the bridge network (requires sudo on macOS)
sudo virsh net-start metal3-net

# Update VM to use metal3-net instead of default
virsh edit metal3-node-0
# Change <source network='default'/> to <source network='metal3-net'/>
```

