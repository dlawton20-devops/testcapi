# Manual Commands Reference - Using CRDs and Manifests

This guide uses **Velero CRDs and YAML manifests** with `kubectl apply` instead of CLI commands.

## Prerequisites

```bash
kubectl cluster-info
kubectl get pods -n rook-ceph
kubectl get crd | grep velero.io
```

## 1. Install Velero (One-time setup)

Velero must be installed first (this is the only step that uses CLI or Helm):

```bash
# Create credentials
cat > credentials-velero <<EOF
[default]
aws_access_key_id=minioadmin
aws_secret_access_key=minioadmin123
EOF

# Install Velero
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket velero-backups \
  --secret-file ./credentials-velero \
  --use-volume-snapshots=false \
  --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=https://minio.velero.svc.cluster.local:9000 \
  --use-node-agent \
  --default-volumes-to-fs-backup
```

Or verify BackupStorageLocation exists:
```bash
kubectl get backupstoragelocation -n velero
```

## 2. Create Backup Using CRD Manifest

### Full Cluster Backup

```bash
# Apply the backup manifest
kubectl apply -f configs/backup-full.yaml

# Check backup status
kubectl get backup -n velero
kubectl describe backup rook-ceph-full-backup -n velero

# Watch backup progress
kubectl get backup rook-ceph-full-backup -n velero -w
```

### Rook Operator Only Backup

```bash
kubectl apply -f configs/backup-rook-operator.yaml
kubectl get backup rook-operator-backup -n velero
```

### Application Only Backup

```bash
kubectl apply -f configs/backup-app-only.yaml
kubectl get backup app-production-backup -n velero
```

### Custom Backup Manifest

Create your own backup manifest:

```yaml
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: my-custom-backup
  namespace: velero
spec:
  includedNamespaces:
    - production
  includeClusterResources: true
  defaultVolumesToFsBackup: true
  storageLocation: default
  ttl: 720h
```

Apply it:
```bash
kubectl apply -f my-custom-backup.yaml
```

## 3. Check Backup Status

```bash
# List all backups
kubectl get backup -n velero

# Get backup details
kubectl get backup <backup-name> -n velero -o yaml

# Describe backup
kubectl describe backup <backup-name> -n velero

# Check backup phase
kubectl get backup <backup-name> -n velero -o jsonpath='{.status.phase}'

# Watch backup until complete
kubectl wait --for=condition=Completed backup/<backup-name> -n velero --timeout=600s
```

## 4. Create Restore Using CRD Manifest

### Full Restore

```bash
# Edit restore manifest to set backupName
# Then apply
kubectl apply -f configs/restore-full.yaml

# Check restore status
kubectl get restore -n velero
kubectl describe restore full-cluster-restore -n velero

# Watch restore progress
kubectl get restore full-cluster-restore -n velero -w
```

### Application Only Restore

```bash
kubectl apply -f configs/restore-app-only.yaml
kubectl get restore app-restore -n velero
```

### Rook Operator Restore

```bash
kubectl apply -f configs/restore-rook-operator.yaml
kubectl get restore rook-operator-restore -n velero
```

### Custom Restore Manifest

```yaml
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: my-custom-restore
  namespace: velero
spec:
  backupName: my-custom-backup
  includedNamespaces:
    - production
  includeClusterResources: false
  restorePVs: true
  storageLocation: default
```

Apply it:
```bash
kubectl apply -f my-custom-restore.yaml
```

## 5. Check Restore Status

```bash
# List all restores
kubectl get restore -n velero

# Get restore details
kubectl get restore <restore-name> -n velero -o yaml

# Describe restore
kubectl describe restore <restore-name> -n velero

# Check restore phase
kubectl get restore <restore-name> -n velero -o jsonpath='{.status.phase}'

# Watch restore until complete
kubectl wait --for=condition=Completed restore/<restore-name> -n velero --timeout=600s
```

## 6. Verify Restore

```bash
# Check Ceph cluster
kubectl get cephcluster -n rook-ceph
kubectl get pods -n rook-ceph

# Check PVCs
kubectl get pvc -A

# Check storage classes
kubectl get storageclass

# Check applications
kubectl get pods -A
```

## 7. Create Scheduled Backup Using CRD

```bash
# Apply schedule manifest
kubectl apply -f configs/backup-schedule.yaml

# Check schedules
kubectl get schedule -n velero

# Describe schedule
kubectl describe schedule rook-ceph-daily-backup -n velero

# List backups created by schedule
kubectl get backup -n velero -l app=rook-ceph,backup-type=daily
```

## Common Operations

### List All Backups

```bash
kubectl get backup -n velero
kubectl get backup -n velero -o wide
```

### List Backups by Label

```bash
kubectl get backup -n velero -l app=rook-ceph
kubectl get backup -n velero -l backup-type=full
```

### Delete Backup

```bash
kubectl delete backup <backup-name> -n velero
```

### List All Restores

```bash
kubectl get restore -n velero
kubectl get restore -n velero -o wide
```

### Delete Restore

```bash
kubectl delete restore <restore-name> -n velero
```

### Check BackupStorageLocation

```bash
kubectl get backupstoragelocation -n velero
kubectl describe backupstoragelocation default -n velero
```

### Check Velero Status

```bash
kubectl get pods -n velero
kubectl logs -n velero -l app.kubernetes.io/name=velero --tail=100
kubectl get deployment velero -n velero
```

## Example: Complete Workflow

```bash
# 1. Create backup
kubectl apply -f configs/backup-full.yaml

# 2. Wait for backup to complete
kubectl wait --for=condition=Completed backup/rook-ceph-full-backup -n velero --timeout=600s

# 3. Verify backup
kubectl get backup rook-ceph-full-backup -n velero

# 4. On target cluster, create restore
kubectl apply -f configs/restore-full.yaml

# 5. Wait for restore to complete
kubectl wait --for=condition=Completed restore/full-cluster-restore -n velero --timeout=600s

# 6. Verify restore
kubectl get cephcluster -n rook-ceph
kubectl get pods -n rook-ceph
```

## Backup/Restore Status Phases

**Backup Phases:**
- `New` - Backup is being created
- `InProgress` - Backup is in progress
- `Completed` - Backup completed successfully
- `Failed` - Backup failed
- `PartiallyFailed` - Some resources failed to backup

**Restore Phases:**
- `New` - Restore is being created
- `InProgress` - Restore is in progress
- `Completed` - Restore completed successfully
- `Failed` - Restore failed
- `PartiallyFailed` - Some resources failed to restore

Check phase:
```bash
kubectl get backup <name> -n velero -o jsonpath='{.status.phase}'
kubectl get restore <name> -n velero -o jsonpath='{.status.phase}'
```

## Troubleshooting

### Check Backup Errors

```bash
kubectl get backup <name> -n velero -o yaml | grep -A 10 errors
kubectl describe backup <name> -n velero | grep -i error
```

### Check Restore Errors

```bash
kubectl get restore <name> -n velero -o yaml | grep -A 10 errors
kubectl describe restore <name> -n velero | grep -i error
```

### Check Velero Logs

```bash
kubectl logs -n velero -l app.kubernetes.io/name=velero --tail=100
kubectl logs -n velero -l component=node-agent --tail=100
```

### Test S3 Connectivity

```bash
kubectl run -it --rm debug --image=amazon/aws-cli --restart=Never -- \
  aws s3 ls s3://velero-backups --endpoint-url=https://minio.velero.svc.cluster.local:9000
```
