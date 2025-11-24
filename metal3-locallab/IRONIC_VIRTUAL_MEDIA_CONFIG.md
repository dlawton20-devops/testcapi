# Ironic Virtual Media Configuration

## Configuration Applied

Updated the Ironic ConfigMap with:

```yaml
ENABLED_BOOT_INTERFACES: "redfish-virtual-media"
DEFAULT_BOOT_INTERFACE: "redfish-virtual-media"
DEFAULT_DEPLOY_INTERFACE: "redfish-virtual-media"
ENABLE_PXE_BOOT: "false"
```

## Current Status

- ✅ ConfigMap updated
- ✅ Ironic pods restarted
- ⚠️  Still seeing PXE validation errors

## Issue

The BareMetalHost is still trying to validate PXE bootloader even though:
- PXE is disabled
- Virtual media is set as default
- Ironic has been restarted

## Possible Solutions

1. **Check if the configuration is being read correctly** - The environment variables might need to be set differently
2. **Verify the Helm chart supports these settings** - SUSE Edge Metal3 might use different configuration keys
3. **Check Ironic conductor logs** - See what configuration it's actually using when creating nodes

## Next Steps

Check the Ironic conductor configuration file inside the pod to see what settings are actually being used.


