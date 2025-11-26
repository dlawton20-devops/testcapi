# Manual Commands Reference

Quick reference for all manual commands needed to backup and restore Rook Ceph with Velero.

## Prerequisites

```bash
velero version --client-only
kubectl cluster-info
kubectl get pods -n rook-ceph
```

## 1. Create Credentials File

```bash
cat > credentials-velero <<EOF
[default]
aws_access_key_id=minioadmin
aws_secret_access_key=minioadmin123
EOF
```

## 2. Install Velero

```bash
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

Verify:
```bash
kubectl get pods -n velero
velero backup-location get
```

## 3. Create Backup

### Full Backup
```bash
velero backup create rook-ceph-backup-$(date +%Y%m%d-%H%M%S) \
  --include-namespaces=rook-ceph,production \
  --include-cluster-resources=true \
  --default-volumes-to-fs-backup \
  --wait
```

### Rook Operator Only
```bash
velero backup create rook-operator-backup-$(date +%Y%m%d-%H%M%S) \
  --include-namespaces=rook-ceph \
  --include-resources=cephclusters.ceph.rook.io,cephblockpools.ceph.rook.io,cephfilesystems.ceph.rook.io \
  --default-volumes-to-fs-backup \
  --wait
```

### Application Only
```bash
velero backup create app-backup-$(date +%Y%m%d-%H%M%S) \
  --include-namespaces=production \
  --default-volumes-to-fs-backup \
  --wait
```

## 4. Check Backup Status

```bash
velero backup get
velero backup describe <backup-name>
velero backup logs <backup-name>
```

## 5. Restore Backup

### Full Restore
```bash
velero restore create restore-$(date +%Y%m%d-%H%M%S) \
  --from-backup <backup-name> \
  --include-cluster-resources=true \
  --wait
```

### Namespace Restore
```bash
velero restore create restore-$(date +%Y%m%d-%H%M%S) \
  --from-backup <backup-name> \
  --include-namespaces=production \
  --wait
```

### With Namespace Mapping
```bash
velero restore create restore-$(date +%Y%m%d-%H%M%S) \
  --from-backup <backup-name> \
  --include-namespaces=production \
  --namespace-mappings production:production-new \
  --wait
```

## 6. Check Restore Status

```bash
velero restore get
velero restore describe <restore-name>
velero restore logs <restore-name>
```

## 7. Verify Restore

```bash
kubectl get cephcluster -n rook-ceph
kubectl get pods -n rook-ceph
kubectl get pvc -A
kubectl get storageclass
```

## Common Operations

### List Backups
```bash
velero backup get
```

### Delete Backup
```bash
velero backup delete <backup-name>
```

### Create Scheduled Backup
```bash
velero schedule create rook-ceph-daily \
  --schedule="0 2 * * *" \
  --include-namespaces=rook-ceph,production \
  --default-volumes-to-fs-backup \
  --ttl=720h
```

### Check Velero Status
```bash
kubectl get pods -n velero
kubectl logs -n velero -l app.kubernetes.io/name=velero --tail=100
```

### Test S3 Connectivity
```bash
kubectl run -it --rm debug --image=amazon/aws-cli --restart=Never -- \
  aws s3 ls s3://velero-backups --endpoint-url=https://minio.velero.svc.cluster.local:9000
```

## Variables Reference

Adjust these as needed:

```bash
BUCKET_NAME=velero-backups
REGION=minio
S3_ENDPOINT=https://minio.velero.svc.cluster.local:9000
```

For AWS S3:
```bash
BUCKET_NAME=your-bucket-name
REGION=us-east-1
# Omit S3_ENDPOINT for AWS
```

