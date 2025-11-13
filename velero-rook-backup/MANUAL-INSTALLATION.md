# Manual Velero Installation Guide

This guide provides step-by-step instructions for manually installing Velero for Rook Ceph backups, with both CLI and Helm methods.

## Prerequisites

Before starting, ensure you have:

- [ ] Kubernetes cluster access with `kubectl` configured
- [ ] Cluster admin permissions
- [ ] Object storage backend (S3, MinIO, Azure, GCS) configured
- [ ] Object storage credentials ready
- [ ] Helm 3.x installed (for Helm method)

## Method 1: Manual Installation with Velero CLI

### Step 1: Download Velero CLI

**On macOS:**
```bash
cd ~/Downloads
wget https://github.com/vmware-tanzu/velero/releases/download/v1.12.0/velero-v1.12.0-darwin-amd64.tar.gz
tar -xzf velero-v1.12.0-darwin-amd64.tar.gz
sudo mv velero-v1.12.0-darwin-amd64/velero /usr/local/bin/
rm -rf velero-v1.12.0-darwin-amd64*
```

**On Linux:**
```bash
cd /tmp
wget https://github.com/vmware-tanzu/velero/releases/download/v1.12.0/velero-v1.12.0-linux-amd64.tar.gz
tar -xzf velero-v1.12.0-linux-amd64.tar.gz
sudo mv velero-v1.12.0-linux-amd64/velero /usr/local/bin/
rm -rf velero-v1.12.0-linux-amd64*
```

**Verify installation:**
```bash
velero version --client
```

### Step 2: Prepare Object Storage Credentials

Create a credentials file for your object storage provider.

#### For AWS S3:

Create `credentials-velero` file:
```bash
cat > credentials-velero <<EOF
[default]
aws_access_key_id=YOUR_ACCESS_KEY_ID
aws_secret_access_key=YOUR_SECRET_ACCESS_KEY
EOF
```

#### For MinIO:

Create `credentials-velero` file:
```bash
cat > credentials-velero <<EOF
[default]
aws_access_key_id=minioadmin
aws_secret_access_key=minioadmin
EOF
```

**Note:** Keep this file secure and don't commit it to version control.

### Step 3: Create Kubernetes Namespace

```bash
kubectl create namespace velero
```

### Step 4: Install Velero Server

#### Option A: AWS S3 Backend

```bash
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket velero-backups \
  --secret-file ./credentials-velero \
  --use-volume-snapshots=false \
  --use-restic \
  --backup-location-config region=us-west-2
```

**Customize:**
- Replace `velero-backups` with your S3 bucket name
- Replace `us-west-2` with your AWS region
- Adjust plugin version if needed

#### Option B: MinIO Backend

```bash
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket velero \
  --secret-file ./credentials-velero \
  --use-volume-snapshots=false \
  --use-restic \
  --backup-location-config region=minio,s3ForcePathStyle=true
```

**Note:** For MinIO, you'll need to set the endpoint. Create a BackupStorageLocation after installation (see Step 6).

#### Option C: Azure Blob Storage

```bash
velero install \
  --provider azure \
  --plugins velero/velero-plugin-for-microsoft-azure:v1.7.0 \
  --bucket velero-backups \
  --secret-file ./credentials-velero \
  --use-volume-snapshots=false \
  --use-restic \
  --backup-location-config resourceGroup=velero-rg,storageAccount=velerosa
```

#### Option D: Google Cloud Storage

```bash
velero install \
  --provider gcp \
  --plugins velero/velero-plugin-for-gcp:v1.7.0 \
  --bucket velero-backups \
  --secret-file ./credentials-velero \
  --use-volume-snapshots=false \
  --use-restic
```

### Step 5: Verify Installation

Check that Velero pods are running:

```bash
kubectl get pods -n velero
```

You should see:
- `velero-xxx` (Velero server pod)
- `restic-xxx` (Restic daemonset pods, one per node)

Check Velero deployment:

```bash
kubectl get deployment -n velero
kubectl get daemonset -n velero
```

### Step 6: Configure Backup Storage Location (if needed)

If you need to customize the backup storage location, create or update it:

**For AWS S3:**
```bash
kubectl apply -f - <<EOF
apiVersion: velero.io/v1
kind: BackupStorageLocation
metadata:
  name: default
  namespace: velero
spec:
  provider: aws
  objectStorage:
    bucket: velero-backups
  config:
    region: us-west-2
EOF
```

**For MinIO:**
```bash
# First, get your MinIO service endpoint
MINIO_ENDPOINT=$(kubectl get svc minio -n minio -o jsonpath='{.spec.clusterIP}')

kubectl apply -f - <<EOF
apiVersion: velero.io/v1
kind: BackupStorageLocation
metadata:
  name: default
  namespace: velero
spec:
  provider: aws
  objectStorage:
    bucket: velero
  config:
    region: minio
    s3ForcePathStyle: "true"
    s3Url: http://${MINIO_ENDPOINT}:9000
EOF
```

### Step 7: Verify Backup Storage Location

```bash
kubectl get backupstoragelocation -n velero
velero backup-location get
```

The status should show `Available`.

### Step 8: Test Installation

Create a test backup:

```bash
velero backup create test-backup --include-namespaces default
```

Check backup status:

```bash
velero backup describe test-backup
velero backup logs test-backup
```

## Method 2: Installation with Helm

### Step 1: Add Helm Repository

```bash
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update
```

### Step 2: Create Namespace

```bash
kubectl create namespace velero
```

### Step 3: Create Credentials Secret

**For AWS S3:**
```bash
kubectl create secret generic cloud-credentials \
  --from-file cloud=./credentials-velero \
  -n velero
```

**For MinIO:**
```bash
kubectl create secret generic cloud-credentials \
  --from-file cloud=./credentials-velero \
  -n velero
```

### Step 4: Install Velero with Helm

#### Option A: Using values.yaml

```bash
# Edit values.yaml to match your configuration
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --values values.yaml
```

#### Option B: Using command-line flags

**For AWS S3:**
```bash
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --set-file credentials.secretContents.cloud=./credentials-velero \
  --set configuration.provider=aws \
  --set configuration.backupStorageLocation.bucket=velero-backups \
  --set configuration.backupStorageLocation.config.region=us-west-2 \
  --set configuration.volumeSnapshotLocation.config.region=us-west-2 \
  --set initContainers[0].name=velero-plugin-for-aws \
  --set initContainers[0].image=velero/velero-plugin-for-aws:v1.8.0 \
  --set initContainers[0].volumeMounts[0].mountPath=/target \
  --set initContainers[0].volumeMounts[0].name=plugins \
  --set configuration.restic.enabled=true
```

**For MinIO:**
```bash
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --set-file credentials.secretContents.cloud=./credentials-velero \
  --set configuration.provider=aws \
  --set configuration.backupStorageLocation.bucket=velero \
  --set configuration.backupStorageLocation.config.region=minio \
  --set configuration.backupStorageLocation.config.s3ForcePathStyle=true \
  --set initContainers[0].name=velero-plugin-for-aws \
  --set initContainers[0].image=velero/velero-plugin-for-aws:v1.8.0 \
  --set initContainers[0].volumeMounts[0].mountPath=/target \
  --set initContainers[0].volumeMounts[0].name=plugins \
  --set configuration.restic.enabled=true
```

### Step 5: Verify Helm Installation

```bash
# Check Helm release
helm list -n velero

# Check pods
kubectl get pods -n velero

# Check deployment
kubectl get deployment -n velero
kubectl get daemonset -n velero
```

### Step 6: Configure Backup Storage Location (if needed)

Same as Step 6 in Method 1. Create the BackupStorageLocation resource if you need custom configuration.

### Step 7: Test Installation

Same as Step 8 in Method 1.

## Post-Installation Configuration

### Enable Restic for PVC Backups

Restic should already be enabled if you used `--use-restic` or `configuration.restic.enabled=true`.

Verify Restic daemonset:

```bash
kubectl get daemonset restic -n velero
```

### Configure Volume Snapshot Location (Optional)

If you want to use CSI volume snapshots instead of Restic:

```bash
kubectl apply -f - <<EOF
apiVersion: velero.io/v1
kind: VolumeSnapshotLocation
metadata:
  name: default
  namespace: velero
spec:
  provider: aws
  config:
    region: us-west-2
EOF
```

**Note:** For Rook Ceph, Restic is typically more reliable than CSI snapshots.

## Verification Checklist

After installation, verify:

- [ ] Velero server pod is running: `kubectl get pods -n velero`
- [ ] Restic daemonset pods are running: `kubectl get daemonset -n velero`
- [ ] Backup storage location is available: `velero backup-location get`
- [ ] Test backup completes successfully: `velero backup create test --include-namespaces default`
- [ ] Backup appears in object storage

## Troubleshooting

### Velero Pod Not Starting

```bash
# Check pod logs
kubectl logs -n velero deployment/velero

# Check pod events
kubectl describe pod -n velero -l component=velero
```

### Restic Daemonset Not Running

```bash
# Check daemonset
kubectl get daemonset -n velero

# Check pod logs
kubectl logs -n velero -l component=restic

# Check if nodes are tainted
kubectl describe nodes | grep -i taint
```

### Backup Storage Location Not Available

```bash
# Check backup storage location
kubectl describe backupstoragelocation default -n velero

# Verify credentials
kubectl get secret cloud-credentials -n velero -o yaml

# Test object storage connectivity
# For AWS: aws s3 ls s3://velero-backups
# For MinIO: mc ls minio/velero
```

### Backup Fails

```bash
# Check backup status
velero backup describe <backup-name>

# Check backup logs
velero backup logs <backup-name>

# Check Velero server logs
kubectl logs -n velero deployment/velero
```

## Next Steps

After successful installation:

1. **Create your first backup:**
   ```bash
   kubectl apply -f backup-pvcs.yaml
   ```

2. **Set up scheduled backups:**
   ```bash
   kubectl apply -f backup-schedule.yaml
   ```

3. **Test restore:**
   ```bash
   velero restore create --from-backup test-backup
   ```

## Uninstallation

### Remove Velero (CLI method)

```bash
kubectl delete namespace velero
```

### Remove Velero (Helm method)

```bash
helm uninstall velero -n velero
kubectl delete namespace velero
```

**Note:** This does not delete backups in object storage. Backups must be deleted manually from object storage if needed.

## Additional Resources

- [Velero Documentation](https://velero.io/docs/)
- [Velero GitHub](https://github.com/vmware-tanzu/velero)
- [Rook Ceph Documentation](https://rook.io/docs/rook/latest/)

