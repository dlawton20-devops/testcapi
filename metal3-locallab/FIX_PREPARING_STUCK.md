# Fix: BareMetalHost Stuck in Preparing State

## Issue
BareMetalHost is stuck in `preparing` state with error:
```
action "preparing" failed: error preparing host: have unexpected ironic node state inspect wait
```

## Root Cause
Ironic started an inspection (even though we disabled it on the BMH), and the node is stuck in "inspect wait" state. Metal3 can't proceed because it expects the node to be in a different state.

## Solution

### Option 1: Abort Inspection via Ironic API (Recommended)

```bash
IRONIC_POD=$(kubectl get pods -n metal3-system -l app.kubernetes.io/component=ironic -o jsonpath='{.items[0].metadata.name}')
NODE_UUID="91796f7c-4023-4068-a3e0-f4ba5ecb2aca"

# Abort the inspection
kubectl exec -n metal3-system $IRONIC_POD -c ironic -- curl -s -X PUT "http://localhost:6385/v1/nodes/${NODE_UUID}/states/provision" -H "Content-Type: application/json" -d '{"target": "abort"}'

# Set to manageable
kubectl exec -n metal3-system $IRONIC_POD -c ironic -- curl -s -X PUT "http://localhost:6385/v1/nodes/${NODE_UUID}/states/provision" -H "Content-Type: application/json" -d '{"target": "manageable"}'

# Restart operator to retry
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=baremetal-operator
```

### Option 2: Delete and Recreate BareMetalHost

If the above doesn't work, you may need to delete the BMH and recreate it:

```bash
# Delete the BMH (this will also clean up the Ironic node)
kubectl delete bmh metal3-node-0 -n metal3-system

# Wait a bit for cleanup
sleep 10

# Recreate from manifest
kubectl apply -f baremetalhost.yaml
```

### Option 3: Use Ironic Python Client

If available in the pod:

```bash
IRONIC_POD=$(kubectl get pods -n metal3-system -l app.kubernetes.io/component=ironic -o jsonpath='{.items[0].metadata.name}')
NODE_UUID="91796f7c-4023-4068-a3e0-f4ba5ecb2aca"

kubectl exec -n metal3-system $IRONIC_POD -c ironic -- python3 <<EOF
from ironicclient import client
import os

kwargs = {'os_auth_token': 'fake'}
ironic = client.Client(1, **kwargs)
node = ironic.node.get(NODE_UUID)
ironic.node.set_provision_state(NODE_UUID, 'abort')
EOF
```

## Current Status
- BareMetalHost: `preparing` (stuck)
- Ironic Node: `inspect wait` (needs to be changed to `manageable`)
- VM: Running ✅
- sushy-tools: Working ✅

## Expected Outcome
After fixing the Ironic node state, the BareMetalHost should:
1. Complete preparation
2. Move to `available` state
3. Be ready for provisioning

