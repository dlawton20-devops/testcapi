# Velero CRD Manifests

This directory contains all Velero CRD manifests for backing up and restoring Rook Ceph clusters.

## Backup Manifests

### `backup-full.yaml`
Full cluster backup including Rook Ceph operator and application namespaces.

**Usage:**
```bash
kubectl apply -f backup-full.yaml
kubectl get backup rook-ceph-full-backup -n velero
```

### `backup-rook-operator.yaml`
Backup only Rook Ceph operator and its resources (CephCluster, CephBlockPool, etc.).

**Usage:**
```bash
kubectl apply -f backup-rook-operator.yaml
kubectl get backup rook-operator-backup -n velero
```

### `backup-app-only.yaml`
Backup only application namespaces and their PVCs.

**Usage:**
```bash
kubectl apply -f backup-app-only.yaml
kubectl get backup app-production-backup -n velero
```

### `backup-schedule.yaml`
Scheduled backups using Schedule CRD (daily, weekly, operator-only).

**Usage:**
```bash
kubectl apply -f backup-schedule.yaml
kubectl get schedule -n velero
```

## Restore Manifests

### `restore-full.yaml`
Full cluster restore from a backup.

**Usage:**
```bash
# Edit manifest to set correct backupName, then:
kubectl apply -f restore-full.yaml
kubectl get restore full-cluster-restore -n velero
```

### `restore-app-only.yaml`
Restore only application namespaces.

**Usage:**
```bash
# Edit manifest to set correct backupName, then:
kubectl apply -f restore-app-only.yaml
kubectl get restore app-restore -n velero
```

### `restore-rook-operator.yaml`
Restore only Rook Ceph operator resources.

**Usage:**
```bash
# Edit manifest to set correct backupName, then:
kubectl apply -f restore-rook-operator.yaml
kubectl get restore rook-operator-restore -n velero
```

## Configuration Manifests

### `backupstoragelocation.yaml`
BackupStorageLocation CRD defining where backups are stored.

**Usage:**
```bash
# Usually created during velero install, but can be applied manually:
kubectl apply -f backupstoragelocation.yaml
kubectl get backupstoragelocation -n velero
```

### `restore-config.yaml`
Example restore configurations showing different restore scenarios.

**Usage:**
Reference only - shows examples of restore configurations.

### `velero-values.yaml`
Helm values for installing Velero (alternative to CLI install).

**Usage:**
```bash
helm install velero vmware-tanzu/velero -f velero-values.yaml
```

## Quick Reference

### Create Backup
```bash
kubectl apply -f backup-full.yaml
kubectl wait --for=condition=Completed backup/rook-ceph-full-backup -n velero --timeout=600s
```

### Check Backup Status
```bash
kubectl get backup -n velero
kubectl describe backup <backup-name> -n velero
kubectl get backup <backup-name> -n velero -o jsonpath='{.status.phase}'
```

### Create Restore
```bash
# Edit restore manifest to set backupName, then:
kubectl apply -f restore-full.yaml
kubectl wait --for=condition=Completed restore/full-cluster-restore -n velero --timeout=600s
```

### Check Restore Status
```bash
kubectl get restore -n velero
kubectl describe restore <restore-name> -n velero
kubectl get restore <restore-name> -n velero -o jsonpath='{.status.phase}'
```

## Customizing Manifests

All manifests can be customized:

1. **Change names**: Update `metadata.name`
2. **Change namespaces**: Update `spec.includedNamespaces`
3. **Change TTL**: Update `spec.ttl`
4. **Add labels**: Update `metadata.labels`
5. **Change storage location**: Update `spec.storageLocation`

Example:
```yaml
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: my-custom-backup
  namespace: velero
spec:
  includedNamespaces:
    - my-namespace
  includeClusterResources: true
  defaultVolumesToFsBackup: true
  storageLocation: default
  ttl: 720h
```

Apply:
```bash
kubectl apply -f my-custom-backup.yaml
```

