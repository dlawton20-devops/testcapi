# Velero Backup for Rook Ceph Storage Cluster

This guide provides instructions for installing Velero and creating backups of a Rook Ceph storage cluster, including PVCs and CephFS layers.

## Overview

Velero is a backup and disaster recovery solution for Kubernetes. This setup enables:
- Backup of PersistentVolumeClaims (PVCs) from Rook Ceph
- Backup of CephFS filesystem layers
- Cross-cluster backup and restore capabilities

## Prerequisites

1. **Kubernetes cluster** with kubectl access
2. **Helm 3.x** installed
3. **Object storage backend** (S3, GCS, Azure Blob, etc.) for Velero backups
4. **Rook Ceph cluster** running on the source cluster
5. **Access to both clusters** (source and destination)

## Architecture

```
Source Cluster (Rook Ceph)          Destination Cluster
┌─────────────────────┐             ┌─────────────────────┐
│  Rook Ceph Cluster  │             │   Velero Server     │
│  - CephFS           │  ────────►  │   - Backup Storage  │
│  - RBD              │   Backup    │   - Restore Engine  │
│  - PVCs             │             │                     │
└─────────────────────┘             └─────────────────────┘
         │                                    │
         └──────────► Object Storage ◄────────┘
                      (S3/GCS/Azure)
```

## Installation

**Choose your installation method:**
- **[Manual Installation Guide](MANUAL-INSTALLATION.md)** - Step-by-step manual installation (CLI or Helm)
- **[Quick Start Guide](QUICK-START.md)** - Automated installation with scripts
- **Installation Script** - Run `./install-velero.sh` for interactive setup

### Step 1: Prepare Object Storage Backend

Velero requires an object storage backend. Choose one:

#### Option A: AWS S3
```bash
# Create S3 bucket
aws s3 mb s3://velero-backups --region us-west-2

# Create IAM user with S3 access
aws iam create-user --user-name velero
aws iam attach-user-policy --user-name velero --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

# Create access key
aws iam create-access-key --user-name velero
```

#### Option B: MinIO (for testing)
```bash
# Install MinIO locally
kubectl create namespace minio
helm repo add minio https://charts.min.io/
helm install minio minio/minio \
  --namespace minio \
  --set accessKey=minioadmin \
  --set secretKey=minioadmin \
  --set buckets[0].name=velero \
  --set buckets[0].policy=public
```

### Step 2: Install Velero

For detailed step-by-step instructions, see **[MANUAL-INSTALLATION.md](MANUAL-INSTALLATION.md)**.

#### Quick Reference:

**Using Helm:**
```bash
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update
kubectl create namespace velero
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --values values.yaml
```

**Using Velero CLI:**
```bash
# Download and install Velero CLI (see MANUAL-INSTALLATION.md for details)
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket velero-backups \
  --secret-file ./credentials-velero \
  --use-volume-snapshots=false \
  --use-restic
```

### Step 3: Install Rook Ceph Plugin (if needed)

For Rook Ceph-specific features, you may need additional plugins:

```bash
velero plugin add quay.io/konveyor/velero-plugin-for-csi:latest
```

## Configuration

### Backup Storage Location

Create a BackupStorageLocation resource:

```yaml
apiVersion: velero.io/v1
kind: BackupStorageLocation
metadata:
  name: default
  namespace: velero
spec:
  provider: aws
  objectStorage:
    bucket: velero-backups
  config:
    region: us-west-2
```

### Volume Snapshot Location

For volume snapshots (if using CSI snapshots):

```yaml
apiVersion: velero.io/v1
kind: VolumeSnapshotLocation
metadata:
  name: default
  namespace: velero
spec:
  provider: aws
  config:
    region: us-west-2
```

## Backup Strategies

### Strategy 1: Backup PVCs with Restic

Restic is Velero's file-level backup solution that works with any storage provider.

**Advantages:**
- Works with any PVC type
- No CSI snapshot support required
- File-level granularity

**Limitations:**
- Slower than volume snapshots
- Higher resource usage

### Strategy 2: Backup with CSI Snapshots

For Rook Ceph, you can use CSI volume snapshots if your cluster supports it.

**Advantages:**
- Faster backups
- Block-level efficiency
- Native Ceph integration

**Requirements:**
- CSI snapshot support enabled
- VolumeSnapshotClass configured

### Strategy 3: Hybrid Approach

Combine both methods:
- Use CSI snapshots for large volumes
- Use Restic for volumes without snapshot support

## Usage

See the individual backup configuration files in this directory:
- `backup-pvcs.yaml` - Backup PVCs using Restic
- `backup-cephfs.yaml` - Backup CephFS filesystem
- `backup-schedule.yaml` - Scheduled backups
- `restore-example.yaml` - Example restore configuration

## Troubleshooting

### Check Velero Status
```bash
kubectl get pods -n velero
velero backup describe <backup-name>
velero backup logs <backup-name>
```

### Common Issues

1. **Backup stuck in InProgress**
   - Check Velero pod logs: `kubectl logs -n velero deployment/velero`
   - Verify object storage connectivity
   - Check Restic daemonset pods

2. **PVC backup fails**
   - Ensure Restic is enabled: `--use-restic` flag
   - Verify pod has volume mounted
   - Check Restic daemonset is running

3. **CephFS backup issues**
   - Verify CephFS is accessible
   - Check Ceph cluster health
   - Ensure proper permissions

## References

- [Velero Documentation](https://velero.io/docs/)
- [Rook Ceph Documentation](https://rook.io/docs/rook/latest/)
- [Velero Restic Integration](https://velero.io/docs/main/restic/)

