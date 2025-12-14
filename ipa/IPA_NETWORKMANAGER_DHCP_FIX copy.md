# Fix: NetworkManager Using DHCP in IPA Instead of Static IP

## Problem

IPA boots but NetworkManager keeps trying to use DHCP instead of the static IP from NetworkData. This prevents IPA from getting the correct static IP configuration.

## Root Causes

1. **NetworkManager is enabled** in IPA ramdisk and starts before NetworkData is applied
2. **NetworkData not being applied** correctly by cloud-init
3. **Interface name mismatch** - NetworkData targets wrong interface
4. **NetworkManager overriding** static configuration

## Diagnostic Steps

### Step 1: Check if NetworkManager is Running in IPA

Access IPA console:
```bash
# Via virsh console
virsh console <vm-name>

# Or via SSH if configured
ssh -i ~/.ssh/id_rsa_ipa root@<vm-ip>
```

Inside IPA, check NetworkManager status:
```bash
# Check if NetworkManager is running
systemctl status NetworkManager

# Check NetworkManager service
systemctl is-active NetworkManager

# See NetworkManager logs
journalctl -u NetworkManager -n 50

# Check what NetworkManager is doing
nmcli device status
nmcli connection show
```

### Step 2: Check NetworkData Was Received

```bash
# Check if NetworkData file exists
cat /var/lib/cloud/seed/nocloud/network-config 2>/dev/null || echo "Not found"

# Check cloud-init received it
cat /var/lib/cloud/seed/nocloud/meta-data 2>/dev/null

# Check cloud-init logs
journalctl -u cloud-init | grep -i network
journalctl -u cloud-init-local | grep -i network
```

### Step 3: Check Current Network Configuration

```bash
# See current IP addresses
ip addr show

# See current routes
ip route show

# Check if DHCP client is running
ps aux | grep -i dhcp
systemctl status dhcpcd 2>/dev/null || systemctl status dhclient 2>/dev/null

# Check what IP was obtained
ip addr show | grep "inet "
```

### Step 4: Check NetworkData Format

From your Kubernetes cluster:
```bash
# View the NetworkData secret
kubectl get secret provisioning-networkdata -n metal3-system -o jsonpath='{.data.networkData}' | base64 -d

# Check BareMetalHost references it
kubectl get baremetalhost <name> -n metal3-system -o jsonpath='{.spec.preprovisioningNetworkDataName}'
```

## Solutions

### Solution 1: Disable NetworkManager in IPA (Recommended)

NetworkManager can be disabled in the IPA ramdisk. This requires configuring Ironic to disable it.

#### Option A: Via Ironic ConfigMap

1. **Check current Ironic configuration**:
   ```bash
   kubectl get configmap ironic -n metal3-system -o yaml
   ```

2. **Add NetworkManager disable parameter**:
   ```bash
   kubectl patch configmap ironic -n metal3-system --type merge -p '{
     "data": {
       "IPA_DISABLE_NETWORK_MANAGER": "true"
     }
   }'
   ```

3. **Restart Ironic to regenerate boot ISO**:
   ```bash
   kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
   ```

4. **Reprovision BareMetalHost** to get new boot ISO:
   ```bash
   # Clear image to force reprovision
   kubectl patch baremetalhost <name> -n metal3-system --type merge -p '{"spec":{"image":null}}'
   
   # Or delete and recreate BareMetalHost
   kubectl delete baremetalhost <name> -n metal3-system
   # Then recreate with same configuration
   ```

#### Option B: Via BareMetalHost UserData (Alternative)

If Ironic doesn't support the config option, you can inject commands via userData:

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: <name>
  namespace: metal3-system
spec:
  userData:
    name: disable-networkmanager
    namespace: metal3-system
  # ... other fields
```

Create a userData secret:
```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: disable-networkmanager
  namespace: metal3-system
type: Opaque
stringData:
  userData: |
    #cloud-config
    runcmd:
      - systemctl stop NetworkManager
      - systemctl disable NetworkManager
      - systemctl mask NetworkManager
EOF
```

### Solution 2: Ensure NetworkData Disables DHCP Explicitly

Make sure your NetworkData explicitly disables DHCP:

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
      # Use MAC address matching for reliability
      match_by_mac:
        match:
          macaddress: "52:54:00:XX:XX:XX"  # Your VM's MAC
        dhcp4: false
        dhcp6: false
        addresses:
          - 10.2.83.181/24
        gateway4: 10.2.83.1
        nameservers:
          addresses:
            - 8.8.8.8
            - 8.8.4.4
```

**Key points**:
- `dhcp4: false` - Explicitly disable DHCP
- `dhcp6: false` - Disable IPv6 DHCP too
- Use MAC address matching instead of interface name

### Solution 3: Use NetworkManager Configuration Format

If NetworkManager must run, configure it via NetworkData using NetworkManager format:

```yaml
networkData: |
  version: 2
  network:
    version: 2
    ethernets:
      match_by_mac:
        match:
          macaddress: "52:54:00:XX:XX:XX"
        dhcp4: false
        dhcp6: false
        addresses:
          - 10.2.83.181/24
        gateway4: 10.2.83.1
        nameservers:
          addresses:
            - 8.8.8.8
            - 8.8.4.4
```

### Solution 4: Manual Fix Inside IPA (Temporary)

If you can access IPA console, you can manually fix it:

1. **Stop NetworkManager**:
   ```bash
   systemctl stop NetworkManager
   systemctl disable NetworkManager
   ```

2. **Stop DHCP client**:
   ```bash
   systemctl stop dhcpcd 2>/dev/null || systemctl stop dhclient 2>/dev/null || true
   ```

3. **Apply static IP manually**:
   ```bash
   # Find interface name
   INTERFACE=$(ip link show | grep -v "lo:" | head -1 | awk '{print $2}' | sed 's/://')
   
   # Configure static IP
   ip addr add 10.2.83.181/24 dev $INTERFACE
   ip link set $INTERFACE up
   ip route add default via 10.2.83.1
   
   # Configure DNS
   echo "nameserver 8.8.8.8" > /etc/resolv.conf
   echo "nameserver 8.8.4.4" >> /etc/resolv.conf
   ```

4. **Verify connectivity**:
   ```bash
   ping -c 3 10.2.83.1
   ```

**Note**: This is temporary - will be lost on reboot. Use this to test, then apply permanent fix.

## Complete Fix Process

### Step 1: Update NetworkData Secret

```bash
# Get VM MAC address
MAC=$(kubectl get baremetalhost <name> -n metal3-system -o jsonpath='{.spec.bootMACAddress}')

# Update NetworkData with MAC matching and explicit DHCP disable
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
      match_by_mac:
        match:
          macaddress: "${MAC}"
        dhcp4: false
        dhcp6: false
        addresses:
          - 10.2.83.181/24
        gateway4: 10.2.83.1
        nameservers:
          addresses:
            - 8.8.8.8
            - 8.8.4.4
EOF
```

### Step 2: Disable NetworkManager in Ironic

```bash
# Add disable NetworkManager config
kubectl patch configmap ironic -n metal3-system --type merge -p '{
  "data": {
    "IPA_DISABLE_NETWORK_MANAGER": "true"
  }
}'

# Restart Ironic
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
```

### Step 3: Reprovision BareMetalHost

```bash
# Force regeneration of boot ISO
kubectl patch baremetalhost <name> -n metal3-system --type merge -p '{"spec":{"image":null}}'

# Wait for it to be ready, then set image again if needed
# Or delete and recreate
kubectl delete baremetalhost <name> -n metal3-system
# Then recreate with same config
```

### Step 4: Verify in IPA

After VM boots with new ISO:

1. **Access IPA console**:
   ```bash
   virsh console <vm-name>
   ```

2. **Check NetworkManager is disabled**:
   ```bash
   systemctl status NetworkManager
   # Should show: inactive (dead) or masked
   ```

3. **Check static IP is configured**:
   ```bash
   ip addr show
   # Should show: 10.2.83.181/24
   ```

4. **Check no DHCP process**:
   ```bash
   ps aux | grep -i dhcp
   # Should show no dhcpcd or dhclient
   ```

5. **Test connectivity**:
   ```bash
   ping -c 3 10.2.83.1
   ```

## Alternative: Use systemd-networkd Instead

If NetworkManager keeps causing issues, ensure IPA uses systemd-networkd:

1. **Check which network manager IPA uses**:
   ```bash
   # In IPA console
   systemctl list-units | grep -E "network|NetworkManager"
   ```

2. **NetworkData should work with systemd-networkd** (which is what netplan uses):
   - NetworkData format is netplan format
   - Netplan renders to systemd-networkd
   - If NetworkManager is running, it may conflict

3. **Ensure systemd-networkd is active**:
   ```bash
   systemctl status systemd-networkd
   ```

## Verification Checklist

After applying fixes:

- [ ] NetworkManager is stopped/disabled in IPA
- [ ] NetworkData file exists in IPA: `/var/lib/cloud/seed/nocloud/network-config`
- [ ] Static IP is configured: `ip addr show` shows correct IP
- [ ] No DHCP client running: `ps aux | grep dhcp` shows nothing
- [ ] Gateway is reachable: `ping 10.2.83.1` works
- [ ] Ironic is reachable: Can connect to Ironic endpoint
- [ ] BareMetalHost progresses past "preparing" state

## Common Issues

### Issue: NetworkManager Still Starts

**Check**:
- Ironic config was updated correctly
- Ironic pod was restarted
- Boot ISO was regenerated (BareMetalHost was reprovisioned)

**Fix**: Ensure all three steps completed, then reprovision again.

### Issue: NetworkData Not Applied

**Check**:
- NetworkData secret exists and is correct
- BareMetalHost references it: `preprovisioningNetworkDataName`
- Boot ISO was regenerated after NetworkData change

**Fix**: Verify secret, update BareMetalHost reference, reprovision.

### Issue: Wrong Interface Name

**Check**:
- Interface name in IPA: `ip link show`
- NetworkData uses MAC matching (recommended) or correct interface name

**Fix**: Use MAC address matching in NetworkData instead of interface name.

### Issue: DHCP Still Running

**Check**:
- NetworkManager is disabled
- No other DHCP client (dhcpcd, dhclient) is installed/running

**Fix**: 
```bash
# In IPA console
systemctl stop NetworkManager
systemctl disable NetworkManager
systemctl mask NetworkManager
systemctl stop dhcpcd 2>/dev/null || true
systemctl stop dhclient 2>/dev/null || true
```

## Key Points

1. **NetworkManager conflicts with static IP** - Disable it in IPA
2. **Use MAC address matching** - More reliable than interface names
3. **Explicitly disable DHCP** - Set `dhcp4: false` and `dhcp6: false`
4. **Reprovision after changes** - Boot ISO must be regenerated
5. **Verify in IPA console** - Don't assume it worked, check it

## References

- [Metal3 NetworkData](https://metal3.io/documentation/api/networkdata.html)
- [Cloud-init Network Config](https://cloudinit.readthedocs.io/en/latest/reference/modules.html#network-config)
- [Netplan Configuration](https://netplan.io/reference/)
- [Ironic Python Agent](https://docs.openstack.org/ironic-python-agent/latest/)

