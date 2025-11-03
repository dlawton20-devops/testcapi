# Metal3 VM Setup: Kind Cluster for External Rancher Management

This folder contains everything needed to set up a Kind cluster on an OpenStack VM that will be **managed by an external Rancher cluster** (running Rancher Turtles and Metal3):
- ✅ Kind cluster (target cluster, managed by Rancher)
- ✅ Redfish simulators (bare metal node simulation)
- ✅ API server exposed for Rancher cluster access
- ✅ Ready for import into external Rancher cluster

## 📁 Folder Structure

```
metal3-vm-setup/
├── README.md                              # This file
├── kind-config.yaml                       # Kind cluster configuration
├── setup.sh                               # Main setup script (wrapper)
├── scripts/
│   ├── setup-vm-with-kind-and-simulators.sh  # Automated setup script
│   ├── setup-for-external-rancher.sh     # Rancher integration script
│   ├── Dockerfile.redfish-simulator      # Dockerfile for Redfish simulator
│   └── redfish-simulator.py               # Python Redfish simulator
└── docs/
    ├── VM-KIND-SIMULATOR-GUIDE.md        # Complete documentation
    ├── MANUAL-SETUP-GUIDE.md             # Step-by-step manual setup
    ├── RANCHER-INTEGRATION.md            # Rancher cluster integration
    ├── NETWORK-ARCHITECTURE.md           # Network flow explanation
    └── CLUSTER-ACCESS.md                 # Cluster access methods
```

## 🚀 Quick Start

### Prerequisites

- OpenStack VM with:
  - Ubuntu 22.04+ or Debian 11+
  - Minimum 4 vCPU, 8GB RAM, 50GB disk
  - External/floating IP
  - SSH access configured
- Local machine with:
  - SSH access to VM
  - SSH key configured

### Step 1: Set VM Details

```bash
export VM_IP="192.168.1.100"      # Your VM's external IP
export VM_USER="ubuntu"            # Your VM user
export SSH_KEY="~/.ssh/id_rsa"     # Your SSH key
export CLUSTER_NAME="metal3-management"
```

### Step 2: Run Setup

```bash
cd metal3-vm-setup
./setup.sh
```

Or use the script directly:

```bash
cd metal3-vm-setup
./scripts/setup-vm-with-kind-and-simulators.sh
```

**Note:** The Kind cluster is configured with `apiServerAddress: "0.0.0.0"` to allow access from your external Rancher cluster.

### Step 3: Configure for External Rancher Access

```bash
# Set Rancher cluster network (CIDR)
export RANCHER_NETWORK="10.0.0.0/8"  # Your Rancher cluster network

# Configure security group and get kubeconfig
cd metal3-vm-setup
./scripts/setup-for-external-rancher.sh
```

This will:
- ✅ Configure OpenStack security group to allow Rancher cluster access
- ✅ Get kubeconfig from Kind cluster
- ✅ Update kubeconfig to use VM external IP
- ✅ Test connectivity

### Step 4: Import into Rancher Cluster

```bash
# Option A: Via Rancher UI (Recommended)
# 1. Access Rancher UI → Clusters → Import Existing
# 2. Copy the import command
# 3. Run: kubectl --kubeconfig=/tmp/kind-metal3-management-kubeconfig.yaml apply -f - <<EOF
#    # ... (paste from Rancher UI)
#    EOF

# Option B: Via Rancher API
export RANCHER_URL="https://rancher.example.com"
export RANCHER_TOKEN="your-api-token"
curl -X POST \
  -H "Authorization: Bearer $RANCHER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"type\":\"cluster\",\"name\":\"kind-metal3\",\"kubeconfig\":\"$(base64 -w 0 /tmp/kind-metal3-management-kubeconfig.yaml)\"}" \
  "$RANCHER_URL/v3/clusters"
```

**See `docs/RANCHER-INTEGRATION.md` for complete integration guide.**

### Step 5: Verify Simulators

```bash
# Test simulators from your local machine
curl http://${VM_IP}:8000/redfish/v1/
curl http://${VM_IP}:8001/redfish/v1/
curl http://${VM_IP}:8002/redfish/v1/
```

## 📋 What Gets Installed

The setup script will:

1. **Install on VM:**
   - Docker Engine
   - kubectl
   - kind
   - helm

2. **Create Kind Cluster:**
   - 1 control plane node
   - 2 worker nodes
   - Kubernetes v1.27.3

3. **Build & Run Simulators:**
   - Redfish simulator Docker image
   - 3 simulator containers (controlplane, worker-0, worker-1)
   - Exposed on ports 8000, 8001, 8002

4. **Output:**
   - Kubeconfig file: `/tmp/metal3-management-kubeconfig.yaml`
   - BMC addresses for BareMetalHost resources

## 🔧 Configuration

### Environment Variables

```bash
VM_IP              # OpenStack VM external IP (required)
VM_USER            # SSH user (default: ubuntu)
SSH_KEY            # SSH key path (default: ~/.ssh/id_rsa)
CLUSTER_NAME       # Kind cluster name (default: metal3-management)
KIND_VERSION       # Kind version (default: v0.20.0)
KUBERNETES_VERSION # Kubernetes version (default: v1.27.3)
```

### Ports

- **8000**: Redfish simulator for control plane
- **8001**: Redfish simulator for worker-0
- **8002**: Redfish simulator for worker-1
- **6443**: Kubernetes API (if accessible)

## 📖 Documentation

- **Manual Setup Guide**: See `docs/MANUAL-SETUP-GUIDE.md` for step-by-step manual instructions
- **Complete Guide**: See `docs/VM-KIND-SIMULATOR-GUIDE.md` for detailed documentation
- **Rancher Integration**: See `docs/RANCHER-INTEGRATION.md` for external Rancher setup
- **Network Architecture**: See `docs/NETWORK-ARCHITECTURE.md` for network flow explanation
- **Cluster Access**: See `docs/CLUSTER-ACCESS.md` for access methods

## 🎯 Usage in Metal3

After setup, use the BMC addresses in your BareMetalHost resources:

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
```

## 🛠️ Management Commands

### View Status

```bash
# SSH to VM
ssh ubuntu@${VM_IP}

# Check cluster
kubectl get nodes
kubectl get pods -A

# Check simulators
docker ps | grep redfish-sim
docker logs redfish-sim-controlplane
```

### Restart Components

```bash
# Restart cluster
ssh ubuntu@${VM_IP} "kind delete cluster --name metal3-management && kind create cluster --name metal3-management --config /tmp/metal3-setup/kind-config.yaml"

# Restart simulators
ssh ubuntu@${VM_IP} "docker restart redfish-sim-controlplane redfish-sim-worker-0 redfish-sim-worker-1"
```

### Clean Up

```bash
ssh ubuntu@${VM_IP} << 'EOF'
kind delete cluster --name metal3-management
docker stop redfish-sim-controlplane redfish-sim-worker-0 redfish-sim-worker-1
docker rm redfish-sim-controlplane redfish-sim-worker-0 redfish-sim-worker-1
docker rmi redfish-simulator:latest
EOF
```

## 🔒 Security Group Configuration

Ensure your OpenStack security group allows:

```bash
# SSH
openstack security group rule create default \
  --protocol tcp --dst-port 22 --remote-ip 0.0.0.0/0

# Redfish APIs
for port in 8000 8001 8002; do
    openstack security group rule create default \
      --protocol tcp --dst-port $port --remote-ip 0.0.0.0/0
done

# Kubernetes API (optional)
openstack security group rule create default \
  --protocol tcp --dst-port 6443 --remote-ip 0.0.0.0/0
```

## 📊 Resource Requirements

**Minimum VM Size:**
- 4 vCPU
- 8GB RAM
- 50GB disk

**Recommended VM Size:**
- 8 vCPU
- 16GB RAM
- 100GB disk

**Typical Usage:**
- Kind Cluster: ~2GB RAM, ~10GB disk
- Simulators: ~50MB RAM each, minimal disk
- Total: ~3GB RAM, ~15GB disk

## 🔗 Integration with External Rancher Cluster

**This setup is configured for external Rancher cluster management.**

The Kind cluster API server is exposed (`apiServerAddress: "0.0.0.0"`) to allow your external Rancher cluster (running Rancher Turtles and Metal3) to manage it.

**Quick integration:**
```bash
# 1. Set Rancher network CIDR
export RANCHER_NETWORK="10.0.0.0/8"  # Your Rancher cluster network

# 2. Run integration script
./scripts/setup-for-external-rancher.sh

# 3. Import into Rancher (see Step 4 above)
```

**See `docs/RANCHER-INTEGRATION.md` for complete integration guide.**

## 🎉 Next Steps

After setup is complete:

1. **Configure for Rancher**: Run `./scripts/setup-for-external-rancher.sh`
2. **Import into Rancher**: Use Rancher UI or API (see Step 4 above)
3. **Verify in Rancher**: Cluster should appear in Rancher UI
4. **Create BareMetalHosts**: Use the BMC addresses provided in Rancher cluster
5. **Deploy workloads**: Rancher Turtles and Metal3 will manage the Kind cluster

**Note:** This setup is specifically for external Rancher cluster management. The Kind cluster on the VM is the **target cluster** that will be managed by your external Rancher cluster.

## 📝 Files Overview

- **`setup.sh`**: Main entry point (wrapper script)
- **`scripts/setup-vm-with-kind-and-simulators.sh`**: Complete setup automation
- **`kind-config.yaml`**: Kind cluster configuration
- **`scripts/Dockerfile.redfish-simulator`**: Docker image for Redfish simulator
- **`scripts/redfish-simulator.py`**: Python Redfish API simulator
- **`docs/VM-KIND-SIMULATOR-GUIDE.md`**: Complete documentation

## 🆘 Troubleshooting

See the troubleshooting section in `docs/VM-KIND-SIMULATOR-GUIDE.md` for:
- Network connectivity issues
- Port conflicts
- Simulator access problems
- Cluster access issues

## 📚 Additional Resources

- [Kind Documentation](https://kind.sigs.k8s.io/)
- [Metal3 Documentation](https://metal3.io/)
- [Redfish API Specification](https://www.dmtf.org/standards/redfish)

