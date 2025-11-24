# Baremetal Operator Ironic Connection - FIXED ✅

## Problem

The baremetal-operator could not connect to Ironic, causing BareMetalHost state to not progress. Error:
```
error: dial tcp 172.18.255.200:6385: connect: no route to host
```

## Root Cause

1. **Wrong URL**: ConfigMap was using LoadBalancer IP (`172.18.255.200`) which isn't reachable from within Kind cluster
2. **Certificate Mismatch**: Service URL had certificate verification issues
3. **Wrong Port**: Initially tried port 6185 for API (should be 6385)

## Solution Applied

### Step 1: Add IRONIC_INSECURE Environment Variable

Added environment variable to operator deployment to skip certificate verification:

```bash
DEPLOYMENT=$(kubectl get deployment -n metal3-system -l app.kubernetes.io/component=baremetal-operator -o name)
kubectl patch $DEPLOYMENT -n metal3-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "IRONIC_INSECURE", "value": "true"}}]'
```

**What this does**: Tells the operator to skip TLS certificate verification (similar to `IPA_INSECURE` for IPA).

### Step 2: Update ConfigMap to Use Service URL

Updated `baremetal-operator-ironic` ConfigMap to use the service URL with correct ports:

```bash
kubectl patch configmap baremetal-operator-ironic -n metal3-system --type merge -p '{
  "data": {
    "IRONIC_ENDPOINT": "https://metal3-metal3-ironic.metal3-system.svc.cluster.local:6385/v1/",
    "CACHEURL": "https://metal3-metal3-ironic.metal3-system.svc.cluster.local:6185/images",
    "IRONIC_INSECURE": "true"
  }
}'
```

**Ports**:
- `6385`: Ironic API endpoint (`/v1/`)
- `6185`: Image cache endpoint (`/images`)

### Step 3: Restart Operator

```bash
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=baremetal-operator
```

## Verification

### Check Operator Logs

```bash
kubectl logs -n metal3-system -l app.kubernetes.io/component=baremetal-operator --tail=20
```

**Success indicators**:
- No connection errors
- `"TLSInsecure":true` in logs
- `"current provision state"` messages showing Ironic communication
- `"provisioningState":"registering"` or progressing states

### Check BMH State

```bash
kubectl get baremetalhost metal3-node-0 -n metal3-system
```

**Expected**: BMH should show a state (e.g., `registering`, `inspecting`, `available`)

## Current Configuration

### baremetal-operator-ironic ConfigMap

```yaml
IRONIC_ENDPOINT: https://metal3-metal3-ironic.metal3-system.svc.cluster.local:6385/v1/
CACHEURL: https://metal3-metal3-ironic.metal3-system.svc.cluster.local:6185/images
IRONIC_INSECURE: "true"
```

### Operator Deployment

Environment variable added:
```yaml
env:
- name: IRONIC_INSECURE
  value: "true"
```

## Result

✅ **Operator is now connected to Ironic!**

- BMH state is progressing (shows `registering`)
- Operator can communicate with Ironic
- No more connection errors
- BMH will continue through states: `registering` → `inspecting` → `available` → `provisioning`

## Complete Fix Command

```bash
# 1. Add IRONIC_INSECURE to operator deployment
DEPLOYMENT=$(kubectl get deployment -n metal3-system -l app.kubernetes.io/component=baremetal-operator -o name)
kubectl patch $DEPLOYMENT -n metal3-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "IRONIC_INSECURE", "value": "true"}}]'

# 2. Update ConfigMap with service URL and correct ports
kubectl patch configmap baremetal-operator-ironic -n metal3-system --type merge -p '{
  "data": {
    "IRONIC_ENDPOINT": "https://metal3-metal3-ironic.metal3-system.svc.cluster.local:6385/v1/",
    "CACHEURL": "https://metal3-metal3-ironic.metal3-system.svc.cluster.local:6185/images",
    "IRONIC_INSECURE": "true"
  }
}'

# 3. Restart operator
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=baremetal-operator

# 4. Verify
kubectl get baremetalhost metal3-node-0 -n metal3-system
kubectl logs -n metal3-system -l app.kubernetes.io/component=baremetal-operator --tail=20
```

## Notes

- The `IRONIC_INSECURE` environment variable in the deployment is what actually enables skipping certificate verification
- The ConfigMap `IRONIC_INSECURE` might not be used by the operator, but it's set for consistency
- Using the service URL (`metal3-metal3-ironic.metal3-system.svc.cluster.local`) works within the cluster
- Port 6385 is for the API, port 6185 is for images (httpd-tls)

## Related Fixes

- IPA connection was fixed with `IPA_INSECURE=1` in Ironic ConfigMap
- Operator connection fixed with `IRONIC_INSECURE=true` in operator deployment
- Both skip certificate verification to work with self-signed certificates


