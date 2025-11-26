# Rook Ceph Restore Guide with Velero

This guide explains how to restore a Rook Ceph cluster from Velero backups to a target cluster.

## Prerequisites

1. **Target cluster** with Rook Ceph installed
2. **Velero installed** on target cluster with access to backup storage
3. **Backup exists** in the backup storage location
4. **kubectl** configured for target cluster

## Pre-Restore Checklist

- [ ] Target cluster has Rook Ceph operator installed
- [ ] Velero is installed on target cluster
- [ ] Backup storage is accessible from target cluster
- [ ] Sufficient storage capacity in target cluster
- [ ] Target cluster has compatible storage classes
- [ ] Namespace mappings identified (if needed)

## Restore Strategies

### Strategy 1: Full Cluster Restore

Restore everything from backup:

```bash
velero restore create rook-ceph-restore \
  --from-backup rook-ceph-backup-20240115-020000 \
  --include-cluster-resources=true
```

### Strategy 2: Selective Namespace Restore

Restore specific namespaces:

```bash
velero restore create app-restore \
  --from-backup app-backup-20240115-020000 \
  --include-namespaces=production
```

### Strategy 3: Application-Only Restore

Restore applications without Rook operator:

```bash
velero restore create app-restore \
  --from-backup app-backup-20240115-020000 \
  --include-namespaces=production \
  --include-resources=pods,deployments,services,pvc
```

## Recommended Restore Process

### Step 1: Verify Backup Availability

```bash
# List available backups
velero backup get

# Describe backup to see contents
velero backup describe <backup-name>

# Verify backup is complete
velero backup get <backup-name>
```

### Step 2: Restore Rook Ceph Operator (if needed)

If the target cluster doesn't have Rook Ceph installed:

```bash
# Restore Rook operator namespace
velero restore create rook-operator-restore \
  --from-backup rook-operator-backup-20240115-020000 \
  --include-namespaces=rook-ceph \
  --include-resources=cephclusters.ceph.rook.io,cephblockpools.ceph.rook.io,cephfilesystems.ceph.rook.io,deployments,statefulsets,configmaps,secrets

# Wait for Rook operator to be ready
kubectl wait --for=condition=ready pod -l app=rook-ceph-operator -n rook-ceph --timeout=300s
```

### Step 3: Restore Ceph Cluster Configuration

```bash
# Restore CephCluster resource
velero restore create ceph-cluster-restore \
  --from-backup rook-operator-backup-20240115-020000 \
  --include-namespaces=rook-ceph \
  --include-resources=cephclusters.ceph.rook.io

# Wait for Ceph cluster to be healthy
kubectl get cephcluster -n rook-ceph
kubectl wait --for=condition=ready cephcluster -n rook-ceph --timeout=600s
```

### Step 4: Restore Storage Classes and Pools

```bash
# Restore CephBlockPool and CephFilesystem
velero restore create storage-restore \
  --from-backup rook-operator-backup-20240115-020000 \
  --include-namespaces=rook-ceph \
  --include-resources=cephblockpools.ceph.rook.io,cephfilesystems.ceph.rook.io,storageclasses.storage.k8s.io

# Verify storage classes
kubectl get storageclass
```

### Step 5: Restore Application Namespaces

```bash
# Restore application namespace with PVCs
velero restore create app-restore \
  --from-backup app-production-backup-20240115-020000 \
  --include-namespaces=production \
  --namespace-mappings production:production
```

## Restore Options

### Namespace Mapping

Restore to different namespace names:

```bash
velero restore create restore-name \
  --from-backup backup-name \
  --namespace-mappings source-ns:target-ns,old-prod:new-prod
```

### Resource Filtering

```bash
# Include specific resources
velero restore create restore-name \
  --from-backup backup-name \
  --include-resources=pods,deployments,services,pvc

# Exclude specific resources
velero restore create restore-name \
  --from-backup backup-name \
  --exclude-resources=events,secrets
```

### Label Selectors

```bash
# Restore resources with specific labels
velero restore create restore-name \
  --from-backup backup-name \
  --selector app=myapp,env=production
```

### Restore Hooks

Execute commands before/after restore:

```bash
# Create restore with hooks
velero restore create restore-name \
  --from-backup backup-name \
  --restore-hooks-only
```

## Complete Restore Script

```bash
#!/bin/bash
set -e

BACKUP_NAME=$1
TARGET_NAMESPACE=${2:-production}

if [ -z "$BACKUP_NAME" ]; then
  echo "Usage: $0 <backup-name> [target-namespace]"
  echo "Available backups:"
  velero backup get
  exit 1
fi

echo "Restoring from backup: $BACKUP_NAME"
echo "Target namespace: $TARGET_NAMESPACE"

# Verify backup exists
if ! velero backup describe $BACKUP_NAME &>/dev/null; then
  echo "Error: Backup $BACKUP_NAME not found"
  exit 1
fi

# Create restore
RESTORE_NAME="restore-$(date +%Y%m%d-%H%M%S)"
velero restore create $RESTORE_NAME \
  --from-backup $BACKUP_NAME \
  --include-namespaces=$TARGET_NAMESPACE \
  --wait

# Check restore status
velero restore describe $RESTORE_NAME

# Show restore details
velero restore get $RESTORE_NAME
```

## Restore to Different Cluster

### Step 1: Install Velero on Target Cluster

```bash
# On target cluster, install Velero pointing to same backup storage
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket velero-backups \
  --secret-file ./credentials-velero \
  --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=https://minio.velero.svc.cluster.local:9000 \
  --use-node-agent \
  --default-volumes-to-fs-backup
```

### Step 2: Verify Backup Access

```bash
# On target cluster, verify backups are visible
velero backup get
```

### Step 3: Restore from Backup

```bash
# Restore to target cluster
velero restore create full-restore \
  --from-backup rook-ceph-backup-20240115-020000 \
  --include-cluster-resources=true
```

## Monitoring Restore

### Check Restore Status

```bash
# List all restores
velero restore get

# Describe specific restore
velero restore describe <restore-name>

# View restore logs
velero restore logs <restore-name>

# Check restore in Kubernetes
kubectl get restores -n velero
```

### Restore Status Phases

- **New**: Restore is being created
- **InProgress**: Restore is in progress
- **Completed**: Restore completed successfully
- **Failed**: Restore failed
- **PartiallyFailed**: Some resources failed to restore

### Verify Restored Resources

```bash
# Check restored pods
kubectl get pods -A

# Check restored PVCs
kubectl get pvc -A

# Check Ceph cluster status
kubectl get cephcluster -n rook-ceph
kubectl get pods -n rook-ceph

# Check storage classes
kubectl get storageclass
```

## Post-Restore Verification

### 1. Verify Ceph Cluster Health

```bash
# Check Ceph cluster status
kubectl get cephcluster -n rook-ceph -o yaml

# Check Ceph pods
kubectl get pods -n rook-ceph

# Check Ceph health (if ceph toolbox available)
kubectl exec -it -n rook-ceph deploy/rook-ceph-tools -- ceph status
```

### 2. Verify Storage Classes

```bash
# List storage classes
kubectl get storageclass

# Verify default storage class
kubectl get storageclass -o json | jq '.items[] | select(.metadata.annotations."storageclass.kubernetes.io/is-default-class"=="true")'
```

### 3. Verify PVCs

```bash
# Check PVC status
kubectl get pvc -A

# Verify PVCs are bound
kubectl get pvc -A | grep -v Bound
```

### 4. Verify Applications

```bash
# Check application pods
kubectl get pods -n <namespace>

# Check application services
kubectl get svc -n <namespace>

# Test application connectivity
kubectl port-forward -n <namespace> svc/<service-name> 8080:80
```

## Common Restore Scenarios

### Scenario 1: Disaster Recovery

Complete cluster restore after disaster:

```bash
# 1. Install Rook Ceph on new cluster
# 2. Install Velero on new cluster
# 3. Restore from latest backup
velero restore create disaster-recovery \
  --from-backup rook-ceph-backup-20240115-020000 \
  --include-cluster-resources=true
```

### Scenario 2: Namespace Migration

Move namespace to different cluster:

```bash
# Restore namespace with mapping
velero restore create namespace-migration \
  --from-backup app-backup-20240115-020000 \
  --include-namespaces=production \
  --namespace-mappings production:production-new
```

### Scenario 3: Application Rollback

Rollback to previous application state:

```bash
# Restore only application resources
velero restore create app-rollback \
  --from-backup app-backup-20240115-020000 \
  --include-namespaces=production \
  --include-resources=pods,deployments,services,configmaps
```

## Troubleshooting

### Restore Stuck in Progress

```bash
# Check Velero pod logs
kubectl logs -n velero -l app.kubernetes.io/name=velero --tail=100

# Check node-agent logs
kubectl logs -n velero -l component=node-agent --tail=100
```

### PVCs Not Restoring

```bash
# Check PVC status
kubectl get pvc -A

# Check storage class exists
kubectl get storageclass

# Check restore logs for errors
velero restore logs <restore-name> | grep -i pvc
```

### Ceph Cluster Not Healthy After Restore

```bash
# Check Ceph cluster status
kubectl get cephcluster -n rook-ceph -o yaml

# Check Ceph pods
kubectl get pods -n rook-ceph

# Check Ceph logs
kubectl logs -n rook-ceph -l app=rook-ceph-operator
```

### Storage Class Mismatch

```bash
# List storage classes in target cluster
kubectl get storageclass

# Update PVC storage class if needed
kubectl patch pvc <pvc-name> -n <namespace> -p '{"spec":{"storageClassName":"<new-storage-class>"}}'
```

## Best Practices

1. **Test Restores**: Regularly test restore procedures in non-production
2. **Incremental Restores**: Restore operator first, then applications
3. **Verify Health**: Always verify cluster and application health after restore
4. **Documentation**: Document restore procedures and any issues encountered
5. **Backup Before Restore**: Create backup before major restore operations
6. **Namespace Mapping**: Use namespace mappings for cross-cluster restores
7. **Resource Filtering**: Restore only what's needed

## Next Steps

After successful restore:
1. Verify all applications are running correctly
2. Test application functionality
3. Monitor cluster health
4. Update documentation with restore procedures

