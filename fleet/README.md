# Fleet Monitoring Stack Deployment Guide

This repository contains a GitOps monitoring stack using Fleet, Kustomize, and Helm to deploy the kube-prometheus-stack from Harbor with GitLab authentication.

## Repository Structure

```
fleet/
├── fleet.yaml                    # Main Fleet GitRepo with Harbor/GitLab auth
├── fleet-with-auth.yaml         # Fleet GitRepo with authentication configured
├── harbor-secret.yaml           # Harbor authentication secret template
├── gitlab-secret.yaml           # GitLab authentication secret template
├── monitoring/
│   ├── 01-crds/                 # CRDs bundle (deployed first)
│   │   ├── fleet.yaml           # Helm configuration
│   │   └── Chart.yaml           # Harbor repository reference
│   ├── 02-custom-manifests/     # Custom manifests bundle (deployed second)
│   │   ├── fleet.yaml           # Kustomize configuration
│   │   ├── kustomization.yaml   # Raw Kubernetes manifests
│   │   └── overlays/
│   │       └── dev/
│   │           └── kustomization.yaml
│   └── 03-monitoring-stack/     # Main monitoring stack (deployed last)
│       ├── fleet.yaml           # Helm configuration
│       ├── Chart.yaml           # Harbor repository reference
│       ├── values.yaml          # Base values
│       ├── values-custom.yaml   # Custom configurations
│       ├── values-dev.yaml      # Dev environment values
│       ├── values-prod.yaml     # Prod environment values
│       └── values-override.yaml # Environment overrides
├── auth-setup.md                # Harbor and GitLab authentication guide
├── harbor-auth-setup.md         # Harbor authentication details
├── deployment-steps.md          # Step-by-step deployment guide
└── .github/
    └── pull_request_template.md # MR template for deployments
```

## Prerequisites

### 1. Fleet Installation
```bash
# Check if Fleet is installed
kubectl get crd | grep fleet

# If not installed, install Fleet
kubectl apply -f https://github.com/rancher/fleet/releases/download/v0.12.4/fleet-crd.yaml
kubectl apply -f https://github.com/rancher/fleet/releases/download/v0.12.4/fleet.yaml
```

### 2. Cluster Registration
```bash
# Check existing clusters
kubectl get clusters.fleet.cattle.io -A

# Check cluster labels
kubectl describe cluster <cluster-name> -n fleet-local
```

## Deployment Steps

### Step 1: Prepare Your Git Repository

1. **Fork/Clone this repository**
2. **Update repository URL** in all fleet.yaml files:
   ```yaml
   spec:
     repo: https://gitlab.com/YOUR_USERNAME/YOUR_REPO_NAME.git
   ```

3. **Update branch names** for your environment:
   ```yaml
   spec:
     branch: dev  # or your branch name
   ```

4. **Update Harbor URLs** in Chart.yaml files:
   ```yaml
   dependencies:
     - name: kube-prometheus-stack
       version: 55.5.0
       repository: oci://harbor.your-domain.com/monitoring
   ```

### Step 2: Set Up Authentication

#### Harbor Authentication
```bash
# Create Harbor secret
kubectl create secret docker-registry harbor-secret \
  --docker-server=harbor.your-domain.com \
  --docker-username=robot$project-name$fleet-robot \
  --docker-password=your-robot-token \
  --docker-email=robot@your-domain.com \
  -n fleet-local
```

#### GitLab Authentication
```bash
# Create GitLab secret
kubectl create secret generic gitlab-secret \
  --from-literal=username=your-gitlab-username \
  --from-literal=password=your-gitlab-token \
  -n fleet-local
```

**Note**: See `auth-setup.md` for detailed authentication setup instructions.

### Step 3: Configure Cluster Labels

Label your target clusters appropriately:

```bash
# Option 1: Label existing cluster
kubectl label cluster <cluster-name> env=dev -n fleet-local

# Option 2: Check existing labels
kubectl get cluster <cluster-name> -n fleet-local --show-labels
```

### Step 4: Deploy Fleet GitRepo

```bash
# Apply Fleet GitRepo with authentication
kubectl apply -f fleet-with-auth.yaml
```

**Note**: The deployment follows a sequential order:
1. **01-crds** - CRDs deployed first
2. **02-custom-manifests** - Custom resources deployed second
3. **03-monitoring-stack** - Main monitoring stack deployed last

### Step 5: Verify Deployment

```bash
# Check authentication secrets
kubectl get secrets -n fleet-local

# Check GitRepo status
kubectl get gitrepo -A

# Check Bundle status
kubectl get bundle -A

# Check BundleDeployment status
kubectl get bundledeployment -A

# Check if pods are running
kubectl get pods -n monitoring

# Check services
kubectl get svc -n monitoring
```

## Environment-Specific Configuration

### Dev Environment
- **Branch**: `dev`
- **Storage**: Smaller sizes (5Gi-20Gi)
- **Retention**: 3 days
- **Password**: `dev123`

### Prod Environment
- **Branch**: `prod`
- **Storage**: Larger sizes (50Gi-500Gi)
- **Retention**: 30 days
- **Password**: `prod456`

## Customization

### Adding Custom Values
1. Edit `monitoring/03-monitoring-stack/values-custom.yaml`
2. Add your custom configurations
3. Commit and push to trigger deployment

### Adding Custom Manifests
1. Add files to `monitoring/02-custom-manifests/`
2. Update `kustomization.yaml` if needed
3. Commit and push to trigger deployment

### Environment-Specific Values
1. Edit `values-<env>.yaml` for your environment
2. Update resource limits, passwords, etc.
3. Commit and push to trigger deployment

## Troubleshooting

### Check Fleet Status
```bash
# Check GitRepo conditions
kubectl describe gitrepo <name> -n fleet-local

# Check Bundle conditions
kubectl describe bundle <name> -n fleet-local

# Check BundleDeployment conditions
kubectl describe bundledeployment <name> -A
```

### Common Issues

#### 1. GitRepo Not Syncing
```bash
# Check GitRepo status
kubectl get gitrepo -A -o wide

# Check for authentication issues
kubectl describe gitrepo <name> -n fleet-local

# Check authentication secrets
kubectl get secrets -n fleet-local
kubectl describe secret harbor-secret -n fleet-local
kubectl describe secret gitlab-secret -n fleet-local
```

#### 2. Bundle Not Deploying
```bash
# Check Bundle status
kubectl get bundle -A

# Check for CRD issues
kubectl get crd | grep prometheus
```

#### 3. Helm Chart Issues
```bash
# Check Helm releases
kubectl get helmrelease -A

# Check for values issues
kubectl describe helmrelease <name> -n monitoring
```

#### 4. Harbor Authentication Issues
```bash
# Test Harbor connection
docker login harbor.your-domain.com -u robot$project-name$fleet-robot -p your-robot-token

# Check Harbor secret
kubectl get secret harbor-secret -n fleet-local -o yaml
```

#### 5. GitLab Authentication Issues
```bash
# Test GitLab connection
curl -H "Authorization: Bearer your-gitlab-token" \
  "https://gitlab.com/api/v4/user"

# Check GitLab secret
kubectl get secret gitlab-secret -n fleet-local -o yaml
```

### Reset/Reinstall
```bash
# Delete all Fleet resources
kubectl delete gitrepo --all -n fleet-local
kubectl delete bundle --all -n fleet-local
kubectl delete bundledeployment --all -A

# Delete authentication secrets (if needed)
kubectl delete secret harbor-secret -n fleet-local
kubectl delete secret gitlab-secret -n fleet-local

# Delete monitoring namespace
kubectl delete namespace monitoring

# Reapply Fleet GitRepo
kubectl apply -f fleet-with-auth.yaml
```

## Monitoring Access

### Grafana
```bash
# Port forward Grafana
kubectl port-forward svc/prometheus-stack-grafana 3000:80 -n monitoring

# Access: http://localhost:3000
# Username: admin
# Password: dev123 (dev) or prod456 (prod)
```

### Prometheus
```bash
# Port forward Prometheus
kubectl port-forward svc/prometheus-stack-kube-prometheus-prometheus 9090:9090 -n monitoring

# Access: http://localhost:9090
```

### Alertmanager
```bash
# Port forward Alertmanager
kubectl port-forward svc/prometheus-stack-kube-prometheus-alertmanager 9093:9093 -n monitoring

# Access: http://localhost:9093
```

## GitOps Workflow

### Development Process
1. **Create feature branch** from dev
2. **Make changes** to values or manifests
3. **Test locally** if possible
4. **Create MR** to dev branch
5. **Review and merge**
6. **Fleet automatically deploys** to dev environment

### Production Deployment
1. **Create MR** from dev to prod branch
2. **Review with required approvers**
3. **Run CI checks**
4. **Merge to prod**
5. **Fleet automatically deploys** to prod environment

## Security Considerations

### Secrets Management
- Use `valuesFrom` for sensitive data
- Store secrets in downstream clusters
- Reference secrets in fleet.yaml

### Access Control
- Protect prod branch with branch protection rules
- Require multiple reviewers for prod deployments
- Use RBAC to control Fleet access

## Maintenance

### Updating Helm Charts
1. Update chart version in `Chart.yaml`
2. Test in dev environment
3. Promote to prod via MR

### Scaling Resources
1. Update values in environment-specific files
2. Commit and push changes
3. Fleet automatically applies updates

### Backup and Recovery
- Fleet state is stored in Git
- Use standard Git backup procedures
- Consider backing up monitoring data separately

## Support

For issues with:
- **Fleet**: Check [Fleet Documentation](https://fleet.rancher.io/)
- **kube-prometheus-stack**: Check [Prometheus Operator Documentation](https://github.com/prometheus-operator/kube-prometheus)
- **Helm**: Check [Helm Documentation](https://helm.sh/docs/) 