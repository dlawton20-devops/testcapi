# Configuring Metal3 via Helm Chart Values

## Overview

Instead of patching ConfigMaps after installation, you can configure Metal3 settings directly in the Helm chart values. This is cleaner and persists across upgrades.

## Kernel Parameters Configuration

### Current Setup (Patching After Install)

Currently, kernel parameters are set during install and then patched:

```bash
# During install
helm install metal3 oci://registry.suse.com/edge/charts/metal3 \
  --set global.ironicKernelParams="console=ttyS0" \
  ...

# Then patched later
CURRENT_PARAMS=$(kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_KERNEL_PARAMS}')
NEW_PARAMS="$CURRENT_PARAMS suse.autologin=ttyS0"
kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_KERNEL_PARAMS\":\"$NEW_PARAMS\"}}"
```

### Better Approach: Set in Helm Values

## Method 1: Helm Install with --set (One-time Install)

### Install with Autologin Enabled

```bash
helm install metal3 oci://registry.suse.com/edge/charts/metal3 \
  --namespace metal3-system \
  --create-namespace \
  --set global.ironicIP="172.18.255.200" \
  --set global.ironicKernelParams="console=ttyS0 suse.autologin=ttyS0" \
  --set ironic.service.type=LoadBalancer \
  --set ironic.service.loadBalancerIP="172.18.255.200"
```

### Install with SSH Key and Autologin

```bash
# Generate SSH key first (if not exists)
if [ ! -f ~/.ssh/id_rsa_ipa ]; then
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_ipa -N "" -C "ipa-root-access"
fi

SSH_KEY=$(cat ~/.ssh/id_rsa_ipa.pub)

helm install metal3 oci://registry.suse.com/edge/charts/metal3 \
  --namespace metal3-system \
  --create-namespace \
  --set global.ironicIP="172.18.255.200" \
  --set global.ironicKernelParams="console=ttyS0 suse.autologin=ttyS0" \
  --set ironic.ramdisk.sshKey="$SSH_KEY" \
  --set ironic.service.type=LoadBalancer \
  --set ironic.service.loadBalancerIP="172.18.255.200"
```

## Method 2: Using values.yaml File (Recommended)

### Create values.yaml

Create a `metal3-values.yaml` file:

```yaml
global:
  ironicIP: "172.18.255.200"
  ironicKernelParams: "console=ttyS0 suse.autologin=ttyS0"

ironic:
  service:
    type: LoadBalancer
    loadBalancerIP: "172.18.255.200"
  
  # SSH key for IPA access (optional)
  ramdisk:
    sshKey: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDrg87hmf/Xv1p7X87Nq6sj0p7F4NSYMdt39ZyNte4k9ZOGPqbzCkOSNl+YyT2vxRGcKm3JGcX++LNgIbXQdHuc8Y9ajEJ2UODuI9WaD0v6rgAgFAmnrMGNp3ddErcU1nK/SFLIryWJY7ouU2U7BBuocIWTQAO0XPAqf34Ae0A9mVPqujyDnTplJKSmbf5+UKXVVh6HUMG/zLIUWNvyOxIVjFCwWwWuyPs2GVXzUpAP77YGCvDiri8h27OaIcpaxKwTEyIMTCKMhAbP+n9FL4fzvr9fuLoEzAperZcSUkCmW37TQdvMzv5x5glGsLtn16ng0Iep9ZrkLsw/MCZXCrLvxOkQtatthCpLS9fUh5vvpx+sDLJkSvX+9xLnDovZlTnbC4ISI55dEV9IV3d9gTMYT72YuShhafU8R3Aj9KOlTuiR33M8cdEr6bNSKOL4jYuad5GIFCARFsZkSWCUeWBbTjite1LTo9RULLnT911CrIFPPWBRNH2PWcDmS4fFUdiTVkFjon2f3BHBTwf+LzfI8H99B6f0JOdD65zuuERXOOzbXjIW0M8RhA7zJhOTT94LJRdgLL/kmILpiYU0mDp/Ca9401IzN2f4oKjkKvXECtfSoVT6tIAD0yTBCE2zZg4bO3ODu7P7fDkCpUxhom3OwJdGgG6Pd8ulsfJ1ssG/gw== ipa-root-access"

  # Additional Ironic configuration
  config:
    IPA_INSECURE: "1"
    IRONIC_EXTERNAL_HTTP_URL: "https://192.168.1.242:6385"
```

### Install with values.yaml

```bash
helm install metal3 oci://registry.suse.com/edge/charts/metal3 \
  --namespace metal3-system \
  --create-namespace \
  --values metal3-values.yaml
```

## Method 3: Update Existing Installation

### Upgrade with New Values

If Metal3 is already installed, you can upgrade it with new values:

```bash
# Option A: Using --set
helm upgrade metal3 oci://registry.suse.com/edge/charts/metal3 \
  --namespace metal3-system \
  --reuse-values \
  --set global.ironicKernelParams="console=ttyS0 suse.autologin=ttyS0"

# Option B: Using values.yaml
helm upgrade metal3 oci://registry.suse.com/edge/charts/metal3 \
  --namespace metal3-system \
  --values metal3-values.yaml
```

### Check Current Values

```bash
# See what values are currently set
helm get values metal3 -n metal3-system

# See all values (including defaults)
helm get values metal3 -n metal3-system --all
```

## Complete Configuration Example

### Full values.yaml with All Common Settings

```yaml
global:
  ironicIP: "172.18.255.200"
  ironicKernelParams: "console=ttyS0 suse.autologin=ttyS0"

ironic:
  service:
    type: LoadBalancer
    loadBalancerIP: "172.18.255.200"
  
  # SSH key for IPA access
  ramdisk:
    sshKey: "ssh-rsa YOUR_PUBLIC_KEY_HERE"
  
  # Ironic configuration
  config:
    # Accept self-signed certificates
    IPA_INSECURE: "1"
    
    # External URL reachable from VMs
    IRONIC_EXTERNAL_HTTP_URL: "https://192.168.1.242:6385"
    
    # Additional kernel parameters (if needed)
    # IRONIC_KERNEL_PARAMS: "console=ttyS0 suse.autologin=ttyS0"
    # Note: This is usually set via global.ironicKernelParams instead

# Baremetal operator configuration (if needed)
baremetalOperator:
  config:
    # Operator-specific settings
    IRONIC_ENDPOINT: "https://metal3-metal3-ironic.metal3-system.svc.cluster.local:6385/v1/"
    IRONIC_INSECURE: "true"
```

## Key Helm Values for Your Use Case

### To Enable Autologin (Remove it later)

**Install/Upgrade with autologin:**
```bash
helm install metal3 oci://registry.suse.com/edge/charts/metal3 \
  --namespace metal3-system \
  --create-namespace \
  --set global.ironicKernelParams="console=ttyS0 suse.autologin=ttyS0" \
  --set global.ironicIP="172.18.255.200" \
  --set ironic.service.type=LoadBalancer \
  --set ironic.service.loadBalancerIP="172.18.255.200"
```

**Remove autologin later:**
```bash
helm upgrade metal3 oci://registry.suse.com/edge/charts/metal3 \
  --namespace metal3-system \
  --reuse-values \
  --set global.ironicKernelParams="console=ttyS0"
```

## Available Helm Values

### Global Values

| Value | Description | Example |
|-------|-------------|---------|
| `global.ironicIP` | Static IP for Ironic | `"172.18.255.200"` |
| `global.ironicKernelParams` | Kernel parameters for IPA | `"console=ttyS0 suse.autologin=ttyS0"` |

### Ironic Values

| Value | Description | Example |
|-------|-------------|---------|
| `ironic.service.type` | Service type | `"LoadBalancer"` |
| `ironic.service.loadBalancerIP` | LoadBalancer IP | `"172.18.255.200"` |
| `ironic.ramdisk.sshKey` | SSH public key for IPA | `"ssh-rsa AAAAB3..."` |
| `ironic.config.IPA_INSECURE` | Accept self-signed certs | `"1"` |
| `ironic.config.IRONIC_EXTERNAL_HTTP_URL` | External Ironic URL | `"https://192.168.1.242:6385"` |

## Verification

### Check Values Are Applied

```bash
# Check Helm values
helm get values metal3 -n metal3-system

# Check ConfigMap (should reflect Helm values)
kubectl get configmap ironic -n metal3-system -o yaml

# Verify kernel params
kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_KERNEL_PARAMS}'
# Should show: console=ttyS0 suse.autologin=ttyS0
```

### Test Autologin

```bash
# Access VM console
virsh console metal3-node-0

# Should automatically log in (no password prompt)
```

## Removing Autologin via Helm

### Method 1: Upgrade with New Values

```bash
helm upgrade metal3 oci://registry.suse.com/edge/charts/metal3 \
  --namespace metal3-system \
  --reuse-values \
  --set global.ironicKernelParams="console=ttyS0"
```

### Method 2: Update values.yaml and Upgrade

```yaml
# metal3-values.yaml
global:
  ironicKernelParams: "console=ttyS0"  # Removed suse.autologin=ttyS0
```

```bash
helm upgrade metal3 oci://registry.suse.com/edge/charts/metal3 \
  --namespace metal3-system \
  --values metal3-values.yaml
```

## Complete Example: Install with All Settings

```bash
#!/bin/bash

# Generate SSH key if needed
if [ ! -f ~/.ssh/id_rsa_ipa ]; then
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_ipa -N "" -C "ipa-root-access"
fi

SSH_KEY=$(cat ~/.ssh/id_rsa_ipa.pub)
IRONIC_IP="172.18.255.200"
EXTERNAL_URL="https://192.168.1.242:6385"

# Install Metal3 with all configurations
helm install metal3 oci://registry.suse.com/edge/charts/metal3 \
  --namespace metal3-system \
  --create-namespace \
  --set global.ironicIP="$IRONIC_IP" \
  --set global.ironicKernelParams="console=ttyS0 suse.autologin=ttyS0" \
  --set ironic.service.type=LoadBalancer \
  --set ironic.service.loadBalancerIP="$IRONIC_IP" \
  --set ironic.ramdisk.sshKey="$SSH_KEY" \
  --set ironic.config.IPA_INSECURE="1" \
  --set ironic.config.IRONIC_EXTERNAL_HTTP_URL="$EXTERNAL_URL" \
  --wait \
  --timeout 10m
```

## Troubleshooting

### Values Not Applied

**Check if Helm upgrade worked:**
```bash
helm get values metal3 -n metal3-system
```

**Check ConfigMap directly:**
```bash
kubectl get configmap ironic -n metal3-system -o yaml
```

**Restart Ironic pod if needed:**
```bash
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
```

### Conflicting Values

If you've patched the ConfigMap manually, Helm values might be overridden. To fix:

1. **Remove manual patches:**
   ```bash
   # Let Helm manage the ConfigMap
   kubectl annotate configmap ironic -n metal3-system \
     meta.helm.sh/release-name=metal3 \
     meta.helm.sh/release-namespace=metal3-system
   ```

2. **Upgrade with Helm:**
   ```bash
   helm upgrade metal3 oci://registry.suse.com/edge/charts/metal3 \
     --namespace metal3-system \
     --reuse-values \
     --set global.ironicKernelParams="console=ttyS0 suse.autologin=ttyS0"
   ```

## Best Practices

1. **Use values.yaml** for complex configurations
2. **Version control** your values.yaml file
3. **Document** why each setting is needed
4. **Test upgrades** in a non-production environment first
5. **Remove autologin** after debugging (security)

## Summary

**Instead of patching:**
```bash
kubectl patch configmap ironic -n metal3-system --type merge -p "..."
```

**Use Helm values:**
```bash
helm install/upgrade metal3 ... --set global.ironicKernelParams="console=ttyS0 suse.autologin=ttyS0"
```

This ensures:
- ✅ Configuration persists across upgrades
- ✅ Values are version-controlled
- ✅ Easier to manage and document
- ✅ No manual patching needed

