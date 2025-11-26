# Manual Edge Image Builder Setup with Podman

## Overview

This guide provides step-by-step instructions for running Edge Image Builder locally using Podman, without requiring Helm or Kubernetes. Edge Image Builder runs as a containerized application that mounts a directory from the host to access configuration files and base images.

**Reference**: [SUSE Edge Image Builder Documentation](https://documentation.suse.com/suse-edge/3.3/html/edge/guides-kiwi-builder-images.html)

## Prerequisites

### 1. System Requirements

- **SUSE Linux Micro 6.1** host (or compatible Linux distribution)
- **Same architecture** as the images you're building (AMD64/Intel 64 or AArch64)
- **Podman** installed and configured
- **At least 10GB free disk space** for:
  - Container image
  - Build workspace
  - Base images
  - Output images

### 2. System Configuration

#### Disable SELinux

Edge Image Builder requires SELinux to be disabled:

```bash
# Check current SELinux status
getenforce

# Disable SELinux (temporary, until reboot)
sudo setenforce 0

# To make permanent, edit /etc/selinux/config:
# SELINUX=disabled
```

#### Verify Podman Installation

```bash
# Check podman version
podman --version

# Test podman can run containers
podman run --rm hello-world
```

### 3. Access to SUSE Registry

Ensure you can pull images from SUSE registry:

```bash
# Test registry access
podman pull registry.suse.com/edge/3.3/edge-image-builder:latest

# If behind a proxy, configure podman:
# Edit ~/.config/containers/containers.conf or set environment variables
export HTTP_PROXY="http://proxy.example.com:8080"
export HTTPS_PROXY="http://proxy.example.com:8080"
```

## Step 1: Create Directory Structure

Edge Image Builder requires a specific directory structure to be mounted from the host. Create the following structure:

```bash
# Create main Edge Image Builder directory
mkdir -p ~/edge-image-builder

# Create required subdirectories
cd ~/edge-image-builder
mkdir -p base-images
mkdir -p network          # Optional, for network configuration scripts
mkdir -p custom/scripts   # For first-boot scripts

# Verify structure
tree -L 3 ~/edge-image-builder
```

Expected structure:

```
~/edge-image-builder/
├── downstream-cluster-config.yaml  # Image definition file (created in Step 3)
├── base-images/                    # Base OS images go here
│   └── SL-Micro.x86_64-6.1-Base-GM.raw
├── network/                        # Optional: network configuration scripts
│   └── configure-network.sh       # Optional: static IP configuration
└── custom/
    └── scripts/                    # First-boot scripts
        └── 01-fix-growfs.sh        # Required: partition resize script
```

## Step 2: Download and Prepare Base Image

### Download Base Image

1. **Download from SUSE Customer Center**:
   - Visit: https://scc.suse.com/ or https://download.suse.com/
   - Download: `SL-Micro.x86_64-6.1-Base-GM.raw.xz` (or appropriate version for your architecture)

2. **Or use wget/curl**:
   ```bash
   cd ~/edge-image-builder/base-images
   
   # Download base image (xz compressed)
   wget https://download.suse.com/SL-Micro.x86_64-6.1-Base-GM.raw.xz
   
   # Or if you have the file already, copy it here
   # cp /path/to/SL-Micro.x86_64-6.1-Base-GM.raw.xz ~/edge-image-builder/base-images/
   ```

### Decompress Base Image

The base image is xz-compressed and must be decompressed:

```bash
cd ~/edge-image-builder/base-images

# Decompress the image
unxz SL-Micro.x86_64-6.1-Base-GM.raw.xz

# Verify the decompressed image exists
ls -lh SL-Micro.x86_64-6.1-Base-GM.raw

# Expected output: ~500MB-1GB raw disk image
```

**Important**: The decompressed `.raw` file must be in the `base-images/` directory. Edge Image Builder will look for it there.

## Step 3: Create Image Definition File

Create `downstream-cluster-config.yaml` in the main Edge Image Builder directory. This file defines how the image will be built.

### Basic Configuration

```bash
cd ~/edge-image-builder

cat > downstream-cluster-config.yaml <<'EOF'
apiVersion: 1.0
image:
  imageType: RAW
  arch: x86_64
  baseImage: SL-Micro.x86_64-6.1-Base-GM.raw
  outputImageName: SLE-Micro-metal3-custom.raw

operatingSystem:
  time:
    timezone: UTC
    ntp:
      forceWait: true
      pools:
        - pool.ntp.org
      servers:
        - 0.pool.ntp.org
        - 1.pool.ntp.org

  kernelArgs:
    - ignition.platform.id=openstack
    - net.ifnames=1

  systemd:
    disable:
      - rebootmgr

  users:
    - name: root
      passwd: "$6$rounds=4096$salt$hashedpassword"  # Generate with: openssl passwd -6
    - name: suse
      groups:
        - wheel
      sshAuthorizedKeys:
        - "ssh-rsa AAAAB3NzaC1yc2E..."  # Your SSH public key

  packages:
    - kubernetes
    - container-runtime
    - NetworkManager
    - cloud-init
EOF
```

### Generate Password Hash

Before finalizing the config, generate a password hash:

```bash
# Generate password hash for root user
openssl passwd -6 "your-password-here"

# Output example: $6$rounds=4096$salt$hashedpassword
# Copy this into the downstream-cluster-config.yaml file
```

### Complete Example with nmstate Support

For static IP configuration support:

```yaml
apiVersion: 1.0
image:
  imageType: RAW
  arch: x86_64
  baseImage: SL-Micro.x86_64-6.1-Base-GM.raw
  outputImageName: SLE-Micro-metal3-static-ip.raw

operatingSystem:
  time:
    timezone: UTC
    ntp:
      forceWait: true
      pools:
        - pool.ntp.org

  kernelArgs:
    - ignition.platform.id=openstack
    - net.ifnames=1

  systemd:
    disable:
      - rebootmgr
    units:
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
          ExecStartPost=/bin/mkdir -p /etc/systemd/system/configure-network.service.d
          ExecStartPost=/bin/touch /etc/systemd/system/configure-network.service.d/ran-once.conf
          
          [Install]
          WantedBy=multi-user.target

  users:
    - name: root
      passwd: "$6$..."  # Generated password hash
    - name: suse
      groups:
        - wheel
      sshAuthorizedKeys:
        - "ssh-rsa AAAAB3..."  # Your SSH key

  packages:
    - nmstate              # For NM Configurator (nmc tool)
    - NetworkManager
    - util-linux
    - cloud-init
    - kubernetes
    - container-runtime

  files:
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
        if [ -n "${DESIRED_HOSTNAME}" ]; then
          echo "${DESIRED_HOSTNAME}" > /etc/hostname
          hostname "${DESIRED_HOSTNAME}"
        fi
        
        mkdir -p /tmp/nmc/{desired,generated}
        cp ${NETWORK_DATA_FILE} /tmp/nmc/desired/_all.yaml
        umount /mnt
        
        /usr/bin/nmc generate --config-dir /tmp/nmc/desired --output-dir /tmp/nmc/generated
        /usr/bin/nmc apply --config-dir /tmp/nmc/generated
```

## Step 4: Create Required First-Boot Script

The `01-fix-growfs.sh` script is required to resize the OS root partition on deployment.

### Create the Script

```bash
cd ~/edge-image-builder/custom/scripts

cat > 01-fix-growfs.sh <<'EOF'
#!/bin/bash
# Script to resize root partition on first boot
# This is required for Edge Image Builder images

set -eux

# Find root filesystem device
ROOT_DEV=$(findmnt -n -o SOURCE /)
ROOT_PART=$(readlink -f "$ROOT_DEV")

# Get partition number and disk
PART_NUM=$(echo "$ROOT_PART" | grep -oE '[0-9]+$')
DISK_DEV=$(echo "$ROOT_PART" | sed "s/[0-9]*$//")

# Resize partition to fill available space
if command -v growpart >/dev/null 2>&1; then
    growpart "$DISK_DEV" "$PART_NUM" || true
fi

# Resize filesystem
if command -v btrfs >/dev/null 2>&1 && [ "$(findmnt -n -o FSTYPE /)" = "btrfs" ]; then
    btrfs filesystem resize max /
elif command -v resize2fs >/dev/null 2>&1; then
    resize2fs "$ROOT_PART" || true
fi

# Mark script as executed
touch /etc/systemd/system/fix-growfs.service.d/ran-once.conf 2>/dev/null || true
EOF

# Make script executable
chmod +x 01-fix-growfs.sh

# Verify
ls -lh ~/edge-image-builder/custom/scripts/
```

**Note**: Edge Image Builder will automatically copy scripts from `custom/scripts/` into the image and configure them to run on first boot.

## Step 5: Optional Network Configuration Script

If you need static IP configuration, you can also place the script in the `network/` folder (though it's better to include it in the image definition as shown in Step 3):

```bash
cd ~/edge-image-builder/network

cat > configure-network.sh <<'EOF'
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
if [ -n "${DESIRED_HOSTNAME}" ]; then
  echo "${DESIRED_HOSTNAME}" > /etc/hostname
  hostname "${DESIRED_HOSTNAME}"
fi

mkdir -p /tmp/nmc/{desired,generated}
cp ${NETWORK_DATA_FILE} /tmp/nmc/desired/_all.yaml
umount /mnt

/usr/bin/nmc generate --config-dir /tmp/nmc/desired --output-dir /tmp/nmc/generated
/usr/bin/nmc apply --config-dir /tmp/nmc/generated
EOF

chmod +x configure-network.sh
```

## Step 6: Pull Edge Image Builder Container

Pull the Edge Image Builder container image:

```bash
# Pull the latest Edge Image Builder image
podman pull registry.suse.com/edge/3.3/edge-image-builder:latest

# Or specify a specific version
podman pull registry.suse.com/edge/3.3/edge-image-builder:1.2.1

# Verify image is available
podman images | grep edge-image-builder
```

## Step 7: Run Edge Image Builder

### Basic Build Command

Navigate to your Edge Image Builder directory and run:

```bash
cd ~/edge-image-builder

# Run Edge Image Builder
podman run --rm --privileged -it \
  -v $PWD:/eib \
  registry.suse.com/edge/3.3/edge-image-builder:latest \
  build --definition-file downstream-cluster-config.yaml
```

### Command Breakdown

- `--rm`: Remove container after it exits
- `--privileged`: Required for image building operations (loop devices, etc.)
- `-it`: Interactive terminal
- `-v $PWD:/eib`: Mount current directory to `/eib` in container
- `build --definition-file downstream-cluster-config.yaml`: Build command with config file

### Expected Output

The build process will:
1. Load the base image from `base-images/`
2. Apply configurations from `downstream-cluster-config.yaml`
3. Copy scripts from `custom/scripts/`
4. Install packages
5. Generate the output image

Build time: Typically 10-30 minutes depending on packages and system resources.

### Build Output Location

After successful build, the output image will be in your Edge Image Builder directory:

```bash
cd ~/edge-image-builder

# List output files
ls -lh *.raw

# Expected: SLE-Micro-metal3-custom.raw (or your outputImageName)
```

## Step 8: Generate Checksum

Generate a SHA256 checksum for the built image (required for Metal3):

```bash
cd ~/edge-image-builder

# Generate checksum
sha256sum SLE-Micro-metal3-custom.raw > SLE-Micro-metal3-custom.raw.sha256

# Verify checksum file
cat SLE-Micro-metal3-custom.raw.sha256
```

## Step 9: Serve Image for Metal3

Make the image accessible to Metal3. Options:

### Option A: Simple HTTP Server

```bash
cd ~/edge-image-builder

# Start Python HTTP server
python3 -m http.server 8080

# Or use a specific IP
python3 -m http.server 8080 --bind 0.0.0.0
```

### Option B: Nginx

```bash
# Install nginx (if not installed)
sudo zypper install nginx

# Configure nginx to serve the directory
sudo tee /etc/nginx/conf.d/eib-images.conf <<EOF
server {
    listen 8080;
    server_name _;
    root /home/$USER/edge-image-builder;
    autoindex on;
}
EOF

# Start nginx
sudo systemctl enable --now nginx
```

## Step 10: Use Image with Metal3

Reference the image in your BareMetalHost:

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-0
  namespace: metal3-system
spec:
  online: true
  bootMACAddress: "52:54:00:XX:XX:XX"
  bmc:
    address: "redfish+http://10.2.83.180:8000/redfish/v1/Systems/node-0"
    credentialsName: node-0-bmc-secret
  bootMode: "UEFI"
  image:
    url: "http://<your-server-ip>:8080/SLE-Micro-metal3-custom.raw"
    checksum: "http://<your-server-ip>:8080/SLE-Micro-metal3-custom.raw.sha256"
    checksumType: "sha256"
    format: "raw"
```

## Troubleshooting

### Build Fails: "Base image not found"

```bash
# Verify base image exists and is decompressed
ls -lh ~/edge-image-builder/base-images/

# Check filename matches downstream-cluster-config.yaml
cat ~/edge-image-builder/downstream-cluster-config.yaml | grep baseImage
```

### Build Fails: "Loop device test failed"

This is a known issue on first run. Simply re-run the build command:

```bash
# Re-run the build
podman run --rm --privileged -it \
  -v $PWD:/eib \
  registry.suse.com/edge/3.3/edge-image-builder:latest \
  build --definition-file downstream-cluster-config.yaml
```

### Build Fails: SELinux Errors

```bash
# Disable SELinux
sudo setenforce 0

# Verify
getenforce
# Should show: Permissive or Disabled
```

### Scripts Not Executing

Verify scripts are executable and in correct location:

```bash
# Check script permissions
ls -lh ~/edge-image-builder/custom/scripts/

# Should show: -rwxr-xr-x (executable)
```

### Package Installation Fails

Check if you have access to SUSE repositories:

```bash
# Test from container
podman run --rm -it \
  registry.suse.com/edge/3.3/edge-image-builder:latest \
  zypper search kubernetes
```

## Complete Example Workflow

```bash
#!/bin/bash
set -e

# 1. Create directory structure
mkdir -p ~/edge-image-builder/{base-images,network,custom/scripts}
cd ~/edge-image-builder

# 2. Download and prepare base image
cd base-images
wget https://download.suse.com/SL-Micro.x86_64-6.1-Base-GM.raw.xz
unxz SL-Micro.x86_64-6.1-Base-GM.raw.xz
cd ..

# 3. Generate password hash
PASSWORD_HASH=$(openssl passwd -6 "changeme")
echo "Password hash: $PASSWORD_HASH"

# 4. Get SSH public key
SSH_KEY=$(cat ~/.ssh/id_rsa.pub 2>/dev/null || echo "# Add your SSH key")

# 5. Create image definition
cat > downstream-cluster-config.yaml <<EOF
apiVersion: 1.0
image:
  imageType: RAW
  arch: x86_64
  baseImage: SL-Micro.x86_64-6.1-Base-GM.raw
  outputImageName: SLE-Micro-metal3-custom.raw

operatingSystem:
  users:
    - name: root
      passwd: "$PASSWORD_HASH"
    - name: suse
      groups:
        - wheel
      sshAuthorizedKeys:
        - "$SSH_KEY"
  packages:
    - kubernetes
    - container-runtime
EOF

# 6. Create first-boot script
cat > custom/scripts/01-fix-growfs.sh <<'SCRIPT'
#!/bin/bash
set -eux
ROOT_DEV=$(findmnt -n -o SOURCE /)
ROOT_PART=$(readlink -f "$ROOT_DEV")
PART_NUM=$(echo "$ROOT_PART" | grep -oE '[0-9]+$')
DISK_DEV=$(echo "$ROOT_PART" | sed "s/[0-9]*$//")
if command -v growpart >/dev/null 2>&1; then
    growpart "$DISK_DEV" "$PART_NUM" || true
fi
if command -v btrfs >/dev/null 2>&1 && [ "$(findmnt -n -o FSTYPE /)" = "btrfs" ]; then
    btrfs filesystem resize max /
fi
SCRIPT
chmod +x custom/scripts/01-fix-growfs.sh

# 7. Pull Edge Image Builder
podman pull registry.suse.com/edge/3.3/edge-image-builder:latest

# 8. Build image
podman run --rm --privileged -it \
  -v $PWD:/eib \
  registry.suse.com/edge/3.3/edge-image-builder:latest \
  build --definition-file downstream-cluster-config.yaml

# 9. Generate checksum
sha256sum SLE-Micro-metal3-custom.raw > SLE-Micro-metal3-custom.raw.sha256

echo "✅ Build complete!"
echo "Image: $(pwd)/SLE-Micro-metal3-custom.raw"
echo "Checksum: $(pwd)/SLE-Micro-metal3-custom.raw.sha256"
```

## Directory Structure Summary

```
~/edge-image-builder/
├── downstream-cluster-config.yaml    # Image definition (REQUIRED)
├── base-images/                       # Base OS images (REQUIRED)
│   └── SL-Micro.x86_64-6.1-Base-GM.raw
├── network/                           # Optional: network scripts
│   └── configure-network.sh
└── custom/
    └── scripts/                       # First-boot scripts (REQUIRED)
        └── 01-fix-growfs.sh           # Required: partition resize
```

## Running Podman in Nested OpenStack VMs

### Can You Run Podman in a Nested VM?

**Yes, you can run Podman inside a nested OpenStack VM**, but there are important considerations and requirements.

### Requirements

#### 1. Nested Virtualization Support

The OpenStack VM must have nested virtualization enabled:

```bash
# Check if nested virtualization is enabled (on the OpenStack VM host)
cat /sys/module/kvm_intel/parameters/nested  # For Intel CPUs
cat /sys/module/kvm_amd/parameters/nested   # For AMD CPUs

# Should show: Y or 1
```

If not enabled, enable it:

```bash
# For Intel
echo "options kvm_intel nested=1" | sudo tee /etc/modprobe.d/kvm.conf
sudo modprobe -r kvm_intel
sudo modprobe kvm_intel

# For AMD
echo "options kvm_amd nested=1" | sudo tee /etc/modprobe.d/kvm.conf
sudo modprobe -r kvm_amd
sudo modprobe kvm_amd
```

#### 2. VM Configuration

When creating the VM in OpenStack (or libvirt), ensure:

```xml
<!-- In libvirt VM XML -->
<cpu mode='host-passthrough' check='none'>
  <!-- This passes CPU features directly to VM -->
</cpu>

<features>
  <acpi/>
  <apic/>
</features>
```

Or in OpenStack flavor:

```bash
# Create flavor with CPU mode passthrough
openstack flavor create --vcpus 4 --ram 8192 --disk 50 \
  --property hw:cpu_policy=dedicated \
  --property hw:cpu_thread_policy=isolate \
  eib-build-vm
```

#### 3. Resource Requirements

Running Edge Image Builder in a nested VM requires significant resources:

- **CPU**: Minimum 4 vCPUs (8+ recommended)
- **Memory**: Minimum 8GB RAM (16GB+ recommended)
- **Disk**: At least 50GB free space
- **Network**: Stable connection for pulling images and packages

#### 4. Podman Configuration in VM

Inside the nested VM:

```bash
# Install Podman
sudo zypper install podman

# Configure Podman for rootless (optional but recommended)
# Enable user namespaces
echo "kernel.unprivileged_userns_clone=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Or run as root (simpler for Edge Image Builder)
# Edge Image Builder needs --privileged anyway
```

### Limitations and Considerations

#### 1. Performance Impact

- **Slower builds**: Nested virtualization adds overhead (20-40% slower)
- **I/O performance**: Disk operations may be slower
- **Memory overhead**: Additional memory needed for nested layers

#### 2. Privileged Containers

Edge Image Builder requires `--privileged` mode, which works in VMs but:
- Requires proper VM configuration
- May need additional capabilities passed through

```bash
# Test privileged containers work
podman run --rm --privileged alpine sh -c "ls -la /dev"

# Should show device files without errors
```

#### 3. Loop Devices

Edge Image Builder uses loop devices for image mounting. In nested VMs:

```bash
# Check loop devices are available
ls -la /dev/loop*

# If missing, create them
sudo mknod /dev/loop0 b 7 0
sudo mknod /dev/loop1 b 7 1
# ... (or use MAKEDEV)
```

Or ensure the VM has access to loop devices:

```bash
# In VM, check if loop module is loaded
lsmod | grep loop

# Load if needed
sudo modprobe loop
```

#### 4. SELinux in Nested VM

```bash
# Disable SELinux in the nested VM (not the OpenStack host)
sudo setenforce 0

# Make permanent
sudo sed -i 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
```

### Recommended Setup for Nested VM

#### Option A: Dedicated Build VM

Create a dedicated VM specifically for Edge Image Builder:

```bash
# Create VM with:
# - 8 vCPUs
# - 16GB RAM
# - 100GB disk
# - host-passthrough CPU mode
# - Nested virtualization enabled

# Install SUSE Linux Micro 6.1 or SLE 15 SP4+
# Install Podman
sudo zypper install podman

# Disable SELinux
sudo setenforce 0

# Configure for Edge Image Builder
mkdir -p ~/edge-image-builder/{base-images,network,custom/scripts}
```

#### Option B: Use OpenStack Instance

If your OpenStack supports nested virtualization:

```bash
# Create instance with:
openstack server create \
  --flavor eib-build-vm \
  --image suse-micro-6.1 \
  --key-name your-key \
  --network your-network \
  eib-builder

# SSH into instance
ssh cloud-user@<instance-ip>

# Follow standard Edge Image Builder setup
```

### Testing Podman in Nested VM

Before running Edge Image Builder, test Podman works:

```bash
# 1. Test basic container
podman run --rm alpine echo "Hello from nested VM"

# 2. Test privileged container
podman run --rm --privileged alpine sh -c "mount -t tmpfs tmpfs /tmp && echo OK"

# 3. Test volume mounts
echo "test" > /tmp/test.txt
podman run --rm -v /tmp:/host alpine cat /host/test.txt

# 4. Test registry access
podman pull registry.suse.com/edge/3.3/edge-image-builder:latest
```

### Troubleshooting Nested VM Issues

#### Issue: "Cannot create loop device"

```bash
# Check loop devices exist
ls -la /dev/loop*

# Create if missing
for i in {0..7}; do
  sudo mknod /dev/loop$i b 7 $i
  sudo chown root:disk /dev/loop$i
  sudo chmod 660 /dev/loop$i
done

# Or load loop module
sudo modprobe loop max_loop=8
```

#### Issue: "Operation not permitted" with --privileged

```bash
# Check if running as root
whoami

# If rootless, switch to root or configure user namespaces
# For Edge Image Builder, running as root is simpler
sudo podman run --privileged ...
```

#### Issue: Slow performance

```bash
# Check CPU features passed through
cat /proc/cpuinfo | grep flags

# Check nested virtualization
cat /sys/module/kvm_intel/parameters/nested

# Consider increasing VM resources
# - More vCPUs
# - More RAM
# - Faster disk (SSD)
```

#### Issue: Build fails with "Early loop device test failed"

This is common in nested VMs. Simply retry:

```bash
# Re-run the build command
podman run --rm --privileged -it \
  -v $PWD:/eib \
  registry.suse.com/edge/3.3/edge-image-builder:latest \
  build --definition-file downstream-cluster-config.yaml
```

### Best Practices for Nested VM Builds

1. **Use dedicated VM**: Don't run other workloads on the build VM
2. **Allocate sufficient resources**: 8+ vCPUs, 16GB+ RAM
3. **Use fast storage**: SSD-backed storage for better I/O
4. **Monitor resources**: Watch CPU/memory during builds
5. **Test first**: Run a simple build before complex configurations
6. **Consider alternatives**: If performance is critical, use bare metal or non-nested VM

### Alternative: Build on OpenStack Host

If nested VM performance is insufficient, consider:

1. **Build directly on OpenStack compute node** (if you have access)
2. **Use a separate physical machine** for builds
3. **Use CI/CD pipeline** with dedicated build runners
4. **Pre-build images** and store in registry

## Key Points

1. **SELinux must be disabled** on the build host (nested VM)
2. **Base image must be decompressed** (unxz) and placed in `base-images/`
3. **downstream-cluster-config.yaml** is the main image definition file
4. **01-fix-growfs.sh** is required in `custom/scripts/` for partition resizing
5. **network/** folder is optional but useful for network configuration scripts
6. **Container runs with --privileged** flag (required for image building)
7. **Directory is mounted** from host to `/eib` in container
8. **Nested VMs work but with performance overhead** - allocate sufficient resources

## References

- [SUSE Edge Image Builder Documentation](https://documentation.suse.com/suse-edge/3.3/html/edge/edge-image-builder.html)
- [SUSE Edge Metal3 Quickstart](https://documentation.suse.com/suse-edge/3.3/html/edge/quickstart-metal3.html)
- [Building Images with Kiwi](https://documentation.suse.com/suse-edge/3.3/html/edge/guides-kiwi-builder-images.html)

