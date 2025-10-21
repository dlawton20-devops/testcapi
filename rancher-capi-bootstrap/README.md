# Rancher CAPI Bootstrap - Sylva-Style

A complete Cluster API (CAPI) bootstrap environment for managing Rancher infrastructure using pure Kubernetes-native resources, inspired by Project Sylva.

## 🎯 What This Provides

1. **Cluster API Management**: Create and manage Kubernetes clusters using CAPI
2. **Rancher Integration**: Custom operator for managing Rancher resources
3. **GitOps Workflow**: Everything managed through Git and Flux
4. **Kubernetes-Native**: No Terraform - pure Kubernetes resources
5. **Sylva-Inspired**: Similar architecture to Project Sylva

## 🏗️ Architecture

```
┌─────────────────────────────────────────┐
│  Git Repository                          │
│  ├── clusters/                          │
│  │   ├── templates/                     │
│  │   └── workloads/                     │
│  ├── gitops/                            │
│  │   ├── sources/                       │
│  │   ├── clusters/                      │
│  │   └── rancher-resources/             │
│  └── components/                        │
└─────────────────────────────────────────┘
                ↓
┌─────────────────────────────────────────┐
│  Kind Cluster (Bootstrap)                │
│  ├── Flux (GitOps)                      │
│  ├── Cluster API                        │
│  │   ├── Core CAPI                      │
│  │   ├── Docker Provider                │
│  │   ├── Kubeadm Bootstrap              │
│  │   └── Kubeadm Control Plane          │
│  ├── Rancher Operator                   │
│  │   ├── RancherUser CRD                │
│  │   └── RancherProject CRD             │
│  └── Workload Clusters                  │
│      ├── Production Cluster             │
│      └── Staging Cluster                │
└─────────────────────────────────────────┘
                ↓
┌─────────────────────────────────────────┐
│  Rancher Resources                       │
│  ├── Users                              │
│  ├── Projects                           │
│  ├── Namespaces                         │
│  └── RBAC                               │
└─────────────────────────────────────────┘
```

## 🚀 Quick Start

### Prerequisites

- Docker Desktop
- kind
- kubectl
- clusterctl
- flux CLI
- yq

### Installation

```bash
# Clone and setup
cd rancher-capi-bootstrap

# Run bootstrap
./bootstrap.sh environment-values/default

# Verify installation
./scripts/validate-deployment.sh
```

## 📁 Directory Structure

```
rancher-capi-bootstrap/
├── bootstrap.sh                          # Main bootstrap script
├── cleanup.sh                            # Cleanup script
├── kind-config.yaml                      # Kind cluster configuration
├── environment-values/                   # Configuration templates
│   └── default/
│       └── values.yaml                  # Default configuration
├── components/                           # Component manifests
│   ├── capi-providers/                  # CAPI provider configurations
│   ├── rancher-operator/                # Rancher operator
│   └── monitoring/                      # Monitoring stack
├── clusters/                            # Cluster definitions
│   ├── templates/                       # Cluster templates
│   │   └── production-cluster.yaml     # Production cluster template
│   └── workloads/                       # Workload cluster configs
├── gitops/                              # GitOps manifests
│   ├── sources/                         # Git repository sources
│   ├── clusters/                        # CAPI cluster resources
│   └── rancher-resources/               # Rancher resources
│       └── rancher-user.yaml           # Rancher user example
├── scripts/                             # Helper scripts
│   ├── install-flux.sh                 # Flux installation
│   ├── install-capi.sh                 # CAPI installation
│   ├── install-rancher-operator.sh     # Rancher operator
│   └── validate-deployment.sh          # Validation
└── README.md                            # This file
```

## 🔧 Key Components

### 1. Cluster API (CAPI)

Manages Kubernetes clusters using declarative resources:

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: production-cluster
spec:
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: KubeadmControlPlane
    name: production-cluster-control-plane
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: DockerCluster
    name: production-cluster
```

### 2. Rancher Operator

Custom operator for managing Rancher resources:

```yaml
apiVersion: rancher.io/v1
kind: RancherUser
metadata:
  name: lma-user
spec:
  username: "lma-user"
  displayName: "LMA User"
  email: "lma-user@example.com"
  rancherApiUrl: "https://rancher.example.com"
  clusterId: "c-xxxxx"
```

### 3. GitOps Integration

Everything managed through Git and Flux:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: GitRepository
metadata:
  name: rancher-infrastructure
spec:
  url: https://github.com/your-org/rancher-capi-infrastructure
  ref:
    branch: main
  interval: 5m
```

## 🎯 Benefits Over Terraform

| Feature | Terraform/Tofu Controller | CAPI + Custom Operator |
|---------|---------------------------|------------------------|
| **State Management** | Remote backend (S3) | Kubernetes etcd |
| **Resource Model** | HCL + Providers | Pure Kubernetes CRDs |
| **GitOps Integration** | Custom resources | Native Kubernetes |
| **Drift Detection** | Terraform plan | Kubernetes reconciliation |
| **Rollback** | Git revert | Kubernetes rollback |
| **Learning Curve** | Terraform knowledge | Kubernetes knowledge |
| **Ecosystem** | Terraform providers | Kubernetes operators |

## 🔄 Workflow

### 1. Create Cluster
```bash
# Apply cluster template
kubectl apply -f clusters/templates/production-cluster.yaml

# Monitor cluster creation
kubectl get clusters -w
kubectl get machines -w
```

### 2. Create Rancher Resources
```bash
# Apply Rancher user
kubectl apply -f gitops/rancher-resources/rancher-user.yaml

# Monitor Rancher user creation
kubectl get rancherusers -w
```

### 3. GitOps Workflow
```bash
# Make changes in Git
git add .
git commit -m "Add new cluster"
git push

# Flux automatically syncs
kubectl get clusters -A
```

## 🛠️ Customization

### Environment Values

Edit `environment-values/default/values.yaml`:

```yaml
# Cluster configuration
cluster:
  name: my-capi-bootstrap
  nodes: 3
  kubernetes_version: "v1.28.5"

# Workload clusters
workload_clusters:
  production:
    name: "production-cluster"
    kubernetes_version: "v1.28.5"
    control_plane_replicas: 1
    worker_replicas: 3
```

### Cluster Templates

Create custom cluster templates in `clusters/templates/`:

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: my-custom-cluster
spec:
  # Your cluster configuration
```

## 🔍 Monitoring

### Check Cluster Status
```bash
# View all clusters
kubectl get clusters -A

# Describe specific cluster
clusterctl describe cluster production-cluster

# Get cluster kubeconfig
clusterctl get kubeconfig production-cluster
```

### Check Rancher Resources
```bash
# View Rancher users
kubectl get rancherusers -A

# View Rancher projects
kubectl get rancherprojects -A

# Describe Rancher user
kubectl describe rancheruser lma-user
```

## 🧹 Cleanup

```bash
# Clean up everything
./cleanup.sh

# Or clean up specific cluster
clusterctl delete cluster production-cluster
```

## 🔗 Resources

- [Cluster API Documentation](https://cluster-api.sigs.k8s.io/)
- [Project Sylva](https://sylva-projects.gitlab.io/)
- [Flux Documentation](https://fluxcd.io/docs/)
- [Rancher Documentation](https://rancher.com/docs/)

## 💡 Tips

1. **Start Small**: Begin with a single cluster template
2. **Use GitOps**: Commit all changes to Git
3. **Monitor Resources**: Watch cluster and machine status
4. **Customize Templates**: Adapt cluster templates for your needs
5. **Operator Development**: Extend the Rancher operator for more features

## 🤝 Contributing

This is a template for building CAPI-based Rancher management. Feel free to:

1. Add more cluster templates
2. Extend the Rancher operator
3. Add monitoring and alerting
4. Improve documentation
5. Add more examples
