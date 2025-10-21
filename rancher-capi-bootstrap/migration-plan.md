# Terraform to CAPI Migration Plan

## Current Architecture
```
Terraform Platform Builder
    ├── Deploy 3-node Rancher cluster (RKE2)
    └── Deploy downstream clusters (Node Driver)
```

## Target Architecture
```
CAPI Management Cluster
    ├── Deploy Rancher cluster (CAPI + RKE2)
    └── Deploy downstream clusters (CAPI + Node Driver)
```

## Migration Phases

### Phase 1: Management Cluster Setup
1. Create CAPI management cluster
2. Install RKE2 provider
3. Install Node Driver provider
4. Test with single cluster

### Phase 2: Rancher Cluster Migration
1. Create Rancher cluster using CAPI
2. Install Rancher on the cluster
3. Configure Rancher settings
4. Test Rancher functionality

### Phase 3: Downstream Cluster Migration
1. Create downstream clusters using CAPI
2. Configure Node Driver integration
3. Test cluster provisioning
4. Migrate existing clusters

### Phase 4: Production Cutover
1. Decommission Terraform platform builder
2. Switch to CAPI-based provisioning
3. Monitor and validate
4. Update documentation

## Manual Steps

### Step 1: Create Management Cluster
```bash
# Create kind cluster for management
kind create cluster --name capi-management

# Install CAPI
clusterctl init --core cluster-api:v1.6.0

# Install RKE2 provider
clusterctl init --infrastructure rke2:v0.3.0

# Install Node Driver provider
clusterctl init --infrastructure openstack:v1.6.0
```

### Step 2: Create Rancher Cluster
```bash
# Apply Rancher cluster template
kubectl apply -f clusters/templates/rancher-cluster.yaml

# Monitor cluster creation
kubectl get clusters -w
kubectl get rke2clusters -w
```

### Step 3: Install Rancher
```bash
# Get cluster kubeconfig
clusterctl get kubeconfig rancher-cluster > rancher-kubeconfig

# Install Rancher
helm install rancher rancher-stable/rancher \
  --kubeconfig rancher-kubeconfig \
  --namespace cattle-system \
  --set hostname=rancher.example.com
```

### Step 4: Create Downstream Clusters
```bash
# Apply downstream cluster template
kubectl apply -f clusters/templates/downstream-cluster.yaml

# Monitor cluster creation
kubectl get clusters -w
kubectl get openstackclusters -w
```

## Benefits of Migration

1. **GitOps**: Everything managed through Git
2. **Declarative**: Infrastructure as code
3. **Scalable**: Can manage hundreds of clusters
4. **Observable**: Clear status and conditions
5. **Extensible**: Easy to add new providers
6. **Reliable**: Self-healing and resilient

## Risks and Mitigation

### Risks
- Learning curve for CAPI
- Migration complexity
- Potential downtime

### Mitigation
- Start with non-production clusters
- Gradual migration approach
- Keep Terraform as backup
- Comprehensive testing
