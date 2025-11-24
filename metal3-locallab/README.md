# Metal3 Setup on macOS

This repository contains scripts to set up Metal3 with SUSE Edge Helm chart on macOS, including libvirt VMs as bare metal hosts.

## Prerequisites

- macOS with Homebrew
- Docker Desktop or Rancher Desktop (for Kubernetes)
- QEMU and libvirt installed via Homebrew
- kubectl, helm, and kind installed

## Quick Start

### 1. Clean Up Old Resources (Optional)

If you want to free up space from old clusters and containers:

```bash
./cleanup.sh
```

**Note:** Docker must be running for the cleanup script to clean Docker resources. Start Docker Desktop or Rancher Desktop first if needed.

### 2. Start Docker/Rancher Desktop

Make sure Docker Desktop or Rancher Desktop is running before proceeding.

### 3. Set Up Metal3

Run the setup script to:
- Create a kind Kubernetes cluster
- Install Metal3 using SUSE Edge Helm chart

```bash
./setup-metal3.sh
```

This will:
- Create a `kind-metal3-management` cluster
- Add the SUSE Edge Helm repository
- Install Metal3 in the `metal3-system` namespace
- Wait for all pods to be ready

### 4. Set Up sushy-tools (BMC Emulator)

sushy-tools provides Redfish BMC emulation for the libvirt VMs:

```bash
./setup-sushy-tools.sh
```

This will:
- Install sushy-tools via pip
- Create configuration files
- Set up a launchd service (macOS) or systemd service (Linux)
- Configure it to work with libvirt

Start sushy-tools:
```bash
# macOS (using launchd)
launchctl load ~/Library/LaunchAgents/com.metal3.sushy-emulator.plist

# Or run manually for testing
~/metal3-sushy/start-sushy.sh
```

### 5. Create Bare Metal Host

Create a libvirt VM with Ubuntu Focal (20.04) and register it as a BareMetalHost:

```bash
./create-baremetal-host.sh
```

This will:
- Download Ubuntu Focal cloud image (if not already present)
- Create a libvirt VM with the image
- Configure cloud-init for SSH access
- Connect to sushy-tools to register the VM
- Create a BareMetalHost resource in Kubernetes pointing to sushy-tools
- Start the VM

## Manual Steps

### Check Metal3 Status

```bash
# Check Metal3 pods
kubectl get pods -n metal3-system

# Check BareMetalHosts
kubectl get baremetalhost -n metal3-system

# Get detailed BareMetalHost info
kubectl get baremetalhost -n metal3-system -o yaml
```

### Check Libvirt VMs

```bash
# List all VMs
virsh list --all

# Get VM details
virsh dominfo metal3-node-0

# Get VM IP address
virsh domifaddr metal3-node-0
```

### Access the VM

The VM is configured with:
- Username: `ubuntu`
- Password: `ubuntu`
- SSH key: Your `~/.ssh/id_rsa.pub` (if it exists)

```bash
# Get VM IP
VM_IP=$(virsh domifaddr metal3-node-0 | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" | head -1)

# SSH into the VM
ssh ubuntu@$VM_IP
```

## Troubleshooting

For comprehensive troubleshooting guidance, see the [SUSE Edge Troubleshooting Documentation](https://documentation.suse.com/suse-edge/3.3/html/edge/troubleshooting-directed-network-provisioning.html).

### Common Issues

#### Docker Not Running

If you see "Cannot connect to the Docker daemon", start Docker Desktop or Rancher Desktop first.

#### sushy-tools Not Running

Check if sushy-tools is running:
```bash
curl -u admin:admin http://localhost:8000/redfish/v1
```

If not running:
```bash
# Check logs
tail -f ~/metal3-sushy/sushy.log

# Start manually
~/metal3-sushy/start-sushy.sh
```

#### BMC Communication Issues

Ensure Metal3 pods can reach sushy-tools. For kind clusters, you may need to:
- Use `host.docker.internal` or the host IP in the BMC address
- Ensure sushy-tools is listening on `0.0.0.0` (not just `127.0.0.1`)

#### BareMetalHost Stuck in Wrong State

Check the BareMetalHost status:
```bash
kubectl get bmh -n metal3-system
kubectl describe bmh -n metal3-system <bmh-name>
kubectl get bmh -n metal3-system <bmh-name> -o jsonpath='{.status}' | jq
```

Common states:
- `registering` - Host is being registered
- `inspecting` - Hardware inspection in progress
- `available` - Ready for provisioning
- `provisioning` - OS installation in progress
- `provisioned` - Successfully provisioned
- `error` - Error occurred (check status for details)

#### Retrigger Inspection

If inspection failed or hardware changed:
```bash
kubectl annotate bmh/<bmh-name> -n metal3-system inspect.metal3.io=""
```

#### Metal3 Pods Not Ready

Check pod logs:
```bash
# Baremetal operator
kubectl logs -n metal3-system -l app.kubernetes.io/component=baremetal-operator

# Ironic (check all containers)
kubectl logs -n metal3-system -l app.kubernetes.io/component=ironic -c ironic
kubectl logs -n metal3-system -l app.kubernetes.io/component=ironic -c ironic-httpd
kubectl logs -n metal3-system -l app.kubernetes.io/component=ironic -c ironic-log-watch

# Describe pods for events
kubectl describe pod -n metal3-system <pod-name>
```

#### Ironic Endpoint Not Reachable

Verify the Ironic service is accessible:
```bash
IRONIC_IP=$(kubectl get svc -n metal3-system metal3-metal3-ironic -o jsonpath='{.spec.clusterIP}')
IRONIC_PORT=$(kubectl get svc -n metal3-system metal3-metal3-ironic -o jsonpath='{.spec.ports[0].port}')

# Test from a pod
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl http://${IRONIC_IP}:${IRONIC_PORT}
```

#### Libvirt Network Issues

If the VM can't get an IP address:
```bash
# List networks
virsh net-list --all

# Start default network if not running
virsh net-start default
virsh net-autostart default

# Check network status
virsh net-info default
```

#### VM Not Starting

Check libvirt:
```bash
virsh dominfo metal3-node-0
virsh list --all

# On macOS, check libvirt service
brew services list | grep libvirt
```

#### SSL/TLS Certificate Issues

If you see SSL errors during provisioning:
- Metal3 may need additional CA certificates injected into the IPA image
- See the [SUSE Edge documentation](https://documentation.suse.com/suse-edge/3.3/html/edge/troubleshooting-directed-network-provisioning.html) for details on adding `ca-additional.crt`

#### Cleaning Process Stuck

If cleaning is stuck, disable it:
```bash
kubectl patch bmh <bmh-name> -n metal3-system --type merge -p '{"spec":{"automatedCleaning":false}}'
```

**Warning:** Don't manually remove finalizers as this can leave the host in Ironic but removed from Kubernetes.

#### Enable IPA Console Access (Debug)

To enable autologin on IPA console for debugging:
```bash
# Edit the ironic-bmo configmap
kubectl edit configmap ironic-bmo -n metal3-system

# Add to IRONIC_KERNEL_PARAMS: console=ttyS0 suse.autologin=ttyS0
# Then restart ironic pod
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
```

**Warning:** This is for debugging only and gives full access to the host.

## Clean Up

To remove everything:

```bash
# Delete the kind cluster
kind delete cluster --name metal3-management

# Delete libvirt VMs
virsh destroy metal3-node-0
virsh undefine metal3-node-0

# Remove images (optional, frees disk space)
rm -rf ~/metal3-images

# Run full cleanup
./cleanup.sh
```

## Notes

- **KVM on macOS**: macOS doesn't support KVM (Linux-specific). This setup uses QEMU with libvirt, which works on macOS using Hypervisor.framework.
- **BMC Emulation**: The BareMetalHost uses a Redfish BMC address. For a full Metal3 setup, you may need to set up BMC emulation (e.g., using sushy-emulator or similar).
- **Network**: The VM uses the default libvirt network. Make sure it's running.
- **Disk Space**: Ubuntu Focal image is ~500MB, and the VM disk can grow to 20GB.

## Troubleshooting Script

Run the troubleshooting helper script for a quick health check:

```bash
./troubleshoot.sh
```

This will check:
- Cluster connectivity
- Metal3 pod status
- BareMetalHost status
- sushy-tools availability
- Ironic service
- Libvirt VMs
- Recent events

## References

- [Metal3 Developer Environment](https://book.metal3.io/developer_environment/tryit)
- [SUSE Edge Metal3 Quickstart](https://documentation.suse.com/suse-edge/3.3/html/edge/quickstart-metal3.html)
- [SUSE Edge Troubleshooting Directed-Network Provisioning](https://documentation.suse.com/suse-edge/3.3/html/edge/troubleshooting-directed-network-provisioning.html)

