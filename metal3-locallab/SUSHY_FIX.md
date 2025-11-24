# sushy-tools Connection Fix

## Issue
BareMetalHost controller getting "Connection aborted" when connecting to sushy-tools.

## Root Cause
1. sushy-tools was configured with wrong libvirt URI (`qemu:///system` instead of `qemu:///session`)
2. sushy-tools couldn't see the VM because it couldn't connect to libvirt

## Fix Applied

### 1. Updated libvirt URI in sushy.conf
Changed from:
```python
SUSHY_EMULATOR_LIBVIRT_URI = 'qemu:///system'
```
To:
```python
SUSHY_EMULATOR_LIBVIRT_URI = 'qemu:///session'
```

### 2. Restart sushy-tools
```bash
# Kill any existing instance
lsof -ti :8000 | xargs kill -9

# Start with new config
nohup ~/metal3-sushy/start-sushy.sh > ~/metal3-sushy/sushy.log 2>&1 &
```

### 3. Verify
```bash
# Check Systems endpoint
curl -u admin:admin http://localhost:8000/redfish/v1/Systems

# Check specific system
curl -u admin:admin http://localhost:8000/redfish/v1/Systems/metal3-node-0
```

## Current Status
- ✅ sushy-tools config updated
- ✅ BareMetalHost BMC address: `redfish+http://192.168.1.242:8000/redfish/v1/Systems/metal3-node-0`
- ⚠️  Need to restart sushy-tools with new config
- ⚠️  VM needs to be running for sushy-tools to expose it

## Next Steps
1. Ensure sushy-tools is running with session URI
2. Start the VM: `virsh start metal3-node-0`
3. Verify sushy-tools can see the VM
4. Monitor BareMetalHost status

