# IPA SSH Access Setup - Complete Guide

## Overview

SSH access to IPA (Ironic Python Agent) allows you to debug network issues, check configuration, and troubleshoot provisioning problems. This was configured using the SUSE Edge documentation method.

**Reference**: [SUSE Edge - Troubleshooting Directed-network provisioning](https://documentation.suse.com/suse-edge/3.3/html/edge/troubleshooting-directed-network-provisioning.html)

---

## How It Works

When IPA boots from the virtual media ISO, Ironic injects the SSH public key into the IPA ramdisk. This allows root login via SSH without a password (using the private key).

---

## Step-by-Step Setup

### Step 1: Generate SSH Key Pair

**Command:**
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_ipa -N "" -C "ipa-root-access"
```

**What this does:**
- Generates a new RSA key pair (4096 bits)
- Private key: `~/.ssh/id_rsa_ipa`
- Public key: `~/.ssh/id_rsa_ipa.pub`
- No passphrase (`-N ""`)
- Comment: "ipa-root-access"

**Output:**
```
Generating public/private rsa key pair.
Your identification has been saved in /Users/dave/.ssh/id_rsa_ipa
Your public key has been saved in /Users/dave/.ssh/id_rsa_ipa.pub
```

---

### Step 2: Add SSH Public Key to Ironic ConfigMap

**Command:**
```bash
SSH_KEY=$(cat ~/.ssh/id_rsa_ipa.pub)
kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_RAMDISK_SSH_KEY\":\"$SSH_KEY\"}}"
```

**What this does:**
- Reads the public key from `~/.ssh/id_rsa_ipa.pub`
- Adds it to Ironic ConfigMap as `IRONIC_RAMDISK_SSH_KEY`
- Ironic will inject this key into IPA ramdisk when generating boot ISO

**Alternative method** (if you prefer to edit directly):
```bash
kubectl edit configmap ironic -n metal3-system
# Add: IRONIC_RAMDISK_SSH_KEY: "<your-ssh-public-key>"
```

---

### Step 3: Enable Autologin (Optional - for Console Access)

**Option A: Via Helm Values (Recommended)**

If installing/upgrading Metal3 via Helm:

```bash
# During install
helm install metal3 oci://registry.suse.com/edge/charts/metal3 \
  --namespace metal3-system \
  --create-namespace \
  --set global.ironicKernelParams="console=ttyS0 suse.autologin=ttyS0" \
  ...

# Or upgrade existing installation
helm upgrade metal3 oci://registry.suse.com/edge/charts/metal3 \
  --namespace metal3-system \
  --reuse-values \
  --set global.ironicKernelParams="console=ttyS0 suse.autologin=ttyS0"
```

**Option B: Patch ConfigMap (After Install)**

If Metal3 is already installed and you want to add it:

```bash
CURRENT_PARAMS=$(kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_KERNEL_PARAMS}')
NEW_PARAMS="$CURRENT_PARAMS suse.autologin=ttyS0"
kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_KERNEL_PARAMS\":\"$NEW_PARAMS\"}}"
```

**What this does:**
- Adds `suse.autologin=ttyS0` to kernel parameters
- Enables automatic login on serial console (ttyS0)
- Useful for console access: `virsh console metal3-node-0`

**Warning**: This is for debugging only and gives full access to the host.

**See**: `METAL3_HELM_VALUES_CONFIG.md` for complete Helm values configuration guide.

---

### Step 4: Restart Ironic Pod

**Command:**
```bash
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
```

**What this does:**
- Restarts Ironic pod to pick up the new configuration
- New boot ISOs will include the SSH key
- Existing boot ISOs won't have the key (need to regenerate)

---

## How It Works Internally

### Boot ISO Generation

When Metal3 generates a boot ISO for IPA:

1. Ironic reads `IRONIC_RAMDISK_SSH_KEY` from ConfigMap
2. Injects the SSH public key into the IPA ramdisk
3. Places it in `/root/.ssh/authorized_keys` in the ramdisk
4. Boot ISO is generated with this configuration

### When IPA Boots

1. IPA ramdisk boots from virtual media ISO
2. SSH public key is already in `/root/.ssh/authorized_keys`
3. Root user can login via SSH using the private key
4. No password required (key-based authentication)

---

## Usage

### SSH Access

**Command:**
```bash
ssh -i ~/.ssh/id_rsa_ipa root@10.0.2.100
```

**What you can do:**
- Check network configuration: `ip addr show`, `ip route show`
- Test Ironic connection: `curl -k https://192.168.1.242:6385/`
- Check IPA logs: `journalctl -u ironic-python-agent`
- Debug network issues
- Verify NetworkData was applied correctly

### Serial Console Access

**Command:**
```bash
virsh console metal3-node-0
```

**What this does:**
- Connects to VM's serial console
- With autologin enabled, you're automatically logged in as root
- No password required
- Useful when SSH isn't available

---

## Verification

### Check SSH Key is Configured

```bash
# Check ConfigMap has the key
kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_RAMDISK_SSH_KEY}'

# Should output your SSH public key
```

### Check Autologin is Enabled

```bash
# Check kernel parameters
kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_KERNEL_PARAMS}'

# Should include: suse.autologin=ttyS0
```

### Test SSH Access (when IPA boots)

```bash
# Try SSH connection
ssh -i ~/.ssh/id_rsa_ipa root@10.0.2.100

# If connection succeeds, you're in!
# Check authorized_keys
cat /root/.ssh/authorized_keys
```

---

## Troubleshooting

### SSH Connection Refused

**Possible causes:**
1. IPA hasn't booted yet (wait for virtual media boot)
2. Network not configured (check NetworkData)
3. SSH service not running in IPA

**Solution:**
- Check VM is booting: `virsh console metal3-node-0`
- Wait for IPA to fully boot
- Verify network: `ip addr show` (should show 10.0.2.100)

### SSH Key Not Working

**Possible causes:**
1. Boot ISO was generated before SSH key was added
2. Ironic pod wasn't restarted after adding key
3. Wrong private key used

**Solution:**
```bash
# Regenerate boot ISO by annotating BMH
kubectl annotate baremetalhost metal3-node-0 -n metal3-system --overwrite inspect.metal3.io=''
kubectl annotate baremetalhost metal3-node-0 -n metal3-system --overwrite provision.metal3.io=''

# Restart Ironic pod
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic

# Verify key is in ConfigMap
kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_RAMDISK_SSH_KEY}'
```

### Autologin Not Working

**Possible causes:**
1. Wrong console device (not ttyS0)
2. Kernel parameters not applied
3. Ironic pod not restarted

**Solution:**
```bash
# Check what console IPA is using
virsh console metal3-node-0
# Look for console name in boot messages

# Update kernel params if needed (e.g., tty1 instead of ttyS0)
kubectl edit configmap ironic -n metal3-system
# Change: suse.autologin=ttyS0 to suse.autologin=tty1 (or appropriate console)

# Restart Ironic pod
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
```

---

## Security Considerations

⚠️ **Warning**: SSH access to IPA gives full root access to the host being provisioned.

**Best practices:**
1. Only use for debugging/troubleshooting
2. Remove SSH key after debugging (set `IRONIC_RAMDISK_SSH_KEY: ""`)
3. Don't use in production without proper security measures
4. Use strong key (4096 bits minimum)
5. Keep private key secure (`~/.ssh/id_rsa_ipa`)

**Remove SSH access:**
```bash
# Remove SSH key from ConfigMap
kubectl patch configmap ironic -n metal3-system --type merge -p '{"data":{"IRONIC_RAMDISK_SSH_KEY":""}}'

# Remove autologin
CURRENT_PARAMS=$(kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_KERNEL_PARAMS}')
NEW_PARAMS=$(echo "$CURRENT_PARAMS" | sed 's/ suse.autologin=ttyS0//')
kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_KERNEL_PARAMS\":\"$NEW_PARAMS\"}}"

# Restart Ironic pod
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
```

---

## Complete Setup Script

Here's a complete script to set up SSH access:

```bash
#!/bin/bash
set -e

echo "🔑 Setting up SSH access to IPA..."

# Step 1: Generate SSH key (if not exists)
if [ ! -f ~/.ssh/id_rsa_ipa ]; then
    echo "Generating SSH key pair..."
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_ipa -N "" -C "ipa-root-access"
    echo "✅ SSH key generated"
else
    echo "✅ SSH key already exists"
fi

# Step 2: Add SSH key to Ironic ConfigMap
echo "Adding SSH key to Ironic ConfigMap..."
SSH_KEY=$(cat ~/.ssh/id_rsa_ipa.pub)
kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_RAMDISK_SSH_KEY\":\"$SSH_KEY\"}}"
echo "✅ SSH key added to ConfigMap"

# Step 3: Enable autologin
echo "Enabling autologin..."
CURRENT_PARAMS=$(kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_KERNEL_PARAMS}')
if [[ ! "$CURRENT_PARAMS" =~ "suse.autologin=ttyS0" ]]; then
    NEW_PARAMS="$CURRENT_PARAMS suse.autologin=ttyS0"
    kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_KERNEL_PARAMS\":\"$NEW_PARAMS\"}}"
    echo "✅ Autologin enabled"
else
    echo "✅ Autologin already enabled"
fi

# Step 4: Restart Ironic pod
echo "Restarting Ironic pod..."
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
echo "✅ Ironic pod restarted"

echo ""
echo "✅ SSH access configured!"
echo ""
echo "To access IPA when it boots:"
echo "  ssh -i ~/.ssh/id_rsa_ipa root@10.0.2.100"
echo ""
echo "Or use serial console:"
echo "  virsh console metal3-node-0"
```

---

## Summary

**What was done:**
1. ✅ Generated SSH key pair (`~/.ssh/id_rsa_ipa`)
2. ✅ Added public key to Ironic ConfigMap (`IRONIC_RAMDISK_SSH_KEY`)
3. ✅ Enabled autologin (`suse.autologin=ttyS0` in kernel params)
4. ✅ Restarted Ironic pod to apply changes

**How it works:**
- Ironic injects SSH public key into IPA ramdisk when generating boot ISO
- When IPA boots, root can login via SSH using the private key
- Autologin enables automatic console access

**Usage:**
- SSH: `ssh -i ~/.ssh/id_rsa_ipa root@10.0.2.100`
- Console: `virsh console metal3-node-0`

**Reference**: Based on [SUSE Edge Documentation](https://documentation.suse.com/suse-edge/3.3/html/edge/troubleshooting-directed-network-provisioning.html)


