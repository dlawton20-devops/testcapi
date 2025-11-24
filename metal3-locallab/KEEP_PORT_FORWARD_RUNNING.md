# Keep Ironic Port-Forward Running

## Critical: Port-Forward Must Stay Active

For Redfish virtual media to work, **you must keep the Ironic port-forward running** while provisioning:

```bash
kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6185:6185
```

## Why It's Needed

1. Ironic generates IPA ISO files at `/shared/html/redfish/boot-<node-uuid>.iso`
2. Ironic's external URL is set to `https://localhost:6185` (accessible from host)
3. sushy-tools (running on host) needs to download the ISO from this URL
4. The port-forward makes the Ironic service accessible on localhost:6185

## Current Configuration

- **Ironic External URL**: `https://localhost:6185`
- **Port-Forward**: `kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6185:6185`
- **BMC Address**: `redfish-virtualmedia+http://192.168.1.242:8000/redfish/v1/Systems/...`

## To Keep Port-Forward Running

### Option 1: Run in Background
```bash
kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6185:6185 > /tmp/ironic-portforward.log 2>&1 &
```

### Option 2: Run in Separate Terminal
```bash
# In a separate terminal window
kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6185:6185
```

### Option 3: Use launchd (macOS)
Create a launchd service to keep it running automatically.

## Verification

Check if port-forward is running:
```bash
ps aux | grep "port-forward.*ironic" | grep -v grep
```

Test if Ironic is accessible:
```bash
curl -k "https://localhost:6185/images/ironic-python-agent_x86_64.kernel" -I
```

## Troubleshooting

If provisioning fails with "Connection refused":
1. Check if port-forward is running: `ps aux | grep port-forward`
2. Restart port-forward if needed
3. Verify Ironic is accessible: `curl -k https://localhost:6185/ -I`


