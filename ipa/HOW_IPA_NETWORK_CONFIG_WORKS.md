# How IPA Ramdisk Network Configuration is Assigned

## Overview

The IPA (Ironic Python Agent) ramdisk network configuration is assigned through a multi-step process that involves:

1. **Building a custom IPA ramdisk** with network configuration scripts
2. **Creating a Kubernetes Secret** with network configuration in nmstate format
3. **Metal3 injecting the config** into a config drive when IPA boots
4. **IPA reading and applying** the network configuration at boot time

## Architecture Flow

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Build Time: Custom IPA Ramdisk                          │
│    - Includes configure-network.sh script                   │
│    - Includes systemd service (configure-network.service)   │
│    - Includes nmstate/nmc (optional, with fallback)         │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. Kubernetes: NetworkData Secret                           │
│    - Secret: provisioning-networkdata                       │
│    - Format: nmstate YAML                                   │
│    - Contains: IP, gateway, DNS, routes                     │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. BareMetalHost: Reference Secret                          │
│    - spec.preprovisioningNetworkDataName:                   │
│      "provisioning-networkdata"                             │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. Metal3/Ironic: Create Config Drive                      │
│    - Reads NetworkData secret                               │
│    - Creates ISO with label "config-2"                      │
│    - Contains: network_data.json                            │
│    - Attaches to VM as virtual media                        │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. IPA Boot: Apply Network Config                          │
│    - Systemd starts configure-network.service               │
│    - Script finds config drive (blkid --label config-2)     │
│    - Mounts config drive                                    │
│    - Reads /mnt/openstack/latest/network_data.json          │
│    - Applies config using nmc or fallback method             │
│    - Network is configured with static IP                   │
└─────────────────────────────────────────────────────────────┘
```

## Step-by-Step Explanation

### Step 1: Build Custom IPA Ramdisk

The custom IPA ramdisk includes:

**Files added to ramdisk:**
- `/usr/local/bin/configure-network.sh` - Network configuration script
- `/etc/systemd/system/configure-network.service` - Systemd service
- `/etc/systemd/system/multi-user.target.wants/configure-network.service` - Service symlink

**How it's built:**
```bash
# Using the build script
cd scripts/setup
./build-ipa-ramdisk.sh

# This creates:
# - ipa-ramdisk.initramfs (the ramdisk)
# - ipa-ramdisk.kernel (the kernel)
```

**What the script does:**
1. Creates a custom diskimage-builder element (`ipa-network-config`)
2. Installs dependencies (jq, python3-yaml, network-manager, nmstate)
3. Copies `configure-network.sh` into the ramdisk
4. Creates and enables the systemd service
5. Builds the ramdisk using `ironic-python-agent-builder`

### Step 2: Create NetworkData Secret

The NetworkData secret contains the network configuration in **nmstate format** (not netplan):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: provisioning-networkdata
  namespace: metal3-system
type: Opaque
stringData:
  networkData: |
    interfaces:
    - name: eth0
      type: ethernet
      state: up
      mac-address: "52:54:00:f5:26:5e"
      ipv4:
        address:
        - ip: 192.168.124.100
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
        next-hop-address: 192.168.124.1
        next-hop-interface: eth0
```

**Key points:**
- Must use **nmstate format** (not netplan YAML)
- Interface can be matched by name or MAC address
- Static IP configuration (dhcp: false)
- Routes and DNS are configured

### Step 3: Reference in BareMetalHost

The BareMetalHost references the secret:

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: metal3-node-0
  namespace: metal3-system
spec:
  preprovisioningNetworkDataName: provisioning-networkdata  # ← References the secret
  # ... other config
```

**What this does:**
- Tells Metal3 to use the `provisioning-networkdata` secret
- Metal3 will inject this into the config drive when IPA boots

### Step 4: Metal3 Creates Config Drive

When IPA boots, Metal3/Ironic:

1. **Reads the NetworkData secret** referenced by BareMetalHost
2. **Creates an ISO image** with:
   - Label: `config-2` (OpenStack standard)
   - Path: `/openstack/latest/network_data.json`
   - Contains the network configuration from the secret
3. **Attaches the ISO** to the VM as virtual media (or via PXE)

**Config drive structure:**
```
/mnt/
└── openstack/
    └── latest/
        ├── network_data.json    ← Network configuration
        └── meta_data.json       ← Metadata (hostname, etc.)
```

### Step 5: IPA Applies Network Configuration

When IPA boots:

1. **Systemd starts** `configure-network.service` (after network-online.target)
2. **Script runs** `/usr/local/bin/configure-network.sh`
3. **Script finds config drive:**
   ```bash
   CONFIG_DRIVE=$(blkid --label config-2)
   ```
4. **Mounts config drive:**
   ```bash
   mount -o ro $CONFIG_DRIVE /mnt
   ```
5. **Reads network_data.json:**
   ```bash
   NETWORK_DATA_FILE="/mnt/openstack/latest/network_data.json"
   ```
6. **Applies configuration:**
   - **Preferred method:** Uses `nmc` (NM Configurator) if available
   - **Fallback method:** Parses JSON and uses `ip` commands directly

**Fallback method (if nmc not available):**
```python
# Parses network_data.json
# Finds interface by name or MAC address
# Configures IP: ip addr add <ip>/<prefix> dev <interface>
# Brings interface up: ip link set up dev <interface>
# Adds routes: ip route add <dest> via <gateway>
# Configures DNS: writes to /etc/resolv.conf
```

## Network Configuration Script Details

The `configure-network.sh` script:

```bash
#!/bin/bash
set -eux

# 1. Find config drive
CONFIG_DRIVE=$(blkid --label config-2 || true)
if [ -z "${CONFIG_DRIVE}" ]; then
  echo "No config-2 device found, skipping network configuration"
  exit 0
fi

# 2. Mount config drive
mount -o ro $CONFIG_DRIVE /mnt

# 3. Read network_data.json
NETWORK_DATA_FILE="/mnt/openstack/latest/network_data.json"
if [ ! -f "${NETWORK_DATA_FILE}" ]; then
  umount /mnt
  echo "No network_data.json found, skipping network configuration"
  exit 0
fi

# 4. Set hostname (if provided)
DESIRED_HOSTNAME=$(cat /mnt/openstack/latest/meta_data.json | ...)
if [ -n "${DESIRED_HOSTNAME}" ]; then
  echo "${DESIRED_HOSTNAME}" > /etc/hostname
  hostname "${DESIRED_HOSTNAME}"
fi

# 5. Copy network_data.json for processing
mkdir -p /tmp/nmc/{desired,generated}
cp ${NETWORK_DATA_FILE} /tmp/nmc/desired/_all.yaml
umount /mnt

# 6. Apply configuration
if command -v nmc &> /dev/null; then
  # Use nmc (preferred)
  nmc generate --config-dir /tmp/nmc/desired --output-dir /tmp/nmc/generated
  nmc apply --config-dir /tmp/nmc/generated
else
  # Fallback: parse JSON and use ip commands
  python3 << PYEOF
  # ... Python code to parse and apply config
  PYEOF
fi
```

## Why This Approach?

1. **Flexibility:** Network config can be changed without rebuilding IPA
2. **Per-host configuration:** Each BareMetalHost can have different network config
3. **Standard format:** Uses OpenStack config drive standard (config-2 label)
4. **Fallback support:** Works even if nmstate/nmc is not available
5. **MAC address matching:** Can match interfaces by MAC if name doesn't match

## Common Issues and Solutions

### Issue: Config drive not found

**Symptoms:**
- IPA boots but network is not configured
- Script logs: "No config-2 device found"

**Solutions:**
1. Verify BareMetalHost has `preprovisioningNetworkDataName` set
2. Check that Metal3/Ironic is creating the config drive
3. Verify the secret exists and is correctly formatted

### Issue: Interface name mismatch

**Symptoms:**
- Network config not applied to correct interface
- Interface name in secret doesn't match actual interface

**Solutions:**
1. Use MAC address matching in NetworkData:
   ```yaml
   interfaces:
   - type: ethernet
     mac-address: "52:54:00:f5:26:5e"  # Match by MAC
     # ... rest of config
   ```
2. Check actual interface name in IPA: `ip link show`

### Issue: nmc not found

**Symptoms:**
- Script logs: "nmc not found, attempting manual network configuration"

**Solutions:**
1. This is OK - fallback method will be used
2. To include nmc, ensure nmstate package is installed in ramdisk build
3. Fallback method uses `ip` commands and works reliably

## Verification

### Check NetworkData Secret:
```bash
kubectl get secret provisioning-networkdata -n metal3-system -o yaml
```

### Check BareMetalHost:
```bash
kubectl get baremetalhost metal3-node-0 -n metal3-system -o yaml | grep preprovisioningNetworkDataName
```

### Check IPA Network (in IPA console):
```bash
# Find config drive
blkid | grep config-2

# Mount and check
mount /dev/sr0 /mnt
cat /mnt/openstack/latest/network_data.json

# Check network
ip addr show
ip route show
systemctl status configure-network.service
journalctl -u configure-network.service -n 50
```

## Quick Setup

Use the setup script:

```bash
cd scripts/setup
./setup-ipa-network-config.sh \
  --interface eth0 \
  --ip 192.168.124.100 \
  --gateway 192.168.124.1 \
  --mac "52:54:00:f5:26:5e"
```

Or interactive mode:
```bash
./setup-ipa-network-config.sh
# Will prompt for values
```

## References

- [SUSE Edge Metal3 Documentation](https://documentation.suse.com/suse-edge/3.3/html/edge/quickstart-metal3.html)
- [Ironic Python Agent Documentation](https://docs.openstack.org/ironic-python-agent/latest/)
- [OpenStack Config Drive Specification](https://docs.openstack.org/nova/latest/user/config-drive.html)

