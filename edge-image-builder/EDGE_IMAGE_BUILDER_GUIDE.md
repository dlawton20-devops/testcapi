# Using SUSE Edge Image Builder for Metal3 Images

## Overview

SUSE Edge Image Builder (EIB) is used to build custom OS images for Metal3 bare-metal provisioning. This guide shows how to build images in a separate environment and use them with Metal3.

**Reference**: [SUSE Edge Metal3 Quickstart](https://documentation.suse.com/suse-edge/3.3/html/edge/quickstart-metal3.html)

## Prerequisites

### Required Image
- **SLE Micro base image**: `SL-Micro.x86_64-6.1-Base-GM.raw`
  - Download from [SUSE Customer Center](https://scc.suse.com/) or [SUSE Download page](https://download.suse.com/)
  - This is the base OS image that will be customized

### Tools Required
- **Kubectl, Helm, Clusterctl** - For Kubernetes operations
- **Container runtime** - Podman or Docker/Rancher Desktop
- **Access to SUSE Edge registry** - For Helm charts

## Architecture

```
Build Environment (Separate)
    │
    ├── Edge Image Builder
    │   ├── Builds custom OS image
    │   ├── Adds packages, configurations
    │   └── Outputs: SLE-Micro-custom.raw
    │
    └── Image Cache/Server
        └── Serves image to Metal3

Metal3 Environment
    │
    ├── Metal3 Management Cluster
    │   ├── Downloads image from cache
    │   └── Provisions to bare-metal hosts
    │
    └── BareMetalHosts
        └── Receive custom OS image
```

## Step 1: Set Up Edge Image Builder

### Option A: Using Edge Image Builder in Kubernetes

1. **Install Edge Image Builder** (if not already installed):

```bash
# Add SUSE Edge Helm repository
helm repo add suse-edge https://registry.suse.com/edge/charts
helm repo update

# Install Edge Image Builder
helm install edge-image-builder oci://registry.suse.com/edge/charts/edge-image-builder \
  --namespace edge-image-builder \
  --create-namespace
```

2. **Verify installation**:

```bash
kubectl get pods -n edge-image-builder
# Should show edge-image-builder pods running
```

### Option B: Using Edge Image Builder Standalone

If building on a separate machine without Kubernetes:

```bash
# Install Edge Image Builder tools
# Follow SUSE Edge Image Builder documentation for standalone installation
```

## Step 2: Prepare Image Build Configuration

### Create Build Configuration File

Create an `image-build-config.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: eib-image-config
  namespace: edge-image-builder
data:
  config.yaml: |
    apiVersion: v1
    kind: ElementalImage
    metadata:
      name: metal3-custom-image
    spec:
      baseImage: "SL-Micro.x86_64-6.1-Base-GM.raw"
      outputImage: "SLE-Micro-metal3-custom.raw"
      cloudConfig:
        users:
          - name: root
            passwd: "$6$rounds=4096$salt$hashedpassword"  # Generate with: openssl passwd -6
          - name: suse
            groups:
              - wheel
            sshAuthorizedKeys:
              - "ssh-rsa AAAAB3NzaC1yc2E..."  # Your SSH public key
        timezone: "UTC"
      packages:
        - kubernetes
        - container-runtime
        - additional-packages
      systemd:
        units:
          - name: custom-service.service
            enabled: true
            contents: |
              [Unit]
              Description=Custom Service
              [Service]
              ExecStart=/usr/bin/custom-script
              [Install]
              WantedBy=multi-user.target
```

### Alternative: Using Elemental Image Definition

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: eib-elemental-config
  namespace: edge-image-builder
data:
  elemental.yaml: |
    apiVersion: v1
    kind: ElementalImage
    metadata:
      name: metal3-image
    spec:
      base: "SL-Micro.x86_64-6.1-Base-GM.raw"
      output: "SLE-Micro-metal3.raw"
      cloudConfig:
        users:
          - name: root
            passwd: "$6$..."
        sshAuthorizedKeys:
          - "ssh-rsa AAAAB3..."
      packages:
        - kubernetes
        - container-runtime
```

## Step 3: Build the Image

### Using Edge Image Builder in Kubernetes

1. **Create the build job**:

```bash
# Apply the build configuration
kubectl apply -f image-build-config.yaml

# Create build job
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
            # Build image using EIB
            elemental build --config /config/config.yaml
        volumeMounts:
        - name: config
          mountPath: /config
        - name: output
          mountPath: /output
      volumes:
      - name: config
        configMap:
          name: eib-image-config
      - name: output
        emptyDir: {}
      restartPolicy: Never
EOF
```

2. **Monitor build progress**:

```bash
# Watch the build job
kubectl get jobs -n edge-image-builder -w

# Check build logs
kubectl logs -n edge-image-builder job/build-metal3-image -f
```

3. **Extract the built image**:

```bash
# Wait for job to complete
kubectl wait --for=condition=complete job/build-metal3-image -n edge-image-builder --timeout=30m

# Copy image from pod
POD=$(kubectl get pods -n edge-image-builder -l job-name=build-metal3-image -o jsonpath='{.items[0].metadata.name}')
kubectl cp edge-image-builder/$POD:/output/SLE-Micro-metal3-custom.raw ./SLE-Micro-metal3-custom.raw
```

### Using Edge Image Builder CLI (Standalone)

If using EIB CLI directly:

```bash
# Build image
elemental build \
  --config image-build-config.yaml \
  --output-dir ./output

# Output will be in ./output/SLE-Micro-metal3-custom.raw
```

## Step 4: Set Up Image Server/Cache

The built image needs to be accessible to Metal3. Set up an image cache server:

### Option A: Simple HTTP Server

```bash
# On your build environment or accessible server
cd /path/to/images
python3 -m http.server 8080

# Or using a more robust server
# Install nginx or apache to serve images
```

### Option B: Using Kubernetes Service

```bash
# Create a ConfigMap with the image
kubectl create configmap metal3-image \
  --from-file=SLE-Micro-metal3-custom.raw \
  -n metal3-system

# Or use a PersistentVolume to store images
```

### Option C: Object Storage (S3-compatible)

```bash
# Upload to S3 or compatible storage
aws s3 cp SLE-Micro-metal3-custom.raw s3://your-bucket/metal3-images/
# Or use MinIO, etc.
```

## Step 5: Configure Metal3 to Use the Image

### Update BareMetalHost with Custom Image

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
    url: "http://imagecache.local:8080/SLE-Micro-metal3-custom.raw"
    checksum: "http://imagecache.local:8080/SLE-Micro-metal3-custom.raw.sha256"
    checksumType: "sha256"
    format: "raw"
```

### Generate Checksum

```bash
# Generate SHA256 checksum
sha256sum SLE-Micro-metal3-custom.raw > SLE-Micro-metal3-custom.raw.sha256

# Make checksum available
# Place in same location as image or serve separately
```

## Step 6: Network Configuration for Image

### Create NetworkData Secret

For the provisioned OS (not IPA), create a separate NetworkData:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: node-0-networkdata
  namespace: metal3-system
type: Opaque
stringData:
  networkData: |
    version: 2
    ethernets:
      # Match by MAC address (more reliable)
      match_by_mac:
        match:
          macaddress: "52:54:00:XX:XX:XX"  # VM's MAC
        dhcp4: false
        addresses:
          - 10.2.83.181/24
        gateway4: 10.2.83.1
        nameservers:
          addresses:
            - 8.8.8.8
            - 8.8.4.4
```

### Reference in BareMetalHost

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-0
spec:
  # ... other fields ...
  networkData:
    name: node-0-networkdata
    namespace: metal3-system
```

## Complete Example: Building and Using Custom Image

### 1. Build Image in Separate Environment

```bash
# On build environment
cd /build/environment

# Download base image
wget https://download.suse.com/SLE-Micro.x86_64-6.1-Base-GM.raw

# Create build config
cat > build-config.yaml <<EOF
apiVersion: v1
kind: ElementalImage
metadata:
  name: metal3-custom
spec:
  base: "SLE-Micro.x86_64-6.1-Base-GM.raw"
  output: "SLE-Micro-metal3-custom.raw"
  cloudConfig:
    users:
      - name: root
        passwd: "$6$..."  # Generated password hash
    sshAuthorizedKeys:
      - "ssh-rsa AAAAB3..."  # Your SSH key
  packages:
    - kubernetes
    - container-runtime
EOF

# Build image
elemental build --config build-config.yaml

# Generate checksum
sha256sum SLE-Micro-metal3-custom.raw > SLE-Micro-metal3-custom.raw.sha256
```

### 2. Serve Image

```bash
# Start simple HTTP server
cd /build/environment
python3 -m http.server 8080

# Or use nginx
# Configure nginx to serve /build/environment directory on port 8080
```

### 3. Use in Metal3 Environment

```bash
# On Metal3 management cluster
kubectl apply -f - <<EOF
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
    url: "http://<build-server-ip>:8080/SLE-Micro-metal3-custom.raw"
    checksum: "http://<build-server-ip>:8080/SLE-Micro-metal3-custom.raw.sha256"
    checksumType: "sha256"
    format: "raw"
  networkData:
    name: node-0-networkdata
    namespace: metal3-system
EOF
```

## Image Build Best Practices

### 1. Include Required Packages

```yaml
packages:
  - kubernetes
  - container-runtime  # containerd, cri-o, etc.
  - network-utilities
  - cloud-init
```

### 2. Configure Users and SSH

```yaml
cloudConfig:
  users:
    - name: root
      passwd: "$6$..."  # Use: openssl passwd -6
    - name: admin
      groups: [wheel]
      sshAuthorizedKeys:
        - "ssh-rsa AAAAB3..."
```

### 3. Set Timezone and Locale

```yaml
cloudConfig:
  timezone: "UTC"
  locale: "en_US.UTF-8"
```

### 4. Configure Systemd Services

```yaml
systemd:
  units:
    - name: custom-service.service
      enabled: true
      contents: |
        [Unit]
        Description=Custom Service
        [Service]
        ExecStart=/usr/bin/custom-script
        [Install]
        WantedBy=multi-user.target
```

## Troubleshooting

### Image Build Fails

```bash
# Check build logs
kubectl logs -n edge-image-builder job/build-metal3-image -f

# Check for common issues:
# - Base image not found
# - Insufficient disk space
# - Package installation failures
```

### Image Not Accessible from Metal3

```bash
# Verify image server is reachable
curl -I http://image-server:8080/SLE-Micro-metal3-custom.raw

# Check network connectivity from Metal3 cluster
# Test from a pod in metal3-system namespace
kubectl run -it --rm test-pod --image=curlimages/curl --restart=Never -- \
  curl -I http://image-server:8080/SLE-Micro-metal3-custom.raw
```

### Image Checksum Mismatch

```bash
# Regenerate checksum
sha256sum SLE-Micro-metal3-custom.raw > SLE-Micro-metal3-custom.raw.sha256

# Verify checksum file format
cat SLE-Micro-metal3-custom.raw.sha256
# Should be: <checksum>  <filename>
```

### Provisioning Fails

```bash
# Check BareMetalHost status
kubectl get baremetalhost node-0 -n metal3-system -o yaml

# Check Ironic logs
kubectl logs -n metal3-system -l app.kubernetes.io/component=ironic

# Check IPA console
virsh console node-0
```

## Key Points from SUSE Documentation

According to the [SUSE Edge Metal3 Quickstart](https://documentation.suse.com/suse-edge/3.3/html/edge/quickstart-metal3.html):

1. **Base Image Required**: `SL-Micro.x86_64-6.1-Base-GM.raw` must be downloaded from SUSE Customer Center

2. **Image Format**: Must be `raw` format for Metal3 provisioning

3. **Image Serving**: Image must be accessible via HTTP/HTTPS from Metal3 management cluster

4. **Checksum**: SHA256 checksum file should be provided for verification

5. **Network Configuration**: Separate NetworkData for provisioned OS (different from IPA NetworkData)

## References

- [SUSE Edge Metal3 Quickstart](https://documentation.suse.com/suse-edge/3.3/html/edge/quickstart-metal3.html)
- [SUSE Edge Image Builder Documentation](https://documentation.suse.com/suse-edge/3.3/html/edge/edge-image-builder.html)
- [SUSE Customer Center](https://scc.suse.com/)
- [SUSE Download Page](https://download.suse.com/)

