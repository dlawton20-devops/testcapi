# Kubernetes Changes - Complete Documentation

This document lists all Kubernetes resource changes made to fix the IPA connection issue and enable SSH access.

---

## Table of Contents

1. [Ironic ConfigMap Changes](#ironic-configmap-changes)
2. [NetworkData Secret](#networkdata-secret)
3. [BareMetalHost Configuration](#baremetalhost-configuration)
4. [BMC Secret](#bmc-secret)
5. [Summary of All Changes](#summary-of-all-changes)
6. [Commands to Apply All Changes](#commands-to-apply-all-changes)

---

## Ironic ConfigMap Changes

**Resource**: `ConfigMap/ironic` in namespace `metal3-system`

### Changes Made

#### 1. IPA_INSECURE

**Before:**
```yaml
IPA_INSECURE: "0"
```

**After:**
```yaml
IPA_INSECURE: "1"
```

**Command:**
```bash
kubectl patch configmap ironic -n metal3-system --type merge -p '{"data":{"IPA_INSECURE":"1"}}'
```

**Purpose**: Tells IPA to accept Ironic's self-signed certificate without verification.

**Why**: Ironic uses self-signed certificates, and IPA was rejecting the connection due to certificate verification failure.

---

#### 2. IRONIC_EXTERNAL_HTTP_URL

**Before:**
```yaml
IRONIC_EXTERNAL_HTTP_URL: "https://localhost:6185"
# or
IRONIC_EXTERNAL_HTTP_URL: "https://172.18.255.200:6385"
```

**After:**
```yaml
IRONIC_EXTERNAL_HTTP_URL: "https://192.168.1.242:6385"
```

**Command:**
```bash
kubectl patch configmap ironic -n metal3-system --type merge -p '{"data":{"IRONIC_EXTERNAL_HTTP_URL":"https://192.168.1.242:6385"}}'
```

**Purpose**: Sets the URL that Ironic advertises to IPA. This URL must be reachable from the VM.

**Why**: 
- The LoadBalancer IP (`172.18.255.200`) was not reachable from the VM's user-mode network
- Changed to host's external IP (`192.168.1.242`) which is accessible via port forwarding
- Port `6385` is forwarded to Ironic's service port `6185`

**Note**: Boot ISO must be regenerated for this to take effect (happens automatically when BMH is reprovisioned).

---

#### 3. IRONIC_RAMDISK_SSH_KEY

**Before:**
```yaml
# Not set (or empty)
```

**After:**
```yaml
IRONIC_RAMDISK_SSH_KEY: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDrg87hmf/Xv1p7X87Nq6sj0p7F4NSYMdt39ZyNte4k9ZOGPqbzCkOSNl+YyT2vxRGcKm3JGcX++LNgIbXQdHuc8Y9ajEJ2UODuI9WaD0v6rgAgFAmnrMGNp3ddErcU1nK/SFLIryWJY7ouU2U7BBuocIWTQAO0XPAqf34Ae0A9mVPqujyDnTplJKSmbf5+UKXVVh6HUMG/zLIUWNvyOxIVjFCwWwWuyPs2GVXzUpAP77YGCvDiri8h27OaIcpaxKwTEyIMTCKMhAbP+n9FL4fzvr9fuLoEzAperZcSUkCmW37TQdvMzv5x5glGsLtn16ng0Iep9ZrkLsw/MCZXCrLvxOkQtatthCpLS9fUh5vvpx+sDLJkSvX+9xLnDovZlTnbC4ISI55dEV9IV3d9gTMYT72YuShhafU8R3Aj9KOlTuiR33M8cdEr6bNSKOL4jYuad5GIFCARFsZkSWCUeWBbTjite1LTo9RULLnT911CrIFPPWBRNH2PWcDmS4fFUdiTVkFjon2f3BHBTwf+LzfI8H99B6f0JOdD65zuuERXOOzbXjIW0M8RhA7zJhOTT94LJRdgLL/kmILpiYU0mDp/Ca9401IzN2f4oKjkKvXECtfSoVT6tIAD0yTBCE2zZg4bO3ODu7P7fDkCpUxhom3OwJdGgG6Pd8ulsfJ1ssG/gw== ipa-root-access"
```

**Command:**
```bash
# First, generate SSH key (if not exists)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_ipa -N "" -C "ipa-root-access"

# Then add to ConfigMap
SSH_KEY=$(cat ~/.ssh/id_rsa_ipa.pub)
kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_RAMDISK_SSH_KEY\":\"$SSH_KEY\"}}"
```

**Purpose**: Injects SSH public key into IPA ramdisk, allowing root login via SSH.

**Why**: Enables debugging and troubleshooting of network issues from within IPA.

**Usage**: `ssh -i ~/.ssh/id_rsa_ipa root@10.0.2.100`

---

#### 4. IRONIC_KERNEL_PARAMS

**Before:**
```yaml
IRONIC_KERNEL_PARAMS: "console=ttyS0 tls.enabled=true"
```

**After:**
```yaml
IRONIC_KERNEL_PARAMS: "console=ttyS0 tls.enabled=true suse.autologin=ttyS0"
```

**Command:**
```bash
CURRENT_PARAMS=$(kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_KERNEL_PARAMS}')
NEW_PARAMS="$CURRENT_PARAMS suse.autologin=ttyS0"
kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_KERNEL_PARAMS\":\"$NEW_PARAMS\"}}"
```

**Purpose**: Enables automatic login on serial console (ttyS0).

**Why**: Makes console access easier for debugging (no password required).

**Usage**: `virsh console metal3-node-0` (automatically logged in)

**Warning**: For debugging only - gives full access to the host.

---

### Complete Ironic ConfigMap Patch

To apply all Ironic ConfigMap changes at once:

```bash
# Generate SSH key first (if not exists)
if [ ! -f ~/.ssh/id_rsa_ipa ]; then
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_ipa -N "" -C "ipa-root-access"
fi

# Get SSH public key
SSH_KEY=$(cat ~/.ssh/id_rsa_ipa.pub)

# Get current kernel params
CURRENT_PARAMS=$(kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_KERNEL_PARAMS}')

# Apply all changes
kubectl patch configmap ironic -n metal3-system --type merge -p "{
  \"data\": {
    \"IPA_INSECURE\": \"1\",
    \"IRONIC_EXTERNAL_HTTP_URL\": \"https://192.168.1.242:6385\",
    \"IRONIC_RAMDISK_SSH_KEY\": \"$SSH_KEY\",
    \"IRONIC_KERNEL_PARAMS\": \"$CURRENT_PARAMS suse.autologin=ttyS0\"
  }
}"

# Restart Ironic pod to apply changes
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
```

---

## NetworkData Secret

**Resource**: `Secret/provisioning-networkdata` in namespace `metal3-system`

### Configuration

**Created/Updated:**
```yaml
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
```

**Command:**
```bash
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
```

**Purpose**: Provides network configuration to IPA when it boots from virtual media ISO.

**Why**: 
- VM needs static IP to route through host gateway
- Matches lab setup (no DHCP requirement)
- Allows IPA to reach Ironic via `192.168.1.242:6385`

**How it works**:
- Referenced in BareMetalHost via `preprovisioningNetworkDataName`
- Metal3 injects this into the boot ISO
- IPA applies it when it boots

---

## BareMetalHost Configuration

**Resource**: `BareMetalHost/metal3-node-0` in namespace `metal3-system`

### Changes Made

#### preprovisioningNetworkDataName

**Before:**
```yaml
# Not set
```

**After:**
```yaml
spec:
  preprovisioningNetworkDataName: "provisioning-networkdata"
```

**Command:**
```bash
kubectl patch baremetalhost metal3-node-0 -n metal3-system --type merge -p '{"spec":{"preprovisioningNetworkDataName":"provisioning-networkdata"}}'
```

**Or via YAML:**
```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: metal3-node-0
  namespace: metal3-system
spec:
  preprovisioningNetworkDataName: "provisioning-networkdata"
  # ... other spec fields
```

**Purpose**: References the NetworkData Secret to provide network configuration to IPA.

**Why**: Allows IPA to have network connectivity immediately when it boots, enabling it to reach Ironic.

---

### Complete BareMetalHost Configuration

**File**: `baremetalhost.yaml`

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: metal3-node-0
  namespace: metal3-system
  annotations:
    inspect.metal3.io: "disabled"
spec:
  online: true
  bootMACAddress: "52:54:00:53:84:3d"  # MAC from VM
  bmc:
    address: "redfish-virtualmedia+http://192.168.1.242:8000/redfish/v1/Systems/721bcaa7-be3d-4d62-99a9-958bb212f2b7"
    credentialsName: metal3-node-0-bmc-secret
  bootMode: "UEFI"
  automatedCleaningMode: "disabled"
  preprovisioningNetworkDataName: "provisioning-networkdata"  # ← Added
  image:
    url: "https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"
    checksum: "https://cloud-images.ubuntu.com/focal/current/SHA256SUMS"
    checksumType: "auto"
---
apiVersion: v1
kind: Secret
metadata:
  name: metal3-node-0-bmc-secret
  namespace: metal3-system
type: Opaque
data:
  username: YWRtaW4=  # admin
  password: YWRtaW4=  # admin
```

**Command:**
```bash
kubectl apply -f baremetalhost.yaml
```

---

## BMC Secret

**Resource**: `Secret/metal3-node-0-bmc-secret` in namespace `metal3-system`

### Configuration

**Status**: Already existed, no changes needed.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: metal3-node-0-bmc-secret
  namespace: metal3-system
type: Opaque
data:
  username: YWRtaW4=  # admin (base64)
  password: YWRtaW4=  # admin (base64)
```

**Purpose**: Provides BMC credentials for Redfish API access.

**Used by**: BareMetalHost to communicate with sushy-tools (BMC emulator).

---

## Summary of All Changes

### ConfigMap Changes (ironic)

| Setting | Before | After | Purpose |
|---------|--------|-------|---------|
| `IPA_INSECURE` | `"0"` | `"1"` | Accept Ironic's self-signed certificate |
| `IRONIC_EXTERNAL_HTTP_URL` | `https://localhost:6185` or `https://172.18.255.200:6385` | `https://192.168.1.242:6385` | URL reachable from VM |
| `IRONIC_RAMDISK_SSH_KEY` | Not set | SSH public key | Enable SSH access to IPA |
| `IRONIC_KERNEL_PARAMS` | `console=ttyS0 tls.enabled=true` | `console=ttyS0 tls.enabled=true suse.autologin=ttyS0` | Enable console autologin |

### Secret Changes

| Resource | Action | Purpose |
|----------|--------|---------|
| `provisioning-networkdata` | Created | Static IP configuration for IPA |
| `metal3-node-0-bmc-secret` | No change | BMC credentials (already existed) |

### BareMetalHost Changes

| Setting | Before | After | Purpose |
|---------|--------|-------|---------|
| `preprovisioningNetworkDataName` | Not set | `"provisioning-networkdata"` | Reference NetworkData Secret |

---

## Commands to Apply All Changes

### Complete Setup Script

```bash
#!/bin/bash
set -e

echo "🔧 Applying all Kubernetes changes..."

# 1. Generate SSH key for IPA access (if not exists)
if [ ! -f ~/.ssh/id_rsa_ipa ]; then
    echo "Generating SSH key pair..."
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_ipa -N "" -C "ipa-root-access"
fi

# 2. Get SSH public key
SSH_KEY=$(cat ~/.ssh/id_rsa_ipa.pub)

# 3. Get current kernel params
CURRENT_PARAMS=$(kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_KERNEL_PARAMS}')

# 4. Apply Ironic ConfigMap changes
echo "Updating Ironic ConfigMap..."
kubectl patch configmap ironic -n metal3-system --type merge -p "{
  \"data\": {
    \"IPA_INSECURE\": \"1\",
    \"IRONIC_EXTERNAL_HTTP_URL\": \"https://192.168.1.242:6385\",
    \"IRONIC_RAMDISK_SSH_KEY\": \"$SSH_KEY\",
    \"IRONIC_KERNEL_PARAMS\": \"$CURRENT_PARAMS suse.autologin=ttyS0\"
  }
}"

# 5. Create NetworkData Secret
echo "Creating NetworkData Secret..."
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

# 6. Update BareMetalHost to reference NetworkData
echo "Updating BareMetalHost..."
kubectl patch baremetalhost metal3-node-0 -n metal3-system --type merge -p '{"spec":{"preprovisioningNetworkDataName":"provisioning-networkdata"}}'

# 7. Restart Ironic pod to apply ConfigMap changes
echo "Restarting Ironic pod..."
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic

echo ""
echo "✅ All Kubernetes changes applied!"
echo ""
echo "Summary:"
echo "  - IPA_INSECURE=1 (accept self-signed certs)"
echo "  - IRONIC_EXTERNAL_HTTP_URL=https://192.168.1.242:6385"
echo "  - SSH key added for IPA access"
echo "  - Autologin enabled for console"
echo "  - NetworkData Secret created"
echo "  - BareMetalHost updated to use NetworkData"
```

---

## Verification

### Verify Ironic ConfigMap

```bash
# Check all settings
kubectl get configmap ironic -n metal3-system -o yaml | grep -E "(IPA_INSECURE|IRONIC_EXTERNAL_HTTP_URL|IRONIC_RAMDISK_SSH_KEY|IRONIC_KERNEL_PARAMS)"
```

### Verify NetworkData Secret

```bash
# Check Secret exists
kubectl get secret provisioning-networkdata -n metal3-system

# View network configuration
kubectl get secret provisioning-networkdata -n metal3-system -o jsonpath='{.data.networkData}' | base64 -d
```

### Verify BareMetalHost

```bash
# Check BareMetalHost configuration
kubectl get baremetalhost metal3-node-0 -n metal3-system -o yaml | grep -A 2 preprovisioningNetworkDataName

# Check status
kubectl get baremetalhost metal3-node-0 -n metal3-system
```

---

## Rollback

To rollback changes:

### Remove SSH Access

```bash
# Remove SSH key
kubectl patch configmap ironic -n metal3-system --type merge -p '{"data":{"IRONIC_RAMDISK_SSH_KEY":""}}'

# Remove autologin
CURRENT_PARAMS=$(kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_KERNEL_PARAMS}')
NEW_PARAMS=$(echo "$CURRENT_PARAMS" | sed 's/ suse.autologin=ttyS0//')
kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_KERNEL_PARAMS\":\"$NEW_PARAMS\"}}"

# Restart Ironic pod
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
```

### Revert Ironic URL

```bash
# Change back to localhost (if needed)
kubectl patch configmap ironic -n metal3-system --type merge -p '{"data":{"IRONIC_EXTERNAL_HTTP_URL":"https://localhost:6185"}}'

# Restart Ironic pod
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
```

### Remove NetworkData

```bash
# Remove from BareMetalHost
kubectl patch baremetalhost metal3-node-0 -n metal3-system --type merge -p '{"spec":{"preprovisioningNetworkDataName":null}}'

# Delete Secret (optional)
kubectl delete secret provisioning-networkdata -n metal3-system
```

---

## References

- [IPA Connection Fix Guide](./IPA_CONNECTION_FIX_COMPLETE.md)
- [Port Forwarding & Network Explained](./PORT_FORWARDING_AND_NETWORK_EXPLAINED.md)
- [IPA SSH Access Setup](./IPA_SSH_ACCESS_SETUP.md)
- [SUSE Edge Documentation](https://documentation.suse.com/suse-edge/3.3/html/edge/troubleshooting-directed-network-provisioning.html)


