# Building Custom IPA Ramdisk: Requirements and Changes from Default

## Overview

The **default IPA ramdisk** only supports **DHCP** for network configuration. To support **static IP configuration** via Metal3's NetworkData secrets, you need to build a custom IPA ramdisk with additional components.

## What You Need on Ubuntu VM

### 1. Required Packages

```bash
sudo apt-get update
sudo apt-get install -y \
    python3-pip \
    python3-dev \
    git \
    qemu-utils \
    kpartx \
    debootstrap \
    squashfs-tools \
    dosfstools \
    curl
```

### 2. Required Python Packages

```bash
pip3 install --user diskimage-builder ironic-python-agent-builder
```

Add to your `~/.bashrc`:
```bash
export PATH=$PATH:$HOME/.local/bin
```

### 3. Fix Known Issues

**Fix pip version requirement:**
```bash
# The default requires pip==25.1.1, but Ubuntu 22.04 has 25.0.1
sed -i 's/REQUIRED_PIP_STR="25\.1\.1"/REQUIRED_PIP_STR="25.0.1"/' \
    ~/.local/share/ironic-python-agent-builder/dib/ironic-python-agent-ramdisk/install.d/ironic-python-agent-ramdisk-source-install/60-ironic-python-agent-ramdisk-install

sed -i 's/REQUIRED_PIP_TUPLE="(25, 1, 1)"/REQUIRED_PIP_TUPLE="(25, 0, 1)"/' \
    ~/.local/share/ironic-python-agent-builder/dib/ironic-python-agent-ramdisk/install.d/ironic-python-agent-ramdisk-source-install/60-ironic-python-agent-ramdisk-install
```

## What the Default IPA Does (DHCP Only)

The default IPA ramdisk:

1. **Boots with DHCP enabled** - NetworkManager or systemd-networkd uses DHCP
2. **No static IP support** - Cannot read NetworkData from config drive
3. **No custom network scripts** - Relies on standard network initialization
4. **Works with DHCP networks only** - Cannot provision on networks without DHCP

**Default network flow:**
```
IPA Boots → NetworkManager starts → DHCP request → Get IP from DHCP server → Connect to Ironic
```

## Changes Needed for Static IP Support

To support static IP configuration, you need to add:

### 1. Network Configuration Script

Create `configure-network.sh` that:
- Reads NetworkData from config drive (`/mnt/openstack/latest/network_data.json`)
- Parses nmstate format JSON
- Applies static IP configuration using `nmc` (nmstate CLI) or fallback `ip` commands

### 2. Custom Diskimage-Builder Element

Create an `ipa-network-config` element that:
- Installs required packages (`jq`, `python3-yaml`, `network-manager`, `python3-nmstate`)
- Copies `configure-network.sh` into the ramdisk
- Creates a systemd service to run the script at boot

### 3. Systemd Service

Create `/etc/systemd/system/configure-network.service` that:
- Runs after network is online
- Executes `configure-network.sh`
- Handles config drive mounting/unmounting

## Detailed Changes Breakdown

### Change 1: Network Configuration Script

**File:** `configure-network.sh`

**What it does:**
1. Finds config drive (labeled `config-2`)
2. Mounts it read-only
3. Reads `/mnt/openstack/latest/network_data.json`
4. Applies network configuration:
   - **Preferred:** Uses `nmc` (nmstate CLI) if available
   - **Fallback:** Uses `ip` commands directly

**Key difference from default:**
- Default: No script, relies on DHCP
- Custom: Active script that reads and applies static config

### Change 2: Diskimage-Builder Element

**Directory structure:**
```
elements/ipa-network-config/
├── element.yaml              # Element metadata
└── install.d/
    └── 10-ipa-network-config # Installation script
```

**What the element does:**
1. **Installs packages:**
   ```bash
   apt-get install -y jq python3-yaml python3-netifaces network-manager python3-nmstate
   ```

2. **Copies script:**
   ```bash
   cp configure-network.sh ${TARGET_ROOT}/usr/local/bin/
   chmod +x ${TARGET_ROOT}/usr/local/bin/configure-network.sh
   ```

3. **Creates systemd service:**
   - Service file at `/etc/systemd/system/configure-network.service`
   - Symlink to enable it: `/etc/systemd/system/multi-user.target.wants/configure-network.service`

**Key difference from default:**
- Default: No custom element, standard IPA build
- Custom: Additional element that adds network configuration capability

### Change 3: Systemd Service

**Service file:**
```ini
[Unit]
Description=Configure Network from Config Drive
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/configure-network.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

**What it does:**
- Runs after network interfaces are up
- Executes the network configuration script
- Runs once per boot

**Key difference from default:**
- Default: NetworkManager handles everything via DHCP
- Custom: Custom service applies static config from NetworkData

## Build Process Comparison

### Default Build
```bash
ironic-python-agent-builder ubuntu -r focal -o ipa-ramdisk
```

**Result:** IPA ramdisk with DHCP only

### Custom Build
```bash
# Create element first
mkdir -p elements/ipa-network-config/install.d
# ... create element files ...

# Build with custom element
export ELEMENTS_PATH=$(pwd)/elements
ironic-python-agent-builder ubuntu -r focal -o ipa-ramdisk -e ipa-network-config
```

**Result:** IPA ramdisk with static IP support via NetworkData

## NetworkData Format

The NetworkData secret must be in **nmstate format** (not netplan):

```yaml
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
    dhcp: false  # ← Key: Must be false for static IP
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

## How It Works at Runtime

### Default IPA (DHCP):
```
1. IPA boots
2. NetworkManager starts
3. DHCP request sent
4. IP obtained from DHCP server
5. IPA connects to Ironic
```

### Custom IPA (Static IP):
```
1. IPA boots
2. NetworkManager starts (gets link up, no IP yet)
3. Config drive mounted by Metal3
4. configure-network.service starts
5. configure-network.sh reads NetworkData from config drive
6. Static IP applied via nmc or ip commands
7. IPA connects to Ironic with static IP
```

## Summary: What's Different

| Component | Default IPA | Custom IPA |
|-----------|-------------|------------|
| **Network Method** | DHCP only | Static IP via NetworkData |
| **Config Source** | DHCP server | Config drive (NetworkData secret) |
| **Network Script** | None | `configure-network.sh` |
| **Systemd Service** | NetworkManager only | `configure-network.service` |
| **Packages** | Standard IPA packages | + `jq`, `python3-yaml`, `nmstate` |
| **Build Elements** | Standard | + `ipa-network-config` element |
| **Config Format** | N/A | nmstate JSON format |

## Quick Build Command

```bash
# On Ubuntu VM
cd ~
mkdir -p ipa-build
cd ipa-build

# Create configure-network.sh (see build script for content)
# Create element directory structure
# Copy script to element

# Build
export PATH=$PATH:$HOME/.local/bin
export PYTHONPATH=$HOME/.local/lib/python3.10/site-packages:$PYTHONPATH
export DIB_RELEASE=focal
export ELEMENTS_PATH=$(pwd)/elements

ironic-python-agent-builder ubuntu -r focal -o ipa-ramdisk -e ipa-network-config
```

## Output Files

After successful build:
- `ipa-ramdisk.kernel` - Kernel image (~5-10 MB)
- `ipa-ramdisk.initramfs` - Initramfs with IPA and network config (~50-100 MB)

These replace the default IPA ramdisk files in Ironic.

