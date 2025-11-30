# Building Ironic Python Agent Ramdisk Manually on Ubuntu

This guide shows how to build an IPA (Ironic Python Agent) ramdisk manually on an Ubuntu VM that includes static network configuration using NM Configurator (nmc), similar to the approach described in the [SUSE Edge Metal3 documentation](https://documentation.suse.com/suse-edge/3.3/html/edge/quickstart-metal3.html).

## Overview

The IPA ramdisk is a minimal Linux environment that runs during bare-metal provisioning. It needs network connectivity to communicate with Ironic. This guide shows how to build a custom IPA ramdisk that:

1. Includes NM Configurator (nmc) for network configuration
2. Includes a script to read network_data.json from the config drive
3. Applies static IP configuration during IPA boot

### Using ironic-python-agent-builder

This guide uses `ironic-python-agent-builder`, which is a specialized tool that simplifies building IPA ramdisks. It automatically includes:
- The base Ubuntu element
- The `ironic-agent` element (IPA itself)
- Proper kernel and initramfs generation

You only need to specify your custom elements for additional functionality.

## Prerequisites

- Ubuntu VM (20.04 or 22.04 recommended)
- Root or sudo access
- At least 10GB free disk space
- Internet connectivity for downloading packages

## Step 1: Install Required Tools

Install the tools needed to build the IPA ramdisk:

```bash
# Update package list
sudo apt-get update

# Install basic build tools
sudo apt-get install -y \
    python3-pip \
    python3-dev \
    git \
    qemu-utils \
    kpartx \
    debootstrap \
    squashfs-tools \
    dosfstools

# Install diskimage-builder and ironic-python-agent-builder
sudo pip3 install diskimage-builder ironic-python-agent-builder

# Verify installation
ironic-python-agent-builder --help

# If the command is not found, add pip user bin to PATH
export PATH=$PATH:$HOME/.local/bin
ironic-python-agent-builder --help
```

## Step 2: Create Network Configuration Script

Create the `configure-network.sh` script that will be included in the IPA ramdisk:

```bash
mkdir -p ~/ipa-build
cd ~/ipa-build

cat > configure-network.sh << 'EOF'
#!/bin/bash
set -eux

# Attempt to statically configure a NIC in the case where we find a network_data.json
# In a configuration drive

CONFIG_DRIVE=$(blkid --label config-2 || true)

if [ -z "${CONFIG_DRIVE}" ]; then
  echo "No config-2 device found, skipping network configuration"
  exit 0
fi

mount -o ro $CONFIG_DRIVE /mnt

NETWORK_DATA_FILE="/mnt/openstack/latest/network_data.json"

if [ ! -f "${NETWORK_DATA_FILE}" ]; then
  umount /mnt
  echo "No network_data.json found, skipping network configuration"
  exit 0
fi

DESIRED_HOSTNAME=$(cat /mnt/openstack/latest/meta_data.json | tr ',{}' '\n' | grep '\"metal3-name\"' | sed 's/.*\"metal3-name\": \"\(.*\)\"/\1/')
if [ -n "${DESIRED_HOSTNAME}" ]; then
  echo "${DESIRED_HOSTNAME}" > /etc/hostname
  hostname "${DESIRED_HOSTNAME}"
fi

mkdir -p /tmp/nmc/{desired,generated}
cp ${NETWORK_DATA_FILE} /tmp/nmc/desired/_all.yaml

umount /mnt

# Use nmc if available, otherwise fall back to manual configuration
if command -v nmc &> /dev/null; then
  nmc generate --config-dir /tmp/nmc/desired --output-dir /tmp/nmc/generated
  nmc apply --config-dir /tmp/nmc/generated
else
  echo "nmc not found, attempting manual network configuration"
  # Fallback: parse network_data.json and configure manually
  # This is a simplified fallback - adjust based on your needs
  python3 << PYEOF
import json
import subprocess
import os

with open('/tmp/nmc/desired/_all.yaml', 'r') as f:
    net_data = json.load(f)

for interface in net_data.get('interfaces', []):
    if_name = interface.get('name')
    if not if_name:
        continue
    
    ipv4 = interface.get('ipv4', {})
    if ipv4.get('enabled') and not ipv4.get('dhcp'):
        addresses = ipv4.get('address', [])
        if addresses:
            addr = addresses[0]
            ip = addr.get('ip')
            prefix = addr.get('prefix-length', 24)
            
            # Configure IP address
            subprocess.run(['ip', 'addr', 'add', f'{ip}/{prefix}', 'dev', if_name], check=False)
            subprocess.run(['ip', 'link', 'set', 'up', 'dev', if_name], check=False)
            
            # Configure routes
            routes = net_data.get('routes', {}).get('config', [])
            for route in routes:
                dest = route.get('destination', '0.0.0.0/0')
                next_hop = route.get('next-hop-address')
                if next_hop:
                    subprocess.run(['ip', 'route', 'add', dest, 'via', next_hop], check=False)
PYEOF
fi
EOF

chmod +x configure-network.sh
```

## Step 3: Create Custom Element for IPA Ramdisk

Create a custom diskimage-builder element that includes nmstate and the network configuration script:

```bash
mkdir -p ~/ipa-build/elements/ipa-network-config
cd ~/ipa-build/elements/ipa-network-config

# Create element.yaml
cat > element.yaml << 'EOF'
---
dependencies:
  - package-install
EOF

# Create install.d script
mkdir -p install.d
cat > install.d/10-ipa-network-config << 'EOF'
#!/bin/bash
set -eux

# Install nmstate and dependencies
if [ -f /etc/debian_version ]; then
    # For Debian/Ubuntu-based IPA
    apt-get update
    apt-get install -y \
        python3-nmstate \
        jq \
        python3-yaml \
        python3-netifaces || true
elif [ -f /etc/redhat-release ]; then
    # For RHEL/CentOS-based IPA
    yum install -y \
        python3-nmstate \
        jq \
        python3-pyyaml || true
fi

# Copy configure-network.sh script
mkdir -p ${TARGET_ROOT}/usr/local/bin
cp ${ELEMENT_PATH}/configure-network.sh ${TARGET_ROOT}/usr/local/bin/configure-network.sh
chmod +x ${TARGET_ROOT}/usr/local/bin/configure-network.sh

# Create systemd service to run on boot
mkdir -p ${TARGET_ROOT}/etc/systemd/system
cat > ${TARGET_ROOT}/etc/systemd/system/configure-network.service << 'SVCEOF'
[Unit]
Description=Configure Network from Config Drive
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/configure-network.sh
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
SVCEOF

# Enable the service
mkdir -p ${TARGET_ROOT}/etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/configure-network.service \
    ${TARGET_ROOT}/etc/systemd/system/multi-user.target.wants/configure-network.service
EOF

chmod +x install.d/10-ipa-network-config

# Copy the configure-network.sh script to the element directory
cp ~/ipa-build/configure-network.sh .
```

## Step 4: Build the IPA Ramdisk

Build the IPA ramdisk with the custom network configuration using `ironic-python-agent-builder`:

```bash
cd ~/ipa-build

# Set environment variables
export DIB_RELEASE=jammy  # or focal for Ubuntu 20.04
export ELEMENTS_PATH=~/ipa-build/elements:${ELEMENTS_PATH:-}

# Additional packages to install (optional, can also be specified in element)
export DIB_INSTALLTYPE_package_install="jq python3-yaml python3-netifaces"

# Build the IPA ramdisk using ironic-python-agent-builder
# Syntax: ironic-python-agent-builder -o OUTPUT_NAME [ELEMENT1] [ELEMENT2] ...
# Note: This may take 10-20 minutes depending on your system
ironic-python-agent-builder -o ipa-ramdisk ipa-network-config

# The output will be:
# - ipa-ramdisk.initramfs (the ramdisk)
# - ipa-ramdisk.kernel (the kernel)
```

**Note**: The `ironic-python-agent-builder` tool automatically includes the `ubuntu` and `ironic-agent` elements, so you only need to specify your custom element (`ipa-network-config`) as an additional argument.

**Package Installation**: Packages like `network-manager`, `jq`, `python3-yaml`, etc. are installed in the custom element's `install.d` script. If you need to add more packages, you can either:
- Modify the element's `install.d/10-ipa-network-config` script
- Use the `-p` flag with `disk-image-create` (fallback method)
- Note: `DIB_EXTRA_PACKAGES` environment variable is not directly supported by `ironic-python-agent-builder`

## Step 5: Verify the Build

Check that the ramdisk was created successfully:

```bash
cd ~/ipa-build

# Check files exist
ls -lh ipa-ramdisk.*

# Check ramdisk contents (optional)
mkdir -p /tmp/ipa-extract
cd /tmp/ipa-extract
zcat ~/ipa-build/ipa-ramdisk.initramfs | cpio -idmv

# Verify configure-network.sh is included
ls -l usr/local/bin/configure-network.sh

# Verify nmc is available (if installed)
find . -name nmc -type f 2>/dev/null || echo "nmc may be in different location"

# Cleanup
cd ~
rm -rf /tmp/ipa-extract
```

## Step 6: Use with Metal3

**See the complete guide**: [`CONFIGURE_METAL3_CUSTOM_IPA.md`](CONFIGURE_METAL3_CUSTOM_IPA.md)

### Quick Start

1. **Copy files to a web server accessible by Metal3**:
   ```bash
   # Example: Copy to a local web server
   sudo mkdir -p /var/www/html/ipa
   sudo cp ~/ipa-build/ipa-ramdisk.* /var/www/html/ipa/
   sudo chmod 644 /var/www/html/ipa/ipa-ramdisk.*
   ```

2. **Update Metal3 Ironic configuration** to use your custom IPA:
   ```bash
   # Set your web server URL
   export IPA_SERVER="http://your-web-server-ip"
   
   # Update Ironic ConfigMap
   kubectl patch configmap ironic -n metal3-system --type merge -p "{
     \"data\": {
       \"IRONIC_RAMDISK_URL\": \"${IPA_SERVER}/ipa/ipa-ramdisk.initramfs\",
       \"IRONIC_KERNEL_URL\": \"${IPA_SERVER}/ipa/ipa-ramdisk.kernel\"
     }
   }"
   
   # Restart Ironic pods
   kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
   ```

For detailed instructions including Helm configuration, troubleshooting, and verification steps, see [`CONFIGURE_METAL3_CUSTOM_IPA.md`](CONFIGURE_METAL3_CUSTOM_IPA.md).

### Option 2: Create NetworkData Secret

Create a Kubernetes Secret with network configuration in nmstate format:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: provisioning-networkdata
  namespace: metal3-system
type: Opaque
stringData:
  networkData: |
    interfaces:
    - name: enp1s0
      type: ethernet
      state: up
      mac-address: "00:f3:65:8a:a3:b0"
      ipv4:
        address:
        - ip: 192.168.125.200
          prefix-length: 24
        enabled: true
        dhcp: false
    dns-resolver:
      config:
        server:
        - 192.168.125.1
    routes:
      config:
      - destination: 0.0.0.0/0
        next-hop-address: 192.168.125.1
        next-hop-interface: enp1s0
EOF
```

### Option 3: Reference in BareMetalHost

Reference the NetworkData secret in your BareMetalHost:

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-0
  namespace: metal3-system
spec:
  online: true
  bootMACAddress: "00:f3:65:8a:a3:b0"
  bmc:
    address: "redfish+http://<bmc-ip>:8000/redfish/v1/Systems/node-0"
    credentialsName: node-0-bmc-secret
  bootMode: "UEFI"
  preprovisioningNetworkDataName: provisioning-networkdata  # Reference the secret
  image:
    url: "http://<image-server>:8080/SLE-Micro.raw"
    checksum: "http://<image-server>:8080/SLE-Micro.raw.sha256"
    checksumType: "sha256"
    format: "raw"
```

## How It Works

1. **IPA boots** from virtual media (ISO) or PXE
2. **Systemd starts** the `configure-network.service`
3. **Script runs** and looks for config drive with label `config-2`
4. **Mounts config drive** and reads `network_data.json`
5. **Applies network config** using nmc (NM Configurator) or fallback method
6. **IPA has network connectivity** and can communicate with Ironic

## Troubleshooting

### Issue: nmc not found in ramdisk

**Solution**: The nmstate package may not be available in the base Ubuntu image. You can:

1. **Use the fallback method** in the script (already included)
2. **Build nmc from source** in the element
3. **Use a different base image** that includes nmstate

### Issue: Config drive not found

**Check**:
- Ironic is creating the config drive correctly
- The BareMetalHost has `preprovisioningNetworkDataName` set
- The config drive is being attached to the VM

```bash
# In IPA, check for config drive
blkid | grep config-2
lsblk
```

### Issue: Network configuration not applied

**Debug**:
```bash
# In IPA, check service status
systemctl status configure-network.service
journalctl -u configure-network.service -n 50

# Check if network_data.json exists
mount /dev/sr0 /mnt  # or appropriate device
ls -la /mnt/openstack/latest/
cat /mnt/openstack/latest/network_data.json
```

### Issue: Interface name mismatch

**Solution**: Use MAC address matching in networkData:

```yaml
interfaces:
- type: ethernet
  state: up
  mac-address: "00:f3:65:8a:a3:b0"  # Match by MAC instead of name
  ipv4:
    # ... rest of config
```

## Alternative: Simpler Build Without nmc

If you want a simpler build without nmstate/nmc, you can modify the script to use basic `ip` commands:

```bash
# Simplified configure-network.sh without nmc
cat > configure-network-simple.sh << 'EOF'
#!/bin/bash
set -eux

CONFIG_DRIVE=$(blkid --label config-2 || true)
[ -z "${CONFIG_DRIVE}" ] && exit 0

mount -o ro $CONFIG_DRIVE /mnt
NETWORK_DATA_FILE="/mnt/openstack/latest/network_data.json"
[ ! -f "${NETWORK_DATA_FILE}" ] && { umount /mnt; exit 0; }

# Parse JSON and configure network using ip commands
python3 << PYEOF
import json
import subprocess

with open('${NETWORK_DATA_FILE}', 'r') as f:
    net_data = json.load(f)

for interface in net_data.get('interfaces', []):
    if_name = interface.get('name')
    mac = interface.get('mac-address')
    
    # Find interface by MAC if name doesn't match
    if not if_name or not any(if_name in line for line in subprocess.check_output(['ip', 'link']).decode().split('\n')):
        if mac:
            for line in subprocess.check_output(['ip', 'link']).decode().split('\n'):
                if mac.lower() in line.lower():
                    if_name = line.split(':')[1].strip()
                    break
    
    if not if_name:
        continue
    
    ipv4 = interface.get('ipv4', {})
    if ipv4.get('enabled') and not ipv4.get('dhcp'):
        addresses = ipv4.get('address', [])
        if addresses:
            addr = addresses[0]
            ip = addr.get('ip')
            prefix = addr.get('prefix-length', 24)
            subprocess.run(['ip', 'addr', 'add', f'{ip}/{prefix}', 'dev', if_name], check=False)
            subprocess.run(['ip', 'link', 'set', 'up', 'dev', if_name], check=False)
    
    routes = net_data.get('routes', {}).get('config', [])
    for route in routes:
        dest = route.get('destination', '0.0.0.0/0')
        next_hop = route.get('next-hop-address')
        if next_hop:
            subprocess.run(['ip', 'route', 'add', dest, 'via', next_hop], check=False)
PYEOF

umount /mnt
EOF
```

## References

- [SUSE Edge Metal3 Documentation - Static IP Configuration](https://documentation.suse.com/suse-edge/3.3/html/edge/quickstart-metal3.html)
- [Ironic Python Agent Documentation](https://docs.openstack.org/ironic-python-agent/latest/)
- [Diskimage Builder Documentation](https://docs.openstack.org/diskimage-builder/latest/)

