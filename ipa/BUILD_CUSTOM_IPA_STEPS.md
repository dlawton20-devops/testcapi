# Complete Steps: Building Custom IPA Ramdisk

## Overview

This guide documents the complete process for building a custom IPA (Ironic Python Agent) ramdisk that can read and apply NetworkData secrets from Metal3.

## Prerequisites

1. **Docker Desktop** installed and running on macOS
2. **Python 3** (for local scripts)
3. **Git** (for cloning repositories if needed)

## Step-by-Step Process

### Step 1: Install Prerequisites

```bash
# Install Python packages (if building locally, though Docker is recommended)
pip3 install --user --break-system-packages diskimage-builder ironic-python-agent-builder

# Add to PATH
export PATH=$PATH:$HOME/Library/Python/3.13/bin
```

**Note**: On macOS, building directly with `diskimage-builder` has compatibility issues. **Docker is the recommended approach**.

### Step 2: Build Using Docker (Recommended for macOS)

The build script creates a Docker container with all dependencies and builds the IPA ramdisk inside it.

```bash
cd scripts/setup
./build-ipa-ramdisk-docker.sh --release focal --output-dir ~/ipa-build
```

**What this does:**
1. Creates a Docker image with Ubuntu 22.04 and all build tools
2. Installs `diskimage-builder` and `ironic-python-agent-builder` in the container
3. Creates the custom `ipa-network-config` element with:
   - `configure-network.sh` script
   - Systemd service to run on boot
   - Dependencies (jq, python3-yaml, network-manager, nmstate)
4. Builds the IPA ramdisk using `ironic-python-agent-builder`
5. Copies output files to `~/ipa-build/`

**Output files:**
- `~/ipa-build/ipa-ramdisk.initramfs` - The ramdisk image
- `~/ipa-build/ipa-ramdisk.kernel` - The kernel

**Build time:** 10-20 minutes (first time, subsequent builds are faster due to Docker caching)

### Step 3: Verify the Build

```bash
# Check files exist
ls -lh ~/ipa-build/ipa-ramdisk.*

# Expected output:
# -rw-r--r--  1 user  staff   45M Dec  4 17:30 ipa-ramdisk.initramfs
# -rw-r--r--  1 user  staff   12M Dec  4 17:30 ipa-ramdisk.kernel
```

### Step 4: Upload to Web Server

The IPA ramdisk files need to be accessible via HTTP/HTTPS by Metal3/Ironic.

**Option A: Local web server**
```bash
# Using Python's built-in server
cd ~/ipa-build
python3 -m http.server 8080

# In another terminal, test:
curl http://localhost:8080/ipa-ramdisk.initramfs | head -c 100
```

**Option B: Copy to existing web server**
```bash
scp ~/ipa-build/ipa-ramdisk.* user@webserver:/var/www/html/ipa/
```

**Option C: Use Kubernetes service (if running in cluster)**
```bash
# Create a ConfigMap or use a PVC with web server
kubectl create configmap ipa-ramdisk --from-file=~/ipa-build/ipa-ramdisk.initramfs --from-file=~/ipa-build/ipa-ramdisk.kernel -n metal3-system
```

### Step 5: Configure Ironic to Use Custom IPA

Update the Ironic ConfigMap to point to your custom IPA:

```bash
kubectl patch configmap ironic -n metal3-system --context kind-metal3-management --type merge -p '{
  "data": {
    "IRONIC_RAMDISK_SSH_KEY": "ssh-rsa AAAAB3NzaC1yc2E...",
    "IRONIC_AGENT_KERNEL_URL": "http://192.168.1.242:8080/ipa-ramdisk.kernel",
    "IRONIC_AGENT_RAMDISK_URL": "http://192.168.1.242:8080/ipa-ramdisk.initramfs"
  }
}'
```

**Note:** Replace `192.168.1.242:8080` with your actual web server address.

### Step 6: Restart Ironic Pods

```bash
kubectl delete pod -n metal3-system --context kind-metal3-management -l app.kubernetes.io/component=ironic
```

Wait for pods to restart:
```bash
kubectl wait --for=condition=Ready pod -n metal3-system --context kind-metal3-management -l app.kubernetes.io/component=ironic --timeout=300s
```

### Step 7: Create NetworkData Secret

Create a secret with network configuration in **nmstate format**:

```bash
kubectl create secret generic provisioning-networkdata \
  -n metal3-system \
  --context kind-metal3-management \
  --from-literal=networkData="
interfaces:
- name: eth0
  type: ethernet
  state: up
  mac-address: \"52:54:00:f5:26:5e\"
  ipv4:
    address:
    - ip: 10.0.2.100
      prefix-length: 24
    enabled: true
    dhcp: false
dns-resolver:
  config:
    server:
    - 8.8.8.8
routes:
  config:
  - destination: 0.0.0.0/0
    next-hop-address: 10.0.2.1
    next-hop-interface: eth0
"
```

### Step 8: Update BareMetalHost

Reference the NetworkData secret in your BareMetalHost:

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: metal3-node-0
  namespace: metal3-system
spec:
  preprovisioningNetworkDataName: provisioning-networkdata  # ← Add this
  # ... rest of config
```

### Step 9: Test Provisioning

Trigger provisioning and monitor:

```bash
# Watch BareMetalHost status
kubectl get baremetalhost metal3-node-0 -n metal3-system --context kind-metal3-management -w

# Watch IPA console (if using virsh)
virsh console metal3-node-0

# Check IPA logs in Ironic
kubectl logs -n metal3-system --context kind-metal3-management -l app.kubernetes.io/component=ironic --tail=50
```

## How It Works

1. **IPA boots** → Systemd starts `configure-network.service`
2. **Script runs** → Looks for config drive (label: `config-2`)
3. **Mounts config drive** → Reads `/mnt/openstack/latest/network_data.json`
4. **Applies config** → Uses `nmc` (if available) or fallback Python method
5. **Network configured** → IPA has static IP and can connect to Ironic

## Troubleshooting

### Build Fails

- **Docker not running**: Start Docker Desktop
- **Out of disk space**: Clean up Docker images: `docker system prune -a`
- **Permission errors**: Check Docker Desktop permissions in System Settings

### IPA Doesn't Apply Network Config

- **Check config drive**: Verify `network_data.json` exists in config drive
- **Check logs**: `virsh console metal3-node-0` to see IPA boot logs
- **Verify script**: Extract ramdisk and check `/usr/local/bin/configure-network.sh` exists

### Network Config Not Applied

- **Verify secret format**: Must be nmstate format (not netplan)
- **Check interface name**: Must match actual interface name in IPA (usually `eth0`)
- **Check MAC address**: Must match the VM's MAC address

## Summary

The complete process:
1. ✅ Build custom IPA ramdisk (Docker method)
2. ✅ Upload to web server
3. ✅ Configure Ironic to use custom IPA
4. ✅ Create NetworkData secret
5. ✅ Update BareMetalHost
6. ✅ Test provisioning

The custom IPA ramdisk will automatically read and apply the NetworkData secret when it boots, giving you static IP configuration instead of relying on DHCP.

