# Next Steps to Get BareMetalHost Online

## 1. Set Up Bridge Network Port Forwarding

First, run the bridge forwarding setup script:

```bash
./setup-bridge-forwarding.sh
```

This will:
- Start the bridge network
- Set up port forwarding from bridge network to NodePort
- Update Ironic external URL
- Restart Ironic pod

## 2. Verify Bridge Network is Active

```bash
virsh net-list --all
```

Should show `metal3-net` as active.

## 3. Update VM to Use Bridge Network

If your VM is still using user-mode networking, you need to update it:

```bash
# Destroy and undefine existing VM
virsh destroy metal3-node-0 2>/dev/null || true
virsh undefine metal3-node-0 2>/dev/null || true

# Recreate VM with bridge network (use continue-setup.sh or complete-metal3-setup.sh)
./continue-setup.sh
```

Or manually update the VM network:

```bash
virsh edit metal3-node-0
```

Change the interface from:
```xml
<interface type='user'>
  <mac address='...'/>
  <model type='virtio'/>
</interface>
```

To:
```xml
<interface type='network'>
  <source network='metal3-net'/>
  <mac address='...'/>
  <model type='virtio'/>
</interface>
```

## 4. Update VM Network Configuration

The VM needs static IP configuration for the bridge network. Update cloud-init:

```bash
# Edit the cloud-init user-data
nano ~/metal3-images/cloud-init/user-data
```

Change network configuration to:
```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses:
        - 192.168.124.100/24
      gateway4: 192.168.124.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
```

Then recreate the cloud-init ISO and restart the VM.

## 5. Verify NetworkData Secret

Make sure the NetworkData secret matches the bridge network:

```bash
kubectl get secret provisioning-networkdata -n metal3-system -o jsonpath='{.data.networkData}' | base64 -d
```

Should show:
```yaml
version: 2
ethernets:
  eth0:
    dhcp4: false
    addresses:
      - 192.168.124.100/24
    gateway4: 192.168.124.1
    nameservers:
      addresses:
        - 8.8.8.8
        - 8.8.4.4
```

If not, update it:
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
          - 192.168.124.100/24
        gateway4: 192.168.124.1
        nameservers:
          addresses:
            - 8.8.8.8
            - 8.8.4.4
EOF
```

## 6. Verify VM is on Bridge Network

```bash
# Check VM status
virsh list --all

# Check VM IP (should be 192.168.124.100)
virsh domifaddr metal3-node-0

# Check VM console
virsh console metal3-node-0
```

## 7. Verify Ironic Configuration

```bash
# Check Ironic external URL
kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_EXTERNAL_HTTP_URL}'
# Should show: https://192.168.124.1:6385

# Check IPA_INSECURE
kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IPA_INSECURE}'
# Should show: 1
```

## 8. Test Connectivity from VM

If VM is running, test Ironic connectivity:

```bash
# SSH into VM (if accessible)
ssh ubuntu@192.168.124.100

# From inside VM, test Ironic
curl -k https://192.168.124.1:6385/
```

## 9. Check BareMetalHost Status

```bash
# Watch BareMetalHost status
kubectl get baremetalhost -n metal3-system -w

# Get detailed status
kubectl get baremetalhost metal3-node-0 -n metal3-system -o yaml

# Check events
kubectl describe baremetalhost metal3-node-0 -n metal3-system
```

## 10. Monitor Provisioning

Watch for the BareMetalHost to progress through states:
- `registering` → `inspecting` → `available` → `provisioning` → `provisioned`

```bash
# Watch status
kubectl get baremetalhost -n metal3-system -w

# Check Ironic logs
kubectl logs -n metal3-system -l app.kubernetes.io/component=ironic -c ironic -f

# Check baremetal operator logs
kubectl logs -n metal3-system -l app.kubernetes.io/component=baremetal-operator -f
```

## Troubleshooting

### VM Can't Reach Ironic

1. **Check port forwarding is running**:
   ```bash
   ps aux | grep socat | grep 6385
   ```

2. **Check bridge network is active**:
   ```bash
   virsh net-list --all
   ```

3. **Test from host**:
   ```bash
   curl -k https://192.168.124.1:6385/
   ```

4. **Check VM IP**:
   ```bash
   virsh domifaddr metal3-node-0
   ```

### BareMetalHost Stuck

1. **Check Ironic node status**:
   ```bash
   kubectl get ironicnode -n metal3-system
   ```

2. **Check VM console** for IPA errors:
   ```bash
   virsh console metal3-node-0
   ```

3. **Retrigger inspection/provisioning**:
   ```bash
   kubectl annotate baremetalhost metal3-node-0 -n metal3-system --overwrite inspect.metal3.io=''
   kubectl annotate baremetalhost metal3-node-0 -n metal3-system --overwrite provision.metal3.io=''
   ```

### Port Forwarding Stopped

If the socat process dies, restart it:

```bash
# Get NodePort
NODE_PORT=$(kubectl get svc metal3-metal3-ironic -n metal3-system -o jsonpath='{.spec.ports[0].nodePort}')

# Restart port forwarding
sudo socat TCP-LISTEN:6385,bind=192.168.124.1,fork,reuseaddr TCP:localhost:$NODE_PORT > /tmp/socat-ironic-bridge.log 2>&1 &
echo $! > /tmp/socat-ironic-bridge.pid
```

## Quick Checklist

- [ ] Bridge network is active (`virsh net-list`)
- [ ] Port forwarding is running (`ps aux | grep socat`)
- [ ] VM is on bridge network (`virsh domifaddr metal3-node-0`)
- [ ] VM has static IP 192.168.124.100
- [ ] Ironic URL is https://192.168.124.1:6385
- [ ] NetworkData secret matches bridge network
- [ ] BareMetalHost exists and is online
- [ ] sushy-tools is running

Once all these are in place, the BareMetalHost should be able to provision!

