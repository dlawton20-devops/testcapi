# Fixing Missing deploy_kernel and deploy_ramdisk

This guide helps you fix the error about missing `deploy_kernel` and `deploy_ramdisk` in Metal3/Ironic.

## 🎯 Quick Answer

**Ironic needs deploy kernel and ramdisk images to provision nodes.** These are typically downloaded automatically, but if missing, you need to configure Ironic to download them or provide them manually.

**Important**: Deploy kernel/ramdisk are generally **OS-agnostic** - they're used to boot nodes during provisioning and should work with any target OS (Ubuntu, CentOS, etc.). However, for best compatibility, use **Metal3 ironic-image releases** which are designed to be OS-agnostic.

## 🔍 What Are deploy_kernel and deploy_ramdisk?

These are special boot images that Ironic uses during provisioning:

- **deploy_kernel**: Linux kernel used to boot nodes during provisioning
- **deploy_ramdisk**: Initial RAM disk (initrd) with provisioning tools

**Purpose**: Ironic boots nodes with these images to:
1. Access the node's disk
2. Download the OS image
3. Write the OS image to disk
4. Configure the node

## 🚨 Common Error

### Error: "Cannot validate PXE bootloader - missing deploy_kernel, deploy_ramdisk"

**This specific error occurs when:**
- Ironic tries to validate the PXE bootloader configuration
- The node's `driver_info` doesn't have `deploy_kernel` and `deploy_ramdisk` parameters
- This happens during node registration/inspection phase

**Why this happens:**
1. When Metal3 registers a BareMetalHost, it creates an Ironic node
2. Ironic validates the node's bootloader configuration (PXE, iPXE, etc.)
3. For PXE bootloader validation, Ironic checks `driver_info` for `deploy_kernel` and `deploy_ramdisk`
4. If these aren't configured in Ironic's global config, they won't be in `driver_info`
5. Validation fails with: "cannot validate pxe bootloader some parameters were missing in the node's driver_info and configuration missing are deploy_kernel, deploy_ramdisk"

**The fix:**
- Configure `deploy_kernel` and `deploy_ramdisk` in Ironic's configuration (see solutions below)
- Ironic will then populate these in the node's `driver_info` during registration
- PXE bootloader validation will pass

### Understanding driver_info and Node Registration

**What is driver_info?**
- `driver_info` is metadata stored in Ironic's node database
- It contains configuration needed by the BMC driver (Redfish, IPMI, etc.)
- For PXE bootloader, it must include `deploy_kernel` and `deploy_ramdisk` URLs

**Registration Flow:**
```
1. You create BareMetalHost
   ↓
2. Metal3 Bare Metal Operator sees it
   ↓
3. Metal3 creates Ironic node (via Ironic API)
   ↓
4. Ironic validates bootloader configuration
   ↓
5. Ironic checks driver_info for required parameters
   ↓
6. If deploy_kernel/deploy_ramdisk missing → Validation fails
   ↓
7. Node registration fails → BareMetalHost stuck in "registering"
```

**Why Ironic needs these in driver_info:**
- Ironic needs to know where to get deploy images when provisioning
- These URLs are stored in `driver_info` for each node
- During validation, Ironic checks that all required parameters are present
- If missing, it can't proceed with provisioning

**How Ironic populates driver_info:**
- Ironic reads its global configuration (`ironic.conf`)
- If `[pxe] deploy_kernel` and `[pxe] deploy_ramdisk` are set, Ironic uses these
- These values are copied into each node's `driver_info` during registration
- If not configured globally, `driver_info` won't have them → validation fails

### Technical Deep Dive: Why This Validation Happens

**The Root Cause:**

Ironic has a **bootloader validation step** that runs **before** it accepts a node for provisioning. This validation ensures that when Ironic needs to provision the node, it will have all the required resources available.

**What Ironic Does During Validation:**

1. **Checks Bootloader Type**: Ironic determines the bootloader (PXE, iPXE, etc.) based on the node configuration
2. **Validates Required Parameters**: For PXE bootloader, Ironic requires:
   - `deploy_kernel` - URL to the kernel image
   - `deploy_ramdisk` - URL to the initramfs image
3. **Looks in driver_info**: Ironic checks the node's `driver_info` dictionary for these parameters
4. **Fails if Missing**: If either parameter is missing, validation fails immediately

**Why driver_info is Empty:**

When Metal3 creates an Ironic node, it populates `driver_info` from:
- **BMC connection info** (from BareMetalHost `bmc.address`)
- **Global Ironic configuration** (from `ironic.conf` or Helm values)

If `deploy_kernel` and `deploy_ramdisk` are **not** in Ironic's global configuration, they won't be added to `driver_info`, and validation fails.

**The Validation Code Path (Conceptual):**

```
Ironic Node Registration:
  ↓
Validate Bootloader (PXE):
  ↓
Check driver_info:
  - driver_info.get('deploy_kernel')  ← Returns None if not set
  - driver_info.get('deploy_ramdisk') ← Returns None if not set
  ↓
If either is None:
  → Raise ValidationError: "cannot validate pxe bootloader..."
  → Node registration fails
  → BareMetalHost stuck in "registering"
```

**Why Ironic Needs These URLs:**

Ironic needs these URLs in `driver_info` because:
1. **During Provisioning**: Ironic will boot the node with these images
2. **Must Be Available**: Ironic validates they exist **before** accepting the node
3. **Per-Node Storage**: Each node's `driver_info` stores its specific configuration
4. **Early Failure**: Better to fail early during registration than during provisioning

**The Fix Explained:**

When you configure `deploy_kernel` and `deploy_ramdisk` in Ironic's global config:

```
ironic.conf:
  [pxe]
  deploy_kernel = http://...
  deploy_ramdisk = http://...
```

Ironic will:
1. Read these values from config
2. Add them to each node's `driver_info` during registration
3. Validation passes ✅
4. Node registration succeeds ✅
5. BareMetalHost moves to "available" or "inspecting" ✅

### How to Verify driver_info Has deploy_kernel/deploy_ramdisk

**Check Ironic Node's driver_info:**

```bash
# From Rancher cluster, access Ironic API
# First, get Ironic service endpoint
IRONIC_SVC=$(kubectl get svc -n metal3-system | grep ironic | grep -v image | awk '{print $1}')
IRONIC_PORT=$(kubectl get svc -n metal3-system $IRONIC_SVC -o jsonpath='{.spec.ports[0].port}')

# Port-forward to Ironic API
kubectl port-forward -n metal3-system svc/$IRONIC_SVC 6385:$IRONIC_PORT &

# Get node UUID from BareMetalHost
NODE_UUID=$(kubectl get bmh node-1 -o jsonpath='{.status.provisioning.ID}')

# Query Ironic API for node's driver_info
curl -s http://localhost:6385/v1/nodes/$NODE_UUID | jq '.driver_info'

# Look for:
# {
#   "deploy_kernel": "http://...",
#   "deploy_ramdisk": "http://...",
#   ...
# }
```

**If driver_info is missing deploy_kernel/deploy_ramdisk:**

```bash
# You'll see driver_info like:
{
  "redfish_address": "http://...",
  "redfish_username": "admin",
  "redfish_password": "...",
  # deploy_kernel: MISSING ❌
  # deploy_ramdisk: MISSING ❌
}
```

**After configuring Ironic and re-registering:**

```bash
# After fixing Ironic config and node re-registers, check again:
curl -s http://localhost:6385/v1/nodes/$NODE_UUID | jq '.driver_info'

# Should now show:
{
  "redfish_address": "http://...",
  "redfish_username": "admin",
  "redfish_password": "...",
  "deploy_kernel": "http://tarballs.openstack.org/...",  # ✅ Present
  "deploy_ramdisk": "http://tarballs.openstack.org/..." # ✅ Present
}
```

**Alternative: Check Ironic Logs for Validation Errors:**

```bash
# Check Ironic logs for the exact validation error
kubectl logs -n metal3-system -l app.kubernetes.io/name=metal3-ironic | \
  grep -A 5 "cannot validate pxe bootloader"

# You'll see something like:
# ERROR: Cannot validate pxe bootloader: some parameters were missing 
# in the node's driver_info and configuration missing are 
# deploy_kernel, deploy_ramdisk
```

### Other Common Errors

```bash
# Error in Ironic logs:
kubectl logs -n metal3-system -l app.kubernetes.io/name=metal3-ironic | grep -i "deploy_kernel\|deploy_ramdisk"

# Common errors:
# - "deploy_kernel not found"
# - "deploy_ramdisk not found"
# - "No deploy kernel available"
# - "No deploy ramdisk available"
# - "cannot validate pxe bootloader" (your specific error)
```

## ✅ Solution 1: Configure Ironic via Helm (For Helm-Managed Metal3)

If Metal3 is installed via Helm (e.g., SUSE Edge Metal3 chart or `metal3-303.0.16+up0.12.6`), Ironic configuration is managed through Helm values, not a standalone ConfigMap.

### Step 1: Check Helm Release

```bash
# Find the Metal3 Helm release
helm list -n metal3-system

# Get the release name (usually "metal3" for SUSE chart)
RELEASE_NAME=$(helm list -n metal3-system -q | head -1)

# Get current Helm values
helm get values $RELEASE_NAME -n metal3-system > current-values.yaml

# Check Ironic configuration in Helm values
helm get values $RELEASE_NAME -n metal3-system | grep -i "ironic\|deploy\|kernel\|ramdisk"

# If nothing shows up, deploy_kernel/deploy_ramdisk are not configured
```

### Step 2: Update Helm Values

**For SUSE Edge Metal3 Chart (Your Setup):**

You installed with:
```bash
helm install metal3 oci://registry.suse.com/edge/charts/metal3 \
  --namespace metal3-system \
  --create-namespace \
  --set global.ironicIP="$STATIC_IRONIC_IP"
```

**Important**: The SUSE Edge Metal3 chart doesn't expose `deploy_kernel` and `deploy_ramdisk` in the values.yaml. We need to patch the Ironic ConfigMap directly.

**Option A: Patch ConfigMap with OpenStack Tarballs (Recommended):**

```bash
# Patch the Ironic ConfigMap to add deploy_kernel and deploy_ramdisk
# These environment variables will be read by Ironic to configure [pxe] section
kubectl patch configmap ironic -n metal3-system --type merge -p '{
  "data": {
    "DEPLOY_KERNEL": "http://tarballs.openstack.org/ironic-python-agent/dib/files/ipa-centos8-stable-wallaby.kernel",
    "DEPLOY_RAMDISK": "http://tarballs.openstack.org/ironic-python-agent/dib/files/ipa-centos8-stable-wallaby.initramfs"
  }
}'

# Restart Ironic to pick up the new configuration
kubectl rollout restart deployment -n metal3-system -l app.kubernetes.io/name=metal3-ironic

# Wait for restart
kubectl rollout status deployment -n metal3-system -l app.kubernetes.io/name=metal3-ironic
```

**Option B: Patch ConfigMap with Your Own HTTP Server:**

If you have an HTTP server serving deploy images (e.g., on your OpenStack VM):

```bash
# Set your VM IP
export VM_IP="10.2.83.181"  # Your OpenStack VM IP

# Patch the ConfigMap
kubectl patch configmap ironic -n metal3-system --type merge -p "{
  \"data\": {
    \"DEPLOY_KERNEL\": \"http://${VM_IP}:8080/deploy/deploy_kernel\",
    \"DEPLOY_RAMDISK\": \"http://${VM_IP}:8080/deploy/deploy_ramdisk\"
  }
}"

# Restart Ironic
kubectl rollout restart deployment -n metal3-system -l app.kubernetes.io/name=metal3-ironic
```

**Verify Configuration:**

```bash
# Check the ConfigMap was updated
kubectl get configmap ironic -n metal3-system -o yaml | grep -i "DEPLOY"

# Should show:
# DEPLOY_KERNEL: http://...
# DEPLOY_RAMDISK: http://...

# Check Ironic logs to verify it's using the configuration
kubectl logs -n metal3-system -l app.kubernetes.io/name=metal3-ironic | \
  grep -i "deploy.*kernel\|deploy.*ramdisk" | tail -10

# Re-register your BareMetalHost (delete and recreate, or wait for it to retry)
kubectl delete bmh node-1
# Then recreate it - it should now register successfully
```

**Note**: The SUSE Edge Metal3 chart uses environment variables in a ConfigMap. Ironic reads `DEPLOY_KERNEL` and `DEPLOY_RAMDISK` environment variables and uses them to configure the `[pxe]` section in `ironic.conf`. Patching the ConfigMap is the correct approach for this chart.

### Step 3: Alternative - Check Ironic ConfigMap (If Managed by Helm)

Even with Helm, Ironic configuration might be in a ConfigMap created by Helm:

```bash
# Check for Ironic ConfigMaps
kubectl get configmap -n metal3-system | grep ironic

# Check if Helm manages the ConfigMap
kubectl get configmap <ironic-configmap-name> -n metal3-system -o yaml | \
  grep -A 5 "helm.sh\|app.kubernetes.io/managed-by"

# If Helm-managed, update via Helm values (see Step 2)
# If not Helm-managed, you can edit directly (see Solution 1B below)
```

### Step 4: Use Ironic's Built-in Image Service (Recommended)

Ironic should automatically download deploy images. If it's not working, check Ironic image service configuration in Helm values.

**Ironic should automatically download images from:**
- `http://tarballs.openstack.org/ironic-python-agent/`
- Or configured image service URLs

**To verify Ironic is configured correctly:**

```bash
# Check Ironic deployment
kubectl get deployment -n metal3-system | grep ironic

# Check Ironic pod environment variables
kubectl get pod -n metal3-system -l app.kubernetes.io/name=metal3-ironic -o yaml | \
  grep -i "deploy\|kernel\|ramdisk\|image"
```

## ✅ Solution 2: Manually Download and Serve Images

If automatic download isn't working, manually download and serve the images:

### Step 1: Download Deploy Images

**Option 1: OpenStack Tarballs (Recommended - Known to work with Ubuntu):**

```bash
# On a machine with internet access
# Download from OpenStack tarballs (OS-agnostic, works with Ubuntu)
# These are the most reliable and widely used
wget http://tarballs.openstack.org/ironic-python-agent/dib/files/ipa-centos8-stable-wallaby.kernel
wget http://tarballs.openstack.org/ironic-python-agent/dib/files/ipa-centos8-stable-wallaby.initramfs
```

**Option 2: Metal3 ironic-image (If available):**

```bash
# Check actual releases at: https://github.com/metal3-io/ironic-image/releases
# Download the actual files from the releases page
# The file names and structure may vary by release
# Example (verify the actual file names on the releases page):
# Visit: https://github.com/metal3-io/ironic-image/releases
# Download the kernel and initramfs files from the latest release
# Then serve them via HTTP (see Step 2)
```

**Option 3: Build Your Own (Advanced):**

```bash
# If you need custom deploy images, you can build them using diskimage-builder
# This is more complex but gives you full control
# See: https://docs.openstack.org/ironic-python-agent/latest/admin/dib.html
```

**Why OpenStack tarballs work well:**
- ✅ OS-agnostic design (despite "centos8" in name)
- ✅ Widely tested and used
- ✅ Reliable download URLs
- ✅ Work with Ubuntu, CentOS, and other Linux distributions

### Step 2: Serve Images via HTTP

```bash
# On your OpenStack VM (or image server)
# Create directory for deploy images
sudo mkdir -p /opt/metal3-dev-env/ironic/html/images/deploy

# Copy deploy images
sudo cp ipa-centos8-stable-wallaby.kernel /opt/metal3-dev-env/ironic/html/images/deploy/deploy_kernel
sudo cp ipa-centos8-stable-wallaby.initramfs /opt/metal3-dev-env/ironic/html/images/deploy/deploy_ramdisk

# Ensure HTTP server serves these files
# (Your existing image server should serve them)
cd /opt/metal3-dev-env/ironic/html/images
python3 -m http.server 8080

# Images accessible at:
# http://${VM_IP}:8080/deploy/deploy_kernel
# http://${VM_IP}:8080/deploy/deploy_ramdisk
```

### Step 3: Configure Ironic to Use These URLs

**If using Helm:**

```bash
# Update Helm values
cat > deploy-images-values.yaml <<EOF
ironic:
  config:
    pxe:
      deploy_kernel: http://${VM_IP}:8080/deploy/deploy_kernel
      deploy_ramdisk: http://${VM_IP}:8080/deploy/deploy_ramdisk
EOF

# Upgrade Helm release
helm upgrade <release-name> <chart-name> -n metal3-system \
  --reuse-values \
  -f deploy-images-values.yaml
```

**If NOT using Helm (standalone ConfigMap):**

```bash
# Update Ironic ConfigMap directly
kubectl edit configmap ironic-config -n metal3-system

# Add:
data:
  ironic.conf: |
    [deploy]
    default_deploy_interface = direct
    
    [pxe]
    deploy_kernel = http://${VM_IP}:8080/deploy/deploy_kernel
    deploy_ramdisk = http://${VM_IP}:8080/deploy/deploy_ramdisk
```

## ✅ Solution 3: Use Metal3's Built-in Image Service (Easiest)

Metal3/Ironic should automatically handle deploy images. If it's not working:

### Step 1: Check Ironic Image Service

```bash
# Check if Ironic image service is running
kubectl get svc -n metal3-system | grep ironic

# Should show:
# ironic-image-cache  ClusterIP  ...  8080/TCP
```

### Step 2: Verify Ironic Can Access Images

```bash
# Check Ironic logs for image download attempts
kubectl logs -n metal3-system -l app.kubernetes.io/name=metal3-ironic | \
  grep -i "download\|kernel\|ramdisk" | tail -20

# Check for errors
kubectl logs -n metal3-system -l app.kubernetes.io/name=metal3-ironic | \
  grep -i "error\|fail" | tail -20
```

### Step 3: Restart Ironic (May Fix Auto-Download)

```bash
# Restart Ironic to retry image download
kubectl rollout restart deployment -n metal3-system -l app.kubernetes.io/name=metal3-ironic

# Wait for restart
kubectl rollout status deployment -n metal3-system -l app.kubernetes.io/name=metal3-ironic

# Check logs again
kubectl logs -n metal3-system -l app.kubernetes.io/name=metal3-ironic | \
  grep -i "kernel\|ramdisk" | tail -20
```

## ✅ Solution 4: Configure BareMetalHost to Skip Deploy (If Using Direct Deploy)

If you're using direct deploy (writing images directly), you might be able to skip deploy kernel/ramdisk:

```yaml
# In BareMetalHost spec
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-0
spec:
  # ... other spec ...
  image:
    url: http://${VM_IP}:8080/ubuntu-22.04.img
    checksum: http://${VM_IP}:8080/ubuntu-22.04.img.sha256
    checksumType: sha256
    format: raw
    # Direct deploy (may skip deploy kernel/ramdisk)
    # This depends on your Ironic configuration
```

**Note**: This may not work depending on your Ironic deploy interface configuration.

## 🔍 Diagnostic Steps

### Step 1: Check Ironic Logs

```bash
# Check for deploy kernel/ramdisk errors
kubectl logs -n metal3-system -l app.kubernetes.io/name=metal3-ironic | \
  grep -i "deploy.*kernel\|deploy.*ramdisk\|no.*deploy" | tail -30

# Check for image download errors
kubectl logs -n metal3-system -l app.kubernetes.io/name=metal3-ironic | \
  grep -i "download.*fail\|image.*error" | tail -20
```

### Step 2: Check Ironic Configuration

**If using Helm:**

```bash
# Check Helm release
helm list -n metal3-system

# Get current Helm values
helm get values <release-name> -n metal3-system | grep -i "ironic\|deploy\|kernel\|ramdisk"

# Check Ironic ConfigMap (may be Helm-managed)
kubectl get configmap -n metal3-system | grep ironic
kubectl get configmap <ironic-configmap-name> -n metal3-system -o yaml | \
  grep -i "deploy\|kernel\|ramdisk"
```

**If NOT using Helm:**

```bash
# Get Ironic ConfigMap
kubectl get configmap ironic-config -n metal3-system -o yaml

# Check for deploy-related settings
kubectl get configmap ironic-config -n metal3-system -o yaml | \
  grep -i "deploy\|kernel\|ramdisk"
```

### Step 3: Check Ironic Image Service

```bash
# Check if image service is running
kubectl get svc -n metal3-system | grep image

# Check image service logs
kubectl logs -n metal3-system -l app.kubernetes.io/name=ironic-image-cache | tail -20
```

### Step 4: Test Image URLs

```bash
# Test if deploy images are accessible
export VM_IP="192.168.1.100"

# Test from Rancher cluster
kubectl run -it --rm test-deploy-kernel \
  --image=curlimages/curl \
  --restart=Never \
  -- curl -I http://${VM_IP}:8080/deploy/deploy_kernel

kubectl run -it --rm test-deploy-ramdisk \
  --image=curlimages/curl \
  --restart=Never \
  -- curl -I http://${VM_IP}:8080/deploy/deploy_ramdisk
```

## 🛠️ Quick Fix: Restart Ironic

Sometimes Ironic just needs to retry downloading images:

```bash
# Restart Ironic
kubectl rollout restart deployment -n metal3-system -l app.kubernetes.io/name=metal3-ironic

# Wait for restart
kubectl rollout status deployment -n metal3-system -l app.kubernetes.io/name=metal3-ironic

# Check if images are downloaded now
kubectl logs -n metal3-system -l app.kubernetes.io/name=metal3-ironic | \
  grep -i "kernel\|ramdisk" | tail -10
```

## 📋 Complete Setup: Manual Deploy Images

If automatic download isn't working, here's a complete manual setup:

### Step 1: Download Images

```bash
# On a machine with internet
mkdir -p /tmp/deploy-images
cd /tmp/deploy-images

# Download from OpenStack tarballs (recommended - reliable URLs)
wget http://tarballs.openstack.org/ironic-python-agent/dib/files/ipa-centos8-stable-wallaby.kernel
wget http://tarballs.openstack.org/ironic-python-agent/dib/files/ipa-centos8-stable-wallaby.initramfs

# Alternative: Check Metal3 ironic-image releases
# Visit: https://github.com/metal3-io/ironic-image/releases
# Download the actual files from the releases page (file names may vary)
```

### Step 2: Copy to Image Server

```bash
# On OpenStack VM
sudo mkdir -p /opt/metal3-dev-env/ironic/html/images/deploy

# Copy images (from your download machine)
# Adjust file names based on what you downloaded
scp /tmp/deploy-images/ipa-centos8-stable-wallaby.kernel ubuntu@${VM_IP}:/opt/metal3-dev-env/ironic/html/images/deploy/deploy_kernel
scp /tmp/deploy-images/ipa-centos8-stable-wallaby.initramfs ubuntu@${VM_IP}:/opt/metal3-dev-env/ironic/html/images/deploy/deploy_ramdisk

# Or if already on VM, just move them
sudo mv /tmp/deploy-images/ipa-centos8-stable-wallaby.kernel /opt/metal3-dev-env/ironic/html/images/deploy/deploy_kernel
sudo mv /tmp/deploy-images/ipa-centos8-stable-wallaby.initramfs /opt/metal3-dev-env/ironic/html/images/deploy/deploy_ramdisk
```

### Step 3: Verify HTTP Server Serves Them

```bash
# On OpenStack VM
cd /opt/metal3-dev-env/ironic/html/images

# Ensure HTTP server is running
python3 -m http.server 8080 &
# Or use your existing systemd service

# Test locally
curl -I http://localhost:8080/deploy/deploy_kernel
curl -I http://localhost:8080/deploy/deploy_ramdisk
```

### Step 4: Update Ironic Configuration

**If using Helm:**

```bash
# Update Helm values
cat > deploy-images-values.yaml <<EOF
ironic:
  config:
    pxe:
      deploy_kernel: http://${VM_IP}:8080/deploy/deploy_kernel
      deploy_ramdisk: http://${VM_IP}:8080/deploy/deploy_ramdisk
EOF

# Upgrade Helm release
helm upgrade <release-name> <chart-name> -n metal3-system \
  --reuse-values \
  -f deploy-images-values.yaml

# Restart Ironic (Helm upgrade should do this automatically)
kubectl rollout restart deployment -n metal3-system -l app.kubernetes.io/name=metal3-ironic
```

**If NOT using Helm:**

```bash
# Update Ironic ConfigMap
kubectl patch configmap ironic-config -n metal3-system --type merge -p '{
  "data": {
    "ironic.conf": "[deploy]\ndefault_deploy_interface = direct\n\n[pxe]\ndeploy_kernel = http://'${VM_IP}':8080/deploy/deploy_kernel\ndeploy_ramdisk = http://'${VM_IP}':8080/deploy/deploy_ramdisk\n"
  }
}'

# Restart Ironic
kubectl rollout restart deployment -n metal3-system -l app.kubernetes.io/name=metal3-ironic
```

## 🔄 Deploy Kernel/Ramdisk Compatibility with Ubuntu

### Will CentOS-based Deploy Images Work with Ubuntu?

**Short answer**: Yes, generally they will work, but **Metal3 ironic-image releases are recommended** for Ubuntu.

**Why:**
- Deploy kernel/ramdisk are used **only during provisioning** (not the final OS)
- They boot the node temporarily to write the OS image to disk
- They're generally OS-agnostic and should work with any target OS

**However:**
- CentOS-based deploy images may have compatibility issues in some cases
- Metal3 ironic-image releases are designed to be OS-agnostic
- Better compatibility and fewer issues with Ubuntu deployments

### Recommended Sources for Ubuntu

1. **OpenStack tarballs** (Recommended - Most Reliable)
   - URL: `http://tarballs.openstack.org/ironic-python-agent/dib/files/`
   - Files: `ipa-centos8-stable-wallaby.kernel` and `ipa-centos8-stable-wallaby.initramfs`
   - Despite "centos8" in name, these are OS-agnostic and work with Ubuntu
   - Widely tested and reliable download URLs
   - **This is the recommended option**

2. **Metal3 ironic-image releases** (If available)
   - URL: `https://github.com/metal3-io/ironic-image/releases`
   - Check the releases page for actual file names and download URLs
   - File names and structure may vary by release
   - May require manual download and serving via HTTP

## 📝 Summary

**To fix missing deploy_kernel and deploy_ramdisk:**

1. **First try**: Restart Ironic (may auto-download)
   ```bash
   kubectl rollout restart deployment -n metal3-system -l app.kubernetes.io/name=metal3-ironic
   ```

2. **If that doesn't work**: Manually download and serve images
   - **Recommended**: Use OpenStack tarballs (reliable, work with Ubuntu)
   - **Alternative**: Check Metal3 ironic-image releases page for actual files
   - Serve via HTTP server
   - Configure Ironic to use the URLs

3. **Verify**: Check Ironic logs for successful image download

**Key Points:**
- ✅ Ironic needs deploy kernel and ramdisk to provision nodes
- ✅ These are typically downloaded automatically
- ✅ **For Ubuntu**: OpenStack tarballs work well (despite "centos8" in name, they're OS-agnostic)
- ✅ Deploy images are OS-agnostic - they only boot nodes temporarily during provisioning
- ✅ If missing, download manually and serve via HTTP
- ✅ **If using Helm**: Configure via Helm values and upgrade the release
- ✅ **If NOT using Helm**: Configure Ironic ConfigMap directly
- ✅ Restart Ironic after configuration changes

**Important**: 
- If Metal3 is installed via Helm (e.g., `metal3-303.0.16+up0.12.6`), configuration should be done through Helm values, not by editing ConfigMaps directly, as Helm will overwrite manual changes.
- **OpenStack tarballs are the most reliable source** - despite the "centos8" name, they work with Ubuntu and other Linux distributions.

**Most Common Fix**: Restart Ironic - it often just needs to retry downloading the images.

