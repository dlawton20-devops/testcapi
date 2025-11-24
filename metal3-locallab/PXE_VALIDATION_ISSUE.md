# PXE Validation Issue - baremetal-operator

## Problem

Even though Ironic is configured to use `redfish-virtual-media`:
- ✅ `ENABLED_BOOT_INTERFACES=redfish-virtual-media`
- ✅ `DEFAULT_BOOT_INTERFACE=redfish-virtual-media`
- ✅ `DEFAULT_DEPLOY_INTERFACE=redfish-virtual-media`
- ✅ `ENABLE_PXE_BOOT=false`

The baremetal-operator is still trying to validate PXE bootloader and failing with:
```
Cannot validate PXE bootloader. Some parameters were missing in node's driver_info and configuration. Missing are: ['deploy_kernel', 'deploy_ramdisk']
```

## Root Cause

The baremetal-operator appears to be validating PXE before checking the node's actual deploy interface. This might be:
1. A bug in the operator version
2. The operator needs additional configuration
3. The operator is using cached node information

## Configuration Applied

### Ironic ConfigMap
```yaml
ENABLED_BOOT_INTERFACES: "redfish-virtual-media"
DEFAULT_BOOT_INTERFACE: "redfish-virtual-media"
DEFAULT_DEPLOY_INTERFACE: "redfish-virtual-media"
ENABLE_PXE_BOOT: "false"
```

### Verification
The environment variables are correctly set in the Ironic pod:
```bash
kubectl exec -n metal3-system <ironic-pod> -c ironic -- env | grep -i BOOT
# Shows: ENABLED_BOOT_INTERFACES=redfish-virtual-media
#        DEFAULT_BOOT_INTERFACE=redfish-virtual-media
#        DEFAULT_DEPLOY_INTERFACE=redfish-virtual-media
#        ENABLE_PXE_BOOT=false
```

## Possible Solutions

1. **Check SUSE Edge Metal3 documentation** for specific configuration for virtual media
2. **Update baremetal-operator configuration** - may need operator-level settings
3. **Check if there's a Helm value** to disable PXE validation in the operator
4. **Upgrade/downgrade operator version** - might be a version-specific issue

## Next Steps

Check the SUSE Edge Metal3 documentation or Helm chart values for:
- `baremetal-operator` configuration options
- Virtual media deployment interface settings
- PXE validation disable options


