# Git Repository Structure for Rancher GitOps

## Why You Need Your Own Repository

You're correct! You need your own Git repository because:

1. **Custom Values**: You need to store your environment-specific values
2. **GitOps Configurations**: Fleet/Flux configurations must be in a Git repo
3. **Secret Management**: Your secrets and environment variables
4. **Version Control**: Track changes to your configurations
5. **Access Control**: Control who can modify your production configs

## Repository Structure

```
your-gitops-repo/
├── README.md
├── fleet/
│   ├── gitrepos/
│   │   ├── monitoring-gitrepo.yaml
│   │   └── logging-gitrepo.yaml
│   └── bundles/
│       ├── monitoring/
│       │   ├── base/
│       │   │   ├── kustomization.yaml
│       │   │   ├── fleet.yaml
│       │   │   ├── values.yaml
│       │   │   └── helmrepository.yaml
│       │   └── overlays/
│       │       ├── dev/
│       │       │   └── kustomization.yaml
│       │       ├── staging/
│       │       │   └── kustomization.yaml
│       │       └── prod/
│       │           └── kustomization.yaml
│       └── logging/
│           ├── base/
│           │   ├── kustomization.yaml
│           │   ├── fleet.yaml
│           │   ├── values.yaml
│           │   └── helmrepository.yaml
│           └── overlays/
│               ├── dev/
│               │   └── kustomization.yaml
│               ├── staging/
│               │   └── kustomization.yaml
│               └── prod/
│                   └── kustomization.yaml
├── flux/ (alternative to fleet)
│   ├── clusters/
│   │   ├── dev/
│   │   ├── staging/
│   │   └── prod/
│   └── apps/
│       ├── monitoring/
│       └── logging/
├── examples/
│   ├── env.dev
│   ├── env.staging
│   └── env.prod
├── scripts/
│   ├── deploy-simple.sh
│   ├── deploy-fleet.sh
│   └── deploy-flux.sh
└── docs/
    ├── variable-management.md
    └── repository-structure.md
```

## How It Works

### 1. Your Repository Contains:
- ✅ **Custom values and configurations**
- ✅ **Environment-specific overlays**
- ✅ **Fleet/Flux manifests**
- ✅ **Secret management**
- ✅ **Deployment scripts**

### 2. Rancher Repository Provides:
- ✅ **Official Helm charts** (rancher-monitoring, rancher-logging)
- ✅ **Chart versions and updates**
- ✅ **Base chart functionality**

### 3. GitOps Flow:
```
Your Git Repo → Fleet/Flux → Rancher Chart Repo → Kubernetes Cluster
     ↓              ↓              ↓                    ↓
Custom Values   GitOps Tool   Official Charts    Deployed Apps
```

## Example: Monitoring Deployment

### Your Repository (fleet/bundles/monitoring/base/fleet.yaml):
```yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: Bundle
metadata:
  name: rancher-monitoring
spec:
  targets:
  - clusterSelector:
      matchLabels:
        env: ${ENVIRONMENT}
    values:
      prometheus:
        prometheusSpec:
          retention: ${PROMETHEUS_RETENTION}
      grafana:
        adminPassword: ${GRAFANA_ADMIN_PASSWORD}
  helm:
    chart: rancher-monitoring
    repo: https://releases.rancher.com/server-charts/stable  # Rancher's repo
    version: 102.0.0+up40.1.2
```

### Your GitRepo Configuration (fleet/gitrepos/monitoring-gitrepo.yaml):
```yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: rancher-monitoring
spec:
  repo: https://github.com/YOUR-ORG/YOUR-GITOPS-REPO  # Your repo
  branch: main
  paths:
  - fleet/bundles/monitoring
```

## Benefits of This Approach

1. **Separation of Concerns**: Your configs vs. official charts
2. **Version Control**: Track your customizations
3. **Environment Management**: Different configs per environment
4. **Security**: Control access to your production configs
5. **Flexibility**: Modify values without touching official charts

## Repository Setup Steps

1. **Create your repository**:
   ```bash
   git init
   git remote add origin https://github.com/YOUR-ORG/YOUR-GITOPS-REPO
   ```

2. **Add your configurations**:
   ```bash
   git add .
   git commit -m "Initial GitOps configuration"
   git push -u origin main
   ```

3. **Update GitRepo references**:
   - Change `repo:` URLs to point to your repository
   - Update deployment scripts with your repo URL

4. **Deploy**:
   ```bash
   ./scripts/deploy-simple.sh prod
   ```

## Security Considerations

- **Never commit secrets** to your repository
- **Use external secret management** (SOPS, External Secrets Operator)
- **Environment files** should be in `.gitignore` for sensitive data
- **RBAC** to control who can access your repository
- **Branch protection** for production configurations 