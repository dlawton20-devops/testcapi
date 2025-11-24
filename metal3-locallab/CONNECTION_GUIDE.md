# Connection Guide - Kubernetes Cluster and KVM VM

## Connecting to the Kubernetes Cluster

### 1. Check Current Context

```bash
kubectl config current-context
```

Should show: `kind-metal3-management`

### 2. Switch to Metal3 Cluster Context (if needed)

```bash
kubectl config use-context kind-metal3-management
```

### 3. Verify Cluster Access

```bash
# Check cluster info
kubectl cluster-info

# List nodes
kubectl get nodes

# List pods
kubectl get pods -A

# Check Metal3 resources
kubectl get bmh -n metal3-system
kubectl get pods -n metal3-system
```

### 4. Access Cluster Services

#### Ironic API (Metal3)
```bash
# Get Ironic service IP
IRONIC_IP=$(kubectl get svc -n metal3-system metal3-metal3-ironic -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Ironic VIP: $IRONIC_IP"

# Access Ironic API
curl http://${IRONIC_IP}:6185
```

#### Port Forwarding (Alternative)
```bash
# Forward Ironic API to localhost
kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6185:6185

# In another terminal
curl http://localhost:6185
```

### 5. View Logs

```bash
# Metal3 baremetal operator logs
kubectl logs -n metal3-system -l app.kubernetes.io/component=baremetal-operator

# Ironic logs
kubectl logs -n metal3-system -l app.kubernetes.io/component=ironic -c ironic

# All Metal3 logs
kubectl logs -n metal3-system --all-containers=true -l app.kubernetes.io/component=ironic
```

### 6. Execute Commands in Pods

```bash
# Get into a Metal3 pod
kubectl exec -it -n metal3-system <pod-name> -- /bin/bash

# Example: Ironic pod
IRONIC_POD=$(kubectl get pods -n metal3-system -l app.kubernetes.io/component=ironic -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it -n metal3-system $IRONIC_POD -c ironic -- /bin/bash
```

---

## Connecting to the KVM/libvirt VM

### 1. Check VM Status

```bash
# List all VMs
virsh list --all

# Get VM info
virsh dominfo metal3-node-0

# Check VM network interfaces
virsh domiflist metal3-node-0
```

### 2. Start the VM

```bash
# Start the VM
virsh start metal3-node-0

# Check if it's running
virsh list
```

### 3. Get VM IP Address

```bash
# Wait a few seconds for VM to boot, then get IP
virsh domifaddr metal3-node-0

# Or check via DHCP leases (macOS)
cat /var/lib/libvirt/dnsmasq/default.leases 2>/dev/null | grep 52:54:00:1c:28:07
```

### 4. Connect via SSH

Once you have the VM IP:

```bash
# Get VM IP
VM_IP=$(virsh domifaddr metal3-node-0 | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" | head -1)

# SSH into the VM
ssh ubuntu@$VM_IP
# Password: ubuntu
```

**Note**: The VM is configured with:
- Username: `ubuntu`
- Password: `ubuntu`
- SSH key: Your `~/.ssh/id_rsa.pub` (if it exists)

### 5. Connect via Console (Serial)

```bash
# Connect to VM console
virsh console metal3-node-0

# To exit console: Press Ctrl+] or Ctrl+5
```

### 6. Connect via VNC (if available)

```bash
# Get VNC display
virsh vncdisplay metal3-node-0

# Connect using VNC client
# Or use built-in macOS Screen Sharing
open vnc://localhost:$(virsh vncdisplay metal3-node-0 | cut -d: -f2)
```

### 7. Access VM via libvirt Tools

```bash
# Get VM XML configuration
virsh dumpxml metal3-node-0

# Edit VM configuration (be careful!)
virsh edit metal3-node-0

# View VM CPU/memory stats
virsh dominfo metal3-node-0

# View VM block devices
virsh domblklist metal3-node-0
```

### 8. Network Access

The VM should be on the libvirt network. To check:

```bash
# List networks
virsh net-list --all

# Get network info
virsh net-info default  # or metal3-net

# Get network DHCP info
virsh net-dhcp-leases default
```

---

## Quick Reference Commands

### Cluster Access
```bash
# Set context
kubectl config use-context kind-metal3-management

# Quick status check
kubectl get all -n metal3-system
kubectl get bmh -n metal3-system

# Port forward Ironic
kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6185:6185
```

### VM Access
```bash
# Start VM
virsh start metal3-node-0

# Get IP and SSH
VM_IP=$(virsh domifaddr metal3-node-0 | grep -oE "([0-9]{1,3}\.){3}[0-9]{1,3}" | head -1)
ssh ubuntu@$VM_IP

# Console access
virsh console metal3-node-0
```

---

## Troubleshooting

### Can't connect to cluster
```bash
# Check if cluster is running
docker ps | grep metal3-management

# Restart cluster if needed
kind delete cluster --name metal3-management
./setup-metal3.sh
```

### Can't connect to VM
```bash
# Check VM status
virsh list --all

# Check network
virsh net-list --all
virsh net-info default

# Start network if needed
sudo virsh net-start default
sudo virsh net-autostart default

# Check VM logs
virsh dumpxml metal3-node-0 | grep -A 5 console
```

### VM has no IP
```bash
# Check if cloud-init completed
virsh console metal3-node-0
# Login and check: cloud-init status

# Restart network in VM
virsh console metal3-node-0
# Then in VM: sudo systemctl restart networking
```

