# Velero Setup Guide for Rook Ceph

This guide walks you through installing and configuring Velero for backing up Rook Ceph clusters.

## Prerequisites

1. **Kubernetes cluster** with Rook Ceph installed
2. **kubectl** configured and connected to your cluster
3. **S3-compatible object storage** (MinIO, AWS S3, Azure Blob, etc.)
4. **Velero CLI** installed locally

### Install Velero CLI

**macOS:**
```bash
brew install velero
```

**Linux:**
```bash
wget https://github.com/vmware-tanzu/velero/releases/download/v1.12.0/velero-v1.12.0-linux-amd64.tar.gz
tar -xzf velero-v1.12.0-linux-amd64.tar.gz
sudo mv velero-v1.12.0-linux-amd64/velero /usr/local/bin/
```

**Verify installation:**
```bash
velero version --client-only
```

## Step 1: Set Up Object Storage

You need an S3-compatible object storage backend. Here are options:

### Option A: MinIO (Local/On-Premises)

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

# Get MinIO endpoint
kubectl get svc minio -n velero
```

### Option B: AWS S3

Create an S3 bucket and IAM user with appropriate permissions.

### Option C: Azure Blob Storage

Create a storage account and container.

## Step 2: Create Velero Credentials

Create a credentials file for your object storage:

### For MinIO:

```bash
cat > credentials-velero <<EOF
[default]
aws_access_key_id=minioadmin
aws_secret_access_key=minioadmin123
EOF
```

### For AWS S3:

```bash
cat > credentials-velero <<EOF
[default]
aws_access_key_id=<your-access-key>
aws_secret_access_key=<your-secret-key>
EOF
```

## Step 3: Install Velero

### Using Velero CLI (Recommended)

```bash
# Set variables
BUCKET_NAME=velero-backups
REGION=minio  # or us-east-1 for AWS
S3_ENDPOINT=https://minio.velero.svc.cluster.local:9000  # For MinIO
# S3_ENDPOINT=s3.amazonaws.com  # For AWS

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

### Using Helm (Alternative)

```bash
# Add Velero Helm repo
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

# Install Velero
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  --set-file credentials.secretContents.cloud=./credentials-velero \
  --set configuration.provider=aws \
  --set configuration.backupStorageLocation.bucket=$BUCKET_NAME \
  --set configuration.backupStorageLocation.config.region=$REGION \
  --set configuration.backupStorageLocation.config.s3ForcePathStyle=true \
  --set configuration.backupStorageLocation.config.s3Url=$S3_ENDPOINT \
  --set initContainers[0].name=velero-plugin-for-aws \
  --set initContainers[0].image=velero/velero-plugin-for-aws:v1.8.0 \
  --set initContainers[0].volumeMounts[0].mountPath=/target \
  --set initContainers[0].volumeMounts[0].name=plugins
```

## Step 4: Verify Installation

```bash
# Check Velero pods
kubectl get pods -n velero

# Check Velero status
velero version

# Test connection to backup storage
velero backup-location get
```

Expected output:
```
NAME      PROVIDER   BUCKET/PREFIX   PHASE       LAST VALIDATED                  ACCESS MODE   DEFAULT
default   aws        velero-backups  Available   2024-01-15 10:30:00 +0000 UTC   ReadWrite     true
```

## Step 5: Install Rook Ceph Plugin (Optional)

For better Rook Ceph integration, you can install the Rook plugin:

```bash
velero plugin add velero/velero-plugin-for-csi:v0.5.0
```

## Step 6: Configure Backup Storage Location

Verify your backup storage location is configured correctly:

```bash
kubectl get backupstoragelocation -n velero -o yaml
```

## Step 7: Test Backup

Create a test backup to verify everything works:

```bash
# Backup a test namespace
velero backup create test-backup --include-namespaces default

# Check backup status
velero backup describe test-backup

# Check backup logs
velero backup logs test-backup
```

## Troubleshooting

### Velero Pod Not Starting

```bash
# Check pod logs
kubectl logs -n velero -l app.kubernetes.io/name=velero

# Check for credential issues
kubectl get secret cloud-credentials -n velero -o yaml
```

### Cannot Connect to S3

```bash
# Test S3 connectivity from within cluster
kubectl run -it --rm debug --image=amazon/aws-cli --restart=Never -- \
  aws s3 ls s3://velero-backups --endpoint-url=https://minio.velero.svc.cluster.local:9000
```

### Volume Snapshot Issues

If you're using volume snapshots, ensure your CSI driver supports snapshots:

```bash
kubectl get volumesnapshotclass
```

## Next Steps

Once Velero is installed and verified:
1. Review the [Backup Guide](BACKUP_GUIDE.md) to create backups
2. Review the [Restore Guide](RESTORE_GUIDE.md) to restore backups
3. Set up scheduled backups using the [backup schedule configuration](../configs/backup-schedule.yaml)

