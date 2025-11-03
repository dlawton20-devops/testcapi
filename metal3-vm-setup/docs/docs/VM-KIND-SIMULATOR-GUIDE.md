# Complete VM Setup: Kind Cluster + Redfish Simulators

This guide shows how to set up **everything on a single OpenStack VM**:
- ✅ Kind management cluster
- ✅ Redfish simulators (bare metal node simulation)
- ✅ All integrated and accessible

## 🎯 Architecture

```
┌─────────────────────────────────────────────────────────┐
│  OpenStack VM (Ubuntu/Debian)                           │
│                                                          │
│  ┌─────────────────────────────────────────────────────┐│
│  │  Kind Cluster (Management Cluster)                 ││
│  │  ├── Control Plane Node (kindest/node)             ││
│  │  ├── Worker Node 1                                  ││
│  │  └── Worker Node 2                                  ││
│  │                                                      ││
│  │  Runs:                                              ││
│  │  - Rancher                                          ││
│  │  - Metal3                                           ││
│  │  - CAPI                                             ││
│  └─────────────────────────────────────────────────────┘│
│                                                          │
│  ┌─────────────────────────────────────────────────────┐│
│  │  Redfish Simulators (Docker Containers)             ││
│  │  ├── redfish-sim-controlplane (port 8000)          ││
│  │  ├── redfish-sim-worker-0 (port 8001)             ││
│  │  └── redfish-sim-worker-1 (port 8002)             ││
│  │                                                      ││
│  │  Simulates bare metal nodes with BMC interfaces    ││
│  └─────────────────────────────────────────────────────┘│
│                                                          │
│  External IP: 192.168.1.100                             │
│  - Kubernetes API: 6443 (via port mapping)            │
│  - Redfish APIs: 8000, 8001, 8002                      │
└─────────────────────────────────────────────────────────┘
```

## 📋 Prerequisites

### OpenStack VM Requirements

- **VM Image**: Ubuntu 22.04+ or Debian 11+
- **VM Flavor**: Minimum 4 vCPU, 8GB RAM, 50GB disk (recommended: 8 vCPU, 16GB RAM)
- **Network**: VM must have external/floating IP
- **Security Group**: Must allow:
  - SSH (port 22) from your management machine
  - Kubernetes API (port 6443) - optional, for remote access
  - Redfish APIs (ports 8000, 8001, 8002) - from networks that need access

### Local Machine Requirements

- SSH access to OpenStack VM
- SSH key configured
- `curl` for testing

## 🚀 Quick Setup

### Step 1: Create OpenStack VM

```bash
# Create VM with adequate resources
openstack server create \
  --flavor m1.large \
  --image ubuntu-22.04 \
  --key-name your-ssh-key \
  --network private \
  --security-group default \
  --tag metal3-complete \
  metal3-vm

# Assign floating IP
FLOATING_IP=$(openstack floating ip create public -f value -c floating_ip_address)
openstack server add floating ip metal3-vm $FLOATING_IP

# Get VM IP
VM_IP=$(openstack server show metal3-vm -f value -c addresses | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
echo "VM IP: $VM_IP"
export VM_IP
```

### Step 2: Configure Security Group

```bash
# Allow SSH
openstack security group rule create default \
  --protocol tcp --dst-port 22 --remote-ip 0.0.0.0/0

# Allow Kubernetes API (optional, for remote kubectl access)
openstack security group rule create default \
  --protocol tcp --dst-port 6443 --remote-ip 0.0.0.0/0

# Allow Redfish simulator ports
for port in 8000 8001 8002; do
    openstack security group rule create default \
      --protocol tcp --dst-port $port --remote-ip 0.0.0.0/0
done
```

### Step 3: Run Complete Setup

```bash
# Set VM details
export VM_IP="192.168.1.100"  # Your VM's external IP
export VM_USER="ubuntu"        # Your VM user
export SSH_KEY="~/.ssh/id_rsa" # Your SSH key
export CLUSTER_NAME="metal3-management"

# Run complete setup script
cd metal3-capi-complete-setup
./scripts/setup-vm-with-kind-and-simulators.sh
```

The script will:
1. ✅ Install Docker, kubectl, kind, helm on VM
2. ✅ Create Kind cluster with 3 nodes
3. ✅ Build and run Redfish simulator containers
4. ✅ Configure networking
5. ✅ Output kubeconfig and BMC addresses

### Step 4: Access Your Cluster

```bash
# Use the kubeconfig saved by the script
export KUBECONFIG=/tmp/metal3-management-kubeconfig.yaml

# Verify cluster
kubectl get nodes
kubectl cluster-info

# Test from outside VM (if port 6443 is accessible)
kubectl --kubeconfig=/tmp/metal3-management-kubeconfig.yaml \
  --server=https://${VM_IP}:6443 get nodes
```

### Step 5: Verify Simulators

```bash
# Test simulators from your local machine
curl http://${VM_IP}:8000/redfish/v1/
curl http://${VM_IP}:8001/redfish/v1/
curl http://${VM_IP}:8002/redfish/v1/

# Test from within the cluster (SSH to VM first)
ssh ubuntu@${VM_IP}
kubectl run -it --rm test \
  --image=curlimages/curl \
  --restart=Never \
  -- curl http://localhost:8000/redfish/v1/
```

## 🔧 Manual Setup (Alternative)

If you prefer step-by-step manual setup:

### 1. SSH to VM and Install Dependencies

```bash
ssh ubuntu@${VM_IP}

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
sudo systemctl enable docker
sudo systemctl start docker

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Install helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Log out and back in for docker group to take effect
exit
ssh ubuntu@${VM_IP}
```

### 2. Create Kind Cluster

```bash
# Copy kind config to VM (from your local machine)
scp metal3-capi-complete-setup/kind-config.yaml ubuntu@${VM_IP}:/tmp/

# On VM, create cluster
ssh ubuntu@${VM_IP}
kind create cluster --name metal3-management --config /tmp/kind-config.yaml

# Verify
kubectl get nodes
```

### 3. Setup Redfish Simulators

```bash
# Copy simulator files to VM
scp metal3-capi-complete-setup/scripts/Dockerfile.redfish-simulator ubuntu@${VM_IP}:/tmp/
scp metal3-capi-complete-setup/scripts/redfish-simulator.py ubuntu@${VM_IP}:/tmp/

# On VM, build and run
ssh ubuntu@${VM_IP}
cd /tmp
docker build -f Dockerfile.redfish-simulator -t redfish-simulator:latest .

# Get kind network
KIND_NETWORK=$(docker network ls | grep kind | awk '{print $1}' | head -1)

# Create simulators
docker run -d \
  --name redfish-sim-controlplane \
  --network $KIND_NETWORK \
  --restart unless-stopped \
  -p 8000:8000 \
  -e PORT=8000 \
  -e CPU_COUNT=8 \
  -e MEMORY_GB=64 \
  redfish-simulator:latest

docker run -d \
  --name redfish-sim-worker-0 \
  --network $KIND_NETWORK \
  --restart unless-stopped \
  -p 8001:8000 \
  -e PORT=8000 \
  -e CPU_COUNT=4 \
  -e MEMORY_GB=32 \
  redfish-simulator:latest

docker run -d \
  --name redfish-sim-worker-1 \
  --network $KIND_NETWORK \
  --restart unless-stopped \
  -p 8002:8000 \
  -e PORT=8000 \
  -e CPU_COUNT=4 \
  -e MEMORY_GB=32 \
  redfish-simulator:latest

# Test
curl http://localhost:8000/redfish/v1/
```

## 🌐 Networking Details

### Internal Network (Within VM)

- **Kind cluster**: Uses Docker bridge network (typically `172.x.x.x`)
- **Simulators**: Can join kind network or use separate bridge
- **Internal access**: Simulators accessible via `localhost:8000-8002` from within VM

### External Network (From Outside)

- **VM External IP**: Access point for all services
- **Kubernetes API**: `https://${VM_IP}:6443` (if port mapped)
- **Redfish APIs**: `http://${VM_IP}:8000-8002`

### Accessing Simulators from Kind Cluster

The simulators can be accessed from pods in the kind cluster using:

```bash
# Option 1: Use VM's host IP (requires host network mode)
# Get host IP from within a pod
HOST_IP=$(ip route | grep default | awk '{print $3}')

# Option 2: Use container IP (if on same Docker network)
CONTROL_PLANE_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' redfish-sim-controlplane)

# Option 3: Use VM's external IP (if accessible from cluster)
# This is the recommended approach for production-like setups
```

## 🔍 Verification Commands

### Check Kind Cluster

```bash
# From VM
ssh ubuntu@${VM_IP}
kubectl get nodes
kubectl get pods -A

# From local machine (if kubeconfig exported)
kubectl --kubeconfig=/tmp/metal3-management-kubeconfig.yaml get nodes
```

### Check Simulators

```bash
# From VM
ssh ubuntu@${VM_IP}
docker ps | grep redfish-sim
docker logs redfish-sim-controlplane

# Test endpoints
curl http://localhost:8000/redfish/v1/
```

### Test from Cluster Pod

```bash
# SSH to VM
ssh ubuntu@${VM_IP}

# Get simulator IP (internal Docker IP)
SIM_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' redfish-sim-controlplane)

# Test from a pod
kubectl run -it --rm test \
  --image=curlimages/curl \
  --restart=Never \
  -- curl http://${SIM_IP}:8000/redfish/v1/
```

## 📝 Using in BareMetalHost Resources

When creating BareMetalHost resources, use the VM's external IP:

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: controlplane-0
spec:
  bmc:
    address: redfish-virtualmedia://${VM_IP}:8000/redfish/v1/Systems/1
    credentialsName: bmc-credentials
    disableCertificateVerification: true
  # ... rest of config
```

Or use internal Docker IPs if accessing from within the cluster:

```bash
# Get internal IPs
ssh ubuntu@${VM_IP} << 'EOF'
CONTROL_PLANE_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' redfish-sim-controlplane)
WORKER_0_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' redfish-sim-worker-0)
WORKER_1_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' redfish-sim-worker-1)

echo "BMC Addresses (internal):"
echo "Control Plane: redfish-virtualmedia://${CONTROL_PLANE_IP}:8000/redfish/v1/Systems/1"
echo "Worker 0: redfish-virtualmedia://${WORKER_0_IP}:8000/redfish/v1/Systems/1"
echo "Worker 1: redfish-virtualmedia://${WORKER_1_IP}:8000/redfish/v1/Systems/1"
EOF
```

## 🛠️ Management

### View Everything

```bash
ssh ubuntu@${VM_IP} << 'EOF'
echo "=== Kind Cluster Nodes ==="
kubectl get nodes

echo ""
echo "=== Simulator Containers ==="
docker ps | grep -E "redfish-sim|kind"

echo ""
echo "=== Network ==="
docker network ls | grep -E "kind|bridge"
EOF
```

### Restart Components

```bash
# Restart kind cluster
ssh ubuntu@${VM_IP} "kind delete cluster --name metal3-management && kind create cluster --name metal3-management --config /tmp/kind-config.yaml"

# Restart simulators
ssh ubuntu@${VM_IP} << 'EOF'
docker restart redfish-sim-controlplane redfish-sim-worker-0 redfish-sim-worker-1
EOF
```

### Clean Up

```bash
ssh ubuntu@${VM_IP} << 'EOF'
# Delete kind cluster
kind delete cluster --name metal3-management

# Stop and remove simulators
docker stop redfish-sim-controlplane redfish-sim-worker-0 redfish-sim-worker-1
docker rm redfish-sim-controlplane redfish-sim-worker-0 redfish-sim-worker-1

# Optional: Remove images
docker rmi redfish-simulator:latest
EOF
```

## 🎯 Next Steps

After setup is complete:

1. **Continue with Metal3 Setup**: Follow `rancher-metal3-simulator-guide.md` starting from Step 2 (Install Rancher)
2. **Use the kubeconfig**: Export the kubeconfig to continue setup
3. **Create BareMetalHosts**: Use the BMC addresses provided by the setup script

## 🔧 Troubleshooting

### Cannot Access Cluster from Outside

```bash
# Check if port 6443 is accessible
curl -k https://${VM_IP}:6443

# If not accessible, you can still use SSH port forwarding
ssh -L 6443:localhost:6443 ubuntu@${VM_IP}
# Then use: kubectl --server=https://localhost:6443
```

### Simulators Not Accessible from Cluster

```bash
# Check if simulators are on the same network as kind
ssh ubuntu@${VM_IP} << 'EOF'
KIND_NETWORK=$(docker network ls | grep kind | awk '{print $1}' | head -1)
docker network inspect $KIND_NETWORK | grep -A 5 redfish-sim
EOF

# If not, recreate simulators on kind network
```

### Port Conflicts

```bash
# Check what's using ports
ssh ubuntu@${VM_IP} "sudo netstat -tlnp | grep -E '8000|8001|8002|6443'"

# Change ports in setup script if needed
```

## 📊 Resource Usage

Typical resource usage on VM:

- **Kind Cluster**: ~2GB RAM, ~10GB disk
- **Simulators**: ~50MB RAM each, minimal disk
- **Total**: ~3GB RAM, ~15GB disk (minimum)

Recommended VM size: **4 vCPU, 8GB RAM, 50GB disk** (or larger)

## 🎉 Summary

You now have:
- ✅ **Kind cluster** running on OpenStack VM
- ✅ **Redfish simulators** as Docker containers
- ✅ **Everything accessible** via VM's external IP
- ✅ **Production-like setup** for testing Metal3

This gives you a complete, isolated environment for testing Metal3 + Rancher!

