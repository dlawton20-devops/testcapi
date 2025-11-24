# VM Network Fix - User Mode Networking

## Problem
The libvirt network can't start because bridge creation requires elevated permissions on macOS that aren't available even in session mode.

## Solution: Use User-Mode Networking

Instead of using a bridge network, we can configure the VM to use user-mode networking, which:
- ✅ Doesn't require bridge creation
- ✅ Works without sudo
- ✅ Provides NAT networking automatically
- ✅ Allows the VM to access the internet and be accessed via port forwarding

## What Was Changed

Modified the VM's network interface from:
```xml
<interface type='network'>
  <source network='metal3-net'/>
  <model type='virtio'/>
</interface>
```

To:
```xml
<interface type='user'>
  <model type='virtio'/>
</interface>
```

## Current Status

- ✅ VM network updated to user mode
- ✅ VM should be able to start without network bridge
- ✅ sushy-tools should be able to see the running VM

## Next Steps

1. **Start the VM** (should work now):
   ```bash
   virsh start metal3-node-0
   ```

2. **Verify VM is running**:
   ```bash
   virsh list
   ```

3. **Test sushy-tools Systems endpoint**:
   ```bash
   curl -u admin:admin http://localhost:8000/redfish/v1/Systems
   ```

4. **Restart Metal3 operator** to retry registration:
   ```bash
   kubectl delete pod -n metal3-system -l app.kubernetes.io/component=baremetal-operator
   ```

## Note on User-Mode Networking

- VM will get an IP via DHCP (usually 10.0.2.x range)
- VM can access host at 10.0.2.2
- Host can access VM via port forwarding (if configured)
- For Metal3, the VM just needs to be running and visible to sushy-tools

