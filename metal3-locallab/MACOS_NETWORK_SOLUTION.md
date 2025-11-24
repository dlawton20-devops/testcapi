# macOS Libvirt Network Solution

## The Problem
On macOS, libvirt in session mode (`qemu:///session`) cannot create bridge devices without special permissions. This prevents the network from starting.

## Workaround: Test sushy-tools Without Network

**Good news**: sushy-tools should be able to see the VM definition even when the VM is shut off. The VM just needs to exist in libvirt.

### Current Status
- ✅ VM `metal3-node-0` exists in libvirt (shut off)
- ✅ sushy-tools is configured with `qemu:///session`
- ❌ Network can't start (bridge permission issue)
- ❌ sushy-tools Systems endpoint not responding

### Test sushy-tools Directly

1. **Verify sushy-tools can see libvirt**:
   ```bash
   # sushy-tools should query libvirt for VMs
   # Check if it can see the VM definition
   curl -u admin:admin http://localhost:8000/redfish/v1/Systems
   ```

2. **Check sushy-tools logs**:
   ```bash
   tail -f ~/metal3-sushy/sushy.log
   # Look for libvirt connection or VM discovery errors
   ```

3. **Verify libvirt connection from sushy-tools perspective**:
   ```bash
   # Test if the session URI works
   virsh -c qemu:///session list --all
   ```

## Alternative: Use Host Network Mode

If the network issue persists, you could modify the VM to use host network mode (less isolated but works without bridge):

```bash
virsh edit metal3-node-0
# Change interface to:
# <interface type='user'>
#   <model type='virtio'/>
# </interface>
```

## For Production/Testing

For a proper setup on macOS, consider:
1. Using Docker Desktop's networking (if using kind)
2. Using a Linux VM to run libvirt with full bridge support
3. Using cloud-based bare metal hosts instead of local VMs

## Next Steps

1. Check if sushy-tools logs show why Systems endpoint fails
2. Verify libvirt connection works: `virsh -c qemu:///session list --all`
3. If sushy-tools can't see VMs, check the libvirt URI in config
4. Consider using a different BMC emulator or testing approach

