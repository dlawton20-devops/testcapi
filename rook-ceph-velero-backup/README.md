# Rook Ceph Backup and Restore with Velero

This guide demonstrates how to backup a Rook Ceph cluster using Velero and restore it to another location/cluster.

## Overview

Velero is a backup and restore tool for Kubernetes that can backup:
- Kubernetes resources (Pods, Services, ConfigMaps, etc.)
- Persistent Volumes (PVs) and Persistent Volume Claims (PVCs)
- Rook Ceph cluster configuration and data

## Architecture

```
Source Cluster                    Backup Storage              Target Cluster
┌──────────────┐                 ┌──────────────┐           ┌──────────────┐
│              │                 │              │           │              │
│ Rook Ceph    │───Backup───────▶│  S3/MinIO/   │───Restore▶│ Rook Ceph    │
│ Cluster      │                 │  Object      │           │ Cluster      │
│              │                 │  Storage     │           │              │
│ - CephFS     │                 │              │           │ - CephFS     │
│ - RBD        │                 │              │           │ - RBD        │
│ - Object     │                 │              │           │ - Object     │
│   Store      │                 │              │           │   Store      │
└──────────────┘                 └──────────────┘           └──────────────┘
```

## Prerequisites

- Kubernetes cluster with Rook Ceph installed
- kubectl configured for source and target clusters
- S3-compatible object storage (MinIO, AWS S3, etc.)
- Velero CLI installed locally

## Quick Start - Manual Execution

- **[MANUAL_COMMANDS.md](MANUAL_COMMANDS.md)** - Quick command reference (copy/paste ready)
- **[QUICK_START.md](QUICK_START.md)** - Detailed step-by-step guide with explanations

**Basic manual workflow:**

1. **Install Velero on source cluster**:
   ```bash
   velero install --provider aws --plugins velero/velero-plugin-for-aws:v1.8.0 \
     --bucket velero-backups --secret-file ./credentials-velero \
     --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=https://minio.velero.svc.cluster.local:9000 \
     --use-node-agent --default-volumes-to-fs-backup
   ```

2. **Create backup**:
   ```bash
   velero backup create rook-ceph-backup-$(date +%Y%m%d-%H%M%S) \
     --include-namespaces=rook-ceph,production \
     --include-cluster-resources=true --default-volumes-to-fs-backup --wait
   ```

3. **Install Velero on target cluster**: Same command as step 1, pointing to same backup storage

4. **Restore backup**:
   ```bash
   velero restore create restore-$(date +%Y%m%d-%H%M%S) \
     --from-backup <backup-name> --include-cluster-resources=true --wait
   ```

> **Note**: This guide focuses on **manual execution**. Scripts in the `scripts/` directory are optional and provided for reference only.

## Directory Structure

```
rook-ceph-velero-backup/
├── README.md                    # This file
├── docs/
│   ├── SETUP_GUIDE.md          # Detailed setup instructions
│   ├── BACKUP_GUIDE.md          # Backup procedures
│   ├── RESTORE_GUIDE.md         # Restore procedures
│   └── TROUBLESHOOTING.md       # Common issues and solutions
├── scripts/
│   ├── install-velero.sh        # Install Velero on cluster
│   ├── create-backup.sh         # Create backup of Rook Ceph
│   ├── restore-backup.sh         # Restore backup to target cluster
│   ├── list-backups.sh           # List available backups
│   └── verify-backup.sh          # Verify backup integrity
└── configs/
    ├── velero-values.yaml        # Velero Helm values
    ├── backup-schedule.yaml      # Scheduled backup configuration
    └── restore-config.yaml       # Restore configuration example
```

## Important Considerations

### What Gets Backed Up

✅ **Backed Up:**
- Rook operator and CRDs
- CephCluster, CephBlockPool, CephFilesystem resources
- PVCs and their metadata
- Application data stored in Ceph volumes

⚠️ **Not Backed Up by Default:**
- Ceph OSD data directly (backed up via PVC snapshots)
- Ceph configuration stored outside Kubernetes
- Node-specific configurations

### Backup Storage Requirements

- **S3-compatible storage** is required
- Ensure sufficient storage capacity (typically 2-3x your data size)
- Consider backup retention policies
- Plan for cross-region replication if needed

### Restore Considerations

- Target cluster must have Rook Ceph installed
- Target cluster should have similar node configuration
- Storage classes must be compatible
- Namespace mappings may be required

## Documentation

- [Setup Guide](docs/SETUP_GUIDE.md) - Install and configure Velero
- [Backup Guide](docs/BACKUP_GUIDE.md) - Create and manage backups
- [Restore Guide](docs/RESTORE_GUIDE.md) - Restore backups to target cluster
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and solutions

## Examples

- **Manual Commands**: See [QUICK_START.md](QUICK_START.md) for complete manual command examples
- **Configuration Files**: See the `configs/` directory for example YAML configurations
- **Scripts** (optional): Scripts in `scripts/` directory are provided for reference only - all operations can be done manually

