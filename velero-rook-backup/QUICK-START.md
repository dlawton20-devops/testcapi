# Quick Start Guide: Velero Backup for Rook Ceph

This guide provides a quick start for backing up your Rook Ceph storage cluster using Velero.

## Prerequisites Checklist

- [ ] Kubernetes cluster with kubectl access
- [ ] Helm 3.x installed
- [ ] Rook Ceph cluster running
- [ ] Object storage backend (S3, MinIO, etc.) configured
- [ ] Access to both source and destination clusters (if cross-cluster)

## Quick Installation (5 minutes)

### Step 1: Install Velero

```bash
cd velero-rook-backup
./install-velero.sh
```

Follow the prompts to:
1. Select your object storage provider (AWS S3, MinIO, etc.)
2. Enter your credentials
3. Choose installation method (Helm recommended)

### Step 2: Verify Installation

```bash
# Check Velero pods
kubectl get pods -n velero

# Check backup storage location
kubectl get backupstoragelocation -n velero

# Verify Restic daemonset (for PVC backups)
kubectl get daemonset -n velero
```

### Step 3: Create Your First Backup

#### Option A: Backup PVCs Only

```bash
./create-backup.sh pvc my-first-backup
```

#### Option B: Backup CephFS

```bash
./create-backup.sh cephfs my-cephfs-backup
```

#### Option C: Full Backup

```bash
./create-backup.sh full my-full-backup
```

### Step 4: Monitor Backup Progress

```bash
# List all backups
./create-backup.sh list

# Check backup status
./create-backup.sh describe my-first-backup

# View backup logs
./create-backup.sh logs my-first-backup
```

## Using YAML Manifests

Alternatively, you can use the provided YAML manifests:

```bash
# Backup PVCs
kubectl apply -f backup-pvcs.yaml

# Backup CephFS
kubectl apply -f backup-cephfs.yaml

# Set up scheduled backups
kubectl apply -f backup-schedule.yaml
```

## Setting Up Scheduled Backups

To automate backups, apply the schedule:

```bash
kubectl apply -f backup-schedule.yaml
```

This creates:
- Daily PVC backups at 2 AM
- Daily CephFS backups at 3 AM
- Weekly full backups on Sundays at 1 AM

## Restoring from Backup

### Restore to Same Cluster

```bash
# Create restore from backup
kubectl apply -f restore-example.yaml

# Or use Velero CLI
velero restore create --from-backup my-first-backup
```

### Restore to Different Cluster

1. Install Velero on the destination cluster
2. Ensure backup storage is accessible
3. Create restore pointing to the backup:

```bash
velero restore create restore-name \
  --from-backup my-first-backup \
  --namespace-mapping source-ns:dest-ns
```

## Common Tasks

### List All Backups

```bash
kubectl get backups -n velero
```

### Delete a Backup

```bash
kubectl delete backup <backup-name> -n velero
```

### Check Backup Details

```bash
velero backup describe <backup-name>
```

### Download Backup Logs

```bash
velero backup logs <backup-name> > backup.log
```

## Troubleshooting

### Backup Stuck in "InProgress"

```bash
# Check Velero server logs
kubectl logs -n velero deployment/velero

# Check Restic daemonset logs
kubectl logs -n velero -l component=restic
```

### PVC Not Backing Up

1. Ensure Restic is enabled: `kubectl get daemonset restic -n velero`
2. Verify pod has volume mounted
3. Check pod annotations: `kubectl get pod <pod-name> -o yaml | grep backup.velero.io`

### CephFS Backup Issues

1. Verify CephFS is accessible: `kubectl get cephfilesystem -n rook-ceph`
2. Check Ceph cluster health
3. Ensure proper permissions on CephFS volumes

## Next Steps

- Review the full [README.md](README.md) for detailed documentation
- Customize backup schedules in `backup-schedule.yaml`
- Set up cross-cluster restore procedures
- Configure backup retention policies
- Set up monitoring and alerting for backups

## Support

For issues or questions:
- [Velero Documentation](https://velero.io/docs/)
- [Rook Ceph Documentation](https://rook.io/docs/rook/latest/)
- Check backup logs: `velero backup logs <backup-name>`

