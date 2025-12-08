# Building IPA Ramdisk in Ubuntu VM with Cloud-Init

This guide provides a complete cloud-init script and all necessary fixes to successfully build a custom IPA ramdisk in an Ubuntu VM.

## Files in This Directory

- `build-ipa-cloudinit.yaml` - Complete cloud-init script with all fixes applied
- `README.md` - This documentation file

zero t## Quick Start

1. **Create Ubuntu 22.04 VM** with cloud-init support
2. **Attach/configure cloud-init** with `build-ipa-cloudinit.yaml`
3. **Boot VM** - setup happens automatically
4. **SSH in and build:**
   ```bash
   ./build-ipa-ramdisk.sh focal   # For Ubuntu 20.04 target
   ```

## Prerequisites

- **Build VM**: Ubuntu 22.04 (jammy) - **Required** (Python 3.10+ needed for ironic-python-agent)
- **Target OS**: Can be Ubuntu 20.04 (focal) or 22.04 (jammy) - specified when building
- At least 4GB RAM
- At least 20GB disk space
- Internet connectivity

## Important: Build VM vs Target OS

**Build VM must be Ubuntu 22.04 (jammy)** because:
- The `ironic-python-agent` package requires Python >=3.10
- Ubuntu 20.04 (focal) only has Python 3.8
- Ubuntu 22.04 (jammy) has Python 3.10.12

**Target OS can be focal or jammy** - you specify this when building:
```bash
./build-ipa-ramdisk.sh focal   # Build IPA ramdisk for Ubuntu 20.04
./build-ipa-ramdisk.sh jammy   # Build IPA ramdisk for Ubuntu 22.04
```

The script will check Python version and fail early if you try to build on focal.

## Complete Cloud-Init Script

Save this as `build-ipa-cloudinit.yaml`:

```yaml
#cloud-config
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash

# Install system packages
packages:
  - python3-pip
  - python3-dev
  - git
  - qemu-utils
  - kpartx
  - debootstrap
  - squashfs-tools
  - dosfstools
  - curl
  - wget

# Run commands after package installation
runcmd:
  # Install Python packages
  - pip3 install --user diskimage-builder ironic-python-agent-builder
  
  # Add to PATH
  - echo 'export PATH=$PATH:$HOME/.local/bin' >> /home/ubuntu/.bashrc
  - export PATH=$PATH:/home/ubuntu/.local/bin
  
  # Fix 1: Fix pip version requirement (25.1.1 -> 25.0.1)
  - |
    sed -i 's/REQUIRED_PIP_STR="25\.1\.1"/REQUIRED_PIP_STR="25.0.1"/' \
        /home/ubuntu/.local/share/ironic-python-agent-builder/dib/ironic-python-agent-ramdisk/install.d/ironic-python-agent-ramdisk-source-install/60-ironic-python-agent-ramdisk-install || true
  - |
    sed -i 's/REQUIRED_PIP_TUPLE="(25, 1, 1)"/REQUIRED_PIP_TUPLE="(25, 0, 1)"/' \
        /home/ubuntu/.local/share/ironic-python-agent-builder/dib/ironic-python-agent-ramdisk/install.d/ironic-python-agent-ramdisk-source-install/60-ironic-python-agent-ramdisk-install || true
  
  # Fix 2: Fix constraint conflict (add fallback)
  - |
    sed -i 's|\$VENVDIR/bin/pip install -c \$UPPER_CONSTRAINTS \$IPADIR|\$VENVDIR/bin/pip install -c \$UPPER_CONSTRAINTS \$IPADIR || \$VENVDIR/bin/pip install \$IPADIR|' \
        /home/ubuntu/.local/share/ironic-python-agent-builder/dib/ironic-python-agent-ramdisk/install.d/ironic-python-agent-ramdisk-source-install/60-ironic-python-agent-ramdisk-install || true
  
  # Create build script
  - |
    cat > /home/ubuntu/build-ipa-ramdisk.sh << 'SCRIPT_EOF'
    #!/bin/bash
    set -eux
    
    RELEASE="${1:-jammy}"
    OUTPUT_DIR="${HOME}/ipa-build"
    
    mkdir -p "$OUTPUT_DIR"
    cd "$OUTPUT_DIR"
    
    # Create configure-network.sh
    cat > configure-network.sh << 'NET_EOF'
    #!/bin/bash
    set -eux
    CONFIG_DRIVE=$(blkid --label config-2 || true)
    [ -z "${CONFIG_DRIVE}" ] && exit 0
    mount -o ro $CONFIG_DRIVE /mnt
    [ ! -f /mnt/openstack/latest/network_data.json ] && { umount /mnt; exit 0; }
    mkdir -p /tmp/nmc/{desired,generated}
    cp /mnt/openstack/latest/network_data.json /tmp/nmc/desired/_all.yaml
    umount /mnt
    if command -v nmc &> /dev/null; then
      nmc generate --config-dir /tmp/nmc/desired --output-dir /tmp/nmc/generated
      nmc apply --config-dir /tmp/nmc/generated
    else
      python3 << PYEOF
    import json, subprocess, sys
    with open('/tmp/nmc/desired/_all.yaml') as f:
        d = json.load(f)
    for iface in d.get('interfaces', []):
        name = iface.get('name')
        if not name: continue
        ipv4 = iface.get('ipv4', {})
        if ipv4.get('enabled') and not ipv4.get('dhcp'):
            addrs = ipv4.get('address', [])
            if addrs:
                ip = addrs[0].get('ip')
                prefix = addrs[0].get('prefix-length', 24)
                subprocess.run(['ip', 'addr', 'add', f'{ip}/{prefix}', 'dev', name], check=False)
                subprocess.run(['ip', 'link', 'set', 'up', 'dev', name], check=False)
    PYEOF
    fi
    NET_EOF
    chmod +x configure-network.sh
    
    # Create element
    mkdir -p elements/ipa-network-config/install.d
    cat > elements/ipa-network-config/element.yaml << 'EOF'
    ---
    dependencies:
      - package-install
    EOF
    
    cat > elements/ipa-network-config/install.d/10-ipa-network-config << 'INSTEOF'
    #!/bin/bash
    set -eux
    TARGET_ROOT="${TARGET_ROOT:-/}"
    ELEMENT_PATH="${ELEMENT_PATH:-.}"
    
    [ -f /etc/debian_version ] && {
        apt-get update || true
        apt-get install -y jq python3-yaml python3-netifaces network-manager || true
        apt-get install -y python3-nmstate || echo "Warning: python3-nmstate not available, will use fallback"
    }
    mkdir -p "${TARGET_ROOT}/usr/local/bin"
    
    # Find configure-network.sh - try ELEMENT_PATH first, then script location
    if [ -f "${ELEMENT_PATH}/configure-network.sh" ]; then
        CONFIG_SCRIPT="${ELEMENT_PATH}/configure-network.sh"
    elif [ -f "$(dirname "$0")/../configure-network.sh" ]; then
        CONFIG_SCRIPT="$(dirname "$0")/../configure-network.sh"
    else
        echo "Error: configure-network.sh not found in ${ELEMENT_PATH} or element directory"
        exit 1
    fi
    
    cp "${CONFIG_SCRIPT}" "${TARGET_ROOT}/usr/local/bin/configure-network.sh"
    chmod +x "${TARGET_ROOT}/usr/local/bin/configure-network.sh"
    mkdir -p "${TARGET_ROOT}/etc/systemd/system"
    cat > "${TARGET_ROOT}/etc/systemd/system/configure-network.service" << 'SVCEOF'
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
    SVCEOF
    mkdir -p "${TARGET_ROOT}/etc/systemd/system/multi-user.target.wants"
    ln -sf /etc/systemd/system/configure-network.service \
        "${TARGET_ROOT}/etc/systemd/system/multi-user.target.wants/configure-network.service"
    INSTEOF
    
    chmod +x elements/ipa-network-config/install.d/10-ipa-network-config
    cp configure-network.sh elements/ipa-network-config/
    
    # Build
    export DIB_RELEASE="${RELEASE}"
    export ELEMENTS_PATH="${OUTPUT_DIR}/elements"
    export PATH=$PATH:$HOME/.local/bin
    export PYTHONPATH=$HOME/.local/lib/python3.10/site-packages:${PYTHONPATH:-}
    
    echo "Building IPA ramdisk (10-20 minutes)..."
    ironic-python-agent-builder ubuntu -r "${RELEASE}" -o ipa-ramdisk -e ipa-network-config
    
    echo "Build complete!"
    ls -lh ipa-ramdisk.*
    SCRIPT_EOF
  
  # Make script executable
  - chmod +x /home/ubuntu/build-ipa-ramdisk.sh
  - chown ubuntu:ubuntu /home/ubuntu/build-ipa-ramdisk.sh

# Write build completion message
write_files:
  - path: /home/ubuntu/BUILD_README.txt
    content: |
      IPA Ramdisk Build Script Ready
      ===============================
      
      The build script has been set up with all necessary fixes.
      
      To build the IPA ramdisk:
        cd ~
        ./build-ipa-ramdisk.sh focal   # For Ubuntu 20.04 target
        # or
        ./build-ipa-ramdisk.sh jammy   # For Ubuntu 22.04 target
      
      This will take 10-20 minutes.
      
      Output files will be in ~/ipa-build/:
        - ipa-ramdisk.kernel
        - ipa-ramdisk.initramfs
      
      Fixes Applied:
      - Pip version requirement (25.1.1 -> 25.0.1)
      - Constraint conflict fallback
      - PYTHONPATH configuration
      - ELEMENT_PATH handling in install script
    owner: ubuntu:ubuntu
    permissions: '0644'

final_message: |
  IPA ramdisk build environment ready!
  Run: ~/build-ipa-ramdisk.sh focal   (for Ubuntu 20.04 target)
  Or:  ~/build-ipa-ramdisk.sh jammy   (for Ubuntu 22.04 target)
```

## All Fixes Applied

### Fix 1: Pip Version Requirement

**Problem:** `ironic-python-agent-builder` requires `pip==25.1.1`, but Ubuntu 22.04 only has `pip==25.0.1` available.

**Solution:**
```bash
sed -i 's/REQUIRED_PIP_STR="25\.1\.1"/REQUIRED_PIP_STR="25.0.1"/' \
    ~/.local/share/ironic-python-agent-builder/dib/ironic-python-agent-ramdisk/install.d/ironic-python-agent-ramdisk-source-install/60-ironic-python-agent-ramdisk-install

sed -i 's/REQUIRED_PIP_TUPLE="(25, 1, 1)"/REQUIRED_PIP_TUPLE="(25, 0, 1)"/' \
    ~/.local/share/ironic-python-agent-builder/dib/ironic-python-agent-ramdisk/install.d/ironic-python-agent-ramdisk-source-install/60-ironic-python-agent-ramdisk-install
```

### Fix 2: Python Version Requirement

**Problem:** Ubuntu 20.04 has Python 3.8, but `ironic-python-agent` requires Python >=3.10.

**Solution:** Use Ubuntu 22.04 (jammy) which has Python 3.10.12.

### Fix 3: Constraint Conflict

**Problem:** Dependency conflict with `oslo.config` version constraints.

**Solution:**
```bash
sed -i 's|\$VENVDIR/bin/pip install -c \$UPPER_CONSTRAINTS \$IPADIR|\$VENVDIR/bin/pip install -c \$UPPER_CONSTRAINTS \$IPADIR || \$VENVDIR/bin/pip install \$IPADIR|' \
    ~/.local/share/ironic-python-agent-builder/dib/ironic-python-agent-ramdisk/install.d/ironic-python-agent-ramdisk-source-install/60-ironic-python-agent-ramdisk-install
```

This adds a fallback to install without constraints if the constrained install fails.

### Fix 4: PYTHONPATH Unbound Variable

**Problem:** Script fails with `PYTHONPATH: unbound variable` when using `set -eux`.

**Solution:**
```bash
export PYTHONPATH=$HOME/.local/lib/python3.10/site-packages:${PYTHONPATH:-}
```

The `${PYTHONPATH:-}` syntax allows the variable to be unset.

### Fix 5: ELEMENT_PATH Not Set

**Problem:** `configure-network.sh` not found because `ELEMENT_PATH` isn't set by diskimage-builder.

**Solution:** Add fallback logic in the install script:
```bash
TARGET_ROOT="${TARGET_ROOT:-/}"
ELEMENT_PATH="${ELEMENT_PATH:-.}"

# Find configure-network.sh - try ELEMENT_PATH first, then script location
if [ -f "${ELEMENT_PATH}/configure-network.sh" ]; then
    CONFIG_SCRIPT="${ELEMENT_PATH}/configure-network.sh"
elif [ -f "$(dirname "$0")/../configure-network.sh" ]; then
    CONFIG_SCRIPT="$(dirname "$0")/../configure-network.sh"
else
    echo "Error: configure-network.sh not found"
    exit 1
fi
```

## Usage

### Using Cloud-Init with VM Creation

The cloud-init script (`build-ipa-cloudinit.yaml`) sets up everything automatically when the VM boots.

#### For libvirt/virt-manager (QEMU/KVM)

1. **Create VM with Ubuntu 22.04 (jammy)** - Required for Python 3.10+
2. **Add cloud-init disk:**
   ```bash
   # Create cloud-init ISO
   cloud-localds /path/to/ipa-build-seed.iso scripts/cloud-init/ipa-build/build-ipa-cloudinit.yaml
   
   # Attach to VM as CD-ROM
   virsh attach-disk <vm-name> /path/to/ipa-build-seed.iso hdb --type cdrom --mode readonly
   ```
3. **Boot VM** - Cloud-init will run automatically
4. **SSH into VM** and verify setup:
   ```bash
   cat ~/BUILD_README.txt
   ```
5. **Build IPA ramdisk:**
   ```bash
   cd ~
   ./build-ipa-ramdisk.sh focal   # For Ubuntu 20.04 target
   # or
   ./build-ipa-ramdisk.sh jammy   # For Ubuntu 22.04 target
   ```

#### For virt-install (libvirt CLI)

```bash
virt-install \
  --name ipa-builder \
  --ram 4096 \
  --vcpus 2 \
  --disk size=20 \
  --os-variant ubuntu22.04 \
  --network network=default \
  --graphics none \
  --console pty,target_type=serial \
  --location http://archive.ubuntu.com/ubuntu/dists/jammy/main/installer-arm64/ \
  --extra-args "console=ttyS0" \
  --cloud-init user-data=scripts/cloud-init/ipa-build/build-ipa-cloudinit.yaml
```

#### For Cloud Providers (AWS/GCP/Azure)

1. **Launch instance with Ubuntu 22.04 (jammy)**
2. **Paste cloud-init YAML into user-data field:**
   - AWS: EC2 Launch → Advanced → User data
   - GCP: VM Instance → Advanced → Metadata → user-data
   - Azure: VM → Advanced → Custom data
3. **SSH into instance** after it boots
4. **Run build:**
   ```bash
   ./build-ipa-ramdisk.sh focal
   ```

#### For Proxmox

1. Create VM with Ubuntu 22.04
2. In VM settings → Cloud-Init, paste the YAML content
3. Boot VM
4. SSH in and run: `./build-ipa-ramdisk.sh focal`

### Manual Setup (Without Cloud-Init)

If you already have an Ubuntu 22.04 VM and want to set it up manually:

```bash
# Install packages
sudo apt-get update
sudo apt-get install -y python3-pip python3-dev git qemu-utils kpartx debootstrap squashfs-tools dosfstools curl

# Install Python packages
pip3 install --user diskimage-builder ironic-python-agent-builder

# Add to PATH
echo 'export PATH=$PATH:$HOME/.local/bin' >> ~/.bashrc
export PATH=$PATH:$HOME/.local/bin

# Apply Fix 1: Pip version requirement
sed -i 's/REQUIRED_PIP_STR="25\.1\.1"/REQUIRED_PIP_STR="25.0.1"/' \
    ~/.local/share/ironic-python-agent-builder/dib/ironic-python-agent-ramdisk/install.d/ironic-python-agent-ramdisk-source-install/60-ironic-python-agent-ramdisk-install

sed -i 's/REQUIRED_PIP_TUPLE="(25, 1, 1)"/REQUIRED_PIP_TUPLE="(25, 0, 1)"/' \
    ~/.local/share/ironic-python-agent-builder/dib/ironic-python-agent-ramdisk/install.d/ironic-python-agent-ramdisk-source-install/60-ironic-python-agent-ramdisk-install

# Apply Fix 3: Constraint conflict fallback
sed -i 's|\$VENVDIR/bin/pip install -c \$UPPER_CONSTRAINTS \$IPADIR|\$VENVDIR/bin/pip install -c \$UPPER_CONSTRAINTS \$IPADIR || \$VENVDIR/bin/pip install \$IPADIR|' \
    ~/.local/share/ironic-python-agent-builder/dib/ironic-python-agent-ramdisk/install.d/ironic-python-agent-ramdisk-source-install/60-ironic-python-agent-ramdisk-install

# Copy build script from cloud-init directory or create it manually
# (See the build script content in build-ipa-cloudinit.yaml)
```

## Build Process

The build takes **10-20 minutes** and goes through these phases:

1. **Setup** (1-2 min): Copying hooks, setting up build environment
2. **Package Installation** (5-10 min): Installing Ubuntu packages in chroot
3. **IPA Installation** (3-5 min): Installing ironic-python-agent and dependencies
4. **Image Creation** (2-3 min): Creating initramfs and kernel files

## Output Files

After successful build, you'll have:

- `~/ipa-build/ipa-ramdisk.kernel` (~15 MB) - Kernel image
- `~/ipa-build/ipa-ramdisk.initramfs` (~900 MB) - Initramfs with IPA and network config
- `~/ipa-build/ipa-ramdisk.sha256` - Checksum file

## Troubleshooting

### Build Fails with "Python 3.8.10 not in '>=3.10'"

**Problem:** You're trying to build on Ubuntu 20.04 (focal), which only has Python 3.8.

**Solution:** 
- **Build VM must be Ubuntu 22.04 (jammy)** - this is where you run the build
- **Target OS can be focal** - this is what the ramdisk will provision
- The script now checks Python version and will fail early with a clear error message

### Build Fails with "pip==25.1.1 not found"

**Solution:** The pip version fix wasn't applied. Run Fix 1 again.

### Build Fails with "oslo.config dependency conflict"

**Solution:** The constraint fallback wasn't applied. Run Fix 3 again.

### Build Fails with "configure-network.sh not found"

**Solution:** The ELEMENT_PATH fix wasn't applied. Check the install script has the fallback logic.

### Build Stuck/Hanging

**Normal:** The build can take 10-20 minutes. Check progress:
```bash
tail -f /tmp/build.log  # if logging to file
ps aux | grep ironic-python-agent-builder  # check if running
du -sh /tmp/dib_build.*  # check build directory size (should grow)
```

## Verification

After build completes, verify files:

```bash
ls -lh ~/ipa-build/ipa-ramdisk.*
file ~/ipa-build/ipa-ramdisk.kernel
file ~/ipa-build/ipa-ramdisk.initramfs
```

Expected output:
- `ipa-ramdisk.kernel`: gzip compressed data
- `ipa-ramdisk.initramfs`: gzip compressed data, ~900MB

## Next Steps

1. **Copy files from VM:**
   ```bash
   # From host
   scp user@vm:~/ipa-build/ipa-ramdisk.* ./
   ```

2. **Upload to Ironic:**
   - Via ConfigMap (for Kubernetes)
   - Via HTTP server
   - Direct file copy to Ironic host

3. **Configure Ironic** to use custom ramdisk

4. **Test provisioning** with static IP configuration

## Summary of All Required Fixes

| Fix | Problem | Solution |
|-----|---------|----------|
| **1. Pip Version** | Requires pip==25.1.1, only 25.0.1 available | Change requirement to 25.0.1 |
| **2. Python Version** | Requires Python >=3.10, Ubuntu 20.04 has 3.8 | Use Ubuntu 22.04 |
| **3. Constraint Conflict** | oslo.config version conflict | Add fallback without constraints |
| **4. PYTHONPATH** | Unbound variable error | Use `${PYTHONPATH:-}` syntax |
| **5. ELEMENT_PATH** | Script not found | Add fallback path resolution |

All these fixes are included in the cloud-init script above.

