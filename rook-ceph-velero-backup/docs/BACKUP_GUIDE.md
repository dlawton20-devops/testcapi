# Rook Ceph Backup Guide with Velero

This guide explains how to create backups of your Rook Ceph cluster using Velero.

## Understanding Rook Ceph Backup

When backing up Rook Ceph with Velero, you're backing up:

1. **Kubernetes Resources**: Rook operator, CephCluster, CephBlockPool, CephFilesystem CRDs
2. **Persistent Volume Claims**: All PVCs that use Rook storage classes
3. **Application Data**: Data stored in Ceph volumes (via PVC backups)
4. **Configuration**: Ceph configuration stored in Kubernetes resources

## Backup Strategies

### Strategy 1: Full Cluster Backup

Backup everything in the cluster:

```bash
velero backup create rook-ceph-full-backup \
  --include-cluster-resources=true \
  --include-namespaces=rook-ceph,default,kube-system
```

### Strategy 2: Selective Namespace Backup

Backup specific namespaces:

```bash
velero backup create rook-ceph-selective-backup \
  --include-namespaces=rook-ceph,production,staging
```

### Strategy 3: Application-Focused Backup

Backup applications and their PVCs:

```bash
velero backup create app-backup \
  --include-namespaces=production \
  --include-resources=pods,deployments,services,pvc,pv
```

### Strategy 4: Rook Ceph Resources Only

Backup only Rook Ceph operator and resources:

```bash
velero backup create rook-ceph-operator-backup \
  --include-namespaces=rook-ceph \
  --include-resources=cephclusters.ceph.rook.io,cephblockpools.ceph.rook.io,cephfilesystems.ceph.rook.io
```

## Recommended Backup Process

### Step 1: Backup Rook Ceph Operator and CRDs

```bash
# Backup Rook operator namespace
velero backup create rook-operator-backup \
  --include-namespaces=rook-ceph \
  --include-resources=cephclusters.ceph.rook.io,cephblockpools.ceph.rook.io,cephfilesystems.ceph.rook.io,cephobjectstores.ceph.rook.io,deployments,statefulsets,configmaps,secrets
```

### Step 2: Backup Application Namespaces with PVCs

```bash
# Backup each application namespace
velero backup create app-production-backup \
  --include-namespaces=production \
  --default-volumes-to-fs-backup
```

### Step 3: Backup System Resources (Optional)

```bash
# Backup system configurations
velero backup create system-config-backup \
  --include-namespaces=kube-system \
  --include-resources=configmaps,secrets
```

## Creating a Complete Backup Script

Here's a comprehensive backup script:

```bash
#!/bin/bash
set -e

BACKUP_NAME="rook-ceph-backup-$(date +%Y%m%d-%H%M%S)"
NAMESPACES="rook-ceph production staging"

echo "Creating backup: $BACKUP_NAME"

# Create backup
velero backup create $BACKUP_NAME \
  --include-namespaces=$NAMESPACES \
  --include-cluster-resources=true \
  --default-volumes-to-fs-backup \
  --wait

# Check backup status
velero backup describe $BACKUP_NAME

# Show backup details
velero backup get $BACKUP_NAME
```

## Backup Options

### Include/Exclude Resources

```bash
# Include specific resources
velero backup create backup-name \
  --include-resources=pods,deployments,services,pvc

# Exclude specific resources
velero backup create backup-name \
  --exclude-resources=events,secrets
```

### Include/Exclude Namespaces

```bash
# Include specific namespaces
velero backup create backup-name \
  --include-namespaces=production,staging

# Exclude specific namespaces
velero backup create backup-name \
  --exclude-namespaces=kube-system,kube-public
```

### Volume Backup Methods

```bash
# Use filesystem backup (default for Rook Ceph)
velero backup create backup-name \
  --default-volumes-to-fs-backup

# Use snapshot backup (if supported)
velero backup create backup-name \
  --snapshot-volumes
```

### Label Selectors

```bash
# Backup resources with specific labels
velero backup create backup-name \
  --selector app=myapp,env=production
```

## Scheduled Backups

Create scheduled backups for automatic backups:

```bash
# Daily backup at 2 AM
velero schedule create rook-ceph-daily \
  --schedule="0 2 * * *" \
  --include-namespaces=rook-ceph,production \
  --default-volumes-to-fs-backup

# Weekly backup on Sundays at 3 AM
velero schedule create rook-ceph-weekly \
  --schedule="0 3 * * 0" \
  --include-namespaces=rook-ceph,production \
  --default-volumes-to-fs-backup \
  --ttl=720h
```

Or use a YAML file (see `configs/backup-schedule.yaml`):

```bash
kubectl apply -f configs/backup-schedule.yaml
```

## Monitoring Backups

### Check Backup Status

```bash
# List all backups
velero backup get

# Describe specific backup
velero backup describe <backup-name>

# View backup logs
velero backup logs <backup-name>

# Check backup in Kubernetes
kubectl get backups -n velero
```

### Backup Status Phases

- **New**: Backup is being created
- **InProgress**: Backup is in progress
- **Completed**: Backup completed successfully
- **Failed**: Backup failed
- **PartiallyFailed**: Some resources failed to backup
- **FailedValidation**: Backup validation failed

### Verify Backup Contents

```bash
# Download backup contents (if needed)
velero backup download <backup-name>

# Check backup storage
aws s3 ls s3://velero-backups/backups/<backup-name>/ --endpoint-url=https://minio.velero.svc.cluster.local:9000
```

## Backup Retention

### Set TTL (Time To Live)

```bash
# Backup expires after 30 days
velero backup create backup-name \
  --ttl=720h \
  --include-namespaces=production
```

### Manual Cleanup

```bash
# Delete old backup
velero backup delete <backup-name>

# Delete backups older than 30 days
velero backup delete --older-than 720h
```

## Best Practices

1. **Regular Backups**: Schedule daily backups for critical data
2. **Test Restores**: Regularly test restore procedures
3. **Backup Verification**: Verify backup integrity after creation
4. **Retention Policy**: Set appropriate TTL based on requirements
5. **Documentation**: Document backup procedures and schedules
6. **Monitoring**: Set up alerts for backup failures
7. **Off-Site Storage**: Consider replicating backups to different regions

## Backup Size Considerations

- **PVC Data**: Largest component, depends on application data
- **Kubernetes Resources**: Small, typically < 100MB
- **Metadata**: Minimal overhead

Estimate backup size:
```bash
# Check PVC sizes
kubectl get pvc -A -o json | jq '.items[] | {name: .metadata.name, namespace: .metadata.namespace, size: .spec.resources.requests.storage}'
```

## Troubleshooting

### Backup Stuck in Progress

```bash
# Check Velero pod logs
kubectl logs -n velero -l app.kubernetes.io/name=velero --tail=100

# Check node-agent logs
kubectl logs -n velero -l component=node-agent --tail=100
```

### Backup Fails with Volume Errors

```bash
# Check if PVCs are mounted
kubectl get pvc -A

# Check pod status
kubectl get pods -A | grep -E "Error|CrashLoop"
```

### Backup Storage Full

```bash
# Check backup storage usage
aws s3 ls s3://velero-backups/ --recursive --summarize --endpoint-url=https://minio.velero.svc.cluster.local:9000

# Clean up old backups
velero backup delete --older-than 720h
```

## Next Steps

After creating backups:
1. Verify backup integrity using `verify-backup.sh`
2. Test restore procedures in a non-production environment
3. Review the [Restore Guide](RESTORE_GUIDE.md) for restore procedures

