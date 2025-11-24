# Troubleshooting Guide - Based on SUSE Edge Documentation

## Reference
[SUSE Edge Troubleshooting Directed-network provisioning](https://documentation.suse.com/suse-edge/3.3/html/edge/troubleshooting-directed-network-provisioning.html)

## Current Issues

### 1. Boot Firmware Requirements
**Problem**: 
- UEFI boot requires OVMF firmware (not installed on macOS)
- BIOS boot requires syslinux in Ironic container (not available)

**Status**: Virtual media ISO is successfully downloaded and stored, but boot process fails due to missing firmware.

### 2. Ironic Endpoint Reachability
**According to documentation**: The host being provisioned needs to reach the Ironic endpoint to report back.

**Current setup**:
- Ironic external URL: `https://localhost:6185` (requires port-forward)
- Port-forward must stay running: `kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6185:6185`

**Action needed**: Verify VM can reach Ironic endpoint once it boots.

## Key Points from Documentation

### Certificate/TLS Issues
The documentation mentions that some BMCs verify SSL connections when attaching virtual-media ISO images. This can cause problems with self-signed certificates.

**Current config**:
- `VMEDIA_TLS_PORT: "6185"` - Virtual media uses TLS
- `IPA_INSECURE: "0"` - TLS enabled for IPA
- `IRONIC_EXTERNAL_HTTP_URL: https://localhost:6185` - HTTPS

**Potential solution**: According to the docs, TLS can be disabled for virtual media ISO attachment if certificate issues occur.

### Verification Steps (from documentation)

1. **Check BareMetalHost status**:
   ```bash
   kubectl get bmh -A
   kubectl describe bmh -n metal3-system metal3-node-0
   kubectl get bmh metal3-node-0 -n metal3-system -o jsonpath='{.status}' | jq
   ```

2. **Test RedFish connectivity**:
   ```bash
   curl -u admin:admin http://192.168.1.242:8000/redfish/v1
   ```

3. **Verify Ironic endpoint reachable from host**:
   ```bash
   kubectl get svc -n metal3-system metal3-metal3-ironic
   # Test from VM once it boots
   ```

4. **Verify IPA image reachable from BMC**:
   - ✅ Port-forward running: `kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6185:6185`
   - ✅ ISO successfully downloaded to storage pool

5. **Examine Metal3 component logs**:
   ```bash
   kubectl logs -n metal3-system -l app.kubernetes.io/component=baremetal-operator
   kubectl logs -n metal3-system -l app.kubernetes.io/component=ironic -c ironic
   ```

## Next Steps

1. **Resolve boot firmware issue**:
   - Option A: Install OVMF firmware for UEFI boot
   - Option B: Configure Ironic container to include syslinux for BIOS boot
   - Option C: Use a different boot method that doesn't require these

2. **Verify network connectivity**:
   - Ensure VM can reach Ironic endpoint once it boots
   - Check if static IP configuration allows communication

3. **Monitor provisioning**:
   - Watch BMH status: `kubectl get bmh -n metal3-system -w`
   - Check logs for any new errors after firmware issue is resolved

## Files Updated

- ✅ `baremetalhost.yaml` - Uses `redfish-virtualmedia+` protocol
- ✅ Ironic ConfigMap - External URL set to `https://localhost:6185`
- ✅ libvirt storage pool `default` created
- ✅ Port-forward running for Ironic access


