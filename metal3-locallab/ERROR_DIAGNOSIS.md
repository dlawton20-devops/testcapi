# Error Diagnosis: sushy-tools Systems Endpoint

## Current Error
```
Failed to get power state for node: Unable to connect to http://192.168.1.242:8000/redfish/v1/Systems/metal3-node-0
Error: ('Connection aborted.', RemoteDisconnected('Remote end closed connection without response'))
```

## Root Cause Analysis

1. **sushy-tools is running** ✅
   - Root endpoint works: `http://localhost:8000/redfish/v1` ✅
   - Systems endpoint fails: Returns empty/crashes ❌

2. **VM Status**
   - VM exists but is shut off
   - VM can't start because network doesn't exist
   - VM needs network to be started first

3. **sushy-tools Systems Endpoint Issue**
   - The endpoint `/redfish/v1/Systems` returns empty reply
   - This happens even when querying locally
   - Likely because:
     a) sushy-tools can't see the VM (VM is shut off)
     b) sushy-tools crashes when Systems collection is empty
     c) Libvirt connection issue with session URI

## Solutions to Try

### Option 1: Start the Network and VM (Requires sudo)
```bash
# Start the network
sudo virsh net-start metal3-net
# OR create/start default network
sudo virsh net-start default

# Then start VM
virsh start metal3-node-0

# Verify sushy-tools can see it
curl -u admin:admin http://localhost:8000/redfish/v1/Systems
```

### Option 2: Check sushy-tools Logs
```bash
tail -f ~/metal3-sushy/sushy.log
# Look for libvirt connection errors or Python tracebacks
```

### Option 3: Test sushy-tools with Debug Mode
Update `~/metal3-sushy/sushy.conf`:
```python
DEBUG = True
```

Then restart sushy-tools to see detailed error messages.

### Option 4: Verify Libvirt Connection
```bash
# Test if sushy-tools can see libvirt
virsh -c qemu:///session list --all

# If this works, sushy-tools should be able to see VMs
```

## Current Status

- ✅ BareMetalHost manifest: `/Users/dave/untitled folder 3/baremetalhost.yaml`
- ✅ BareMetalHost is online (`spec.online: true`)
- ✅ BMC address configured: `redfish+http://192.168.1.242:8000/redfish/v1/Systems/metal3-node-0`
- ✅ sushy-tools running on port 8000
- ❌ Systems endpoint not responding
- ❌ VM can't start (network issue)
- ❌ Registration failing due to connection abort

## Next Steps

1. **Start the libvirt network** (requires sudo password):
   ```bash
   sudo virsh net-start metal3-net
   ```

2. **Start the VM**:
   ```bash
   virsh start metal3-node-0
   ```

3. **Verify sushy-tools can see the VM**:
   ```bash
   curl -u admin:admin http://localhost:8000/redfish/v1/Systems
   ```

4. **Restart baremetal-operator** to retry:
   ```bash
   kubectl delete pod -n metal3-system -l app.kubernetes.io/component=baremetal-operator
   ```

## Alternative: Use Different BMC Emulator

If sushy-tools continues to have issues, consider:
- Using `sushy-emulator` from a container
- Using a different BMC emulator
- Testing with a physical BMC if available

