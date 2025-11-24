# NetworkData Not Working with Bridge Network - Troubleshooting Guide

## Problem

NetworkData works with NAT/user-mode networks but **doesn't apply** when using a bridge network.

## Root Causes

### 1. Interface Name Mismatch (Most Common)

**NAT/User-mode networks** typically use:
- `eth0` (predictable, assigned by QEMU)

**Bridge networks** may use:
- `ens3` (systemd predictable naming)
- `enp1s0` (PCI-based naming)
- `eth1`, `eth2` (if multiple interfaces)
- Or other names based on systemd/udev rules

**Solution**: Use MAC address matching instead of interface name.

---

### 2. NetworkData Format

**Problem**: NetworkData using `eth0:` won't match if the interface is named `ens3`.

**Solution**: Use MAC address matching or match all interfaces.

---

### 3. IPA Network Detection

**Problem**: IPA might not detect the interface correctly on bridge networks.

**Solution**: Use more flexible NetworkData format.

---

## Solutions

### Solution 1: Match by MAC Address (Recommended)

This is the most reliable method for bridge networks:

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
      # Match by MAC address (works regardless of interface name)
      match_by_mac:
        match:
          macaddress: "52:54:00:f5:26:5e"  # Your VM's MAC address
        dhcp4: false
        addresses:
          - 192.168.124.100/24
        gateway4: 192.168.124.1
        nameservers:
          addresses:
            - 8.8.8.8
            - 8.8.4.4
```

**How to get MAC address:**
```bash
# From BareMetalHost
kubectl get baremetalhost <name> -n metal3-system -o jsonpath='{.spec.bootMACAddress}'

# Or from libvirt VM
virsh domiflist <vm-name>
```

---

### Solution 2: Match All Interfaces

If you're not sure of the interface name, match all:

```yaml
networkData: |
  version: 2
  ethernets:
    # Match any interface
    "*":
      dhcp4: false
      addresses:
        - 192.168.124.100/24
      gateway4: 192.168.124.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
```

**Note**: This might apply to all interfaces, which could cause issues if you have multiple.

---

### Solution 3: Try Common Interface Names

Create multiple NetworkData secrets and test:

```bash
# For ens3
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: provisioning-networkdata-ens3
  namespace: metal3-system
type: Opaque
stringData:
  networkData: |
    version: 2
    ethernets:
      ens3:
        dhcp4: false
        addresses:
          - 192.168.124.100/24
        gateway4: 192.168.124.1
        nameservers:
          addresses:
            - 8.8.8.8
            - 8.8.4.4
EOF

# Test it
kubectl patch baremetalhost <name> -n metal3-system --type merge -p '{"spec":{"preprovisioningNetworkDataName":"provisioning-networkdata-ens3"}}'
```

---

### Solution 4: Use NetworkManager Format (Alternative)

Some IPA versions support NetworkManager format:

```yaml
networkData: |
  version: 2
  network:
    version: 2
    ethernets:
      match_by_mac:
        match:
          macaddress: "52:54:00:f5:26:5e"
        addresses:
          - 192.168.124.100/24
        gateway4: 192.168.124.1
        nameservers:
          addresses:
            - 8.8.8.8
            - 8.8.4.4
```

---

## Diagnostic Steps

### 1. Check Current NetworkData

```bash
kubectl get secret provisioning-networkdata -n metal3-system -o jsonpath='{.data.networkData}' | base64 -d
```

### 2. Check Interface Name in IPA

Access IPA console:
```bash
virsh console <vm-name>
# or via SSH if configured
ssh -i ~/.ssh/id_rsa_ipa root@<vm-ip>
```

Inside IPA, check interface:
```bash
# List interfaces
ip link show

# Check current IP
ip addr show

# Check routing
ip route show
```

### 3. Check NetworkData is Applied

In IPA console:
```bash
# Check if NetworkData was received
cat /var/lib/cloud/seed/nocloud/network-config 2>/dev/null || echo "Not found"

# Check cloud-init logs
journalctl -u cloud-init | grep -i network

# Check IPA logs
journalctl -u ironic-python-agent | grep -i network
```

### 4. Verify BareMetalHost References NetworkData

```bash
kubectl get baremetalhost <name> -n metal3-system -o jsonpath='{.spec.preprovisioningNetworkDataName}'
```

Should output: `provisioning-networkdata`

---

## Complete Fix Script

Use the provided script:

```bash
./fix-networkdata-bridge.sh
```

This script will:
1. Find your BareMetalHost MAC address
2. Create NetworkData with MAC address matching
3. Update BareMetalHost to reference it
4. Restart Ironic to regenerate boot ISO

---

## Verification

After applying the fix:

1. **Reprovision BareMetalHost** to regenerate boot ISO:
   ```bash
   kubectl patch baremetalhost <name> -n metal3-system --type merge -p '{"spec":{"image":null}}'
   kubectl patch baremetalhost <name> -n metal3-system --type merge -p '{"spec":{"image":{"url":"..."}}}'
   ```

2. **Boot VM and check IPA console**:
   ```bash
   virsh console <vm-name>
   ```

3. **Inside IPA, verify network**:
   ```bash
   ip addr show
   # Should show your static IP configured
   
   ip route show
   # Should show gateway route
   
   ping <gateway-ip>
   # Should work
   ```

---

## Common Issues

### Issue: NetworkData Still Not Applied

**Check:**
1. Boot ISO was regenerated after NetworkData change
2. BareMetalHost references the correct secret name
3. Ironic pod was restarted
4. Interface name/MAC address is correct

**Solution:**
```bash
# Force regenerate boot ISO
kubectl delete baremetalhost <name> -n metal3-system
# Recreate with correct NetworkData reference
```

### Issue: Multiple Interfaces

If VM has multiple interfaces, NetworkData might apply to the wrong one.

**Solution:** Use MAC address matching to target the specific interface.

### Issue: NetworkData Format Error

IPA might reject NetworkData if format is incorrect.

**Check IPA logs:**
```bash
journalctl -u ironic-python-agent | grep -i "network\|error"
```

**Solution:** Verify YAML format is correct (indentation, syntax).

---

## Comparison: NAT vs Bridge

| Aspect | NAT/User-mode | Bridge |
|--------|--------------|--------|
| Interface name | Usually `eth0` | Variable (`ens3`, `enp1s0`, etc.) |
| NetworkData format | `eth0:` works | Need MAC matching |
| Gateway | Host IP (e.g., `10.0.2.2`) | Bridge gateway (e.g., `192.168.124.1`) |
| IP range | `10.0.2.0/24` | Your bridge network range |

---

## Best Practice

**Always use MAC address matching** for bridge networks:

```yaml
networkData: |
  version: 2
  ethernets:
    match_by_mac:
      match:
        macaddress: "<vm-mac-address>"
      dhcp4: false
      addresses:
        - <static-ip>/<netmask>
      gateway4: <gateway-ip>
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
```

This works regardless of:
- Interface name
- Network type (NAT, bridge, etc.)
- Systemd naming rules

---

## References

- [Cloud-init Network Configuration](https://cloudinit.readthedocs.io/en/latest/reference/modules.html#network-config)
- [Netplan Configuration](https://netplan.io/reference/)
- [Metal3 NetworkData Documentation](https://metal3.io/documentation/api/networkdata.html)

