# Velero Installation for On-Prem Rancher with MinIO

This guide specifically addresses Velero installation in on-premises Rancher environments using MinIO as the S3-compatible backup storage backend.

## Critical Architecture Clarification

### ⚠️ IMPORTANT: Where to Install Velero

**Velero MUST be installed on EACH cluster you want to backup.**

```
┌─────────────────────────────────────────────────────────────┐
│                    Rancher Management Cluster               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Rancher Server                                      │   │
│  │  - Manages multiple clusters                        │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ Cluster A    │    │ Cluster B    │    │ Cluster C    │
│ (Rook Ceph)  │    │ (Rook Ceph)  │    │ (Other)      │
│              │    │              │    │              │
│ Velero A ◄───┼────┼──► Velero B  │    │ Velero C     │
│              │    │              │    │              │
└──────┬───────┘    └──────┬───────┘    └──────┬───────┘
       │                   │                   │
       │                   │                   │
       └───────────────────┼───────────────────┘
                           │
                           ▼
                  ┌─────────────────┐
                  │   MinIO Server  │
                  │  (Shared S3)    │
                  │                 │
                  │  Buckets:       │
                  │  - cluster-a/   │
                  │  - cluster-b/   │
                  │  - cluster-c/   │
                  └─────────────────┘
```

### Key Points:

1. **Velero runs IN the cluster being backed up**
   - Velero needs Kubernetes API access to discover resources
   - Velero needs pod access to backup volumes via Restic
   - Velero needs to access PVCs, ConfigMaps, Secrets, etc.

2. **MinIO can be shared across clusters**
   - One MinIO instance can serve multiple clusters
   - Each cluster's Velero writes to separate buckets or paths
   - MinIO can be on a separate server or in one of the clusters

3. **Each cluster needs its own Velero installation**
   - Rancher management cluster: Install Velero if you want to backup it
   - Downstream Cluster A: Install Velero to backup Cluster A
   - Downstream Cluster B: Install Velero to backup Cluster B
   - Each installation is independent but can use the same MinIO

## Prerequisites

- [ ] Rancher management cluster access
- [ ] Access to downstream cluster(s) you want to backup
- [ ] MinIO server deployed and accessible from all clusters
- [ ] MinIO credentials (access key and secret key)
- [ ] Network connectivity from clusters to MinIO

## Step 1: Deploy MinIO (if not already deployed)

### Option A: Deploy MinIO in Rancher Management Cluster

```bash
# Set kubectl context to management cluster
kubectl config use-context <management-cluster-context>

# Create namespace
kubectl create namespace minio

# Deploy MinIO with Helm
helm repo add minio https://charts.min.io/
helm repo update

helm install minio minio/minio \
  --namespace minio \
  --set accessKey=minioadmin \
  --set secretKey=minioadmin \
  --set buckets[0].name=velero-cluster-a \
  --set buckets[1].name=velero-cluster-b \
  --set buckets[2].name=velero-cluster-c \
  --set persistence.enabled=true \
  --set persistence.size=100Gi
```

### Option B: Deploy MinIO on Separate Server

If MinIO is on a separate server, ensure:
- MinIO is accessible via network from all clusters
- Firewall rules allow access on port 9000 (API) and 9001 (Console)
- DNS or IP address is resolvable from cluster nodes

### Get MinIO Endpoint

**If MinIO is in Kubernetes:**
```bash
# Get MinIO service endpoint
kubectl get svc minio -n minio

# Internal endpoint (use this from within cluster)
MINIO_ENDPOINT="http://minio.minio.svc.cluster.local:9000"

# Or use NodePort/LoadBalancer if external access needed
```

**If MinIO is external:**
```bash
# Use external IP or hostname
MINIO_ENDPOINT="http://minio.example.com:9000"
# or
MINIO_ENDPOINT="http://192.168.1.100:9000"
```

## Step 2: Create MinIO Credentials

Create credentials file for each cluster:

```bash
cat > credentials-velero <<EOF
[default]
aws_access_key_id=minioadmin
aws_secret_access_key=minioadmin
EOF
```

**Security Note:** Change default credentials in production!

## Step 3: Install Velero on Each Cluster

### For Rancher Management Cluster

```bash
# Switch to management cluster context
kubectl config use-context <management-cluster-context>

# Create namespace
kubectl create namespace velero

# Create credentials secret
kubectl create secret generic cloud-credentials \
  --from-file cloud=./credentials-velero \
  -n velero

# Install Velero with Helm
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

helm install velero vmware-tanzu/velero \
  --namespace velero \
  --set-file credentials.secretContents.cloud=./credentials-velero \
  --set configuration.provider=aws \
  --set configuration.backupStorageLocation.bucket=velero-management \
  --set configuration.backupStorageLocation.config.region=minio \
  --set configuration.backupStorageLocation.config.s3ForcePathStyle=true \
  --set configuration.backupStorageLocation.config.s3Url=http://minio.minio.svc.cluster.local:9000 \
  --set initContainers[0].name=velero-plugin-for-aws \
  --set initContainers[0].image=velero/velero-plugin-for-aws:v1.8.0 \
  --set initContainers[0].volumeMounts[0].mountPath=/target \
  --set initContainers[0].volumeMounts[0].name=plugins \
  --set configuration.restic.enabled=true
```

### For Downstream Cluster A (with Rook Ceph)

```bash
# Switch to downstream cluster context
kubectl config use-context <cluster-a-context>

# Create namespace
kubectl create namespace velero

# Create credentials secret
kubectl create secret generic cloud-credentials \
  --from-file cloud=./credentials-velero \
  -n velero

# Install Velero
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --set-file credentials.secretContents.cloud=./credentials-velero \
  --set configuration.provider=aws \
  --set configuration.backupStorageLocation.bucket=velero-cluster-a \
  --set configuration.backupStorageLocation.config.region=minio \
  --set configuration.backupStorageLocation.config.s3ForcePathStyle=true \
  --set configuration.backupStorageLocation.config.s3Url=http://<minio-endpoint>:9000 \
  --set initContainers[0].name=velero-plugin-for-aws \
  --set initContainers[0].image=velero/velero-plugin-for-aws:v1.8.0 \
  --set initContainers[0].volumeMounts[0].mountPath=/target \
  --set initContainers[0].volumeMounts[0].name=plugins \
  --set configuration.restic.enabled=true
```

**Important:** Replace `<minio-endpoint>` with your MinIO endpoint. If MinIO is in the management cluster and you're installing on a downstream cluster, use the external endpoint.

### For Additional Clusters

Repeat the process for each cluster, changing:
- Cluster context
- Bucket name (e.g., `velero-cluster-b`, `velero-cluster-c`)
- MinIO endpoint (if different per cluster)

## Step 4: Verify Installation on Each Cluster

For each cluster:

```bash
# Switch to cluster context
kubectl config use-context <cluster-context>

# Check Velero pods
kubectl get pods -n velero

# Check backup storage location
kubectl get backupstoragelocation -n velero
kubectl describe backupstoragelocation default -n velero

# Test backup
velero backup create test-backup --include-namespaces default
velero backup describe test-backup
```

## Step 5: Configure Backup Storage Location (if needed)

If the Helm installation didn't configure the endpoint correctly, create/update manually:

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
    bucket: velero-cluster-a
  config:
    region: minio
    s3ForcePathStyle: "true"
    s3Url: http://<minio-endpoint>:9000
EOF
```

## Network Considerations

### MinIO in Management Cluster, Velero in Downstream Cluster

If MinIO is in the management cluster and you're backing up downstream clusters:

**Option 1: Use NodePort/LoadBalancer**
```bash
# Expose MinIO via NodePort
kubectl patch svc minio -n minio -p '{"spec":{"type":"NodePort"}}'
kubectl get svc minio -n minio

# Use node IP:port in downstream cluster Velero config
```

**Option 2: Use Ingress**
```bash
# Create ingress for MinIO
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: minio
  namespace: minio
spec:
  rules:
  - host: minio.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: minio
            port:
              number: 9000
EOF
```

**Option 3: Use External MinIO**
Deploy MinIO on a separate server accessible from all clusters.

## MinIO Bucket Organization

Recommended bucket structure:

```
MinIO Buckets:
├── velero-management/     (Rancher management cluster backups)
├── velero-cluster-a/      (Downstream cluster A backups)
├── velero-cluster-b/      (Downstream cluster B backups)
└── velero-cluster-c/      (Downstream cluster C backups)
```

Or use a single bucket with prefixes:

```
velero-backups/
├── management/
├── cluster-a/
├── cluster-b/
└── cluster-c/
```

## Creating Backups

### Backup Rook Ceph on Cluster A

```bash
# Switch to cluster A context
kubectl config use-context <cluster-a-context>

# Create backup
kubectl apply -f backup-pvcs.yaml
# or
velero backup create rook-ceph-backup --include-namespaces rook-ceph,default
```

### View Backups from Any Cluster

```bash
# Each cluster only sees its own backups
kubectl get backups -n velero

# But all backups are in MinIO
# Access MinIO console to see all backups
```

## Restore to Different Cluster

To restore Cluster A backup to Cluster B:

```bash
# 1. Install Velero on Cluster B (if not already)
# 2. Configure Cluster B Velero to access same MinIO bucket
# 3. Restore from Cluster A backup

kubectl config use-context <cluster-b-context>
velero restore create restore-from-cluster-a --from-backup <backup-name>
```

**Note:** You may need to adjust namespace mappings and storage classes.

## Troubleshooting

### Velero Can't Connect to MinIO

```bash
# Test connectivity from cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- curl http://<minio-endpoint>:9000

# Check MinIO service
kubectl get svc minio -n minio

# Check network policies
kubectl get networkpolicies -A
```

### Backup Storage Location Not Available

```bash
# Check backup storage location
kubectl describe backupstoragelocation default -n velero

# Check Velero logs
kubectl logs -n velero deployment/velero

# Verify MinIO credentials
kubectl get secret cloud-credentials -n velero -o yaml
```

### Cross-Cluster MinIO Access

If downstream clusters can't reach MinIO in management cluster:

1. **Check DNS resolution:**
   ```bash
   kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup minio.minio.svc.cluster.local
   ```

2. **Use external endpoint:**
   - Expose MinIO via NodePort, LoadBalancer, or Ingress
   - Use external IP/hostname in Velero config

3. **Check firewall rules:**
   - Ensure port 9000 is accessible between clusters

## Best Practices

1. **Separate buckets per cluster** - Easier to manage and secure
2. **Use external MinIO** - Better for multi-cluster scenarios
3. **Secure credentials** - Use Kubernetes secrets, not hardcoded
4. **Monitor MinIO** - Ensure sufficient storage capacity
5. **Test restores** - Regularly test restore procedures
6. **Backup MinIO** - Consider backing up MinIO data itself

## Quick Reference

### Install Velero on Cluster (Helm)

```bash
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --set-file credentials.secretContents.cloud=./credentials-velero \
  --set configuration.provider=aws \
  --set configuration.backupStorageLocation.bucket=<cluster-bucket> \
  --set configuration.backupStorageLocation.config.region=minio \
  --set configuration.backupStorageLocation.config.s3ForcePathStyle=true \
  --set configuration.backupStorageLocation.config.s3Url=http://<minio-endpoint>:9000 \
  --set configuration.restic.enabled=true
```

### Verify Installation

```bash
kubectl get pods -n velero
kubectl get backupstoragelocation -n velero
velero backup-location get
```

### Create Test Backup

```bash
velero backup create test --include-namespaces default
velero backup describe test
```

