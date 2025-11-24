# Baremetal Operator Ironic Connection Fix

## Problem

The baremetal-operator cannot connect to Ironic, causing BareMetalHost state to not progress. Error in logs:

```
error caught while checking endpoint, will retry
endpoint: https://172.18.255.200:6385/v1/
error: dial tcp 172.18.255.200:6385: connect: no route to host
```

## Root Cause

The `baremetal-operator-ironic` ConfigMap has `IRONIC_ENDPOINT` set to the LoadBalancer IP (`172.18.255.200`), which is not reachable from within the Kubernetes cluster (especially in Kind clusters where LoadBalancers don't work the same way).

## Solutions Attempted

### Attempt 1: Use Service URL (HTTP)
**Result**: Failed - Ironic requires HTTPS
```
error: You're speaking plain HTTP to an SSL-enabled server port
```

### Attempt 2: Use Service URL (HTTPS)
**Result**: Failed - Certificate doesn't match service name
```
error: certificate is not valid for any names, but wanted to match metal3-metal3-ironic.metal3-system.svc.cluster.local
```

### Attempt 3: Use Cluster IP (HTTPS)
**Result**: Failed - Certificate doesn't match cluster IP
```
error: certificate is valid for 172.18.255.200, not 10.108.146.230
```

### Attempt 4: Use LoadBalancer IP (HTTPS)
**Result**: Failed - Not reachable from within cluster
```
error: dial tcp 172.18.255.200:6385: connect: no route to host
```

## Current Status

The operator needs to connect to Ironic, but:
- LoadBalancer IP is not reachable from within the cluster
- Service URL has certificate mismatch
- Certificate is only valid for LoadBalancer IP

## Recommended Solution

### Option 1: Configure Operator to Skip Certificate Verification

Check if the baremetal-operator supports an environment variable to skip certificate verification (similar to `IPA_INSECURE` for IPA).

**Check operator deployment:**
```bash
kubectl get deployment -n metal3-system -l app.kubernetes.io/component=baremetal-operator -o yaml | grep -i -E "(env|ironic|cert|tls|insecure)"
```

**If supported, add environment variable:**
```bash
# This would need to be done via Helm values or by editing the deployment
# Example (if supported):
# IRONIC_INSECURE: "true"
```

### Option 2: Use LoadBalancer IP with Proper Routing

If using a real LoadBalancer (not Kind), ensure the LoadBalancer IP is reachable from within the cluster:

```bash
# Current configuration (cert matches, but not reachable)
kubectl patch configmap baremetal-operator-ironic -n metal3-system --type merge -p '{
  "data": {
    "IRONIC_ENDPOINT": "https://172.18.255.200:6385/v1/",
    "CACHEURL": "https://172.18.255.200:6185/images"
  }
}'
```

### Option 3: Regenerate Ironic Certificate

Generate a new certificate that includes the service name and cluster IP:

```bash
# This would require reconfiguring Ironic to generate a new certificate
# with SAN (Subject Alternative Names) including:
# - metal3-metal3-ironic.metal3-system.svc.cluster.local
# - 10.108.146.230 (cluster IP)
# - 172.18.255.200 (LoadBalancer IP)
```

### Option 4: Use NodePort Directly

Since the service is NodePort, access it via the node IP:

```bash
# Get node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Use node IP with NodePort
kubectl patch configmap baremetal-operator-ironic -n metal3-system --type merge -p "{
  \"data\": {
    \"IRONIC_ENDPOINT\": \"https://${NODE_IP}:31385/v1/\",
    \"CACHEURL\": \"https://${NODE_IP}:31592/images\"
  }
}"
```

**Note**: This will still have certificate issues unless the cert includes the node IP.

## Temporary Workaround

For now, the operator is stuck. The BMH won't progress until this is fixed.

**To check current configuration:**
```bash
kubectl get configmap baremetal-operator-ironic -n metal3-system -o yaml
```

**To check operator logs:**
```bash
kubectl logs -n metal3-system -l app.kubernetes.io/component=baremetal-operator --tail=50
```

## Next Steps

1. Check Metal3 documentation for operator certificate verification settings
2. Check if there's a Helm value to configure this
3. Consider regenerating Ironic certificate with proper SANs
4. Or configure operator to skip certificate verification

## Related Issues

- IPA connection was fixed by setting `IPA_INSECURE=1` in Ironic ConfigMap
- Similar fix might be needed for baremetal-operator
- Check Metal3 Helm chart values for operator configuration

## References

- [Metal3 Documentation](https://metal3.io/documentation/)
- [Ironic Configuration](https://docs.openstack.org/ironic/latest/admin/configuration.html)


