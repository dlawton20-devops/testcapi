# Integrating Kind Cluster with External Rancher Cluster

This guide explains how to integrate the Kind cluster on your OpenStack VM with an external Rancher cluster that's running Rancher Turtles and Metal3.

## 🏗️ Architecture

```
┌─────────────────────────────────────────┐
│  External Rancher Cluster               │
│  ├── Rancher UI                         │
│  ├── Rancher Turtles                    │
│  └── Metal3 (Management)                │
└─────────────────────────────────────────┘
              ↓ (Manages)
┌─────────────────────────────────────────┐
│  OpenStack VM                           │
│  ├── Kind Cluster (Target)              │
│  │   └── Managed by Rancher            │
│  └── Redfish Simulators                 │
└─────────────────────────────────────────┘
```

## 🔧 Prerequisites

1. **Rancher cluster** running and accessible (with Rancher Turtles and Metal3)
2. **Kind cluster** on VM with API server exposed
3. **Network connectivity** between Rancher cluster and VM
4. **Security groups** configured to allow:
   - Port 6443 (Kubernetes API) from Rancher cluster
   - Ports 8000-8002 (Redfish simulators) from Rancher cluster

## 📋 Step-by-Step Setup

### Step 1: Expose Kind API Server

The Kind cluster API server must be accessible from the Rancher cluster network.

#### Option A: Expose on VM External IP (Recommended)

```bash
# 1. Edit kind-config.yaml
cat > kind-config.yaml <<EOF
networking:
  apiServerAddress: "0.0.0.0"  # Allow external access
  apiServerPort: 6443
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 6443
        hostPort: 6443        # Expose Kubernetes API
        protocol: TCP
EOF

# 2. Recreate cluster with new config
ssh ubuntu@${VM_IP} << 'ENDSSH'
kind delete cluster --name metal3-management
kind create cluster --name metal3-management --config /tmp/metal3-setup/kind-config.yaml
ENDSSH

# 3. Configure security group (Kubernetes API + Redfish Simulators)
RANCHER_NETWORK="<RANCHER_CLUSTER_NETWORK_CIDR>"

# Kubernetes API
openstack security group rule create default \
  --protocol tcp --dst-port 6443 \
  --remote-ip "$RANCHER_NETWORK"

# Redfish Simulators (for Metal3/Ironic)
for port in 8000 8001 8002; do
    openstack security group rule create default \
      --protocol tcp --dst-port $port \
      --remote-ip "$RANCHER_NETWORK"
done
```

#### Option B: Use Load Balancer

```bash
# Create OpenStack Load Balancer
openstack loadbalancer create \
  --name kind-api-lb \
  --vip-subnet-id <subnet-id>

# Configure listener and pool
openstack loadbalancer listener create \
  --protocol TCP --protocol-port 6443 \
  kind-api-lb

openstack loadbalancer pool create \
  --lb-algorithm ROUND_ROBIN --protocol TCP \
  --listener kind-api-lb kind-api-pool

# Add VM as member
openstack loadbalancer member create \
  --address ${VM_IP} --protocol-port 6443 \
  kind-api-pool

# Get VIP
LB_VIP=$(openstack loadbalancer show kind-api-lb -f value -c vip_address)
```

### Step 2: Get Kind Cluster Kubeconfig

```bash
# Get kubeconfig from VM
ssh ubuntu@${VM_IP} "kind get kubeconfig --name metal3-management" > /tmp/kind-kubeconfig.yaml

# Update server URL to use accessible endpoint
# If using direct VM IP:
sed -i.bak "s|server: https://.*:6443|server: https://${VM_IP}:6443|" /tmp/kind-kubeconfig.yaml

# If using Load Balancer:
sed -i.bak "s|server: https://.*:6443|server: https://${LB_VIP}:6443|" /tmp/kind-kubeconfig.yaml
```

### Step 3: Verify Connectivity from Rancher Cluster

```bash
# From a pod in the Rancher cluster, test connectivity
kubectl run -it --rm test-connectivity \
  --image=curlimages/curl \
  --restart=Never \
  -- curl -k https://${VM_IP}:6443/healthz

# Or test from Rancher cluster node
kubectl --kubeconfig=/tmp/kind-kubeconfig.yaml get nodes
```

### Step 4: Import Cluster into Rancher

#### Method A: Via Rancher UI

1. **Access Rancher UI**: Navigate to your Rancher cluster UI
2. **Import Cluster**: Go to "Clusters" → "Import Existing"
3. **Get Import Command**: Copy the kubectl command provided
4. **Run on Kind Cluster**: Execute the command on the Kind cluster

```bash
# Example import command (your actual command will be different)
kubectl --kubeconfig=/tmp/kind-kubeconfig.yaml apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: cattle-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cattle-import
  namespace: cattle-system
---
# ... rest of import manifest from Rancher UI
EOF
```

#### Method B: Via Rancher API

```bash
# Get Rancher API token
RANCHER_URL="https://rancher.example.com"
RANCHER_TOKEN="your-api-token"

# Create cluster import
curl -X POST \
  -H "Authorization: Bearer $RANCHER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "cluster",
    "name": "kind-metal3-management",
    "kubeconfig": "'$(cat /tmp/kind-kubeconfig.yaml | base64 -w 0)'"
  }' \
  "$RANCHER_URL/v3/clusters"
```

#### Method C: Via Rancher Turtles (CAPI Integration)

If using Rancher Turtles, you can create a Cluster resource that Rancher will discover:

```bash
# Create cluster in Rancher cluster (if Rancher Turtles is configured)
kubectl apply -f - <<EOF
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: kind-metal3-management
  namespace: default
  labels:
    management.cattle.io/cluster-display-name: kind-metal3-management
spec:
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: KubeadmControlPlane
    name: kind-metal3-management-control-plane
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: DockerCluster
    name: kind-metal3-management
EOF
```

### Step 5: Verify Integration

```bash
# Check cluster in Rancher UI
# Navigate to: Clusters → kind-metal3-management

# Verify from Rancher cluster
kubectl get clusters -A

# Check cluster status
kubectl get cluster kind-metal3-management -o yaml
```

## 🔍 Troubleshooting

### Cannot Connect from Rancher Cluster

```bash
# 1. Verify network connectivity
kubectl run -it --rm test-net \
  --image=nicolaka/netshoot \
  --restart=Never \
  -- nc -zv ${VM_IP} 6443

# 2. Check security groups
openstack security group rule list default

# 3. Verify API server is listening
ssh ubuntu@${VM_IP} "sudo netstat -tlnp | grep 6443"

# 4. Check firewall on VM
ssh ubuntu@${VM_IP} "sudo ufw status"
```

### Certificate Issues

```bash
# If you see certificate errors, verify the certificate
openssl s_client -connect ${VM_IP}:6443 -showcerts

# Update kubeconfig to skip verification (NOT for production)
kubectl --kubeconfig=/tmp/kind-kubeconfig.yaml \
  --insecure-skip-tls-verify get nodes
```

### Load Balancer Not Working

```bash
# Check load balancer status
openstack loadbalancer show kind-api-lb

# Check pool members
openstack loadbalancer member list kind-api-pool

# Check listener
openstack loadbalancer listener show <listener-id>

# Test VIP
curl -k https://${LB_VIP}:6443/healthz
```

## 🎯 Alternative: Run Rancher on Kind Cluster

If you prefer to have everything on the VM:

**Architecture:**
```
OpenStack VM
├── Kind Cluster
│   ├── Rancher
│   ├── Rancher Turtles
│   └── Metal3
└── Redfish Simulators
```

In this case, you access Rancher UI directly (no cluster import needed). See `rancher-metal3-simulator-guide.md` for this setup.

## 📝 Summary

**For External Rancher Cluster:**
1. ✅ Expose Kind API server (VM IP or Load Balancer)
2. ✅ Configure security groups
3. ✅ Get kubeconfig
4. ✅ Import into Rancher (UI, API, or Turtles)

**Network Requirements:**
- Rancher cluster → Kind cluster: TCP 6443
- Security group rules configured
- DNS resolution (if using hostnames)

**Access Methods:**
- **Direct VM IP**: Simple, no LB needed (if same network)
- **Load Balancer**: For production, high availability, or network separation
- **VPN**: For secure network connectivity

See `CLUSTER-ACCESS.md` for more details on exposing the API server.

