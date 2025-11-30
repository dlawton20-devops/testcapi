# Configuring Metal3 to Use Custom IPA Ramdisk

This guide shows how to configure Metal3 in Kubernetes to use your custom IPA ramdisk built with `focal-raw` (Ubuntu 20.04).

## Prerequisites

- Custom IPA ramdisk built: `ipa-ramdisk.initramfs` and `ipa-ramdisk.kernel`
- Metal3 installed in Kubernetes cluster
- Web server accessible by Metal3/Ironic (to serve the ramdisk files)

## Step 1: Make Ramdisk Files Accessible

The ramdisk and kernel files must be accessible via HTTP/HTTPS from Metal3/Ironic.

### Option A: Use Existing Web Server

If you have a web server (nginx, apache, etc.):

```bash
# Copy files to web server directory
sudo cp ~/ipa-build/ipa-ramdisk.initramfs /var/www/html/ipa/
sudo cp ~/ipa-build/ipa-ramdisk.kernel /var/www/html/ipa/
sudo chmod 644 /var/www/html/ipa/ipa-ramdisk.*

# Verify accessibility
curl -I http://your-server-ip/ipa/ipa-ramdisk.initramfs
curl -I http://your-server-ip/ipa/ipa-ramdisk.kernel
```

### Option B: Use Kubernetes Service (Recommended for Testing)

Create a simple HTTP server in Kubernetes to serve the files:

```bash
# Create a ConfigMap with the files (for small files)
# Note: ConfigMaps have size limits, so this may not work for large ramdisks

# Better: Use a PersistentVolume or hostPath
# Or use a simple nginx pod
```

### Option C: Use Metal3's Image Cache

If Metal3 has an image cache service, you can use it:

```bash
# Check if image cache exists
kubectl get svc -n metal3-system | grep image

# Upload files to image cache
# (method depends on your setup)
```

## Step 2: Configure Metal3 to Use Custom IPA

There are two methods to configure Metal3: via ConfigMap (quick) or via Helm values (persistent).

### Method 1: Update Ironic ConfigMap (Quick Method)

This method patches the existing ConfigMap:

```bash
# Set your web server URL
export IPA_SERVER="http://your-web-server-ip"
export RAMDISK_URL="${IPA_SERVER}/ipa/ipa-ramdisk.initramfs"
export KERNEL_URL="${IPA_SERVER}/ipa/ipa-ramdisk.kernel"

# Update Ironic ConfigMap
kubectl patch configmap ironic -n metal3-system --type merge -p "{
  \"data\": {
    \"IRONIC_RAMDISK_URL\": \"${RAMDISK_URL}\",
    \"IRONIC_KERNEL_URL\": \"${KERNEL_URL}\"
  }
}"

# Verify the update
kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_RAMDISK_URL}'
kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_KERNEL_URL}'

# Restart Ironic pods to apply changes
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic

# Wait for pods to restart
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=ironic -n metal3-system --timeout=5m
```

### Method 2: Use Helm Values (Persistent Method)

This method uses Helm values, which persist across upgrades:

#### Option A: Helm Upgrade with --set

```bash
# Set your web server URL
export IPA_SERVER="http://your-web-server-ip"
export RAMDISK_URL="${IPA_SERVER}/ipa/ipa-ramdisk.initramfs"
export KERNEL_URL="${IPA_SERVER}/ipa/ipa-ramdisk.kernel"

# Upgrade Metal3 with custom IPA URLs
helm upgrade metal3 oci://registry.suse.com/edge/charts/metal3 \
  --namespace metal3-system \
  --reuse-values \
  --set ironic.config.IRONIC_RAMDISK_URL="${RAMDISK_URL}" \
  --set ironic.config.IRONIC_KERNEL_URL="${KERNEL_URL}"

# Restart Ironic pods
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
```

#### Option B: Create/Update values.yaml

Create or update your `metal3-values.yaml`:

```yaml
global:
  ironicIP: "172.18.255.200"  # Your Ironic IP
  ironicKernelParams: "console=ttyS0"

ironic:
  service:
    type: LoadBalancer
    loadBalancerIP: "172.18.255.200"
  
  # Custom IPA ramdisk URLs
  config:
    IRONIC_RAMDISK_URL: "http://your-web-server-ip/ipa/ipa-ramdisk.initramfs"
    IRONIC_KERNEL_URL: "http://your-web-server-ip/ipa/ipa-ramdisk.kernel"
    
    # Other Ironic settings
    IPA_INSECURE: "1"
    IRONIC_EXTERNAL_HTTP_URL: "https://your-ironic-external-ip:6385"
```

Then upgrade:

```bash
helm upgrade metal3 oci://registry.suse.com/edge/charts/metal3 \
  --namespace metal3-system \
  --values metal3-values.yaml

# Restart Ironic pods
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
```

## Step 3: Verify Configuration

### Check ConfigMap

```bash
# View the full ConfigMap
kubectl get configmap ironic -n metal3-system -o yaml | grep -A 2 -B 2 RAMDISK

# Or get specific values
kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_RAMDISK_URL}'
echo ""
kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_KERNEL_URL}'
echo ""
```

### Check Ironic Pod Logs

```bash
# Get Ironic pod name
IRONIC_POD=$(kubectl get pod -n metal3-system -l app.kubernetes.io/component=ironic -o jsonpath='{.items[0].metadata.name}')

# Check logs for IPA download
kubectl logs -n metal3-system $IRONIC_POD | grep -i "ramdisk\|kernel\|ipa"

# Follow logs in real-time
kubectl logs -n metal3-system -f $IRONIC_POD | grep -i "ramdisk\|kernel"
```

### Test IPA Download

From within the cluster or a pod that can reach Ironic:

```bash
# Get the ramdisk URL from ConfigMap
RAMDISK_URL=$(kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_RAMDISK_URL}')

# Test download (from a pod)
kubectl run test-download --image=curlimages/curl --rm -it --restart=Never -- \
  curl -I "$RAMDISK_URL"
```

## Step 4: Test with BareMetalHost

When you create or update a BareMetalHost, Ironic will use your custom IPA:

```bash
# Create or update a BareMetalHost
kubectl apply -f your-baremetalhost.yaml

# Watch the provisioning process
kubectl get bmh -n metal3-system -w

# Check Ironic node status
# (Ironic will download and use your custom IPA ramdisk)
```

## Troubleshooting

### Issue: Ironic Can't Download Ramdisk

**Symptoms**: Ironic logs show download errors or timeouts.

**Solutions**:
1. **Verify URL is accessible**:
   ```bash
   # From a pod in the cluster
   kubectl run test-curl --image=curlimages/curl --rm -it --restart=Never -- \
     curl -I "http://your-server-ip/ipa/ipa-ramdisk.initramfs"
   ```

2. **Check network connectivity**:
   - Ensure Ironic pods can reach your web server
   - Check firewall rules
   - Verify DNS resolution if using hostnames

3. **Use HTTPS if needed**:
   ```bash
   # Update URLs to use HTTPS
   kubectl patch configmap ironic -n metal3-system --type merge -p '{
     "data": {
       "IRONIC_RAMDISK_URL": "https://your-server/ipa/ipa-ramdisk.initramfs",
       "IRONIC_KERNEL_URL": "https://your-server/ipa/ipa-ramdisk.kernel"
     }
   }'
   ```

### Issue: ConfigMap Changes Not Applied

**Symptoms**: Changes to ConfigMap don't take effect.

**Solutions**:
1. **Restart Ironic pods**:
   ```bash
   kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
   ```

2. **Check if Helm is managing the ConfigMap**:
   ```bash
   # If Helm is managing it, use Helm to update
   helm upgrade metal3 ... --set ironic.config.IRONIC_RAMDISK_URL="..."
   ```

3. **Verify ConfigMap was updated**:
   ```bash
   kubectl get configmap ironic -n metal3-system -o yaml
   ```

### Issue: Wrong IPA Version Used

**Symptoms**: Ironic still uses default IPA instead of your custom one.

**Solutions**:
1. **Clear Ironic cache** (if using image cache):
   ```bash
   # Delete cached images
   kubectl exec -n metal3-system <ironic-pod> -- rm -rf /var/lib/ironic/httpboot/*
   ```

2. **Force BareMetalHost reprovisioning**:
   ```bash
   # Annotate BMH to force reprovision
   kubectl annotate bmh <bmh-name> -n metal3-system \
     baremetalhost.metal3.io/detached=""
   kubectl delete bmh <bmh-name> -n metal3-system
   # Recreate BMH
   ```

### Issue: Ramdisk Too Large for ConfigMap

**Symptoms**: Can't use ConfigMap to store ramdisk (size limit ~1MB).

**Solutions**:
1. **Use external web server** (recommended)
2. **Use PersistentVolume** with hostPath
3. **Use object storage** (S3, etc.) and configure Ironic to use it

## Complete Example Script

Here's a complete script to configure Metal3 with your custom IPA:

```bash
#!/bin/bash
set -euo pipefail

# Configuration
IPA_SERVER="${IPA_SERVER:-http://your-web-server-ip}"
RAMDISK_URL="${IPA_SERVER}/ipa/ipa-ramdisk.initramfs"
KERNEL_URL="${IPA_SERVER}/ipa/ipa-ramdisk.kernel"
NAMESPACE="metal3-system"

echo "Configuring Metal3 to use custom IPA ramdisk..."
echo "Ramdisk URL: $RAMDISK_URL"
echo "Kernel URL: $KERNEL_URL"

# Method 1: Update ConfigMap directly
echo ""
echo "Updating Ironic ConfigMap..."
kubectl patch configmap ironic -n "$NAMESPACE" --type merge -p "{
  \"data\": {
    \"IRONIC_RAMDISK_URL\": \"${RAMDISK_URL}\",
    \"IRONIC_KERNEL_URL\": \"${KERNEL_URL}\"
  }
}"

# Verify
echo ""
echo "Verifying configuration..."
kubectl get configmap ironic -n "$NAMESPACE" -o jsonpath='{.data.IRONIC_RAMDISK_URL}'
echo ""
kubectl get configmap ironic -n "$NAMESPACE" -o jsonpath='{.data.IRONIC_KERNEL_URL}'
echo ""

# Restart Ironic pods
echo ""
echo "Restarting Ironic pods..."
kubectl delete pod -n "$NAMESPACE" -l app.kubernetes.io/component=ironic

# Wait for pods to be ready
echo ""
echo "Waiting for Ironic pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=ironic -n "$NAMESPACE" --timeout=5m

echo ""
echo "Configuration complete!"
echo ""
echo "Next steps:"
echo "  1. Verify Ironic can download the ramdisk (check logs)"
echo "  2. Create/update BareMetalHost to test"
echo "  3. Monitor provisioning process"
```

## Using with Helm (Persistent Configuration)

For a persistent configuration that survives upgrades:

```bash
# Create values file
cat > metal3-custom-ipa-values.yaml <<EOF
ironic:
  config:
    IRONIC_RAMDISK_URL: "http://your-web-server-ip/ipa/ipa-ramdisk.initramfs"
    IRONIC_KERNEL_URL: "http://your-web-server-ip/ipa/ipa-ramdisk.kernel"
EOF

# Upgrade Metal3
helm upgrade metal3 oci://registry.suse.com/edge/charts/metal3 \
  --namespace metal3-system \
  --values metal3-custom-ipa-values.yaml \
  --reuse-values

# Restart Ironic
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
```

## Summary

1. ✅ **Make ramdisk accessible**: Copy files to web server
2. ✅ **Configure Metal3**: Update ConfigMap or Helm values
3. ✅ **Restart Ironic**: Apply changes
4. ✅ **Verify**: Check logs and test with BareMetalHost

Your custom IPA ramdisk (built with `focal-raw`) will now be used by Metal3 for all bare-metal provisioning!

