# Rook Ceph Backup Guide with Velero

This guide explains how to create backups of your Rook Ceph cluster using Velero **CRDs and YAML manifests**.

## Understanding Rook Ceph Backup

When backing up Rook Ceph with Velero, you're backing up:

1. **Kubernetes Resources**: Rook operator, CephCluster, CephBlockPool, CephFilesystem CRDs
2. **Persistent Volume Claims**: All PVCs that use Rook storage classes
3. **Application Data**: Data stored in Ceph volumes (via PVC backups)
4. **Configuration**: Ceph configuration stored in Kubernetes resources

## Backup Strategies Using CRDs

All backups are created using `Backup` CRD manifests with `kubectl apply`.

### Strategy 1: Full Cluster Backup

Backup everything in the cluster using manifest:

```bash
# Apply pre-configured manifest
kubectl apply -f configs/backup-full.yaml

# Or create custom manifest
cat > my-backup.yaml <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: rook-ceph-full-backup
  namespace: velero
spec:
  includedNamespaces:
    - rook-ceph
    - production
    - staging
  includeClusterResources: true
  defaultVolumesToFsBackup: true
  storageLocation: default
  ttl: 720h
EOF

kubectl apply -f my-backup.yaml
kubectl get backup -n velero
```

**Check backup status:**
```bash
kubectl get backup rook-ceph-full-backup -n velero
kubectl describe backup rook-ceph-full-backup -n velero
kubectl wait --for=condition=Completed backup/rook-ceph-full-backup -n velero --timeout=600s
```

### Strategy 2: Selective Namespace Backup

Backup specific namespaces using manifest:

```yaml
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: rook-ceph-selective-backup
  namespace: velero
spec:
  includedNamespaces:
    - rook-ceph
    - production
    - staging
  includeClusterResources: false
  defaultVolumesToFsBackup: true
  storageLocation: default
```

```bash
kubectl apply -f selective-backup.yaml
kubectl get backup -n velero
```

### Strategy 3: Application-Focused Backup

Backup applications and their PVCs:

```bash
velero backup create app-backup \
  --include-namespaces=production \
  --include-resources=pods,deployments,services,pvc,pv
```

### Strategy 4: Rook Ceph Resources Only

Backup only Rook Ceph operator and resources using manifest:

```bash
# Use pre-configured manifest
kubectl apply -f configs/backup-rook-operator.yaml

# Check status
kubectl get backup rook-operator-backup -n velero
```

## Recommended Backup Process Using CRDs

### Step 1: Backup Rook Ceph Operator and CRDs

```bash
# Apply Rook operator backup manifest
kubectl apply -f configs/backup-rook-operator.yaml

# Wait for completion
kubectl wait --for=condition=Completed backup/rook-operator-backup -n velero --timeout=600s

# Verify
kubectl get backup rook-operator-backup -n velero
```

### Step 2: Backup Application Namespaces with PVCs

```bash
# Apply application backup manifest
kubectl apply -f configs/backup-app-only.yaml

# Or create custom manifest for specific namespaces
# Wait for completion
kubectl wait --for=condition=Completed backup/app-production-backup -n velero --timeout=600s

# Verify
kubectl get backup -n velero
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

## Scheduled Backups Using Schedule CRD

Create scheduled backups using `Schedule` CRD:

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

The schedule manifest creates backups automatically based on the cron schedule defined in the CRD.

## Monitoring Backups

### Check Backup Status

```bash
# List all backups
kubectl get backup -n velero

# Describe specific backup
kubectl describe backup <backup-name> -n velero

# Get backup details as YAML
kubectl get backup <backup-name> -n velero -o yaml

# Check backup phase
kubectl get backup <backup-name> -n velero -o jsonpath='{.status.phase}'

# Watch backup progress
kubectl get backup <backup-name> -n velero -w

# Wait for backup to complete
kubectl wait --for=condition=Completed backup/<backup-name> -n velero --timeout=600s
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
# Delete backup using kubectl
kubectl delete backup <backup-name> -n velero

# Delete multiple backups
kubectl delete backup -n velero -l backup-type=daily
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

