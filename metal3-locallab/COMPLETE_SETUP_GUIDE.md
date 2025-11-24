# Complete Metal3 Setup Guide

This guide explains how to use the `complete-metal3-setup.sh` script to set up a complete Metal3 environment with a kind cluster, SUSE Edge Helm chart, and a KVM/libvirt node with all IPA fixes applied.

## What the Script Does

The `complete-metal3-setup.sh` script performs a complete end-to-end setup:

1. **Creates a kind cluster** (`metal3-management`)
2. **Installs MetalLB** for LoadBalancer support
3. **Installs cert-manager** (required by Metal3)
4. **Installs Metal3** using SUSE Edge Helm chart
5. **Configures IPA fixes**:
   - Sets `IPA_INSECURE=1` to accept self-signed certificates
   - Sets `IRONIC_EXTERNAL_HTTP_URL` to host IP for VM accessibility
   - Enables console autologin for debugging
6. **Creates NetworkData secret** for IPA static IP configuration
7. **Sets up port forwarding** (kubectl port-forward + socat) for Ironic service
8. **Checks/sets up sushy-tools** for BMC emulation
9. **Creates libvirt VM** with:
   - Network boot support (PXE)
   - Static IP configuration (10.0.2.100/24)
   - Cloud-init for initial setup
10. **Creates BareMetalHost** resource with all proper configurations

## Prerequisites

- macOS with Homebrew (or Linux with appropriate package manager)
- Docker Desktop or Rancher Desktop running
- kubectl, helm, kind installed
- QEMU and libvirt installed
- Python 3 (for sushy-tools)

## Quick Start

```bash
# Make sure Docker is running first!
# Then run the setup script:
./complete-metal3-setup.sh
```

The script will:
- Take approximately 10-15 minutes to complete
- Create all necessary resources
- Set up port forwarding in the background
- Create and start the VM
- Register the BareMetalHost

## What Gets Created

### Kubernetes Resources

- **Namespace**: `metal3-system`
- **Metal3 components**: baremetal-operator, ironic, mariadb
- **ConfigMap**: `ironic` (with IPA fixes)
- **Secret**: `provisioning-networkdata` (for IPA network config)
- **BareMetalHost**: `metal3-node-0`
- **BMC Secret**: `metal3-node-0-bmc-secret`

### VM Resources

- **VM Name**: `metal3-node-0`
- **VM Image**: `~/metal3-images/focal-server-cloudimg-amd64.img`
- **VM Disk**: `~/metal3-images/metal3-node-0.qcow2`
- **Network**: Uses libvirt `default` network
- **IP Address**: `10.0.2.100/24` (static)

### Port Forwarding

The script sets up two background processes:
1. **kubectl port-forward**: Forwards Ironic service (port 6185) to localhost:6385
2. **socat**: Forwards localhost:6385 to host IP:6385 (accessible from VM)

These processes run in the background and must stay running for IPA to connect.

## IPA Fixes Applied

### 1. Certificate Verification (`IPA_INSECURE=1`)

**Problem**: Ironic uses self-signed certificates, and IPA was rejecting connections.

**Solution**: Set `IPA_INSECURE=1` in Ironic ConfigMap to tell IPA to accept self-signed certificates.

### 2. Ironic External URL

**Problem**: Boot ISO contained LoadBalancer IP (`172.18.255.200`) which VM couldn't reach.

**Solution**: Set `IRONIC_EXTERNAL_HTTP_URL` to host IP (`192.168.1.242:6385`) which is accessible via port forwarding.

### 3. Network Configuration

**Problem**: VM needed static IP to reach Ironic via gateway.

**Solution**: Created `provisioning-networkdata` secret with static IP configuration (`10.0.2.100/24` with gateway `10.0.2.2`).

### 4. Port Forwarding

**Problem**: Ironic service is only accessible within Kubernetes cluster.

**Solution**: Set up two-stage port forwarding:
- `kubectl port-forward` exposes Ironic on localhost
- `socat` forwards from host IP to localhost

## Verification

After the script completes, verify everything is working:

### 1. Check Metal3 Pods

```bash
kubectl get pods -n metal3-system
```

All pods should be `Running` and `Ready`.

### 2. Check BareMetalHost Status

```bash
kubectl get baremetalhost -n metal3-system -w
```

Watch for the BareMetalHost to progress through states:
- `registering` → `inspecting` → `available` → `provisioning` → `provisioned`

### 3. Check Port Forwarding

```bash
# Check if processes are running
ps aux | grep "kubectl port-forward.*metal3-metal3-ironic"
ps aux | grep "socat.*6385"

# Test Ironic accessibility
curl -k https://localhost:6385/
curl -k https://192.168.1.242:6385/
```

### 4. Check VM Status

```bash
virsh list --all
virsh domifaddr metal3-node-0
```

### 5. Check VM Console

```bash
virsh console metal3-node-0
```

Press Enter to activate console. You should see IPA boot messages if provisioning is in progress.

## Troubleshooting

### Port Forwarding Stopped

If port forwarding processes die, restart them:

```bash
# Kill existing processes
pkill -f "kubectl port-forward.*metal3-metal3-ironic"
pkill -f "socat.*6385"

# Restart port forwarding
nohup kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6385:6185 > /tmp/ironic-port-forward.log 2>&1 &
nohup socat TCP-LISTEN:6385,fork,reuseaddr TCP:localhost:6385 > /tmp/socat-ironic.log 2>&1 &
```

### BareMetalHost Stuck

If the BareMetalHost is stuck in a state:

1. **Check Ironic logs**:
   ```bash
   kubectl logs -n metal3-system -l app.kubernetes.io/component=ironic -c ironic
   ```

2. **Check BareMetalHost events**:
   ```bash
   kubectl describe baremetalhost metal3-node-0 -n metal3-system
   ```

3. **Check VM console** for IPA errors:
   ```bash
   virsh console metal3-node-0
   ```

4. **Retrigger inspection/provisioning**:
   ```bash
   kubectl annotate baremetalhost metal3-node-0 -n metal3-system --overwrite inspect.metal3.io=''
   kubectl annotate baremetalhost metal3-node-0 -n metal3-system --overwrite provision.metal3.io=''
   ```

### VM Not Booting from Network

If the VM isn't booting from network:

1. **Check VM boot order**:
   ```bash
   virsh dumpxml metal3-node-0 | grep -A 5 "<os>"
   ```

2. **Verify network is active**:
   ```bash
   virsh net-list --all
   virsh net-start default  # if not active
   ```

3. **Check VM console** to see boot messages:
   ```bash
   virsh console metal3-node-0
   ```

### IPA Connection Errors

If IPA can't connect to Ironic:

1. **Verify port forwarding is running** (see above)

2. **Verify Ironic URL**:
   ```bash
   kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_EXTERNAL_HTTP_URL}'
   ```
   Should show: `https://<host-ip>:6385`

3. **Verify IPA_INSECURE is set**:
   ```bash
   kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IPA_INSECURE}'
   ```
   Should show: `1`

4. **Test connectivity from VM**:
   ```bash
   # SSH into VM (if accessible)
   ssh ubuntu@10.0.2.100
   
   # From inside VM, test Ironic connection
   curl -k https://192.168.1.242:6385/
   ```

### sushy-tools Not Running

If sushy-tools is not accessible:

```bash
# Check if running
curl -u admin:admin http://localhost:8000/redfish/v1

# If not running, start it
if [ -f "$HOME/metal3-sushy/start-sushy.sh" ]; then
    nohup "$HOME/metal3-sushy/start-sushy.sh" > "$HOME/metal3-sushy/sushy.log" 2>&1 &
fi
```

## Clean Up

To remove everything:

```bash
# Stop port forwarding
pkill -f "kubectl port-forward.*metal3-metal3-ironic"
pkill -f "socat.*6385"

# Delete kind cluster
kind delete cluster --name metal3-management

# Delete VM
virsh destroy metal3-node-0
virsh undefine metal3-node-0

# Remove VM disk (optional)
rm -rf ~/metal3-images
```

## Next Steps

Once the BareMetalHost is `provisioned`:

1. **Access the provisioned VM**:
   ```bash
   ssh ubuntu@10.0.2.100
   ```

2. **Check installed OS**:
   ```bash
   lsb_release -a
   ```

3. **Use the VM** for your workloads!

## References

- [SUSE Edge Metal3 Documentation](https://documentation.suse.com/suse-edge/3.3/html/edge/quickstart-metal3.html)
- [SUSE Edge Troubleshooting](https://documentation.suse.com/suse-edge/3.3/html/edge/troubleshooting-directed-network-provisioning.html)
- [Metal3 Documentation](https://metal3.io/documentation/)

