# Redfish Virtual Media Setup with Static IP

## Configuration

### VM Boot Configuration
- **Boot Order**: CD/DVD first (for virtual media), then hard disk
- **Virtual Media**: Ironic will provide IPA ISO via Redfish virtual media
- **Network**: User-mode networking (works on macOS without bridge)

### Static IP Configuration
- **IP Address**: `192.168.122.100`
- **Gateway**: `192.168.122.1`
- **Netmask**: `255.255.255.0`
- **DNS**: `8.8.8.8`, `8.8.4.4`

## How It Works

1. **Ironic provides IPA ISO** via Redfish virtual media endpoint
2. **sushy-tools** mounts this ISO as a virtual CD/DVD drive
3. **VM boots from CD/DVD** (virtual media) first
4. **IPA runs** from the virtual media and communicates with Ironic
5. **VM has static IP** for consistent network access

## Current VM Configuration

```xml
<os>
  <boot dev='cdrom'/>  <!-- Virtual media first -->
  <boot dev='hd'/>     <!-- Hard disk second -->
  <bootmenu enable='yes'/>
</os>
```

## Cloud-init Static IP

The cloud-init configuration includes:
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

## Benefits of Virtual Media vs PXE

1. ✅ **No PXE/TFTP required** - simpler network setup
2. ✅ **Works with user-mode networking** - no bridge needed on macOS
3. ✅ **Static IP** - predictable network configuration
4. ✅ **Redfish standard** - uses standard Redfish virtual media API

## Next Steps

1. **VM is configured** for virtual media boot ✅
2. **Static IP configured** in cloud-init ✅
3. **BareMetalHost** should use Redfish virtual media automatically
4. **Monitor inspection**:
   ```bash
   kubectl get bmh -n metal3-system -w
   ```

## Troubleshooting

If IPA doesn't boot from virtual media:

1. **Check sushy-tools virtual media**:
   ```bash
   curl -u admin:admin http://localhost:8000/redfish/v1/Systems/721bcaa7-be3d-4d62-99a9-958bb212f2b7/Media
   ```

2. **Check VM boot order**:
   ```bash
   virsh dumpxml metal3-node-0 | grep -A 5 "<os>"
   ```

3. **Check VM console** to see boot process:
   ```bash
   virsh console metal3-node-0
   ```

4. **Verify static IP** is configured:
   ```bash
   # After VM boots, check IP
   virsh domifaddr metal3-node-0
   # Should show 192.168.122.100
   ```

