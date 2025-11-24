# Port Forwarding Required for sushy-tools

## Problem

sushy-tools (Redfish BMC emulator) needs to reach Ironic to fetch boot ISOs, but the connection fails:

```
Failed fetching image from URL https://192.168.1.242:6385/redfish/boot-*.iso
HTTPSConnectionPool: Max retries exceeded
Connection refused
```

## Root Cause

sushy-tools runs on the macOS host and needs to access Ironic at `192.168.1.242:6385`, but:
- Ironic runs inside Kubernetes (not directly accessible)
- Port forwarding is required to expose Ironic to the host
- Port forwarding was not running

## Solution

Set up two-stage port forwarding:

### Step 1: kubectl port-forward

Forward Ironic service to localhost:

```bash
kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6385:6185 > /tmp/ironic-port-forward.log 2>&1 &
```

**What this does:**
- Listens on: `localhost:6385` (on macOS host)
- Forwards to: Ironic service port `6185` (inside Kubernetes)
- Makes Ironic accessible at `localhost:6385`

### Step 2: socat forwarder

Forward from host IP to localhost:

```bash
socat TCP-LISTEN:6385,fork,reuseaddr TCP:localhost:6385 > /tmp/socat-ironic.log 2>&1 &
```

**What this does:**
- Listens on: `192.168.1.242:6385` (host's external IP)
- Forwards to: `localhost:6385` (where kubectl port-forward listens)
- Makes Ironic accessible at `192.168.1.242:6385` from sushy-tools

## Complete Setup Script

```bash
#!/bin/bash
set -e

echo "🔧 Setting up port forwarding for Ironic..."

# Check if already running
if ps aux | grep -q "[k]ubectl port-forward.*ironic"; then
    echo "✅ kubectl port-forward already running"
else
    echo "Starting kubectl port-forward..."
    nohup kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6385:6185 > /tmp/ironic-port-forward.log 2>&1 &
    sleep 2
    echo "✅ kubectl port-forward started"
fi

if ps aux | grep -q "[s]ocat.*6385"; then
    echo "✅ socat already running"
else
    echo "Starting socat..."
    nohup socat TCP-LISTEN:6385,fork,reuseaddr TCP:localhost:6385 > /tmp/socat-ironic.log 2>&1 &
    sleep 2
    echo "✅ socat started"
fi

# Verify connection
echo "Testing connection..."
if curl -k -s -o /dev/null -w "HTTP %{http_code}\n" https://192.168.1.242:6385/ | grep -q "200\|404"; then
    echo "✅ Ironic is accessible at 192.168.1.242:6385"
else
    echo "⚠️  Connection test failed - check logs"
fi

echo ""
echo "✅ Port forwarding is set up!"
echo "sushy-tools can now fetch boot ISOs from Ironic."
```

## Verification

### Check if running

```bash
# Check kubectl port-forward
ps aux | grep "[k]ubectl port-forward.*ironic"

# Check socat
ps aux | grep "[s]ocat.*6385"
```

### Test connection

```bash
# Test from host
curl -k https://192.168.1.242:6385/

# Should return HTML (404 is OK, means connection works)
```

## Why This Is Needed

1. **sushy-tools runs on host**: The Redfish BMC emulator runs on macOS host
2. **Ironic runs in Kubernetes**: Ironic service is inside the Kind cluster
3. **Virtual media requires host access**: When Ironic tells sushy-tools to mount a boot ISO, sushy-tools needs to fetch it from Ironic
4. **Port forwarding bridges the gap**: Makes Ironic accessible from the host

## Connection Flow

```
Ironic (Kubernetes)
    │
    │ Generates boot ISO URL: https://192.168.1.242:6385/redfish/boot-*.iso
    │ Tells sushy-tools to mount it
    ▼
sushy-tools (macOS host)
    │
    │ Fetches ISO from: https://192.168.1.242:6385/redfish/boot-*.iso
    │
    ▼
socat (192.168.1.242:6385)
    │
    │ Forwards to localhost:6385
    ▼
kubectl port-forward (localhost:6385)
    │
    │ Forwards to Ironic service (port 6185)
    ▼
Ironic Service
    │
    │ Serves boot ISO
    ▼
sushy-tools receives ISO and mounts it as virtual media
```

## Keep It Running

**Important**: These processes must stay running for provisioning to work.

### Option 1: Run in background with nohup

```bash
nohup kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6385:6185 > /tmp/ironic-port-forward.log 2>&1 &
nohup socat TCP-LISTEN:6385,fork,reuseaddr TCP:localhost:6385 > /tmp/socat-ironic.log 2>&1 &
```

### Option 2: Use a process manager

Create a launchd plist or use systemd to keep it running.

### Option 3: Run in separate terminal

Keep a terminal open with:
```bash
kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6385:6185
```

And another with:
```bash
socat TCP-LISTEN:6385,fork,reuseaddr TCP:localhost:6385
```

## Troubleshooting

### Connection still fails

1. **Check processes are running**:
   ```bash
   ps aux | grep -E "(kubectl port-forward|socat.*6385)"
   ```

2. **Check logs**:
   ```bash
   tail -20 /tmp/ironic-port-forward.log
   tail -20 /tmp/socat-ironic.log
   ```

3. **Test connection**:
   ```bash
   curl -k https://192.168.1.242:6385/
   ```

4. **Check Ironic service**:
   ```bash
   kubectl get svc metal3-metal3-ironic -n metal3-system
   ```

### Port already in use

If port 6385 is already in use:
```bash
# Find what's using it
lsof -i :6385

# Kill the process or use a different port
```

## Related

- [Port Forwarding & Network Explained](./PORT_FORWARDING_AND_NETWORK_EXPLAINED.md)
- [IPA Connection Fix](./IPA_CONNECTION_FIX_COMPLETE.md)


