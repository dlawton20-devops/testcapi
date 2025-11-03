# Accessing Kind Cluster on OpenStack VM

This guide explains how to access your Kind cluster running on an OpenStack VM. You **don't need a Load Balancer VIP** - there are simpler options.

## 🎯 Current Setup

By default, Kind binds the Kubernetes API server to `127.0.0.1` (localhost), which means:
- ✅ Accessible from **within the VM** via `kubectl`
- ❌ **NOT accessible** from outside the VM directly

## 🔧 Option 1: SSH Port Forwarding (Recommended, No LB Needed)

This is the **simplest and most secure** method - no Load Balancer required!

### Setup SSH Port Forwarding

```bash
# Forward local port 6443 to VM's Kubernetes API
ssh -L 6443:localhost:6443 ubuntu@${VM_IP}

# Keep this SSH session open, then in another terminal:
export KUBECONFIG=/tmp/metal3-management-kubeconfig.yaml

# Use localhost instead of VM IP
kubectl --server=https://localhost:6443 get nodes
```

### Automated SSH Tunnel Script

Create a helper script to automate this:

```bash
# File: metal3-vm-setup/scripts/ssh-tunnel.sh
#!/bin/bash
VM_IP="${VM_IP:-192.168.1.100}"
VM_USER="${VM_USER:-ubuntu}"
SSH_KEY="${SSH_KEY:-~/.ssh/id_rsa}"

echo "Setting up SSH tunnel to Kind cluster..."
echo "Keep this terminal open. Use kubectl in another terminal."
echo ""

ssh -i "$SSH_KEY" \
    -L 6443:localhost:6443 \
    -N \
    "$VM_USER@$VM_IP"
```

Usage:
```bash
# Terminal 1: Start tunnel
./scripts/ssh-tunnel.sh

# Terminal 2: Use kubectl
export KUBECONFIG=/tmp/metal3-management-kubeconfig.yaml
kubectl --server=https://localhost:6443 get nodes
```

## 🔧 Option 2: Expose API Server on VM External IP (Simpler, No LB)

Modify the kind config to bind to `0.0.0.0` so it's accessible from outside:

### Update kind-config.yaml

```yaml
networking:
  apiServerAddress: "0.0.0.0"  # Changed from 127.0.0.1
  apiServerPort: 6443
```

### Add Port Mapping

```yaml
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 6443
        hostPort: 6443        # Expose Kubernetes API
        protocol: TCP
```

### Security Group Rule

```bash
# Allow Kubernetes API from outside
openstack security group rule create default \
  --protocol tcp --dst-port 6443 --remote-ip 0.0.0.0/0
```

### Access

```bash
# Get kubeconfig from VM
ssh ubuntu@${VM_IP} "kind get kubeconfig --name metal3-management" > /tmp/kubeconfig.yaml

# Update server URL in kubeconfig to use VM IP
sed -i.bak "s|server: https://.*:6443|server: https://${VM_IP}:6443|" /tmp/kubeconfig.yaml

# Use it
export KUBECONFIG=/tmp/kubeconfig.yaml
kubectl get nodes
```

## 🔧 Option 3: Use LoadBalancer (Overkill, Not Recommended)

If you really want a Load Balancer VIP (not necessary for Kind):

### Option 3a: MetalLB on Kind Cluster

This would require:
1. Installing MetalLB on the Kind cluster
2. Configuring an IP pool
3. Creating a LoadBalancer service for the API server

**Why not recommended:**
- Kind is a development/testing tool
- Adds complexity
- MetalLB requires specific network setup
- The API server is already accessible via other methods

### Option 3b: OpenStack Load Balancer

Create an OpenStack Load Balancer:
```bash
# Create load balancer
openstack loadbalancer create --name metal3-api-lb --vip-subnet-id <subnet-id>

# Create listener
openstack loadbalancer listener create \
  --protocol TCP \
  --protocol-port 6443 \
  metal3-api-lb

# Create pool
openstack loadbalancer pool create \
  --lb-algorithm ROUND_ROBIN \
  --protocol TCP \
  --listener metal3-api-lb \
  metal3-api-pool

# Add VM as member
openstack loadbalancer member create \
  --address ${VM_IP} \
  --protocol-port 6443 \
  metal3-api-pool
```

**Why not recommended:**
- Overkill for a single-node kind cluster
- Adds cost and complexity
- SSH port forwarding is simpler and free

## ✅ Recommended Approach

**For most use cases, use Option 1 (SSH Port Forwarding):**

1. ✅ **Simple** - No configuration changes needed
2. ✅ **Secure** - Traffic encrypted through SSH
3. ✅ **No LB needed** - Works immediately
4. ✅ **No firewall changes** - Uses existing SSH access

**For automated/CI use cases, use Option 2 (Expose on VM IP):**

1. ✅ **Direct access** - No SSH tunnel needed
2. ✅ **Simple** - Just update kind config
3. ✅ **Works with automation** - CI/CD can access directly

## 📝 Updated Setup Script

The setup script already handles getting the kubeconfig. You just need to choose your access method:

### Method 1: SSH Port Forwarding

```bash
# Run setup
export VM_IP="192.168.1.100"
./setup.sh

# In one terminal, start tunnel
ssh -L 6443:localhost:6443 ubuntu@${VM_IP}

# In another terminal, use kubectl
export KUBECONFIG=/tmp/metal3-management-kubeconfig.yaml
kubectl --server=https://localhost:6443 get nodes
```

### Method 2: Direct Access

```bash
# Update kind-config.yaml to use 0.0.0.0
# Then run setup
export VM_IP="192.168.1.100"
./setup.sh

# Update kubeconfig server URL
sed -i.bak "s|server: https://.*:6443|server: https://${VM_IP}:6443|" /tmp/metal3-management-kubeconfig.yaml

# Use kubectl
export KUBECONFIG=/tmp/metal3-management-kubeconfig.yaml
kubectl get nodes
```

## 🔒 Security Considerations

### SSH Port Forwarding (Option 1)
- ✅ **Most secure** - All traffic encrypted
- ✅ **No exposed ports** - API server stays on localhost
- ✅ **Uses existing SSH access** - No additional firewall rules

### Direct Access (Option 2)
- ⚠️ **Less secure** - API server exposed on network
- ⚠️ **Requires TLS** - Ensure certificates are valid
- ⚠️ **Firewall rules** - Need security group configured
- ✅ **Convenient** - Direct access without SSH

### Load Balancer (Option 3)
- ⚠️ **More complex** - Additional infrastructure
- ⚠️ **Cost** - Load balancer costs money
- ⚠️ **Overkill** - Not needed for single VM

## 🎯 Multi-Cluster Scenarios

### Scenario 1: Kind Cluster Runs Everything (Current Setup)

In this setup, the Kind cluster on the VM IS the management cluster:
- ✅ Kind cluster runs Rancher, Turtles, and Metal3
- ✅ Simulators are on the same VM
- ✅ Everything is self-contained

**Access from local machine:**
- Use SSH port forwarding (Option 1) or direct access (Option 2)

### Scenario 2: External Rancher Cluster Managing Kind Cluster

If you have a **separate Rancher cluster** that needs to import/manage the Kind cluster:

**Requirements:**
- ✅ Kind API server must be accessible from Rancher cluster network
- ✅ Load Balancer or exposed endpoint needed
- ✅ Network connectivity between clusters

**Setup:**

1. **Expose Kind API Server:**

```bash
# Edit kind-config.yaml
networking:
  apiServerAddress: "0.0.0.0"  # Allow external access
  apiServerPort: 6443

# Add port mapping
extraPortMappings:
  - containerPort: 6443
    hostPort: 6443
    protocol: TCP
```

2. **Configure Security Group:**

```bash
# Allow access from Rancher cluster network
openstack security group rule create default \
  --protocol tcp --dst-port 6443 \
  --remote-ip <RANCHER_CLUSTER_NETWORK_CIDR>
```

3. **Get kubeconfig for Rancher:**

```bash
# Get kubeconfig from VM
ssh ubuntu@${VM_IP} "kind get kubeconfig --name metal3-management" > /tmp/kind-kubeconfig.yaml

# Update server URL to use VM's external IP
sed -i.bak "s|server: https://.*:6443|server: https://${VM_IP}:6443|" /tmp/kind-kubeconfig.yaml
```

4. **Import into Rancher:**

```bash
# From Rancher cluster, import the Kind cluster
# Option A: Via Rancher UI
# - Go to Clusters -> Import
# - Copy the import command
# - Run on Kind cluster

# Option B: Via kubectl
kubectl --kubeconfig=/tmp/kind-kubeconfig.yaml apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cattle-import
  namespace: cattle-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cattle-import
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: cattle-import
  namespace: cattle-system
EOF
```

### Scenario 3: Load Balancer for Rancher Access

If the Rancher cluster is in a different network and needs reliable access:

**Option A: OpenStack Load Balancer**

```bash
# Create load balancer
openstack loadbalancer create \
  --name kind-api-lb \
  --vip-subnet-id <subnet-id>

# Create listener
openstack loadbalancer listener create \
  --protocol TCP \
  --protocol-port 6443 \
  kind-api-lb

# Create pool
openstack loadbalancer pool create \
  --lb-algorithm ROUND_ROBIN \
  --protocol TCP \
  --listener kind-api-lb \
  kind-api-pool

# Add VM as member
openstack loadbalancer member create \
  --address ${VM_IP} \
  --protocol-port 6443 \
  kind-api-pool

# Get VIP
LB_VIP=$(openstack loadbalancer show kind-api-lb -f value -c vip_address)
echo "Load Balancer VIP: $LB_VIP"
```

**Option B: MetalLB on Kind Cluster (If Kind runs MetalLB)**

```yaml
# Create LoadBalancer service for API server
apiVersion: v1
kind: Service
metadata:
  name: kind-api-loadbalancer
  namespace: default
spec:
  type: LoadBalancer
  ports:
  - port: 6443
    targetPort: 6443
    protocol: TCP
  selector:
    # This would need to target the API server pod
```

## 🎯 Summary

**For local access:**
- ✅ SSH port forwarding (Option 1) - No LB needed
- ✅ Direct access (Option 2) - No LB needed

**For external Rancher cluster:**
- ✅ Expose API server on VM IP (Option 2) - Simple, no LB
- ⚠️ Load Balancer (Option 3) - Only if network separation requires it

**Recommended:**
- **Same network/cluster**: Direct access (Option 2)
- **Different networks**: Load Balancer or VPN
- **Local development**: SSH port forwarding (Option 1)

## 📚 Additional Resources

- [Kind Documentation - Accessing Clusters](https://kind.sigs.k8s.io/docs/user/quick-start/#accessing-your-cluster)
- [SSH Port Forwarding Guide](https://www.ssh.com/academy/ssh/tunneling/example)

