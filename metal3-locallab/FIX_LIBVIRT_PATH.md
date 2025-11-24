# Fix: libvirt PATH Issue for sushy-tools

## Problem
sushy-tools is trying to use libvirt binaries but can't find them because:
- libvirt is looking for binaries in `/opt/homebrew/Cellar/libvirt/11.2.0/sbin/`
- Actual binaries are in `/opt/homebrew/Cellar/libvirt/11.9.0_1/sbin/`

## Solution Applied

### 1. Updated launchd plist
Added libvirt sbin to PATH in `~/Library/LaunchAgents/com.metal3.sushy-emulator.plist`:
```xml
<key>PATH</key>
<string>/opt/homebrew/Cellar/libvirt/11.9.0_1/sbin:/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin</string>
```

### 2. Updated sushy.conf
Added PATH update in Python config:
```python
libvirt_sbin = '/opt/homebrew/Cellar/libvirt/11.9.0_1/sbin'
if libvirt_sbin not in os.environ.get('PATH', ''):
    os.environ['PATH'] = libvirt_sbin + ':' + os.environ.get('PATH', '')
```

### 3. Created Symlinks (if needed)
Created symlinks from old path to new path:
```bash
ln -sf /opt/homebrew/Cellar/libvirt/11.9.0_1/sbin/virtlogd /opt/homebrew/Cellar/libvirt/11.2.0/sbin/virtlogd
ln -sf /opt/homebrew/Cellar/libvirt/11.9.0_1/sbin/virtnetworkd /opt/homebrew/Cellar/libvirt/11.2.0/sbin/virtnetworkd
ln -sf /opt/homebrew/Cellar/libvirt/11.9.0_1/sbin/virtlockd /opt/homebrew/Cellar/libvirt/11.2.0/sbin/virtlockd
```

## Restart sushy-tools

After making changes:
```bash
launchctl unload ~/Library/LaunchAgents/com.metal3.sushy-emulator.plist
launchctl load ~/Library/LaunchAgents/com.metal3.sushy-emulator.plist
```

## Verify

Check if sushy-tools can now control VMs:
```bash
# Check sushy-tools is running
curl -u admin:admin http://localhost:8000/redfish/v1

# Check BareMetalHost power operations
kubectl get bmh -n metal3-system
kubectl describe bmh metal3-node-0 -n metal3-system
```

## Alternative: Update libvirt Configuration

If symlinks don't work, you may need to reinstall libvirt or update its configuration to use the correct path.

