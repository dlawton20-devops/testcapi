# Manual Migration Guide: Terraform to CAPI

## Overview
This guide walks you through manually replacing your Terraform platform builder with CAPI.

## Prerequisites
- OpenStack access
- SSH keys for VM access
- Docker and kind installed
- clusterctl installed

## Step 1: Create Management Cluster

### 1.1 Create Kind Cluster
```bash
# Create management cluster
kind create cluster --name capi-management --config kind-config.yaml

# Verify cluster
kubectl cluster-info
```

### 1.2 Install CAPI
```bash
# Install core CAPI
clusterctl init --core cluster-api:v1.6.0

# Install OpenStack provider
clusterctl init --infrastructure openstack:v1.6.0

# Install RKE2 provider (for Rancher cluster)
clusterctl init --infrastructure rke2:v0.3.0

# Verify installation
kubectl get pods -n capi-system
kubectl get pods -n capo-system
kubectl get pods -n capi-rke2-system
```

### 1.3 Configure OpenStack Credentials
```bash
# Create OpenStack credentials secret
kubectl create secret generic openstack-credentials \
  --from-file=clouds.yaml=./openstack-clouds.yaml \
  -n capo-system

# Verify secret
kubectl get secret openstack-credentials -n capo-system
```

## Step 2: Create Rancher Cluster

### 2.1 Apply Rancher Cluster Template
```bash
# Apply the Rancher cluster template
kubectl apply -f clusters/templates/rancher-cluster.yaml

# Monitor cluster creation
kubectl get clusters -w
kubectl get rke2clusters -w
kubectl get openstackclusters -w
```

### 2.2 Wait for Cluster to be Ready
```bash
# Check cluster status
kubectl describe cluster rancher-cluster

# Wait for control plane to be ready
kubectl wait --for=condition=ready cluster/rancher-cluster --timeout=30m

# Get cluster kubeconfig
clusterctl get kubeconfig rancher-cluster > rancher-kubeconfig
```

### 2.3 Install Rancher
```bash
# Add Rancher Helm repository
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update

# Install Rancher
helm install rancher rancher-stable/rancher \
  --kubeconfig rancher-kubeconfig \
  --namespace cattle-system \
  --create-namespace \
  --set hostname=rancher.example.com \
  --set bootstrapPassword=admin \
  --set replicas=1

# Wait for Rancher to be ready
kubectl --kubeconfig rancher-kubeconfig wait --for=condition=ready pod -l app=rancher -n cattle-system --timeout=10m
```

## Step 3: Create Downstream Cluster

### 3.1 Apply Downstream Cluster Template
```bash
# Apply the downstream cluster template
kubectl apply -f clusters/templates/downstream-cluster.yaml

# Monitor cluster creation
kubectl get clusters -w
kubectl get kubeadmcontrolplanes -w
kubectl get openstackclusters -w
```

### 3.2 Wait for Downstream Cluster to be Ready
```bash
# Check cluster status
kubectl describe cluster downstream-cluster

# Wait for control plane to be ready
kubectl wait --for=condition=ready cluster/downstream-cluster --timeout=30m

# Get cluster kubeconfig
clusterctl get kubeconfig downstream-cluster > downstream-kubeconfig
```

### 3.3 Register Cluster with Rancher
```bash
# Get cluster registration command from Rancher UI
# Or use Rancher CLI
rancher clusters import downstream-cluster \
  --kubeconfig rancher-kubeconfig \
  --cluster-kubeconfig downstream-kubeconfig
```

## Step 4: Validation

### 4.1 Verify Rancher Cluster
```bash
# Check Rancher cluster status
kubectl --kubeconfig rancher-kubeconfig get nodes
kubectl --kubeconfig rancher-kubeconfig get pods -n cattle-system

# Access Rancher UI
echo "Rancher UI: https://rancher.example.com"
echo "Username: admin"
echo "Password: admin"
```

### 4.2 Verify Downstream Cluster
```bash
# Check downstream cluster status
kubectl --kubeconfig downstream-kubeconfig get nodes
kubectl --kubeconfig downstream-kubeconfig get pods -A

# Verify cluster is registered in Rancher
kubectl --kubeconfig rancher-kubeconfig get clusters.management.cattle.io
```

## Step 5: GitOps Integration

### 5.1 Install Flux on Management Cluster
```bash
# Install Flux
flux install --components=source-controller,kustomize-controller

# Create Git repository source
kubectl apply -f gitops/sources/git-repository.yaml

# Apply cluster templates via GitOps
kubectl apply -f gitops/clusters/
```

### 5.2 Monitor GitOps
```bash
# Check Flux status
flux check

# Monitor GitOps resources
kubectl get gitrepositories -A
kubectl get kustomizations -A
```

## Troubleshooting

### Common Issues

#### 1. OpenStack Credentials
```bash
# Check OpenStack credentials
kubectl get secret openstack-credentials -n capo-system -o yaml

# Test OpenStack connection
openstack --os-cloud production server list
```

#### 2. Cluster Not Ready
```bash
# Check cluster conditions
kubectl describe cluster rancher-cluster

# Check control plane status
kubectl describe rke2controlplane rancher-cluster-control-plane

# Check infrastructure status
kubectl describe openstackcluster rancher-cluster
```

#### 3. Machines Not Ready
```bash
# Check machine status
kubectl get machines -A
kubectl describe machine rancher-cluster-control-plane-0

# Check bootstrap status
kubectl describe rke2config rancher-cluster-control-plane-0
```

## Cleanup

### Remove Clusters
```bash
# Delete downstream cluster
kubectl delete cluster downstream-cluster

# Delete Rancher cluster
kubectl delete cluster rancher-cluster

# Delete management cluster
kind delete cluster --name capi-management
```

## Next Steps

1. **Automate**: Set up GitOps workflows
2. **Scale**: Create multiple downstream clusters
3. **Monitor**: Set up monitoring and alerting
4. **Backup**: Implement cluster backup strategies
5. **Security**: Configure RBAC and network policies

## Benefits Achieved

- ✅ **GitOps**: Infrastructure managed through Git
- ✅ **Declarative**: No more imperative Terraform scripts
- ✅ **Scalable**: Can manage hundreds of clusters
- ✅ **Observable**: Clear status and conditions
- ✅ **Reliable**: Self-healing and resilient
- ✅ **Extensible**: Easy to add new providers
