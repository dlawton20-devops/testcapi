# Metal3 + CAPI Complete Setup

A complete, production-ready setup for Metal3 + Cluster API (CAPI) using OpenStack VMs to simulate bare metal nodes. This setup follows the [SUSE Edge Metal3 documentation](https://documentation.suse.com/suse-edge/3.3/html/edge/quickstart-metal3.html) and provides a full GitOps-ready environment.

## 🎯 What This Provides

- **Complete Metal3 + CAPI Environment** - Production-grade bare metal management
- **OpenStack VM Simulation** - Simulates real bare metal servers with BMC/Redfish interfaces
- **GitOps Ready** - Everything managed through Git and declarative resources
- **Automated Setup** - One-command deployment with comprehensive validation
- **Production-like** - Real Metal3, CAPI, and Rancher Turtles stack

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Management Cluster (Kind/Rancher)                     │
│  ├── Metal3 (Bare Metal Management)                    │
│  │   ├── Ironic (Provisioning)                         │
│  │   ├── Inspector (Hardware Discovery)                │
│  │   └── Bare Metal Operator                           │
│  ├── CAPI (Cluster API)                                │
│  │   ├── Core Controllers                              │
│  │   ├── RKE2 Control Plane                            │
│  │   └── Metal3 Infrastructure                         │
│  ├── Rancher Turtles                                   │
│  └── MetalLB (Load Balancing)                          │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│  OpenStack VMs (Bare Metal Simulation)                 │
│  ├── Control Plane VM                                  │
│  │   ├── Redfish API Simulator                         │
│  │   ├── Virtual Media Support                         │
│  │   └── Power Management                              │
│  ├── Worker VM 1                                       │
│  │   ├── Redfish API Simulator                         │
│  │   ├── Virtual Media Support                         │
│  │   └── Power Management                              │
│  └── Worker VM 2                                       │
│      ├── Redfish API Simulator                         │
│      ├── Virtual Media Support                         │
│      └── Power Management                              │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│  RKE2 Cluster (Managed by Metal3 + CAPI)               │
│  ├── Control Plane Node                                │
│  ├── Worker Node 1                                     │
│  └── Worker Node 2                                     │
└─────────────────────────────────────────────────────────┘
```

## 🚀 Quick Start

### Prerequisites

- OpenStack access with admin privileges
- SSH key pair for VM access
- Docker and kind installed
- clusterctl installed
- kubectl installed

### Option 1: Automated Setup (Recommended)

```bash
# Clone or download this repository
cd metal3-capi-complete-setup

# Run automated setup for Kind cluster
./auto-setup.sh kind

# OR run for existing Rancher cluster
./auto-setup.sh rancher
```

### Option 2: Manual Setup

Follow the step-by-step guide in `complete-setup-guide.md` for detailed manual setup instructions.

## 📁 Directory Structure

```
metal3-capi-complete-setup/
├── README.md                           # This file
├── auto-setup.sh                       # Automated setup script
├── complete-setup-guide.md             # Manual setup guide
├── kind-config.yaml                    # Kind cluster configuration
├── scripts/
│   ├── create-baremetal-vms.sh         # OpenStack VM creation
│   ├── setup-oob-simulation.sh         # OOB simulation setup
│   ├── install-metal3.sh               # Metal3 installation
│   └── install-rancher-turtles.sh      # Rancher Turtles installation
├── clusters/
│   ├── rke2-metal3-cluster.yaml        # RKE2 cluster template
│   └── rke2-metal3-workers.yaml        # Worker nodes template
├── baremetal-hosts/
│   ├── controlplane-0.yaml             # Control plane BareMetalHost
│   ├── worker-0.yaml                   # Worker 0 BareMetalHost
│   └── worker-1.yaml                   # Worker 1 BareMetalHost
├── secrets/
│   ├── bmc-credentials.yaml            # BMC authentication
│   └── network-data.yaml               # Network configuration
└── images/
    └── sle-micro.raw                   # OS image for provisioning
```

## 🔧 Key Components

### Metal3
- **Bare Metal Management**: Manages bare metal servers via BMC
- **Image Provisioning**: Deploys OS images to bare metal
- **Hardware Inspection**: Discovers hardware capabilities
- **Power Management**: Controls server power states

### Cluster API (CAPI)
- **Cluster Management**: Manages Kubernetes clusters
- **Machine Management**: Manages individual machines
- **Lifecycle Management**: Handles cluster lifecycle
- **Provider Integration**: Integrates with infrastructure providers

### Rancher Turtles
- **CAPI Integration**: Integrates CAPI with Rancher
- **Cluster Management**: Manages clusters through Rancher UI
- **GitOps Workflow**: Enables GitOps for cluster management

## 🎯 Features

### Out-of-Band (OOB) Simulation
- **Redfish API**: Simulates BMC interfaces on OpenStack VMs
- **Virtual Media**: Supports ISO mounting for OS installation
- **Power Management**: Simulates power on/off operations
- **Hardware Inspection**: Discovers CPU, memory, and storage

### GitOps Integration
- **Declarative Resources**: All infrastructure defined as YAML
- **Git-based Management**: Everything managed through Git
- **Automated Reconciliation**: Continuous synchronization
- **Version Control**: Full history and rollback capabilities

### Production Features
- **High Availability**: Multi-node management cluster
- **Scalability**: Can manage hundreds of bare metal servers
- **Observability**: Comprehensive logging and monitoring
- **Security**: RBAC, network policies, and secure communication

## 🔄 Workflow

### 1. Setup Phase
```bash
# Create management cluster
kind create cluster --name metal3-management

# Install CAPI and Metal3
clusterctl init --core cluster-api:v1.6.0
clusterctl init --infrastructure metal3:v1.6.0

# Install Metal3 dependencies
helm install metal3 oci://registry.suse.com/edge/charts/metal3
```

### 2. Infrastructure Phase
```bash
# Create OpenStack VMs
openstack server create --flavor m1.large --image ubuntu-22.04 controlplane-0

# Setup OOB simulation
ssh ubuntu@<VM_IP> 'sudo systemctl start redfish-simulator'

# Register BareMetalHost resources
kubectl apply -f baremetal-hosts/
```

### 3. Cluster Creation Phase
```bash
# Create RKE2 cluster
kubectl apply -f clusters/rke2-metal3-cluster.yaml

# Monitor cluster creation
kubectl get clusters -w
kubectl get bmh -w
```

### 4. Validation Phase
```bash
# Check cluster status
clusterctl describe cluster sample-cluster

# Access the created cluster
clusterctl get kubeconfig sample-cluster > sample-cluster-kubeconfig
kubectl --kubeconfig sample-cluster-kubeconfig get nodes
```

## 🛠️ Configuration

### Environment Variables
```bash
export STATIC_IRONIC_IP=10.0.0.100
export SSH_KEY=~/.ssh/id_rsa
export SSH_USER=ubuntu
export CLUSTER_NAME=metal3-management
```

### Customization
- **VM Flavors**: Modify VM sizes in `scripts/create-baremetal-vms.sh`
- **Network Configuration**: Update network settings in `secrets/network-data.yaml`
- **Cluster Configuration**: Customize cluster settings in `clusters/`
- **BMC Settings**: Modify BMC configuration in `baremetal-hosts/`

## 🔍 Monitoring and Troubleshooting

### Useful Commands
```bash
# Monitor cluster creation
kubectl get clusters -w
kubectl get bmh -w
kubectl get metal3clusters -w
kubectl get metal3machines -w

# Check specific resources
kubectl describe cluster sample-cluster
kubectl describe bmh controlplane-0
clusterctl describe cluster sample-cluster

# View logs
kubectl logs -n metal3-system -l app.kubernetes.io/name=baremetal-operator
kubectl logs -n capi-system -l control-plane=controller-manager

# Check OOB simulation
curl http://<VM_IP>:8000/redfish/v1/
ssh ubuntu@<VM_IP> 'sudo systemctl status redfish-simulator'
```

### Common Issues

#### 1. Metal3 Not Ready
```bash
# Check Metal3 pods
kubectl get pods -n metal3-system

# Check Metal3 logs
kubectl logs -n metal3-system -l app.kubernetes.io/name=baremetal-operator
```

#### 2. BareMetalHost Not Ready
```bash
# Check BareMetalHost status
kubectl describe bmh controlplane-0

# Check BMC connectivity
curl http://<VM_IP>:8000/redfish/v1/
```

#### 3. Cluster Not Ready
```bash
# Check cluster conditions
kubectl describe cluster sample-cluster

# Check control plane status
kubectl describe rke2controlplane sample-cluster-control-plane
```

## 🧹 Cleanup

### Remove Clusters
```bash
# Delete RKE2 cluster
kubectl delete cluster sample-cluster

# Delete BareMetalHost resources
kubectl delete bmh --all

# Delete OpenStack VMs
openstack server delete controlplane-0 worker-0 worker-1
```

### Remove Management Cluster
```bash
# Delete Kind cluster
kind delete cluster --name metal3-management

# OR clean up Rancher cluster
kubectl delete namespace metal3-system
kubectl delete namespace capi-system
kubectl delete namespace capm3-system
```

## 🔗 Resources

- [SUSE Edge Metal3 Documentation](https://documentation.suse.com/suse-edge/3.3/html/edge/quickstart-metal3.html)
- [Metal3 Project](https://metal3.io/)
- [Cluster API](https://cluster-api.sigs.k8s.io/)
- [Rancher Turtles](https://github.com/rancher/turtles)
- [RKE2 Documentation](https://docs.rke2.io/)

## 🤝 Contributing

This setup is designed to be:
- **Extensible**: Easy to add new features and providers
- **Configurable**: Customizable for different environments
- **Maintainable**: Clear structure and documentation
- **Testable**: Comprehensive validation and testing

## 📝 License

This project is provided as-is for educational and testing purposes. Please review the licenses of the individual components (Metal3, CAPI, Rancher Turtles) for production use.

## 🆘 Support

For issues and questions:
1. Check the troubleshooting section above
2. Review the component documentation
3. Check the logs and status of resources
4. Verify OpenStack connectivity and VM status

---

**Happy Bare Metal Management with Metal3 + CAPI! 🚀**