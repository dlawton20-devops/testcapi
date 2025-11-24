# IPA Connection Fixes - Applied to Local Environment

These fixes resolved the IPA timeout/connection issues. Apply the same fixes to your OpenStack environment.

## Fix 1: Disable Certificate Verification (IPA_INSECURE)

**Problem**: IPA was trying to verify Ironic's self-signed HTTPS certificate and rejecting the connection.

**Solution**:
```bash
kubectl patch configmap ironic -n metal3-system --type merge -p '{"data":{"IPA_INSECURE":"1"}}'
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
```

**What this does**: 
- Tells IPA to accept Ironic's self-signed certificate without verification
- Allows the HTTPS connection to proceed without certificate errors

**For OpenStack**: Same command, just ensure you're in the correct namespace (usually `openstack` or `ironic`).

---

## Fix 2: Configure Correct Ironic External URL

**Problem**: Boot ISO contained an Ironic URL that the VM couldn't reach (e.g., LoadBalancer IP or internal service IP).

**Solution**:
```bash
# Set Ironic external URL to IP accessible from VMs
HOST_IP="<your-host-ip-accessible-from-vms>"
IRONIC_PORT="6385"  # Or your Ironic port

kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_EXTERNAL_HTTP_URL\":\"https://${HOST_IP}:${IRONIC_PORT}\"}}"
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
```

**What this does**: 
- Changes the URL that Ironic advertises to IPA in the boot ISO
- Uses an IP address that VMs can actually reach
- The boot ISO must be regenerated for this to take effect (happens automatically when BMH is reprovisioned)

**For OpenStack with MetalLB**: 
- **Option 1 (Recommended)**: Use the MetalLB VIP if your KVM VMs can reach it:
  ```bash
  # Get MetalLB VIP
  IRONIC_IP=$(kubectl get svc -n metal3-system -l app.kubernetes.io/component=ironic -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')
  ```
- **Option 2**: Use the OpenStack VM IP (where Rancher runs) + NodePort or port forwarding
- **Option 3**: Use the OpenStack controller IP or floating IP that VMs can reach
- Port is typically `6385` for HTTPS

**See**: `OPENSTACK_IRONIC_URL_GUIDE.md` for detailed decision tree

---

## Fix 3: Network Configuration (NetworkData Secret)

**Problem**: VM needed static IP configuration to reach Ironic via gateway.

**Solution**:
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
          - <vm-static-ip>/<netmask>
        gateway4: <gateway-ip>
        nameservers:
          addresses:
            - 8.8.8.8
            - 8.8.4.4
EOF
```

**What this does**:
- Provides network configuration to IPA when it boots from virtual media
- Sets static IP so VM can reach Ironic
- Applied automatically when IPA boots

**For OpenStack**: 
- Configure the network IPs based on your OpenStack network topology
- Gateway should be the router/network gateway IP
- Reference this secret in BareMetalHost: `preprovisioningNetworkDataName: "provisioning-networkdata"`

---

## Fix 4: BareMetal Operator Ironic Connection

**Problem**: BareMetal operator couldn't reach Ironic at LoadBalancer IP from within cluster.

**Solution**:
```bash
# Update baremetal-operator-ironic ConfigMap to use service URL
kubectl patch configmap baremetal-operator-ironic -n metal3-system --type merge -p '{
  "data": {
    "IRONIC_ENDPOINT": "https://metal3-metal3-ironic.metal3-system.svc.cluster.local:6385/v1/",
    "CACHEURL": "https://metal3-metal3-ironic.metal3-system.svc.cluster.local:6185/images",
    "IRONIC_INSECURE": "true"
  }
}'

# Add IRONIC_INSECURE to operator deployment
DEPLOYMENT=$(kubectl get deployment -n metal3-system -l app.kubernetes.io/component=baremetal-operator -o name)
kubectl patch $DEPLOYMENT -n metal3-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "IRONIC_INSECURE", "value": "true"}}]'

# Restart operator
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=baremetal-operator
```

**What this does**:
- Operator uses service DNS name (accessible from within cluster) instead of LoadBalancer IP
- Skips certificate verification for operator-to-Ironic communication
- Allows operator to communicate with Ironic

**For OpenStack**: 
- Use the Ironic service name in your OpenStack namespace
- Or use the Ironic API endpoint if accessible from operator pods

---

## Fix 5: Port Forwarding (Local Environment Only)

**Note**: This was only needed in our local kind cluster setup. In OpenStack, Ironic should be directly accessible.

**Local Setup** (not needed in OpenStack):
```bash
# Two-stage port forwarding for kind cluster
# Stage 1: kubectl port-forward
kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6385:6185 &

# Stage 2: socat (if needed)
socat TCP-LISTEN:6385,bind=<host-ip>,fork,reuseaddr TCP:localhost:6385 &
```

**For OpenStack**: 
- Ironic should be accessible via its service endpoint
- No port forwarding needed
- Just ensure the `IRONIC_EXTERNAL_HTTP_URL` points to the correct accessible IP

---

## Complete Fix Summary for OpenStack

Apply these fixes in order:

```bash
# 1. Disable certificate verification
kubectl patch configmap ironic -n <ironic-namespace> --type merge -p '{"data":{"IPA_INSECURE":"1"}}'

# 2. Set Ironic external URL (use your OpenStack Ironic endpoint)
IRONIC_IP="<ironic-api-endpoint-ip>"
IRONIC_PORT="6385"
kubectl patch configmap ironic -n <ironic-namespace> --type merge -p "{\"data\":{\"IRONIC_EXTERNAL_HTTP_URL\":\"https://${IRONIC_IP}:${IRONIC_PORT}\"}}"

# 3. Create NetworkData secret (adjust IPs for your network)
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: provisioning-networkdata
  namespace: <ironic-namespace>
type: Opaque
stringData:
  networkData: |
    version: 2
    ethernets:
      eth0:
        dhcp4: false
        addresses:
          - <vm-ip>/<netmask>
        gateway4: <gateway-ip>
        nameservers:
          addresses:
            - 8.8.8.8
            - 8.8.4.4
EOF

# 4. Fix baremetal operator connection (if needed)
kubectl patch configmap baremetal-operator-ironic -n <ironic-namespace> --type merge -p '{
  "data": {
    "IRONIC_ENDPOINT": "https://<ironic-service-name>.<namespace>.svc.cluster.local:6385/v1/",
    "IRONIC_INSECURE": "true"
  }
}'

# 5. Restart pods
kubectl delete pod -n <ironic-namespace> -l app.kubernetes.io/component=ironic
kubectl delete pod -n <ironic-namespace> -l app.kubernetes.io/component=baremetal-operator
```

---

## Key Points

1. **IPA_INSECURE=1**: Critical - allows IPA to accept self-signed certificates
2. **IRONIC_EXTERNAL_HTTP_URL**: Must be an IP/URL that VMs can reach from their network
3. **NetworkData**: Provides static IP so VM can route to Ironic
4. **Service URL for Operator**: Operator should use service DNS, not LoadBalancer IP

## ⚠️ SSH Keys - NOT Required for Fix

**Question**: Did SSH keys fix the timeout issue?

**Answer**: **NO** - SSH keys (`IRONIC_RAMDISK_SSH_KEY`) were only for debugging/access purposes. They did NOT fix the connection timeout.

**What SSH keys do**:
- Allow SSH access to IPA console: `ssh -i ~/.ssh/id_rsa_ipa root@<vm-ip>`
- Useful for debugging network issues manually
- Help verify NetworkData was applied correctly

**What SSH keys DON'T do**:
- Don't fix certificate verification issues (that's `IPA_INSECURE=1`)
- Don't fix wrong Ironic URL (that's `IRONIC_EXTERNAL_HTTP_URL`)
- Don't fix network routing (that's NetworkData secret)

**Conclusion**: SSH keys are optional for debugging. The actual fixes are:
1. `IPA_INSECURE=1` ✅
2. `IRONIC_EXTERNAL_HTTP_URL` ✅  
3. NetworkData secret ✅

---

## Verification

After applying fixes:

```bash
# Check Ironic configuration
kubectl get configmap ironic -n <namespace> -o jsonpath='{.data.IPA_INSECURE}'
kubectl get configmap ironic -n <namespace> -o jsonpath='{.data.IRONIC_EXTERNAL_HTTP_URL}'

# Check BareMetalHost status
kubectl get baremetalhost -n <namespace> -w

# Check IPA connection (from VM console or logs)
# Should see successful connection to Ironic, no timeout errors
```

---

## Common OpenStack Issues

1. **Ironic not accessible from VM network**: 
   - Ensure `IRONIC_EXTERNAL_HTTP_URL` uses an IP on the provisioning network
   - Or use a floating IP that VMs can reach

2. **Certificate errors**:
   - `IPA_INSECURE=1` should fix this
   - Or properly configure Ironic certificates

3. **Network routing**:
   - Ensure VM can reach Ironic gateway
   - Check network routes and firewall rules

4. **Port conflicts**:
   - Ensure Ironic port (6385) is not blocked
   - Check security groups in OpenStack

