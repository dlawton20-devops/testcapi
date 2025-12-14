# IPA Connection Error Fix - Complete Guide

## Problem Statement

IPA (Ironic Python Agent) was failing to connect to Ironic with the following error in the virsh console:

```
HTTPSConnectionPool(host='172.18.255.200', port=6385): Max retries exceeded with url: / 
(Caused by ConnectTimeoutError(...))
```

## Root Causes Identified

1. **Certificate Verification Failure**: IPA was trying to verify Ironic's self-signed HTTPS certificate and rejecting it
2. **Wrong Ironic URL**: The boot ISO contained the LoadBalancer IP (`172.18.255.200`) which the VM couldn't reach from user-mode network (`10.0.2.x`)
3. **Network Configuration**: VM needed static IP configuration to reach Ironic via port forwarding
4. **Port Forwarding**: Ironic service wasn't accessible from the VM's network

## Complete Fix Summary

### Fix 1: Disable Certificate Verification (IPA_INSECURE)

**Problem**: Ironic uses self-signed certificates (generated automatically), and IPA was rejecting the connection because it couldn't verify the certificate.

**Solution**:
```bash
# Set IPA_INSECURE to 1 to accept self-signed certificates
kubectl patch configmap ironic -n metal3-system --type merge -p '{"data":{"IPA_INSECURE":"1"}}'

# Restart Ironic pod to apply changes
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
```

**What this does**: 
- Ironic already has a self-signed certificate (auto-generated)
- IPA was trying to verify it and failing
- Setting `IPA_INSECURE=1` tells IPA: "trust Ironic's self-signed certificate, don't verify it"
- This allows the HTTPS connection to proceed without certificate verification errors

**Important**: We did NOT add a certificate. We told IPA to accept Ironic's existing self-signed certificate.

---

### Fix 2: Configure Correct Ironic External URL

**Problem**: Boot ISO contained `172.18.255.200:6385` (LoadBalancer IP) which VM couldn't reach.

**Solution**:
```bash
# Set Ironic external URL to host IP accessible from VM
kubectl patch configmap ironic -n metal3-system --type merge -p '{"data":{"IRONIC_EXTERNAL_HTTP_URL":"https://192.168.1.242:6385"}}'

# Restart Ironic pod
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
```

**What this does**: 
- Changes the URL that Ironic advertises to IPA
- Uses the host's external IP (`192.168.1.242`) which is reachable via port forwarding
- Port `6385` is forwarded to Ironic's service port

**Note**: The boot ISO must be regenerated for this to take effect (happens automatically when BMH is reprovisioned).

---

### Fix 3: Set Up Port Forwarding

**Problem**: Ironic service is only accessible within the Kubernetes cluster, not from the VM.

**Solution**:
```bash
# Step 1: Forward Ironic service to localhost
kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6385:6185 > /tmp/ironic-port-forward.log 2>&1 &

# Step 2: Forward from host IP to localhost (so VM can reach it)
socat TCP-LISTEN:6385,fork,reuseaddr TCP:localhost:6385 > /tmp/socat-ironic.log 2>&1 &
```

**What this does**:
- `kubectl port-forward`: Exposes Ironic service on `localhost:6385`
- `socat`: Forwards traffic from `192.168.1.242:6385` (host IP) to `localhost:6385`
- VM can now reach Ironic at `192.168.1.242:6385` via the gateway (`10.0.2.2`)

**Keep these running**: These processes must stay running for IPA to connect. Use `nohup` or run in background.

---

### Fix 4: Configure Static IP Network (NetworkData)

**Problem**: VM needed static IP configuration to reach Ironic, matching lab setup.

**Solution**:
```bash
# Create/update NetworkData secret
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: provisioning-networkdata
  namespace: metal3-system
type: Opaque
stringData:
  networkData: |
    version: 2
    ethernets:
      eth0:
        dhcp4: false
        addresses:
          - 10.0.2.100/24
        gateway4: 10.0.2.2
        nameservers:
          addresses:
            - 8.8.8.8
            - 8.8.4.4
EOF

# Reference it in BareMetalHost
# Add to baremetalhost.yaml:
# spec:
#   preprovisioningNetworkDataName: "provisioning-networkdata"
```

**What this does**:
- Provides network configuration to IPA when it boots
- Sets static IP `10.0.2.100/24` (matches user-mode network)
- Gateway `10.0.2.2` is the host, allowing VM to reach Ironic via port forwarding
- Applied automatically when IPA boots from virtual media ISO

---

### Fix 5: Enable SSH Access to IPA (Debugging - Optional)

**Problem**: Needed to access IPA console to debug network issues.

**Note**: This fix is for debugging/access purposes only. It did NOT fix the connection issue itself.

**Solution**:
```bash
# Generate SSH key for IPA root access
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_ipa -N "" -C "ipa-root-access"

# Add SSH key to Ironic configmap
SSH_KEY=$(cat ~/.ssh/id_rsa_ipa.pub)
kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_RAMDISK_SSH_KEY\":\"$SSH_KEY\"}}"

# Enable autologin for console access
CURRENT_PARAMS=$(kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_KERNEL_PARAMS}')
NEW_PARAMS="$CURRENT_PARAMS suse.autologin=ttyS0"
kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_KERNEL_PARAMS\":\"$NEW_PARAMS\"}}"

# Restart Ironic pod
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
```

**What this does**:
- Injects SSH public key into IPA ramdisk
- Enables automatic login on serial console
- Allows SSH access: `ssh -i ~/.ssh/id_rsa_ipa root@10.0.2.100`
- Allows console access: `virsh console metal3-node-0`

**Reference**: [SUSE Edge Documentation - Troubleshooting Directed-network provisioning](https://documentation.suse.com/suse-edge/3.3/html/edge/troubleshooting-directed-network-provisioning.html)

---

## Complete Configuration State

### Ironic ConfigMap Settings

```bash
# View current configuration
kubectl get configmap ironic -n metal3-system -o yaml | grep -E "(IPA_INSECURE|IRONIC_EXTERNAL_HTTP_URL|IRONIC_RAMDISK_SSH_KEY|IRONIC_KERNEL_PARAMS)"
```

**Expected values**:
- `IPA_INSECURE: "1"` - Accepts self-signed certificates
- `IRONIC_EXTERNAL_HTTP_URL: "https://192.168.1.242:6385"` - Accessible from VM
- `IRONIC_RAMDISK_SSH_KEY: "<your-ssh-public-key>"` - SSH access to IPA
- `IRONIC_KERNEL_PARAMS: "console=ttyS0 tls.enabled=true suse.autologin=ttyS0"` - Console autologin

### Network Configuration

**Base OS (Ubuntu)** - via cloud-init:
- Static IP: `10.0.2.100/24`
- Gateway: `10.0.2.2`
- Configured in: `create-baremetal-host.sh` (cloud-init user-data)

**IPA (Ironic Python Agent)** - via NetworkData Secret:
- Static IP: `10.0.2.100/24`
- Gateway: `10.0.2.2`
- Secret: `provisioning-networkdata`
- Applied via: `preprovisioningNetworkDataName` in BareMetalHost

### Port Forwarding

**Required processes** (must stay running):
```bash
# Check if running
ps aux | grep "kubectl port-forward.*metal3-metal3-ironic"
ps aux | grep "socat.*6385"

# Start if not running
kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6385:6185 &
socat TCP-LISTEN:6385,fork,reuseaddr TCP:localhost:6385 &
```

---

## Verification Steps

### 1. Verify Ironic Configuration
```bash
kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IPA_INSECURE}'
kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_EXTERNAL_HTTP_URL}'
```

### 2. Verify Port Forwarding
```bash
# Test Ironic accessibility
curl -k https://localhost:6385/
curl -k https://192.168.1.242:6385/
```

### 3. Verify NetworkData Secret
```bash
kubectl get secret provisioning-networkdata -n metal3-system -o jsonpath='{.data.networkData}' | base64 -d
```

### 4. Verify BareMetalHost Configuration
```bash
kubectl get baremetalhost metal3-node-0 -n metal3-system -o yaml | grep -A 2 preprovisioningNetworkDataName
```

### 5. Test IPA Connection (when IPA boots)
```bash
# SSH into IPA
ssh -i ~/.ssh/id_rsa_ipa root@10.0.2.100

# Or use serial console
virsh console metal3-node-0

# From inside IPA, test Ironic connection
curl -k https://192.168.1.242:6385/
```

---

## Troubleshooting

### IPA Still Can't Connect

1. **Check port forwarding is running**:
   ```bash
   ps aux | grep -E "(kubectl port-forward|socat.*6385)"
   ```

2. **Check Ironic pod is running**:
   ```bash
   kubectl get pods -n metal3-system -l app.kubernetes.io/component=ironic
   ```

3. **Check boot ISO was regenerated**:
   ```bash
   # Annotate BMH to trigger reprovisioning
   kubectl annotate baremetalhost metal3-node-0 -n metal3-system --overwrite inspect.metal3.io=''
   kubectl annotate baremetalhost metal3-node-0 -n metal3-system --overwrite provision.metal3.io=''
   ```

4. **Check VM network**:
   ```bash
   virsh domifaddr metal3-node-0
   # Should show 10.0.2.100
   ```

5. **Check IPA logs** (via console or SSH):
   ```bash
   virsh console metal3-node-0
   # Look for connection errors
   ```

### Certificate Errors

If you see certificate errors:
```bash
# Verify IPA_INSECURE is set
kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IPA_INSECURE}'
# Should output: 1
```

### Connection Timeout

If connection times out:
1. Verify port forwarding is running
2. Verify Ironic URL is correct (`192.168.1.242:6385`)
3. Verify VM can reach gateway (`ping 10.0.2.2`)
4. Verify boot ISO was regenerated after URL change

---

## Files Modified

1. **Ironic ConfigMap** (`ironic` in `metal3-system` namespace):
   - `IPA_INSECURE: "1"`
   - `IRONIC_EXTERNAL_HTTP_URL: "https://192.168.1.242:6385"`
   - `IRONIC_RAMDISK_SSH_KEY: "<ssh-key>"`
   - `IRONIC_KERNEL_PARAMS: "... suse.autologin=ttyS0"`

2. **NetworkData Secret** (`provisioning-networkdata` in `metal3-system` namespace):
   - Static IP configuration for IPA

3. **BareMetalHost** (`metal3-node-0` in `metal3-system` namespace):
   - `preprovisioningNetworkDataName: "provisioning-networkdata"`

4. **VM Creation Script** (`create-baremetal-host.sh`):
   - Updated cloud-init to use static IP `10.0.2.100/24`

---

## References

- [SUSE Edge - Troubleshooting Directed-network provisioning](https://documentation.suse.com/suse-edge/3.3/html/edge/troubleshooting-directed-network-provisioning.html)
- [Metal3 Documentation](https://metal3.io/documentation/)

---

## Quick Reference Commands

```bash
# Apply all fixes at once
kubectl patch configmap ironic -n metal3-system --type merge -p '{"data":{"IPA_INSECURE":"1","IRONIC_EXTERNAL_HTTP_URL":"https://192.168.1.242:6385"}}'
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic

# Start port forwarding
kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6385:6185 &
socat TCP-LISTEN:6385,fork,reuseaddr TCP:localhost:6385 &

# Access IPA
ssh -i ~/.ssh/id_rsa_ipa root@10.0.2.100
# or
virsh console metal3-node-0
```

