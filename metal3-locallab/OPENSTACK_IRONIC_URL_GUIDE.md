# Setting IRONIC_EXTERNAL_HTTP_URL for OpenStack with MetalLB

## Your Environment
- **OpenStack VM**: Running KVM and sushy-tools
- **Rancher Cluster**: With MetalLB VIP
- **KVM VMs**: Bare metal hosts being provisioned

## The Question: Which IP Should You Use?

The `IRONIC_EXTERNAL_HTTP_URL` must be an IP address that **your KVM VMs (bare metal hosts) can reach** when they boot from the virtual media ISO.

## Option 1: MetalLB VIP (Recommended if reachable)

**Use this if**: Your KVM VMs are on the same network as the Rancher cluster and can reach the MetalLB VIP.

```bash
# Find the MetalLB VIP
kubectl get svc -n metal3-system -l app.kubernetes.io/component=ironic

# Example output:
# NAME                      TYPE           CLUSTER-IP      EXTERNAL-IP    PORT(S)
# metal3-metal3-ironic      LoadBalancer   10.43.x.x       192.168.1.100  6385:31885/TCP

# Use the EXTERNAL-IP (MetalLB VIP)
IRONIC_IP="192.168.1.100"  # Your MetalLB VIP
IRONIC_PORT="6385"

kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_EXTERNAL_HTTP_URL\":\"https://${IRONIC_IP}:${IRONIC_PORT}\"}}"
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
```

**Pros**: 
- Direct access, no port forwarding needed
- Cleanest solution

**Cons**: 
- Only works if KVM VMs can route to MetalLB VIP
- Requires proper network configuration

---

## Option 2: OpenStack VM IP (If MetalLB VIP not reachable)

**Use this if**: Your KVM VMs can reach the OpenStack VM's IP, but not the MetalLB VIP.

```bash
# Find your OpenStack VM IP (where Rancher runs)
# This is the IP of the VM hosting your Rancher cluster

OPENSTACK_VM_IP="<your-openstack-vm-ip>"  # e.g., 192.168.1.50
IRONIC_PORT="6385"

# Set the URL
kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_EXTERNAL_HTTP_URL\":\"https://${OPENSTACK_VM_IP}:${IRONIC_PORT}\"}}"
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
```

**⚠️ Important**: You must also expose Ironic on this IP:

### Option 2a: Use NodePort
```bash
# Get the NodePort
NODE_PORT=$(kubectl get svc -n metal3-system -l app.kubernetes.io/component=ironic -o jsonpath='{.items[0].spec.ports[?(@.name=="http")].nodePort}')

# Update URL to use NodePort
kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_EXTERNAL_HTTP_URL\":\"https://${OPENSTACK_VM_IP}:${NODE_PORT}\"}}"
```

### Option 2b: Use Port Forwarding
```bash
# On the OpenStack VM, forward port 6385 to Ironic service
kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6385:6385 &
```

**Pros**: 
- Works if KVM VMs can reach OpenStack VM
- Flexible

**Cons**: 
- Requires port forwarding or NodePort setup
- More complex

---

## Option 3: OpenStack Controller IP

**Use this if**: Your KVM VMs can reach the OpenStack controller, and Ironic is exposed there.

```bash
OPENSTACK_CTRL_IP="<openstack-controller-ip>"
IRONIC_PORT="6385"

kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_EXTERNAL_HTTP_URL\":\"https://${OPENSTACK_CTRL_IP}:${IRONIC_PORT}\"}}"
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
```

---

## Quick Decision Tree

```
Can KVM VMs reach MetalLB VIP?
├─ YES → Use MetalLB VIP (Option 1)
└─ NO
   ├─ Can KVM VMs reach OpenStack VM IP?
   │  ├─ YES → Use OpenStack VM IP + NodePort/Port Forward (Option 2)
   │  └─ NO
   │     └─ Can KVM VMs reach OpenStack Controller?
   │        ├─ YES → Use Controller IP (Option 3)
   │        └─ NO → Check network routing/firewall rules
```

---

## How to Test Connectivity

From your KVM VM (or a VM on the same network):

```bash
# Test if IP is reachable
ping <ironic-ip>

# Test if port is open
telnet <ironic-ip> 6385
# or
nc -zv <ironic-ip> 6385

# Test HTTPS connection
curl -k https://<ironic-ip>:6385
```

---

## Complete Setup Script

Use the interactive script to determine the correct IP:

```bash
./openstack-ironic-url-setup.sh
```

Or manually:

```bash
# 1. Find MetalLB VIP
kubectl get svc -n metal3-system -l app.kubernetes.io/component=ironic

# 2. Test if KVM VMs can reach it
# (from a KVM VM or same network)
ping <metallb-vip>

# 3. If reachable, use it:
IRONIC_IP="<metallb-vip>"
IRONIC_PORT="6385"

# 4. Apply
kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_EXTERNAL_HTTP_URL\":\"https://${IRONIC_IP}:${IRONIC_PORT}\"}}"
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic

# 5. Reprovision BareMetalHost to regenerate boot ISO
kubectl patch baremetalhost <bmh-name> -n metal3-system --type merge -p '{"spec":{"image":null}}'
kubectl patch baremetalhost <bmh-name> -n metal3-system --type merge -p '{"spec":{"image":{"url":"..."}}}'
```

---

## Important Notes

1. **Boot ISO Regeneration**: After changing `IRONIC_EXTERNAL_HTTP_URL`, you must reprovision the BareMetalHost to regenerate the boot ISO with the new URL.

2. **Network Routing**: Ensure your KVM VMs have a route to the Ironic IP. Check:
   - Network configuration
   - Firewall rules
   - Security groups (in OpenStack)

3. **Port Accessibility**: Port 6385 (or your Ironic port) must be open and accessible from KVM VMs.

4. **Certificate**: Don't forget `IPA_INSECURE=1` to accept self-signed certificates:
   ```bash
   kubectl patch configmap ironic -n metal3-system --type merge -p '{"data":{"IPA_INSECURE":"1"}}'
   ```

---

## Verification

After applying:

```bash
# Check configuration
kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_EXTERNAL_HTTP_URL}'

# Check BareMetalHost status
kubectl get baremetalhost -n metal3-system -w

# Check IPA connection (from VM console)
# Should see successful connection, no timeout errors
```

