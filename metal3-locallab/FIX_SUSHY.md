# Fixed sushy-tools Configuration

## Issues Fixed

1. **Config file format**: Changed from INI to Python format
2. **Auth file**: Updated to use bcrypt hashed passwords
3. **BMC address**: Updated BareMetalHost to use host IP (192.168.1.242) instead of host.docker.internal

## Current Status

✅ **sushy-tools is running** on port 8000
✅ **BareMetalHost BMC address updated** to: `redfish+http://192.168.1.242:8000/redfish/v1/Systems/metal3-node-0`

## To Start sushy-tools

```bash
# Method 1: Manual start (current)
nohup ~/metal3-sushy/start-sushy.sh > ~/metal3-sushy/sushy.log 2>&1 &

# Method 2: Using launchctl
launchctl load ~/Library/LaunchAgents/com.metal3.sushy-emulator.plist

# Verify it's running
curl -u admin:admin http://localhost:8000/redfish/v1
```

## Files Updated

- `/Users/dave/metal3-sushy/sushy.conf` - Python config format
- `/Users/dave/metal3-sushy/auth.conf` - bcrypt hashed password
- BareMetalHost spec - Updated BMC address

## Next Steps

The BareMetalHost controller should now be able to connect to sushy-tools. Monitor with:

```bash
kubectl get bmh -n metal3-system -w
kubectl describe bmh metal3-node-0 -n metal3-system
```

If connection still fails, ensure:
1. sushy-tools is accessible from the kind cluster
2. Firewall allows port 8000
3. The VM is registered in sushy-tools (start the VM first)

