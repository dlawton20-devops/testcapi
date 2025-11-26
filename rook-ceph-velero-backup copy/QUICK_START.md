# Quick Start Guide - Using CRDs and Manifests

This guide uses **Velero CRDs and YAML manifests** with `kubectl apply` for all operations.

## Prerequisites Check

```bash
# Check kubectl connectivity
kubectl cluster-info

# Check if Rook Ceph is installed
kubectl get pods -n rook-ceph

# Check if Velero CRDs exist
kubectl get crd | grep velero.io
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

## Step 3: Install Velero (One-time Setup)

Velero must be installed first. This is the only step that uses CLI:

```bash
# Set variables
BUCKET_NAME=velero-backups
REGION=minio
S3_ENDPOINT=https://minio.velero.svc.cluster.local:9000

# Install Velero
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

# Check BackupStorageLocation CRD
kubectl get backupstoragelocation -n velero

# Verify CRDs exist
kubectl get crd | grep velero.io
```

## Step 4: Create Backup Using Manifest

### Option 1: Use Pre-configured Manifest

```bash
# Apply full backup manifest
kubectl apply -f configs/backup-full.yaml

# Check backup status
kubectl get backup -n velero
kubectl describe backup rook-ceph-full-backup -n velero

# Watch backup progress
kubectl get backup rook-ceph-full-backup -n velero -w
```

### Option 2: Create Custom Backup Manifest

Create `my-backup.yaml`:

```yaml
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: my-backup-$(date +%Y%m%d-%H%M%S)
  namespace: velero
spec:
  includedNamespaces:
    - rook-ceph
    - production
  includeClusterResources: true
  defaultVolumesToFsBackup: true
  storageLocation: default
  ttl: 720h
```

Apply it:

```bash
kubectl apply -f my-backup.yaml
```

### Check Backup Status

```bash
# List all backups
kubectl get backup -n velero

# Get backup details
kubectl get backup <backup-name> -n velero -o yaml

# Check backup phase
kubectl get backup <backup-name> -n velero -o jsonpath='{.status.phase}'

# Wait for backup to complete
kubectl wait --for=condition=Completed backup/<backup-name> -n velero --timeout=600s
```

## Step 5: Verify Backup

```bash
# List backups
kubectl get backup -n velero

# Describe backup
kubectl describe backup <backup-name> -n velero

# Check backup phase (should be "Completed")
kubectl get backup <backup-name> -n velero -o jsonpath='{.status.phase}'

# Check for errors
kubectl get backup <backup-name> -n velero -o yaml | grep -A 10 errors
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
# Same installation command as source cluster
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket velero-backups \
  --secret-file ./credentials-velero \
  --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=https://minio.velero.svc.cluster.local:9000 \
  --use-node-agent \
  --default-volumes-to-fs-backup

# Verify backups are visible
kubectl get backup -n velero
```

## Step 7: Restore from Backup Using Manifest

### Option 1: Use Pre-configured Manifest

First, edit the manifest to set the correct backup name:

```bash
# Edit restore manifest
kubectl apply -f configs/restore-full.yaml

# Check restore status
kubectl get restore -n velero
kubectl describe restore full-cluster-restore -n velero

# Watch restore progress
kubectl get restore full-cluster-restore -n velero -w
```

### Option 2: Create Custom Restore Manifest

Create `my-restore.yaml`:

```yaml
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: my-restore-$(date +%Y%m%d-%H%M%S)
  namespace: velero
spec:
  backupName: <backup-name>  # Replace with your backup name
  includedNamespaces:
    - rook-ceph
    - production
  includeClusterResources: true
  restorePVs: true
  storageLocation: default
```

Apply it:

```bash
kubectl apply -f my-restore.yaml
```

### Check Restore Status

```bash
# List all restores
kubectl get restore -n velero

# Get restore details
kubectl get restore <restore-name> -n velero -o yaml

# Check restore phase
kubectl get restore <restore-name> -n velero -o jsonpath='{.status.phase}'

# Wait for restore to complete
kubectl wait --for=condition=Completed restore/<restore-name> -n velero --timeout=600s
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

## Scheduled Backups Using CRDs

Create scheduled backups using Schedule CRD:

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

### List Backups

```bash
# Simple list
kubectl get backup -n velero

# With details
kubectl get backup -n velero -o wide

# By label
kubectl get backup -n velero -l app=rook-ceph
```

### Delete Backup

```bash
kubectl delete backup <backup-name> -n velero
```

### List Restores

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
# Check Velero pods
kubectl get pods -n velero

# Check Velero logs
kubectl logs -n velero -l app.kubernetes.io/name=velero --tail=100

# Check node-agent pods
kubectl get pods -n velero -l component=node-agent

# Check node-agent logs
kubectl logs -n velero -l component=node-agent --tail=100
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

### Test S3 Connectivity

```bash
kubectl run -it --rm debug --image=amazon/aws-cli --restart=Never -- \
  aws s3 ls s3://velero-backups --endpoint-url=https://minio.velero.svc.cluster.local:9000
```

## Complete Example Workflow

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

# 2. Install Velero (one-time)
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket velero-backups \
  --secret-file ./credentials-velero \
  --use-volume-snapshots=false \
  --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=https://minio.velero.svc.cluster.local:9000 \
  --use-node-agent \
  --default-volumes-to-fs-backup

# 3. Wait for Velero to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=velero -n velero --timeout=300s

# 4. Create backup using manifest
kubectl apply -f configs/backup-full.yaml

# 5. Wait for backup to complete
kubectl wait --for=condition=Completed backup/rook-ceph-full-backup -n velero --timeout=600s

# 6. Verify backup
kubectl get backup rook-ceph-full-backup -n velero

# ============================================
# TARGET CLUSTER - Restore
# ============================================

# 7. Switch to target cluster
kubectl config use-context <target-cluster-context>

# 8. Install Velero (same as step 2)
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket velero-backups \
  --secret-file ./credentials-velero \
  --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=https://minio.velero.svc.cluster.local:9000 \
  --use-node-agent \
  --default-volumes-to-fs-backup

# 9. Verify backups are visible
kubectl get backup -n velero

# 10. Restore backup using manifest
kubectl apply -f configs/restore-full.yaml

# 11. Wait for restore to complete
kubectl wait --for=condition=Completed restore/full-cluster-restore -n velero --timeout=600s

# 12. Verify restore
kubectl get cephcluster -n rook-ceph
kubectl get pods -n rook-ceph
kubectl get pvc -A
```

## Notes

- **All operations use kubectl apply** with YAML manifests
- **Only Velero installation** uses CLI (one-time setup)
- Replace `<backup-name>` and other placeholders with actual values
- Always verify backups before relying on them for disaster recovery
- Test restore procedures in a non-production environment first
- All manifests are in the `configs/` directory
