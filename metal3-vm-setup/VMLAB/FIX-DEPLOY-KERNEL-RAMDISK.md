# Fixing Missing deploy_kernel and deploy_ramdisk

This guide helps you fix the error about missing `deploy_kernel` and `deploy_ramdisk` in Metal3/Ironic.

## 🎯 Quick Answer

**Ironic needs deploy kernel and ramdisk images to provision nodes.** These are typically downloaded automatically, but if missing, you need to configure Ironic to download them or provide them manually.

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

```bash
# Error in Ironic logs:
kubectl logs -n metal3-system -l app.kubernetes.io/name=metal3-ironic | grep -i "deploy_kernel\|deploy_ramdisk"

# Common errors:
# - "deploy_kernel not found"
# - "deploy_ramdisk not found"
# - "No deploy kernel available"
# - "No deploy ramdisk available"
```

## ✅ Solution 1: Configure Ironic to Download Images (Recommended)

Ironic can automatically download deploy kernel and ramdisk from upstream sources. Configure it:

### Step 1: Check Ironic Configuration

```bash
# Check Ironic ConfigMap
kubectl get configmap -n metal3-system | grep ironic

# Check Ironic configuration
kubectl get configmap ironic-config -n metal3-system -o yaml | grep -i "deploy\|kernel\|ramdisk"
```

### Step 2: Update Ironic Configuration

```bash
# Edit Ironic ConfigMap
kubectl edit configmap ironic-config -n metal3-system

# Add or update these settings:
```

**Add to Ironic ConfigMap:**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ironic-config
  namespace: metal3-system
data:
  ironic.conf: |
    [deploy]
    # Deploy kernel and ramdisk download URLs
    default_boot_interface = ipxe
    default_deploy_interface = direct
    
    [pxe]
    # iPXE boot configuration
    ipxe_boot_script = /etc/ironic/ipxe_boot_script
    
    [image_download_source]
    # Where to download deploy images from
    deploy_kernel = http://tarballs.openstack.org/ironic-python-agent/dib/files/ipa-centos8-stable-wallaby.kernel
    deploy_ramdisk = http://tarballs.openstack.org/ironic-python-agent/dib/files/ipa-centos8-stable-wallaby.initramfs
```

**However, the better approach is to use Ironic's built-in image service.**

### Step 3: Use Ironic Image Service (Better Approach)

Ironic should automatically use its image service. Check if it's configured:

```bash
# Check Ironic deployment
kubectl get deployment -n metal3-system | grep ironic

# Check Ironic pod environment variables
kubectl get pod -n metal3-system -l app.kubernetes.io/name=metal3-ironic -o yaml | \
  grep -i "deploy\|kernel\|ramdisk\|image"
```

**Ironic should automatically download images from:**
- `http://tarballs.openstack.org/ironic-python-agent/`
- Or configured image service URLs

## ✅ Solution 2: Manually Download and Serve Images

If automatic download isn't working, manually download and serve the images:

### Step 1: Download Deploy Images

```bash
# On a machine with internet access
# Download deploy kernel and ramdisk

# Option 1: Download from OpenStack tarballs
wget http://tarballs.openstack.org/ironic-python-agent/dib/files/ipa-centos8-stable-wallaby.kernel
wget http://tarballs.openstack.org/ironic-python-agent/dib/files/ipa-centos8-stable-wallaby.initramfs

# Option 2: Download from Metal3 releases
# Check: https://github.com/metal3-io/ironic-image/releases
# Or use latest stable:
wget https://github.com/metal3-io/ironic-image/releases/download/v1.2.0/ironic-python-agent.kernel
wget https://github.com/metal3-io/ironic-image/releases/download/v1.2.0/ironic-python-agent.initramfs
```

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

```bash
# Update Ironic ConfigMap
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

# Download from Metal3 releases (recommended)
wget https://github.com/metal3-io/ironic-image/releases/download/v1.2.0/ironic-python-agent.kernel
wget https://github.com/metal3-io/ironic-image/releases/download/v1.2.0/ironic-python-agent.initramfs

# Or from OpenStack tarballs
# wget http://tarballs.openstack.org/ironic-python-agent/dib/files/ipa-centos8-stable-wallaby.kernel
# wget http://tarballs.openstack.org/ironic-python-agent/dib/files/ipa-centos8-stable-wallaby.initramfs
```

### Step 2: Copy to Image Server

```bash
# On OpenStack VM
sudo mkdir -p /opt/metal3-dev-env/ironic/html/images/deploy

# Copy images (from your download machine)
scp /tmp/deploy-images/ironic-python-agent.kernel ubuntu@${VM_IP}:/opt/metal3-dev-env/ironic/html/images/deploy/deploy_kernel
scp /tmp/deploy-images/ironic-python-agent.initramfs ubuntu@${VM_IP}:/opt/metal3-dev-env/ironic/html/images/deploy/deploy_ramdisk

# Or if already on VM, just move them
sudo mv /tmp/deploy-images/ironic-python-agent.kernel /opt/metal3-dev-env/ironic/html/images/deploy/deploy_kernel
sudo mv /tmp/deploy-images/ironic-python-agent.initramfs /opt/metal3-dev-env/ironic/html/images/deploy/deploy_ramdisk
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

## 📝 Summary

**To fix missing deploy_kernel and deploy_ramdisk:**

1. **First try**: Restart Ironic (may auto-download)
   ```bash
   kubectl rollout restart deployment -n metal3-system -l app.kubernetes.io/name=metal3-ironic
   ```

2. **If that doesn't work**: Manually download and serve images
   - Download from Metal3 releases or OpenStack tarballs
   - Serve via HTTP server
   - Configure Ironic to use the URLs

3. **Verify**: Check Ironic logs for successful image download

**Key Points:**
- ✅ Ironic needs deploy kernel and ramdisk to provision nodes
- ✅ These are typically downloaded automatically
- ✅ If missing, download manually and serve via HTTP
- ✅ Configure Ironic ConfigMap to point to the image URLs
- ✅ Restart Ironic after configuration changes

**Most Common Fix**: Restart Ironic - it often just needs to retry downloading the images.

