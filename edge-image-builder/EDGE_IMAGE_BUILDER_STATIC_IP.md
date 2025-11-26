# Implementing Static IP Configuration with Edge Image Builder

## Overview

This guide shows how to configure static IPs for Metal3-provisioned hosts using Edge Image Builder's network configuration script and nmstate format.

**Reference**: [SUSE Edge Metal3 Documentation - Static IP Configuration](https://documentation.suse.com/suse-edge/3.3/html/edge/quickstart-metal3.html)

## Architecture

```
Edge Image Builder
    │
    ├── Builds OS image
    │   └── Includes: configure-network.sh script
    │
    └── Network folder
        └── configure-network.sh

Metal3 Provisioning
    │
    ├── BareMetalHost
    │   └── preprovisioningNetworkDataName: controlplane-0-networkdata
    │
    ├── Secret (nmstate format)
    │   └── networkData: (nmstate YAML)
    │
    └── Provisioned Host
        ├── First boot runs configure-network.sh
        ├── Reads network_data.json from config drive
        └── Applies static IP via NM Configurator
```

## Step 1: Create configure-network.sh Script

### Location in Edge Image Builder

When building the image with Edge Image Builder, create this script in the **network folder**:

```bash
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
echo "${DESIRED_HOSTNAME}" > /etc/hostname

mkdir -p /tmp/nmc/{desired,generated}
cp ${NETWORK_DATA_FILE} /tmp/nmc/desired/_all.yaml
umount /mnt

./nmc generate --config-dir /tmp/nmc/desired --output-dir /tmp/nmc/generated
./nmc apply --config-dir /tmp/nmc/generated
```

### What This Script Does

1. **Finds config drive**: Looks for device with label `config-2` (standard OpenStack/Ironic config drive)
2. **Mounts config drive**: Mounts it read-only to `/mnt`
3. **Reads network data**: Looks for `/mnt/openstack/latest/network_data.json`
4. **Sets hostname**: Extracts hostname from `meta_data.json`
5. **Uses NM Configurator**: 
   - Copies network data to nmc desired directory
   - Generates NetworkManager connections
   - Applies the configuration

## Step 2: Include Script in Edge Image Builder Build

### Option A: Using Edge Image Builder Config

Create your Edge Image Builder configuration:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: eib-build-config
  namespace: edge-image-builder
data:
  build-config.yaml: |
    apiVersion: v1
    kind: ElementalImage
    metadata:
      name: metal3-static-ip-image
    spec:
      base: "SL-Micro.x86_64-6.1-Base-GM.raw"
      output: "SLE-Micro-metal3-static-ip.raw"
      cloudConfig:
        users:
          - name: root
            passwd: "$6$..."  # Generated with: openssl passwd -6
      systemd:
        units:
          # Service to run configure-network.sh on first boot
          - name: configure-network.service
            enabled: true
            contents: |
              [Unit]
              Description=Configure Network from Config Drive
              After=network-online.target
              Wants=network-online.target
              ConditionPathExists=!/etc/systemd/system/configure-network.service.d/ran-once.conf
              
              [Service]
              Type=oneshot
              ExecStart=/usr/local/bin/configure-network.sh
              RemainAfterExit=yes
              StandardOutput=journal+console
              StandardError=journal+console
              
              [Install]
              WantedBy=multi-user.target
      files:
        # Copy configure-network.sh to image
        - path: /usr/local/bin/configure-network.sh
          permissions: "0755"
          contents: |
            #!/bin/bash
            set -eux
            
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
            echo "${DESIRED_HOSTNAME}" > /etc/hostname
            
            mkdir -p /tmp/nmc/{desired,generated}
            cp ${NETWORK_DATA_FILE} /tmp/nmc/desired/_all.yaml
            umount /mnt
            
            ./nmc generate --config-dir /tmp/nmc/desired --output-dir /tmp/nmc/generated
            ./nmc apply --config-dir /tmp/nmc/generated
```

### Option B: Manual File Addition

If building manually or using different methods:

1. **Create the script file**:
   ```bash
   mkdir -p /path/to/eib/network
   cat > /path/to/eib/network/configure-network.sh <<'EOF'
   #!/bin/bash
   set -eux
   
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
   echo "${DESIRED_HOSTNAME}" > /etc/hostname
   
   mkdir -p /tmp/nmc/{desired,generated}
   cp ${NETWORK_DATA_FILE} /tmp/nmc/desired/_all.yaml
   umount /mnt
   
   ./nmc generate --config-dir /tmp/nmc/desired --output-dir /tmp/nmc/generated
   ./nmc apply --config-dir /tmp/nmc/generated
   EOF
   
   chmod +x /path/to/eib/network/configure-network.sh
   ```

2. **Ensure NM Configurator (nmc) is in the image**:
   ```yaml
   packages:
     - nmstate  # Provides nmc tool
   ```

## Step 3: Create NetworkData Secret (nmstate Format)

### Secret Format

The networkData must be in **nmstate format** (not netplan):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: controlplane-0-networkdata
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
```

### For Your Bridge Network Setup

Adapted for your OpenStack VM bridge network (10.2.83.x):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: node-0-networkdata
  namespace: metal3-system
type: Opaque
stringData:
  networkData: |
    interfaces:
    - name: ens3
      type: ethernet
      state: up
      mac-address: "52:54:00:XX:XX:XX"  # Your VM's MAC address
      ipv4:
        address:
        - ip: 10.2.83.181
          prefix-length: 24
        enabled: true
        dhcp: false
    dns-resolver:
      config:
        server:
        - 8.8.8.8
        - 8.8.4.4
    routes:
      config:
      - destination: 0.0.0.0/0
        next-hop-address: 10.2.83.1
        next-hop-interface: ens3
```

### Multiple Interfaces Example

If you have multiple network interfaces:

```yaml
networkData: |
  interfaces:
  - name: ens3
    type: ethernet
    state: up
    mac-address: "52:54:00:XX:XX:XX"
    ipv4:
      address:
      - ip: 10.2.83.181
        prefix-length: 24
      enabled: true
      dhcp: false
  - name: ens4
    type: ethernet
    state: up
    mac-address: "52:54:00:YY:YY:YY"
    ipv4:
      enabled: false
  dns-resolver:
    config:
      server:
      - 8.8.8.8
  routes:
    config:
    - destination: 0.0.0.0/0
      next-hop-address: 10.2.83.1
      next-hop-interface: ens3
```

## Step 4: Reference in BareMetalHost

### Complete BareMetalHost Example

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-0
  namespace: metal3-system
  labels:
    cluster-role: control-plane
spec:
  online: true
  bootMACAddress: "52:54:00:XX:XX:XX"
  bmc:
    address: "redfish+http://10.2.83.180:8000/redfish/v1/Systems/node-0"
    credentialsName: node-0-bmc-secret
  bootMode: "UEFI"
  automatedCleaning: false
  # Reference the networkData secret
  preprovisioningNetworkDataName: node-0-networkdata
  image:
    url: "http://imagecache.local:8080/SLE-Micro-metal3-static-ip.raw"
    checksum: "http://imagecache.local:8080/SLE-Micro-metal3-static-ip.raw.sha256"
    checksumType: "sha256"
    format: "raw"
---
apiVersion: v1
kind: Secret
metadata:
  name: node-0-bmc-secret
  namespace: metal3-system
type: Opaque
data:
  username: YWRtaW4=  # admin
  password: YWRtaW4=  # admin
```

## Step 5: Apply Configuration

### Create NetworkData Secret

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: node-0-networkdata
  namespace: metal3-system
type: Opaque
stringData:
  networkData: |
    interfaces:
    - name: ens3
      type: ethernet
      state: up
      mac-address: "52:54:00:XX:XX:XX"
      ipv4:
        address:
        - ip: 10.2.83.181
          prefix-length: 24
        enabled: true
        dhcp: false
    dns-resolver:
      config:
        server:
        - 8.8.8.8
        - 8.8.4.4
    routes:
      config:
      - destination: 0.0.0.0/0
        next-hop-address: 10.2.83.1
        next-hop-interface: ens3
EOF
```

### Create BareMetalHost

```bash
# Get MAC address from VM
MAC=$(sudo virsh domiflist node-0 | grep -oE "([0-9a-f]{2}:){5}[0-9a-f]{2}" | head -1)

kubectl apply -f - <<EOF
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-0
  namespace: metal3-system
spec:
  online: true
  bootMACAddress: "${MAC}"
  bmc:
    address: "redfish+http://10.2.83.180:8000/redfish/v1/Systems/node-0"
    credentialsName: node-0-bmc-secret
  bootMode: "UEFI"
  preprovisioningNetworkDataName: node-0-networkdata
  image:
    url: "http://<image-server>:8080/SLE-Micro-metal3-static-ip.raw"
    checksum: "http://<image-server>:8080/SLE-Micro-metal3-static-ip.raw.sha256"
    checksumType: "sha256"
    format: "raw"
EOF
```

## How It Works

### Provisioning Flow

1. **Metal3 provisions the host**:
   - Downloads OS image
   - Creates config drive with network_data.json
   - Attaches config drive to host

2. **Host boots for first time**:
   - OS boots from provisioned image
   - `configure-network.service` runs
   - Script finds config drive (label: config-2)
   - Mounts config drive

3. **Network configuration applied**:
   - Script reads `network_data.json` from config drive
   - Extracts hostname from `meta_data.json`
   - Uses NM Configurator (nmc) to:
     - Generate NetworkManager connection files
     - Apply static IP configuration

4. **Network is configured**:
   - Static IP is set
   - Routes are configured
   - DNS is configured
   - Hostname is set

## Key Differences from Netplan Approach

| Aspect | Netplan (Previous) | nmstate (This Method) |
|--------|-------------------|----------------------|
| Format | netplan YAML | nmstate YAML |
| Tool | netplan/systemd-networkd | NM Configurator (nmc) |
| Applied by | cloud-init | configure-network.sh script |
| When | During IPA boot | On first OS boot |
| Location | IPA ramdisk | Provisioned OS |

## Finding Interface Names

### For Your Bridge Network

Bridge networks may use different interface names. Find the actual name:

```bash
# From provisioned host (after first boot)
ip link show

# Common names:
# - ens3 (systemd predictable naming)
# - enp1s0 (PCI-based naming)
# - eth0 (traditional, less common on bridges)
```

### Use MAC Address Matching (Alternative)

If interface name is unpredictable, you can match by MAC in nmstate:

```yaml
networkData: |
  interfaces:
  - type: ethernet
    state: up
    mac-address: "52:54:00:XX:XX:XX"  # Match by MAC
    ipv4:
      address:
      - ip: 10.2.83.181
        prefix-length: 24
      enabled: true
      dhcp: false
```

## Complete Example: Multiple Nodes

### Create NetworkData for Each Node

```bash
# Node 0
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: node-0-networkdata
  namespace: metal3-system
type: Opaque
stringData:
  networkData: |
    interfaces:
    - name: ens3
      type: ethernet
      state: up
      mac-address: "52:54:00:XX:XX:XX"
      ipv4:
        address:
        - ip: 10.2.83.181
          prefix-length: 24
        enabled: true
        dhcp: false
    routes:
      config:
      - destination: 0.0.0.0/0
        next-hop-address: 10.2.83.1
        next-hop-interface: ens3
EOF

# Node 1
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: node-1-networkdata
  namespace: metal3-system
type: Opaque
stringData:
  networkData: |
    interfaces:
    - name: ens3
      type: ethernet
      state: up
      mac-address: "52:54:00:YY:YY:YY"
      ipv4:
        address:
        - ip: 10.2.83.182
          prefix-length: 24
        enabled: true
        dhcp: false
    routes:
      config:
      - destination: 0.0.0.0/0
        next-hop-address: 10.2.83.1
        next-hop-interface: ens3
EOF

# Node 2
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: node-2-networkdata
  namespace: metal3-system
type: Opaque
stringData:
  networkData: |
    interfaces:
    - name: ens3
      type: ethernet
      state: up
      mac-address: "52:54:00:ZZ:ZZ:ZZ"
      ipv4:
        address:
        - ip: 10.2.83.183
          prefix-length: 24
        enabled: true
        dhcp: false
    routes:
      config:
      - destination: 0.0.0.0/0
        next-hop-address: 10.2.83.1
        next-hop-interface: ens3
EOF
```

### Create BareMetalHosts

```bash
# Node 0
MAC0=$(sudo virsh domiflist node-0 | grep -oE "([0-9a-f]{2}:){5}[0-9a-f]{2}" | head -1)
kubectl apply -f - <<EOF
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-0
  namespace: metal3-system
spec:
  bootMACAddress: "${MAC0}"
  bmc:
    address: "redfish+http://10.2.83.180:8000/redfish/v1/Systems/node-0"
    credentialsName: node-0-bmc-secret
  preprovisioningNetworkDataName: node-0-networkdata
  image:
    url: "http://<image-server>:8080/SLE-Micro-metal3-static-ip.raw"
    checksum: "http://<image-server>:8080/SLE-Micro-metal3-static-ip.raw.sha256"
    checksumType: "sha256"
    format: "raw"
EOF

# Repeat for node-1, node-2 with respective MACs and networkData names
```

## Troubleshooting

### Script Not Running

```bash
# Check if script exists in image
# After provisioning, SSH into host:
ls -l /usr/local/bin/configure-network.sh

# Check systemd service status
systemctl status configure-network.service

# Check service logs
journalctl -u configure-network.service -n 50
```

### Config Drive Not Found

```bash
# Check if config drive is mounted
lsblk | grep config

# Check for config-2 label
blkid | grep config-2

# Verify Ironic created config drive
# Check Ironic logs
kubectl logs -n metal3-system -l app.kubernetes.io/component=ironic | grep -i config
```

### Network Not Configured

```bash
# Check if network_data.json exists
# On provisioned host:
mount /dev/sr0 /mnt  # Config drive usually on first CD-ROM
ls -l /mnt/openstack/latest/

# Check network_data.json content
cat /mnt/openstack/latest/network_data.json

# Check NM Configurator logs
journalctl | grep nmc
```

### Interface Name Mismatch

```bash
# Find actual interface name
ip link show

# Update NetworkData secret with correct interface name
kubectl edit secret node-0-networkdata -n metal3-system
# Change "name: ens3" to actual interface name
```

### NM Configurator Not Available

```bash
# Check if nmc is installed
which nmc

# Install if missing (should be in image)
# Add to Edge Image Builder packages:
packages:
  - nmstate  # Provides nmc
```

## Verification

### After Provisioning

```bash
# SSH into provisioned host
ssh root@10.2.83.181

# Check network configuration
ip addr show
# Should show: 10.2.83.181/24

# Check routes
ip route show
# Should show: default via 10.2.83.1

# Check hostname
hostname
# Should match metal3-name from meta_data.json

# Check NetworkManager connections
nmcli connection show
nmcli device status
```

## Key Points

1. **Script location**: Must be in network folder or copied to `/usr/local/bin/` during image build
2. **NM Configurator required**: Image must include `nmstate` package (provides `nmc` tool)
3. **nmstate format**: NetworkData must be in nmstate YAML format (not netplan)
4. **Config drive**: Ironic creates config drive with network_data.json automatically
5. **First boot only**: Script runs on first boot, then should be disabled
6. **Interface names**: May need to match actual interface name (ens3, enp1s0, etc.)

## References

- [SUSE Edge Metal3 Quickstart - Static IP Configuration](https://documentation.suse.com/suse-edge/3.3/html/edge/quickstart-metal3.html#sec-edge-metal3-static-ip)
- [NM Configurator Documentation](https://documentation.suse.com/suse-edge/3.3/html/edge/edge-networking.html)
- [nmstate Format](https://nmstate.io/)

