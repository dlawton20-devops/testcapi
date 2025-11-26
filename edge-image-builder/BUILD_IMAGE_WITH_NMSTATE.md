# Building Edge Image Builder Image with nmstate Support

## Overview

This guide shows how to build a SLE Micro image using Edge Image Builder that includes:
- nmstate package (provides NM Configurator - nmc tool)
- configure-network.sh script for static IP configuration
- Systemd service to run the script on first boot

## Prerequisites

1. **Base Image**: `SL-Micro.x86_64-6.1-Base-GM.raw`
   - Download from [SUSE Customer Center](https://scc.suse.com/) or [SUSE Download page](https://download.suse.com/)

2. **Edge Image Builder**: Installed and accessible
   - Can be in Kubernetes or standalone

3. **Access to SUSE repositories**: For installing packages

## Step 1: Prepare Build Configuration

### Create Complete Build Configuration

Create `eib-build-config.yaml`:

```yaml
apiVersion: v1
kind: ElementalImage
metadata:
  name: metal3-static-ip-image
spec:
  # Base image (must be downloaded first)
  base: "SL-Micro.x86_64-6.1-Base-GM.raw"
  
  # Output image name
  output: "SLE-Micro-metal3-static-ip.raw"
  
  # Cloud configuration
  cloudConfig:
    users:
      - name: root
        passwd: "$6$rounds=4096$salt$hashedpassword"  # Generate with: openssl passwd -6
      - name: suse
        groups:
          - wheel
        sshAuthorizedKeys:
          - "ssh-rsa AAAAB3NzaC1yc2E..."  # Your SSH public key
  
  # Required packages - MUST include nmstate
  packages:
    - nmstate              # Provides NM Configurator (nmc tool)
    - NetworkManager       # NetworkManager (required by nmstate)
    - util-linux           # Provides blkid command
    - cloud-init           # For metadata handling
  
  # Systemd units
  systemd:
    units:
      # Service to configure network on first boot
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
          # Mark as run once
          ExecStartPost=/bin/mkdir -p /etc/systemd/system/configure-network.service.d
          ExecStartPost=/bin/touch /etc/systemd/system/configure-network.service.d/ran-once.conf
          
          [Install]
          WantedBy=multi-user.target
  
  # Files to include in image
  files:
    # configure-network.sh script
    - path: /usr/local/bin/configure-network.sh
      permissions: "0755"
      contents: |
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
        
        # Use nmc (NM Configurator) to generate and apply network config
        /usr/bin/nmc generate --config-dir /tmp/nmc/desired --output-dir /tmp/nmc/generated
        /usr/bin/nmc apply --config-dir /tmp/nmc/generated
```

## Step 2: Generate Password Hash

Before building, generate the password hash:

```bash
# Generate password hash for root user
openssl passwd -6 "your-password-here"

# Output example: $6$rounds=4096$salt$hashedpassword
# Use this in the cloudConfig.users[0].passwd field
```

## Step 3: Build Image with Edge Image Builder

### Option A: Using Edge Image Builder in Kubernetes

1. **Create ConfigMap with build configuration**:

```bash
kubectl create configmap eib-build-config \
  --from-file=config.yaml=eib-build-config.yaml \
  -n edge-image-builder
```

2. **Create build job**:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: build-metal3-image
  namespace: edge-image-builder
spec:
  template:
    spec:
      containers:
      - name: image-builder
        image: registry.suse.com/edge/edge-image-builder:latest
        command: ["/bin/sh", "-c"]
        args:
          - |
            # Copy base image if needed
            if [ ! -f /workspace/SL-Micro.x86_64-6.1-Base-GM.raw ]; then
              echo "Base image not found. Please ensure it's available."
              exit 1
            fi
            
            # Build image
            elemental build \
              --config /config/config.yaml \
              --output-dir /output
        volumeMounts:
        - name: config
          mountPath: /config
        - name: base-image
          mountPath: /workspace
        - name: output
          mountPath: /output
        resources:
          requests:
            memory: "4Gi"
            cpu: "2"
          limits:
            memory: "8Gi"
            cpu: "4"
      volumes:
      - name: config
        configMap:
          name: eib-build-config
      - name: base-image
        persistentVolumeClaim:
          claimName: base-image-pvc  # Or use hostPath/emptyDir
      - name: output
        emptyDir: {}
      restartPolicy: Never
  backoffLimit: 1
EOF
```

3. **Monitor build**:

```bash
# Watch job status
kubectl get jobs -n edge-image-builder -w

# Watch build logs
kubectl logs -n edge-image-builder job/build-metal3-image -f
```

4. **Extract built image**:

```bash
# Wait for completion
kubectl wait --for=condition=complete job/build-metal3-image -n edge-image-builder --timeout=60m

# Get pod name
POD=$(kubectl get pods -n edge-image-builder -l job-name=build-metal3-image -o jsonpath='{.items[0].metadata.name}')

# Copy image from pod
kubectl cp edge-image-builder/$POD:/output/SLE-Micro-metal3-static-ip.raw \
  ./SLE-Micro-metal3-static-ip.raw

# Generate checksum
sha256sum SLE-Micro-metal3-static-ip.raw > SLE-Micro-metal3-static-ip.raw.sha256
```

### Option B: Using Edge Image Builder CLI (Standalone)

If you have Edge Image Builder CLI installed locally:

1. **Prepare workspace**:

```bash
# Create build directory
mkdir -p ~/eib-build
cd ~/eib-build

# Download base image (if not already present)
wget https://download.suse.com/SL-Micro.x86_64-6.1-Base-GM.raw

# Create build config
cat > build-config.yaml <<EOF
# ... (use the config from Step 1)
EOF
```

2. **Build image**:

```bash
# Build using elemental CLI
elemental build \
  --config build-config.yaml \
  --output-dir ./output

# Output will be in: ./output/SLE-Micro-metal3-static-ip.raw
```

3. **Generate checksum**:

```bash
cd output
sha256sum SLE-Micro-metal3-static-ip.raw > SLE-Micro-metal3-static-ip.raw.sha256
```

### Option C: Using Elemental Operator (Alternative)

If using Elemental Operator in Kubernetes:

```yaml
apiVersion: elemental.cattle.io/v1beta1
kind: MachineInventorySelectorTemplate
metadata:
  name: metal3-image-build
spec:
  template:
    spec:
      config:
        elementals:
          install:
            device: /dev/sda
            reboot: false
          reset:
            enabled: false
        cloud-init:
          network:
            # Network configuration will be applied via configure-network.sh
            passwd: true
```

## Step 4: Verify Image Contents

### Check nmstate is Installed

After building, verify the image includes required components:

```bash
# Mount the image to check contents
sudo mkdir -p /mnt/image-check
sudo mount -o loop,offset=$((2048*512)) SLE-Micro-metal3-static-ip.raw /mnt/image-check

# Check nmstate is installed
sudo chroot /mnt/image-check rpm -qa | grep nmstate

# Check nmc tool exists
sudo chroot /mnt/image-check which nmc
sudo chroot /mnt/image-check nmc --version

# Check script exists
sudo ls -l /mnt/image-check/usr/local/bin/configure-network.sh

# Check systemd service
sudo ls -l /mnt/image-check/etc/systemd/system/configure-network.service

# Unmount
sudo umount /mnt/image-check
```

### Alternative: Boot Test VM

```bash
# Create test VM with the image
qemu-img create -f qcow2 -F raw -b SLE-Micro-metal3-static-ip.raw test-vm.qcow2 20G

# Boot VM and check
virt-install \
  --name test-vm \
  --memory 2048 \
  --vcpus 2 \
  --disk path=test-vm.qcow2 \
  --import \
  --noautoconsole

# Connect to console
virsh console test-vm

# Inside VM, check:
which nmc
nmc --version
ls -l /usr/local/bin/configure-network.sh
systemctl status configure-network.service
```

## Step 5: Complete Build Script

Here's a complete script to build the image:

```bash
#!/bin/bash
set -e

echo "🔨 Building Metal3 Image with nmstate Support"
echo "=============================================="

# Configuration
BASE_IMAGE="SL-Micro.x86_64-6.1-Base-GM.raw"
OUTPUT_IMAGE="SLE-Micro-metal3-static-ip.raw"
BUILD_DIR="./eib-build"
OUTPUT_DIR="./output"

# Generate password hash
echo "Generating password hash..."
ROOT_PASSWORD_HASH=$(openssl passwd -6 "changeme")  # Change password
echo "Password hash: $ROOT_PASSWORD_HASH"

# Get SSH public key
SSH_PUBLIC_KEY=$(cat ~/.ssh/id_rsa.pub 2>/dev/null || echo "# Add your SSH key")

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Download base image if not exists
if [ ! -f "$BASE_IMAGE" ]; then
    echo "Downloading base image..."
    echo "Please download $BASE_IMAGE from SUSE Customer Center"
    echo "Place it in: $BUILD_DIR/$BASE_IMAGE"
    exit 1
fi

# Create build configuration
cat > build-config.yaml <<EOF
apiVersion: v1
kind: ElementalImage
metadata:
  name: metal3-static-ip-image
spec:
  base: "$BASE_IMAGE"
  output: "$OUTPUT_IMAGE"
  cloudConfig:
    users:
      - name: root
        passwd: "$ROOT_PASSWORD_HASH"
      - name: suse
        groups:
          - wheel
        sshAuthorizedKeys:
          - "$SSH_PUBLIC_KEY"
  packages:
    - nmstate
    - NetworkManager
    - util-linux
    - cloud-init
  systemd:
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
  files:
    - path: /usr/local/bin/configure-network.sh
      permissions: "0755"
      contents: |
        #!/bin/bash
        set -eux
        
        CONFIG_DRIVE=\$(blkid --label config-2 || true)
        if [ -z "\${CONFIG_DRIVE}" ]; then
          echo "No config-2 device found, skipping network configuration"
          exit 0
        fi
        
        mount -o ro \$CONFIG_DRIVE /mnt
        
        NETWORK_DATA_FILE="/mnt/openstack/latest/network_data.json"
        
        if [ ! -f "\${NETWORK_DATA_FILE}" ]; then
          umount /mnt
          echo "No network_data.json found, skipping network configuration"
          exit 0
        fi
        
        DESIRED_HOSTNAME=\$(cat /mnt/openstack/latest/meta_data.json | tr ',{}' '\n' | grep '\"metal3-name\"' | sed 's/.*\"metal3-name\": \"\(.*\)\"/\1/')
        if [ -n "\${DESIRED_HOSTNAME}" ]; then
          echo "\${DESIRED_HOSTNAME}" > /etc/hostname
          hostname "\${DESIRED_HOSTNAME}"
        fi
        
        mkdir -p /tmp/nmc/{desired,generated}
        cp \${NETWORK_DATA_FILE} /tmp/nmc/desired/_all.yaml
        umount /mnt
        
        /usr/bin/nmc generate --config-dir /tmp/nmc/desired --output-dir /tmp/nmc/generated
        /usr/bin/nmc apply --config-dir /tmp/nmc/generated
EOF

# Build image
echo "Building image..."
elemental build \
  --config build-config.yaml \
  --output-dir "$OUTPUT_DIR"

# Generate checksum
echo "Generating checksum..."
cd "$OUTPUT_DIR"
sha256sum "$OUTPUT_IMAGE" > "${OUTPUT_IMAGE}.sha256"

echo "✅ Image built: $OUTPUT_DIR/$OUTPUT_IMAGE"
echo "✅ Checksum: $OUTPUT_DIR/${OUTPUT_IMAGE}.sha256"
```

## Step 6: Using Elemental Build with Kiwi (Alternative)

If using Kiwi-based builds:

```xml
<?xml version="1.0" encoding="utf-8"?>
<image name="metal3-static-ip" displayname="Metal3 Static IP Image">
  <description type="system">
    <author>SUSE</author>
    <contact>support@suse.com</contact>
    <specification>SLE Micro for Metal3 with static IP support</specification>
  </description>
  
  <preferences>
    <type image="oem" filesystem="btrfs" bootloader="grub2_efi"/>
    <version>1.0.0</version>
    <packagemanager>zypper</packagemanager>
    <rpm-excludedocs>true</rpm-excludedocs>
  </preferences>
  
  <users>
    <user pwdformat="sha512" pwdhash="$6$..." name="root"/>
  </users>
  
  <packages type="image">
    <package name="nmstate"/>
    <package name="NetworkManager"/>
    <package name="util-linux"/>
    <package name="cloud-init"/>
  </packages>
  
  <systemd>
    <service name="configure-network.service" enabled="true">
      <unit>
        <description>Configure Network from Config Drive</description>
        <after>network-online.target</after>
        <wants>network-online.target</wants>
      </unit>
      <service>
        <type>oneshot</type>
        <execstart>/usr/local/bin/configure-network.sh</execstart>
      </service>
      <install>
        <wantedby>multi-user.target</wantedby>
      </install>
    </service>
  </systemd>
  
  <files>
    <file name="configure-network.sh" target="/usr/local/bin/configure-network.sh" mode="0755">
      <contents>
        #!/bin/bash
        set -eux
        # ... (script contents)
      </contents>
    </file>
  </files>
</image>
```

## Step 7: Verify nmstate Package Availability

### Check SUSE Repository

Ensure nmstate is available in your repositories:

```bash
# If building in SLE Micro, check repositories
zypper search nmstate

# If not found, add required repository
zypper addrepo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/SLE_15_SP4/ containers
zypper refresh
zypper install nmstate
```

### Package Dependencies

nmstate requires:
- NetworkManager
- python3-nmstate (usually included)
- libnm (NetworkManager library)

These should be automatically resolved when installing nmstate.

## Troubleshooting Build Issues

### nmstate Package Not Found

```bash
# Check available repositories
zypper repos

# Add SUSE repository if needed
zypper addrepo https://download.suse.com/repositories/... suse-repo
zypper refresh

# Verify package exists
zypper search nmstate
```

### Script Not Executable

```bash
# In build config, ensure permissions are set:
files:
  - path: /usr/local/bin/configure-network.sh
    permissions: "0755"  # Must be executable
```

### Systemd Service Not Enabled

```bash
# Verify service is enabled in build config:
systemd:
  units:
    - name: configure-network.service
      enabled: true  # Must be true
```

### Build Fails with Package Errors

```bash
# Check build logs for specific package errors
# Common issues:
# - Repository not accessible
# - Package name incorrect
# - Dependency conflicts

# Verify package names:
zypper search nmstate
zypper search NetworkManager
```

## Complete Example: Full Build Process

```bash
#!/bin/bash
set -e

# 1. Download base image
BASE_IMAGE="SL-Micro.x86_64-6.1-Base-GM.raw"
if [ ! -f "$BASE_IMAGE" ]; then
    echo "Please download $BASE_IMAGE from SUSE Customer Center"
    exit 1
fi

# 2. Generate password
PASSWORD_HASH=$(openssl passwd -6 "your-password")

# 3. Create build config (see Step 1 for full config)

# 4. Build image
elemental build --config build-config.yaml --output-dir ./output

# 5. Verify
cd output
ls -lh SLE-Micro-metal3-static-ip.raw
sha256sum SLE-Micro-metal3-static-ip.raw > SLE-Micro-metal3-static-ip.raw.sha256

# 6. Test (optional)
# Create test VM and verify nmc is available
```

## Key Requirements Summary

### Must Include in Image:

1. **nmstate package** - Provides NM Configurator (nmc tool)
2. **NetworkManager** - Required by nmstate
3. **util-linux** - Provides blkid command
4. **configure-network.sh script** - Network configuration script
5. **configure-network.service** - Systemd service to run script

### Build Configuration Checklist:

- [ ] Base image specified correctly
- [ ] nmstate in packages list
- [ ] NetworkManager in packages list
- [ ] Script file path: `/usr/local/bin/configure-network.sh`
- [ ] Script permissions: `0755`
- [ ] Systemd service enabled: `true`
- [ ] Service runs after `network-online.target`

## References

- [SUSE Edge Image Builder Documentation](https://documentation.suse.com/suse-edge/3.3/html/edge/edge-image-builder.html)
- [SUSE Edge Metal3 Static IP Configuration](https://documentation.suse.com/suse-edge/3.3/html/edge/quickstart-metal3.html)
- [NM Configurator Documentation](https://documentation.suse.com/suse-edge/3.3/html/edge/edge-networking.html)

