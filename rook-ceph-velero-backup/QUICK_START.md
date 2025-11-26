# Quick Start Guide - Manual Execution

This guide provides **manual commands only** for backing up and restoring Rook Ceph with Velero. Copy and paste these commands directly.

## Prerequisites Check

```bash
# Check if Velero CLI is installed
velero version --client-only

# Check kubectl connectivity
kubectl cluster-info

# Check if Rook Ceph is installed
kubectl get pods -n rook-ceph
```

## Step 1: Set Up Object Storage (MinIO Example)

If you don't have object storage yet, install MinIO:

```bash
# Install MinIO using Helm
helm repo add minio https://charts.min.io/
helm install minio minio/minio \
  --namespace velero \
  --create-namespace \
  --set mode=standalone \
  --set persistence.size=100Gi \
  --set rootUser=minioadmin \
  --set rootPassword=minioadmin123

# Wait for MinIO to be ready
kubectl wait --for=condition=ready pod -l app=minio -n velero --timeout=300s

# Get MinIO service endpoint
kubectl get svc minio -n velero
```

## Step 2: Create Credentials File

Create a credentials file for Velero:

```bash
cat > credentials-velero <<EOF
[default]
aws_access_key_id=minioadmin
aws_secret_access_key=minioadmin123
EOF
```

For AWS S3, use your actual credentials:
```bash
cat > credentials-velero <<EOF
[default]
aws_access_key_id=YOUR_ACCESS_KEY
aws_secret_access_key=YOUR_SECRET_KEY
EOF
```

## Step 3: Install Velero on Source Cluster

Set your variables first:

```bash
# Set variables (adjust as needed)
BUCKET_NAME=velero-backups
REGION=minio
S3_ENDPOINT=https://minio.velero.svc.cluster.local:9000
```

Install Velero:

```bash
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket $BUCKET_NAME \
  --secret-file ./credentials-velero \
  --use-volume-snapshots=false \
  --backup-location-config region=$REGION,s3ForcePathStyle="true",s3Url=$S3_ENDPOINT \
  --use-node-agent \
  --default-volumes-to-fs-backup
```

Verify installation:

```bash
# Check Velero pods
kubectl get pods -n velero

# Wait for Velero to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=velero -n velero --timeout=300s

# Check backup storage location
velero backup-location get
```

## Step 4: Create a Backup

### Full Cluster Backup

```bash
# Create backup with timestamp
BACKUP_NAME="rook-ceph-full-backup-$(date +%Y%m%d-%H%M%S)"
velero backup create $BACKUP_NAME \
  --include-namespaces=rook-ceph,production \
  --include-cluster-resources=true \
  --default-volumes-to-fs-backup \
  --wait

# Check backup status
velero backup get
velero backup describe $BACKUP_NAME
```

### Rook Operator Only Backup

```bash
BACKUP_NAME="rook-operator-backup-$(date +%Y%m%d-%H%M%S)"
velero backup create $BACKUP_NAME \
  --include-namespaces=rook-ceph \
  --include-resources=cephclusters.ceph.rook.io,cephblockpools.ceph.rook.io,cephfilesystems.ceph.rook.io,cephobjectstores.ceph.rook.io,deployments,statefulsets,configmaps,secrets \
  --default-volumes-to-fs-backup \
  --wait

velero backup describe $BACKUP_NAME
```

### Application Namespaces Only

```bash
BACKUP_NAME="app-backup-$(date +%Y%m%d-%H%M%S)"
velero backup create $BACKUP_NAME \
  --include-namespaces=production,staging \
  --default-volumes-to-fs-backup \
  --wait

velero backup describe $BACKUP_NAME
```

## Step 5: Verify Backup

```bash
# List all backups
velero backup get

# Describe specific backup (replace with your backup name)
velero backup describe <backup-name>

# View backup logs
velero backup logs <backup-name>

# Check backup phase (should be "Completed")
velero backup describe <backup-name> | grep Phase
```

## Step 6: Install Velero on Target Cluster

Switch to your target cluster context:

```bash
# List available contexts
kubectl config get-contexts

# Switch to target cluster
kubectl config use-context <target-cluster-context>
```

Install Velero (same command as Step 3, pointing to same backup storage):

```bash
# Set variables (same as source cluster)
BUCKET_NAME=velero-backups
REGION=minio
S3_ENDPOINT=https://minio.velero.svc.cluster.local:9000

# Install Velero
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket $BUCKET_NAME \
  --secret-file ./credentials-velero \
  --backup-location-config region=$REGION,s3ForcePathStyle="true",s3Url=$S3_ENDPOINT \
  --use-node-agent \
  --default-volumes-to-fs-backup

# Verify backups are visible
velero backup get
```

## Step 7: Restore from Backup

### Full Restore

```bash
# Replace <backup-name> with your actual backup name
RESTORE_NAME="restore-$(date +%Y%m%d-%H%M%S)"
velero restore create $RESTORE_NAME \
  --from-backup <backup-name> \
  --include-cluster-resources=true \
  --wait

# Check restore status
velero restore get
velero restore describe $RESTORE_NAME
```

### Restore Specific Namespaces

```bash
RESTORE_NAME="restore-$(date +%Y%m%d-%H%M%S)"
velero restore create $RESTORE_NAME \
  --from-backup <backup-name> \
  --include-namespaces=production \
  --wait

velero restore describe $RESTORE_NAME
```

### Restore with Namespace Mapping

```bash
RESTORE_NAME="restore-$(date +%Y%m%d-%H%M%S)"
velero restore create $RESTORE_NAME \
  --from-backup <backup-name> \
  --include-namespaces=production \
  --namespace-mappings production:production-new \
  --wait

velero restore describe $RESTORE_NAME
```

## Step 8: Verify Restore

```bash
# Check Ceph cluster
kubectl get cephcluster -n rook-ceph
kubectl get pods -n rook-ceph

# Check Ceph cluster health (if toolbox available)
kubectl exec -it -n rook-ceph deploy/rook-ceph-tools -- ceph status

# Check PVCs
kubectl get pvc -A

# Check application pods
kubectl get pods -A

# Check storage classes
kubectl get storageclass

# Check specific namespace
kubectl get all -n <namespace>
```

## Common Manual Commands

### List Backups

```bash
# Simple list
velero backup get

# Detailed information
velero backup describe <backup-name> --details
```

### Delete Backup

```bash
velero backup delete <backup-name>
```

### Create Scheduled Backup

```bash
# Daily backup at 2 AM UTC
velero schedule create rook-ceph-daily \
  --schedule="0 2 * * *" \
  --include-namespaces=rook-ceph,production \
  --default-volumes-to-fs-backup \
  --ttl=720h

# List schedules
velero schedule get

# Describe schedule
velero schedule describe <schedule-name>
```

### Check Velero Status

```bash
# Check Velero pods
kubectl get pods -n velero

# Check Velero logs
kubectl logs -n velero -l app.kubernetes.io/name=velero --tail=100

# Check node-agent pods
kubectl get pods -n velero -l component=node-agent

# Check node-agent logs
kubectl logs -n velero -l component=node-agent --tail=100
```

### List Restores

```bash
# List all restores
velero restore get

# Describe restore
velero restore describe <restore-name>

# View restore logs
velero restore logs <restore-name>
```

## Troubleshooting Commands

```bash
# Check backup storage location
velero backup-location get

# Test S3 connectivity from cluster
kubectl run -it --rm debug --image=amazon/aws-cli --restart=Never -- \
  aws s3 ls s3://velero-backups --endpoint-url=https://minio.velero.svc.cluster.local:9000

# Check Velero configuration
kubectl get deployment velero -n velero -o yaml

# Check Velero secret
kubectl get secret cloud-credentials -n velero -o yaml

# View backup details
velero backup describe <backup-name> --details

# View restore details
velero restore describe <restore-name> --details

# Check for errors in backup
velero backup logs <backup-name> | grep -i error

# Check for errors in restore
velero restore logs <restore-name> | grep -i error
```

## Complete Example Workflow

Here's a complete example you can copy and adapt:

```bash
# ============================================
# SOURCE CLUSTER - Backup
# ============================================

# 1. Create credentials
cat > credentials-velero <<EOF
[default]
aws_access_key_id=minioadmin
aws_secret_access_key=minioadmin123
EOF

# 2. Install Velero
BUCKET_NAME=velero-backups
REGION=minio
S3_ENDPOINT=https://minio.velero.svc.cluster.local:9000

velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket $BUCKET_NAME \
  --secret-file ./credentials-velero \
  --use-volume-snapshots=false \
  --backup-location-config region=$REGION,s3ForcePathStyle="true",s3Url=$S3_ENDPOINT \
  --use-node-agent \
  --default-volumes-to-fs-backup

# 3. Wait for Velero to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=velero -n velero --timeout=300s

# 4. Create backup
BACKUP_NAME="rook-ceph-backup-$(date +%Y%m%d-%H%M%S)"
velero backup create $BACKUP_NAME \
  --include-namespaces=rook-ceph,production \
  --include-cluster-resources=true \
  --default-volumes-to-fs-backup \
  --wait

# 5. Verify backup
velero backup get
velero backup describe $BACKUP_NAME

# ============================================
# TARGET CLUSTER - Restore
# ============================================

# 6. Switch to target cluster
kubectl config use-context <target-cluster-context>

# 7. Install Velero (same as step 2)
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket $BUCKET_NAME \
  --secret-file ./credentials-velero \
  --backup-location-config region=$REGION,s3ForcePathStyle="true",s3Url=$S3_ENDPOINT \
  --use-node-agent \
  --default-volumes-to-fs-backup

# 8. Verify backups are visible
velero backup get

# 9. Restore backup
RESTORE_NAME="restore-$(date +%Y%m%d-%H%M%S)"
velero restore create $RESTORE_NAME \
  --from-backup $BACKUP_NAME \
  --include-cluster-resources=true \
  --wait

# 10. Verify restore
velero restore get
kubectl get cephcluster -n rook-ceph
kubectl get pods -n rook-ceph
kubectl get pvc -A
```

## Notes

- **All commands are manual** - copy and paste as needed
- Replace `<backup-name>`, `<restore-name>`, and other placeholders with actual values
- Always verify backups before relying on them for disaster recovery
- Test restore procedures in a non-production environment first
- Scripts in `scripts/` directory are optional and provided for reference only
