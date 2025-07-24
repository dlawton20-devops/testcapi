# Quick Start Guide

This guide will help you quickly deploy Rook Ceph using this Helm chart.

## Prerequisites

- Kubernetes cluster (v1.28 - v1.33)
- Helm 3.x
- kubectl configured to access your cluster
- Raw storage devices available on your nodes

## Step 1: Get Node Information

First, identify your nodes and their hostnames:

```bash
./deploy.sh -n
```

This will show you all available nodes in your cluster. Note down the hostnames.

## Step 2: Prepare Your Configuration

Copy the example configuration and customize it for your environment:

```bash
cp examples/3-nodes-example.yaml my-config.yaml
```

Edit `my-config.yaml` and replace:
- Node hostnames with your actual node hostnames
- Device names with your actual device names (e.g., `sdb`, `sdc`, etc.)

## Step 3: Deploy Rook Ceph

Deploy using the deployment script:

```bash
./deploy.sh -f my-config.yaml
```

Or deploy manually with Helm:

```bash
# Add Rook repository
helm repo add rook-release https://charts.rook.io/release
helm repo update

# Deploy the chart
helm install rook-ceph . -f my-config.yaml --wait --timeout=10m
```

## Step 4: Verify Deployment

Check that all pods are running:

```bash
kubectl get pods -n rook-ceph
```

Check cluster health:

```bash
kubectl -n rook-ceph exec -it deploy/rook-ceph-toolbox -- ceph status
```

## Step 5: Use Storage

Create a PVC using the RBD storage class:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: rook-ceph-block
  resources:
    requests:
      storage: 1Gi
```

## Troubleshooting

### Common Issues

1. **OSDs not being created**: Ensure devices are raw (not formatted)
2. **Cluster not healthy**: Check device availability and permissions
3. **Node names don't match**: Verify hostnames match `kubernetes.io/hostname` labels

### Useful Commands

```bash
# Check node labels
kubectl get nodes --show-labels

# Check available devices on nodes
kubectl -n rook-ceph exec -it deploy/rook-ceph-toolbox -- lsblk

# Check OSD status
kubectl -n rook-ceph exec -it deploy/rook-ceph-toolbox -- ceph osd tree

# Check storage classes
kubectl get storageclass
```

## Next Steps

- Read the full [README.md](README.md) for detailed configuration options
- Explore the [examples/](examples/) directory for more configuration examples
- Visit the [Rook documentation](https://rook.io/docs/rook/latest/) for advanced features 