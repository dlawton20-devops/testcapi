# Velero Installation Options

This document outlines the different ways to install Velero for Rook Ceph backups.

## Installation Methods Comparison

| Method | Difficulty | Automation | Best For |
|--------|-----------|------------|----------|
| **Manual CLI** | Medium | Low | Learning, customization, troubleshooting |
| **Manual Helm** | Easy | Medium | Production, GitOps, repeatability |
| **Installation Script** | Easy | High | Quick setup, testing |

## Method 1: Manual Installation with Velero CLI

**Best for:** Learning, full control, troubleshooting

**Pros:**
- Full visibility into each step
- Easy to customize
- Good for understanding how Velero works
- No Helm dependency

**Cons:**
- More manual steps
- Requires downloading CLI tool
- More time-consuming

**See:** [MANUAL-INSTALLATION.md](MANUAL-INSTALLATION.md#method-1-manual-installation-with-velero-cli)

**Quick Start:**
```bash
# 1. Download Velero CLI
wget https://github.com/vmware-tanzu/velero/releases/download/v1.12.0/velero-v1.12.0-linux-amd64.tar.gz
tar -xzf velero-v1.12.0-linux-amd64.tar.gz
sudo mv velero-v1.12.0-linux-amd64/velero /usr/local/bin/

# 2. Create credentials file
cat > credentials-velero <<EOF
[default]
aws_access_key_id=YOUR_KEY
aws_secret_access_key=YOUR_SECRET
EOF

# 3. Install Velero
kubectl create namespace velero
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket velero-backups \
  --secret-file ./credentials-velero \
  --use-restic
```

## Method 2: Manual Installation with Helm

**Best for:** Production, GitOps, repeatable deployments

**Pros:**
- Industry standard approach
- Easy to version control
- Repeatable deployments
- Good for GitOps workflows
- Easy upgrades

**Cons:**
- Requires Helm installed
- Need to understand Helm values

**See:** [MANUAL-INSTALLATION.md](MANUAL-INSTALLATION.md#method-2-installation-with-helm)

**Quick Start:**
```bash
# 1. Add Helm repo
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

# 2. Create namespace and secret
kubectl create namespace velero
kubectl create secret generic cloud-credentials \
  --from-file cloud=./credentials-velero \
  -n velero

# 3. Install with Helm
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --set-file credentials.secretContents.cloud=./credentials-velero \
  --set configuration.provider=aws \
  --set configuration.backupStorageLocation.bucket=velero-backups \
  --set configuration.restic.enabled=true
```

## Method 3: Automated Installation Script

**Best for:** Quick setup, testing, development

**Pros:**
- Fastest setup
- Interactive prompts
- Handles multiple providers
- Good for testing

**Cons:**
- Less control
- Script may need customization
- Less visibility into steps

**See:** [QUICK-START.md](QUICK-START.md)

**Quick Start:**
```bash
./install-velero.sh
```

## Recommended Approach by Use Case

### Production Environment
**Recommended:** Manual Helm installation
- Use `values.yaml` for configuration
- Store in GitOps repository
- Version controlled
- Easy to audit

### Development/Testing
**Recommended:** Installation script
- Fast setup
- Easy to tear down and recreate
- Good for experimentation

### Learning/Training
**Recommended:** Manual CLI installation
- Understand each step
- See exactly what gets created
- Better for troubleshooting

### GitOps Workflow
**Recommended:** Helm with Flux/ArgoCD
- Declarative configuration
- Automated deployments
- Version controlled
- Easy rollbacks

## Step-by-Step Decision Tree

```
Do you want full control and visibility?
├─ YES → Manual CLI Installation
└─ NO → Continue
    │
    Do you use Helm in your environment?
    ├─ YES → Manual Helm Installation
    └─ NO → Installation Script
```

## Common Customizations

### Using Custom Values File (Helm)

```bash
# Edit values.yaml
vim values.yaml

# Install with custom values
helm install velero vmware-tanzu/velero \
  --namespace velero \
  --values values.yaml
```

### Installing Additional Plugins

**CLI Method:**
```bash
velero plugin add quay.io/konveyor/velero-plugin-for-csi:latest
```

**Helm Method:**
Add to `values.yaml`:
```yaml
initContainers:
  - name: velero-plugin-for-csi
    image: quay.io/konveyor/velero-plugin-for-csi:latest
    volumeMounts:
      - mountPath: /target
        name: plugins
```

### Custom Resource Limits

**Helm Method:**
Edit `values.yaml`:
```yaml
deployments:
  server:
    resources:
      limits:
        cpu: "2"
        memory: 2Gi
      requests:
        cpu: 500m
        memory: 512Mi
```

## Verification After Installation

Regardless of installation method, verify:

```bash
# Check pods
kubectl get pods -n velero

# Check backup storage location
velero backup-location get

# Test backup
velero backup create test --include-namespaces default
velero backup describe test
```

## Upgrading Velero

### CLI Method
```bash
# Download new version
# Re-run velero install (it will upgrade)
velero install --upgrade
```

### Helm Method
```bash
# Update values.yaml with new version
helm upgrade velero vmware-tanzu/velero \
  --namespace velero \
  --values values.yaml
```

## Uninstallation

### CLI Method
```bash
kubectl delete namespace velero
```

### Helm Method
```bash
helm uninstall velero -n velero
kubectl delete namespace velero
```

## Next Steps

After installation:
1. Review [backup configurations](backup-pvcs.yaml)
2. Set up [scheduled backups](backup-schedule.yaml)
3. Test restore procedures
4. Configure monitoring

