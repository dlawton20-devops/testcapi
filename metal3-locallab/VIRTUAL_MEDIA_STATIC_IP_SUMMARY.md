# Redfish Virtual Media with Static IP - Setup Complete ✅

## Configuration Summary

### ✅ VM Configuration
- **Boot Order**: CD/DVD first (for Redfish virtual media), then hard disk
- **Network**: User-mode networking (works on macOS without bridge)
- **Static IP**: `192.168.122.100/24`
- **Gateway**: `192.168.122.1`
- **DNS**: `8.8.8.8`, `8.8.4.4`

### ✅ BareMetalHost Status
- **State**: `available` ✅
- **Online**: `true` ✅
- **BMC**: Connected via Redfish
- **Boot Mode**: UEFI
- **Virtual Media**: Ready for IPA boot

## How Redfish Virtual Media Works

1. **Ironic provides IPA ISO** via Redfish virtual media API
2. **sushy-tools** receives the virtual media mount request
3. **sushy-tools** mounts the ISO as a virtual CD/DVD drive in libvirt
4. **VM boots from CD/DVD** (virtual media) first
5. **IPA runs** from virtual media and communicates with Ironic
6. **VM has static IP** for consistent network access

## Current VM XML Configuration

```xml
<os>
  <type arch='x86_64' machine='pc-q35-7.2'>hvm</type>
  <bootmenu enable='yes'/>
</os>
...
<disk type='file' device='cdrom'>
  <boot order='1'/>  <!-- Virtual media first -->
</disk>
<disk type='file' device='disk'>
  <boot order='2'/>  <!-- Hard disk second -->
</disk>
<interface type='user'>  <!-- User-mode networking -->
  <mac address='52:54:00:75:d4:96'/>
  <model type='virtio'/>
</interface>
```

## Cloud-init Static IP Configuration

The VM is configured with a static IP via cloud-init:

```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses:
        - 192.168.122.100/24
      gateway4: 192.168.122.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
```

## Known Issue: libvirt PATH

There's a PATH issue with libvirt binaries on macOS. The binaries are in `/opt/homebrew/Cellar/libvirt/11.2.0/sbin/` but not in PATH.

### Fix the PATH Issue

Add to your `~/.zshrc` or `~/.bash_profile`:

```bash
export PATH="/opt/homebrew/Cellar/libvirt/11.2.0/sbin:$PATH"
```

Or create a symlink:

```bash
sudo ln -s /opt/homebrew/Cellar/libvirt/11.2.0/sbin/* /opt/homebrew/bin/
```

### For sushy-tools

Update `~/metal3-sushy/sushy.conf` to include the PATH:

```python
import os
os.environ['PATH'] = '/opt/homebrew/Cellar/libvirt/11.2.0/sbin:' + os.environ.get('PATH', '')
```

Or update the launchd plist to include the PATH in EnvironmentVariables.

## Next Steps

1. **Fix libvirt PATH** (see above)
2. **Restart sushy-tools** with the updated PATH:
   ```bash
   launchctl unload ~/Library/LaunchAgents/com.metal3.sushy-emulator.plist
   launchctl load ~/Library/LaunchAgents/com.metal3.sushy-emulator.plist
   ```
3. **Provision the host** when ready:
   ```bash
   kubectl get bmh -n metal3-system
   # The host should be in 'available' state
   ```

## Benefits of Virtual Media vs PXE

1. ✅ **No PXE/TFTP required** - simpler network setup
2. ✅ **Works with user-mode networking** - no bridge needed on macOS
3. ✅ **Static IP** - predictable network configuration
4. ✅ **Redfish standard** - uses standard Redfish virtual media API
5. ✅ **Better for libvirt VMs** - native support in sushy-tools

## Files Updated

- ✅ `create-baremetal-host.sh` - Updated with static IP and virtual media boot order
- ✅ `baremetalhost.yaml` - Already configured for Redfish
- ✅ VM XML - Configured for CD/DVD boot first
- ✅ Cloud-init - Configured with static IP

## Verification

Check the setup:

```bash
# Check BareMetalHost
kubectl get bmh -n metal3-system

# Check VM boot order
virsh dumpxml metal3-node-0 | grep -A 5 "<os>"

# Check static IP (after VM boots)
virsh domifaddr metal3-node-0
# Should show 192.168.122.100

# Check sushy-tools virtual media support
curl -u admin:admin http://localhost:8000/redfish/v1/Systems/721bcaa7-be3d-4d62-99a9-958bb212f2b7/Media
```

