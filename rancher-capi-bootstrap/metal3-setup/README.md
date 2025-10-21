# Metal3 + CAPI Setup on OpenStack

This guide shows how to set up Metal3 with CAPI using OpenStack VMs to simulate bare metal nodes, based on the [SUSE Edge Metal3 documentation](https://documentation.suse.com/suse-edge/3.3/html/edge/quickstart-metal3.html).

## 🎯 Architecture

```
Management Cluster (RKE2)
    ├── Metal3 (Bare Metal Management)
    ├── CAPI (Cluster API)
    ├── Rancher Turtles
    └── Simulated Bare Metal Nodes (OpenStack VMs)
```

## 🚀 Quick Start

### Prerequisites
- OpenStack access
- SSH keys for VM access
- Docker and kind installed
- clusterctl installed

### 1. Create Management Cluster
```bash
# Create management cluster
kind create cluster --name metal3-management --config kind-config.yaml

# Install CAPI
clusterctl init --core cluster-api:v1.6.0

# Install Metal3 provider
clusterctl init --infrastructure metal3:v1.6.0
```

### 2. Install Metal3 Dependencies
```bash
# Install MetalLB
helm install metallb oci://registry.suse.com/edge/charts/metallb \
  --namespace metallb-system \
  --create-namespace

# Configure IP pool
export STATIC_IRONIC_IP=10.0.0.100
kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: ironic-ip-pool
  namespace: metallb-system
spec:
  addresses:
  - ${STATIC_IRONIC_IP}/32
  serviceAllocation:
    priority: 100
    serviceSelectors:
    - matchExpressions:
      - {key: app.kubernetes.io/name, operator: In, values: [metal3-ironic]}
EOF

# Install Metal3
helm install metal3 oci://registry.suse.com/edge/charts/metal3 \
  --namespace metal3-system \
  --create-namespace \
  --set global.ironicIP="$STATIC_IRONIC_IP"
```

### 3. Install Rancher Turtles
```bash
# Install Rancher Turtles
helm install rancher-turtles oci://registry.suse.com/edge/charts/rancher-turtles \
  --namespace rancher-turtles-system \
  --create-namespace \
  --set rancherTurtles.features.embedded-capi.disabled=true
```

### 4. Create Simulated Bare Metal Nodes
```bash
# Create OpenStack VMs to simulate bare metal
./scripts/create-baremetal-vms.sh

# Register BareMetalHost resources
kubectl apply -f baremetal-hosts/
```

### 5. Create Downstream Cluster
```bash
# Create RKE2 cluster using Metal3
kubectl apply -f clusters/rke2-metal3-cluster.yaml

# Monitor cluster creation
kubectl get clusters -w
kubectl get bmh -w
```

## 📁 Directory Structure

```
metal3-setup/
├── README.md
├── kind-config.yaml
├── scripts/
│   ├── create-baremetal-vms.sh
│   ├── install-metal3.sh
│   └── install-rancher-turtles.sh
├── baremetal-hosts/
│   ├── controlplane-0.yaml
│   └── worker-0.yaml
├── clusters/
│   ├── rke2-metal3-cluster.yaml
│   └── rke2-metal3-workers.yaml
├── images/
│   └── sle-micro.raw
└── secrets/
    ├── bmc-credentials.yaml
    └── network-data.yaml
```

## 🔧 Key Components

### Metal3
- **Bare Metal Management**: Manages bare metal servers via BMC
- **Image Provisioning**: Deploys OS images to bare metal
- **Hardware Inspection**: Discovers hardware capabilities

### CAPI
- **Cluster Management**: Manages Kubernetes clusters
- **Machine Management**: Manages individual machines
- **Lifecycle Management**: Handles cluster lifecycle

### Rancher Turtles
- **CAPI Integration**: Integrates CAPI with Rancher
- **Cluster Management**: Manages clusters through Rancher UI

## 🎯 Benefits

- ✅ **Bare Metal Management**: Full control over hardware
- ✅ **GitOps**: Everything managed through Git
- ✅ **Scalable**: Can manage hundreds of bare metal servers
- ✅ **Observable**: Clear status and conditions
- ✅ **Reliable**: Self-healing and resilient

## 🔗 Resources

- [SUSE Edge Metal3 Documentation](https://documentation.suse.com/suse-edge/3.3/html/edge/quickstart-metal3.html)
- [Metal3 Project](https://metal3.io/)
- [Cluster API](https://cluster-api.sigs.k8s.io/)
- [Rancher Turtles](https://github.com/rancher/turtles)
