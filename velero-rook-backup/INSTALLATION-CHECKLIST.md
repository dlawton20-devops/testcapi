# Velero Installation Checklist

Use this checklist to track your installation progress.

## Pre-Installation

- [ ] Kubernetes cluster access verified (`kubectl cluster-info`)
- [ ] Cluster admin permissions confirmed
- [ ] Object storage backend selected (S3/MinIO/Azure/GCS)
- [ ] Object storage credentials obtained
- [ ] Object storage bucket/container created
- [ ] Helm 3.x installed (if using Helm method)

## Installation Method Selection

Choose one:
- [ ] **Method 1:** Manual CLI Installation
- [ ] **Method 2:** Manual Helm Installation
- [ ] **Method 3:** Automated Script Installation

## Method 1: Manual CLI Installation

### Step 1: Download Velero CLI
- [ ] Downloaded Velero CLI for your OS
- [ ] Extracted and moved to `/usr/local/bin/`
- [ ] Verified installation: `velero version --client`

### Step 2: Prepare Credentials
- [ ] Created `credentials-velero` file
- [ ] Added object storage credentials
- [ ] Verified file permissions (secure)

### Step 3: Create Namespace
- [ ] Created `velero` namespace: `kubectl create namespace velero`

### Step 4: Install Velero
- [ ] Ran `velero install` command with correct parameters
- [ ] Verified installation completed successfully

### Step 5: Verify Installation
- [ ] Checked Velero pod: `kubectl get pods -n velero`
- [ ] Checked Restic daemonset: `kubectl get daemonset -n velero`
- [ ] Verified backup storage location: `velero backup-location get`

### Step 6: Test Installation
- [ ] Created test backup: `velero backup create test --include-namespaces default`
- [ ] Verified backup completed: `velero backup describe test`
- [ ] Checked backup in object storage

## Method 2: Manual Helm Installation

### Step 1: Add Helm Repository
- [ ] Added Velero Helm repo: `helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts`
- [ ] Updated Helm repos: `helm repo update`

### Step 2: Create Namespace
- [ ] Created `velero` namespace: `kubectl create namespace velero`

### Step 3: Create Credentials Secret
- [ ] Created secret: `kubectl create secret generic cloud-credentials --from-file cloud=./credentials-velero -n velero`

### Step 4: Install with Helm
- [ ] Option A: Used `values.yaml`: `helm install velero vmware-tanzu/velero --namespace velero --values values.yaml`
- [ ] Option B: Used command-line flags (see MANUAL-INSTALLATION.md)
- [ ] Verified installation: `helm list -n velero`

### Step 5: Verify Installation
- [ ] Checked Velero pod: `kubectl get pods -n velero`
- [ ] Checked Restic daemonset: `kubectl get daemonset -n velero`
- [ ] Verified backup storage location: `kubectl get backupstoragelocation -n velero`

### Step 6: Test Installation
- [ ] Created test backup: `velero backup create test --include-namespaces default`
- [ ] Verified backup completed: `velero backup describe test`
- [ ] Checked backup in object storage

## Post-Installation Configuration

### Backup Configuration
- [ ] Reviewed `backup-pvcs.yaml` for PVC backups
- [ ] Reviewed `backup-cephfs.yaml` for CephFS backups
- [ ] Customized backup configurations for your environment

### Scheduled Backups
- [ ] Reviewed `backup-schedule.yaml`
- [ ] Applied scheduled backups: `kubectl apply -f backup-schedule.yaml`
- [ ] Verified schedules: `kubectl get schedules -n velero`

### Testing
- [ ] Created test PVC backup
- [ ] Created test CephFS backup
- [ ] Tested restore procedure
- [ ] Verified data integrity after restore

## Documentation Review

- [ ] Read [README.md](README.md)
- [ ] Read [MANUAL-INSTALLATION.md](MANUAL-INSTALLATION.md)
- [ ] Read [QUICK-START.md](QUICK-START.md)
- [ ] Reviewed backup YAML files
- [ ] Reviewed restore examples

## Troubleshooting Prepared

- [ ] Know how to check Velero logs: `kubectl logs -n velero deployment/velero`
- [ ] Know how to check Restic logs: `kubectl logs -n velero -l component=restic`
- [ ] Know how to check backup status: `velero backup describe <name>`
- [ ] Know how to check backup storage location: `kubectl describe backupstoragelocation -n velero`

## Production Readiness

- [ ] Backup storage location is highly available
- [ ] Credentials are stored securely (not in Git)
- [ ] Backup retention policies configured
- [ ] Monitoring/alerting configured (optional)
- [ ] Restore procedures documented
- [ ] Disaster recovery plan created
- [ ] Regular backup testing scheduled

## Notes

Use this space to record any custom configurations or important notes:

```
Date: ___________
Installer: ___________
Method: ___________
Object Storage: ___________
Custom Configurations:
- 
- 
- 

Issues Encountered:
- 
- 
- 

Resolution:
- 
- 
- 
```

