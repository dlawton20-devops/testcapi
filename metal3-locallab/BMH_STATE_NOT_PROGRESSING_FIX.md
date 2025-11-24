# BareMetalHost State Not Progressing - Diagnosis & Fix

## Problem

BareMetalHost shows no `STATE` in Kubernetes, and the VM console shows Ubuntu login prompt instead of IPA.

## Root Cause

**Primary Issue**: The baremetal-operator cannot connect to Ironic because it's using the wrong URL (LoadBalancer IP `172.18.255.200` which isn't reachable from within the cluster).

**Secondary Issue**: The VM is booting to the base Ubuntu OS instead of booting from virtual media (IPA ISO). For the BareMetalHost to progress, IPA must boot and connect to Ironic.

## Diagnosis

### Check Current State

```bash
# Check BMH state
kubectl get baremetalhost metal3-node-0 -n metal3-system

# Check Ironic node state
IRONIC_POD=$(kubectl get pods -n metal3-system -l app.kubernetes.io/component=ironic -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n metal3-system $IRONIC_POD -c ironic -- curl -s http://localhost:6385/v1/nodes | jq -r '.nodes[] | "\(.uuid) - \(.provision_state) - \(.power_state)"'

# Check baremetal-operator logs
kubectl logs -n metal3-system -l app.kubernetes.io/component=baremetal-operator --tail=50
```

### What You're Seeing

- **Console shows**: `metal3-node-0 login:` (Ubuntu login prompt)
- **BMH STATE**: Empty or stuck
- **This means**: VM booted to base OS, not IPA

### What Should Happen

1. Metal3/Ironic should power cycle the VM
2. VM should boot from virtual media (IPA ISO)
3. IPA should boot and connect to Ironic
4. BMH state should progress: `registering` → `inspecting` → `available` → `provisioning`

## Solutions

### Solution 1: Fix baremetal-operator Ironic URL (CRITICAL - Do This First!)

**Problem**: The baremetal-operator is trying to connect to Ironic at `https://172.18.255.200:6385/v1/` which isn't reachable.

**Fix**:
```bash
# Update baremetal-operator-ironic ConfigMap to use service URL
kubectl patch configmap baremetal-operator-ironic -n metal3-system --type merge -p '{
  "data": {
    "IRONIC_ENDPOINT": "http://metal3-metal3-ironic.metal3-system.svc.cluster.local:6185/v1/",
    "CACHEURL": "http://metal3-metal3-ironic.metal3-system.svc.cluster.local:6185/images"
  }
}'

# Restart baremetal-operator
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=baremetal-operator
```

**Why**: The operator runs inside the cluster and should use the service URL, not the LoadBalancer IP.

---

### Solution 2: Trigger Provisioning

If the BMH is registered but not progressing, trigger provisioning:

```bash
# Annotate BMH to trigger provisioning
kubectl annotate baremetalhost metal3-node-0 -n metal3-system --overwrite provision.metal3.io=''

# Watch for state changes
kubectl get baremetalhost metal3-node-0 -n metal3-system -w
```

This will:
1. Power cycle the VM
2. Mount virtual media (IPA ISO)
3. Boot from virtual media
4. IPA will connect to Ironic

### Solution 2: Check Virtual Media Mount

Verify virtual media is being mounted:

```bash
# Check Redfish boot source
curl -u admin:admin http://192.168.1.242:8000/redfish/v1/Systems/721bcaa7-be3d-4d62-99a9-958bb212f2b7 | jq -r '.Boot'

# Should show:
# - BootSourceOverrideTarget: "Cd" or "Pxe"
# - BootSourceOverrideEnabled: "Once" or "Continuous"
```

### Solution 3: Force Power Cycle

If the VM is stuck, force a power cycle:

```bash
# Power off VM
virsh destroy metal3-node-0

# Power on via sushy-tools (Metal3 will handle this, but you can test)
curl -X POST -u admin:admin http://192.168.1.242:8000/redfish/v1/Systems/721bcaa7-be3d-4d62-99a9-958bb212f2b7/Actions/ComputerSystem.Reset -H "Content-Type: application/json" -d '{"ResetType": "On"}'
```

### Solution 4: Check Ironic Node State

If Ironic node exists but is stuck:

```bash
IRONIC_POD=$(kubectl get pods -n metal3-system -l app.kubernetes.io/component=ironic -o jsonpath='{.items[0].metadata.name}')

# Get node UUID from BMH status
NODE_UUID=$(kubectl get baremetalhost metal3-node-0 -n metal3-system -o jsonpath='{.status.provisioning.ID}')

# Check node state
kubectl exec -n metal3-system $IRONIC_POD -c ironic -- curl -s http://localhost:6385/v1/nodes/$NODE_UUID | jq -r '.provision_state, .power_state'

# If stuck, abort and reset
kubectl exec -n metal3-system $IRONIC_POD -c ironic -- curl -s -X PUT "http://localhost:6385/v1/nodes/${NODE_UUID}/states/provision" -H "Content-Type: application/json" -d '{"target": "abort"}'
kubectl exec -n metal3-system $IRONIC_POD -c ironic -- curl -s -X PUT "http://localhost:6385/v1/nodes/${NODE_UUID}/states/provision" -H "Content-Type: application/json" -d '{"target": "manageable"}'
```

### Solution 5: Delete and Recreate BMH

If all else fails:

```bash
# Delete BMH (this will clean up Ironic node)
kubectl delete baremetalhost metal3-node-0 -n metal3-system

# Wait for cleanup
sleep 10

# Recreate
kubectl apply -f baremetalhost.yaml
```

## Expected Behavior

When working correctly:

1. **Registration**: BMH registers with Ironic
   - State: `registering` → `inspecting` or `available`

2. **Inspection** (if enabled):
   - Ironic powers on VM
   - Mounts IPA ISO via virtual media
   - VM boots from ISO
   - IPA connects to Ironic
   - Hardware inspection runs
   - State: `inspecting` → `available`

3. **Provisioning** (when image is specified):
   - Ironic powers on VM
   - Mounts IPA ISO via virtual media
   - VM boots from ISO
   - IPA connects to Ironic
   - OS image is downloaded and written
   - State: `provisioning` → `provisioned`

## Console Output

### What You're Seeing (Wrong)
```
metal3-node-0 login: 
```
This is Ubuntu base OS - not IPA.

### What You Should See (Correct)
```
[  OK  ] Started Ironic Python Agent.
[  OK  ] Started Network Manager.
ironic-python-agent[848]: Connecting to Ironic at https://192.168.1.242:6385...
```
This is IPA booting and connecting to Ironic.

## Troubleshooting Checklist

- [ ] Is virtual media mounted? (Check Redfish Boot.BootSourceOverrideTarget)
- [ ] Is VM booting from virtual media? (Check console output)
- [ ] Is IPA connecting to Ironic? (Check IPA logs in console)
- [ ] Is port forwarding running? (`ps aux | grep "kubectl port-forward"`)
- [ ] Is Ironic accessible? (`curl -k https://192.168.1.242:6385/`)
- [ ] Is NetworkData configured? (`kubectl get secret provisioning-networkdata`)
- [ ] Is IPA_INSECURE set? (`kubectl get configmap ironic -o jsonpath='{.data.IPA_INSECURE}'`)

## Disk Space Cleanup

### Current Usage
- Total: ~2.4GB in `~/metal3-images/`
- Base image: 618MB (needed)
- VM disk: 801MB (needed)
- Storage pool: 978MB (might be from old setup)

### Cleanup Options

```bash
# Remove old storage pool (if not needed)
rm -rf ~/metal3-images/storage-pool

# Remove old cloud-init ISO (will be regenerated)
rm -f ~/metal3-images/metal3-node-0-cloud-init.iso

# Remove old VM disk (if recreating VM)
rm -f ~/metal3-images/metal3-node-0.qcow2

# Keep base image (needed for VM creation)
# ~/metal3-images/focal-server-cloudimg-amd64.img (618MB)
```

**Note**: Only 16GB free (93% used). Consider cleaning up other files if needed.

## Quick Fix Script

```bash
#!/bin/bash
set -e

echo "🔧 Fixing BMH state progression..."

# 1. Check if BMH exists
if ! kubectl get baremetalhost metal3-node-0 -n metal3-system &>/dev/null; then
    echo "BMH doesn't exist. Creating..."
    kubectl apply -f baremetalhost.yaml
    exit 0
fi

# 2. Trigger provisioning
echo "Triggering provisioning..."
kubectl annotate baremetalhost metal3-node-0 -n metal3-system --overwrite provision.metal3.io=''

# 3. Restart baremetal-operator to retry
echo "Restarting baremetal-operator..."
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=baremetal-operator

# 4. Watch for changes
echo "Watching BMH state (Ctrl+C to stop)..."
kubectl get baremetalhost metal3-node-0 -n metal3-system -w
```

## Summary

**Problem**: VM booting to Ubuntu instead of IPA, BMH state not progressing.

**Root Cause**: Virtual media (IPA ISO) not being used for boot.

**Solution**: Trigger provisioning to force IPA boot, or check why virtual media isn't mounting.

**Next Steps**: 
1. Annotate BMH to trigger provisioning
2. Watch console for IPA boot
3. Verify IPA connects to Ironic
4. BMH state should progress

