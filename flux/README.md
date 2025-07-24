# Flux GitOps Multi-Tenant Setup - Step by Step Guide

This repository contains a repeatable GitOps process for managing clusters across tenants with dev/pre-prod/prod environments using Flux v2.

## Architecture Overview

```
├── clusters/                    # Cluster-specific configurations
│   └── tenant1/
│       ├── dev-cluster/         # Development environment
│       ├── preprod-cluster/     # Pre-production environment
│       └── prod-cluster/        # Production environment
├── tenants/                     # Tenant-specific applications
│   └── tenant1/
├── shared/                      # Shared infrastructure components
│   ├── monitoring/             # Rancher monitoring (Prometheus/Grafana)
│   └── logging/                # Rancher logging (Fluentbit/Fluentd)
└── scripts/                     # Automation scripts (optional)
```

## Rancher-Managed Clusters Setup

### Architecture for Rancher Environment

```
Rancher Admin Cluster
├── Manages downstream clusters
└── Centralized cluster management

Downstream Cluster 1 (Dev)
├── Flux installed locally
├── GitOps repo: tenant1-dev
├── Rancher Logging (via Flux)
├── Rancher Monitoring (via Flux)
└── Tenant applications

Downstream Cluster 2 (Preprod)
├── Flux installed locally
├── GitOps repo: tenant1-preprod
├── Rancher Logging (via Flux)
├── Rancher Monitoring (via Flux)
└── Tenant applications

Downstream Cluster 3 (Prod)
├── Flux installed locally
├── GitOps repo: tenant1-prod
├── Rancher Logging (via Flux)
├── Rancher Monitoring (via Flux)
└── Tenant applications
```

### Platform Worker Node Configuration

This setup is configured for Rancher-managed clusters with custom platform worker nodes that have:

- **Label**: `node-role.com/platform-worker=true`
- **Taint**: `node-role..com/platform-worker=NoExecute`

All Flux components, monitoring, logging, and applications are configured to:
- **Node Selector**: Schedule only on platform worker nodes
- **Tolerations**: Tolerate the platform worker taint

This ensures that:
- ✅ All workloads run on dedicated platform worker nodes
- ✅ Proper isolation from control plane nodes
- ✅ Consistent resource allocation
- ✅ Security compliance with your platform architecture

### Why Install Flux on Downstream Clusters?

- **Direct cluster management** - Flux manages resources directly on the cluster where they run
- **Better isolation** - Each cluster manages its own GitOps state
- **Faster reconciliation** - No network latency between admin and downstream
- **Independent scaling** - Each cluster can have different Flux configurations
- **Platform worker compatibility** - Works seamlessly with Rancher platform workers
- **Easier troubleshooting** - Issues are contained to individual clusters

## Prerequisites

- Kubernetes clusters (v1.24+) managed by Rancher
- Helm v3.8+
- kubectl configured for each downstream cluster
- GitLab repository with basic auth
- Flux CLI v0.40+
- Platform workers running on downstream clusters

## Step 1: Prepare Your GitLab Repository

### 1.1 Create GitLab Repository Structure

Create a new GitLab repository with the following structure:
```
your-org/tenant1-gitops/
├── clusters/tenant1/dev-cluster/
├── clusters/tenant1/preprod-cluster/
├── clusters/tenant1/prod-cluster/
├── tenants/tenant1/
└── shared/
```

### 1.2 Create GitLab Access Token

1. Go to GitLab → User Settings → Access Tokens
2. Create a new token with `read_repository` scope
3. Copy the token for use in Flux configuration

## Step 2: Install Flux on Each Downstream Cluster

### 2.1 Switch to Downstream Cluster Context

For each downstream cluster, first switch to the correct context:

```bash
# List available contexts
kubectl config get-contexts

# Switch to dev cluster
kubectl config use-context <dev-cluster-context>

# Switch to preprod cluster  
kubectl config use-context <preprod-cluster-context>

# Switch to prod cluster
kubectl config use-context <prod-cluster-context>
```

### 2.2 Add Flux Helm Repository

```bash
helm repo add flux https://fluxcd.github.io/helm-charts
helm repo update
```

### 2.3 Install Flux via Helm

For each downstream cluster (dev, preprod, prod), run:

```bash
# Create namespace
kubectl create namespace flux-system

# Install Flux
helm upgrade --install flux flux/flux2 \
    --namespace flux-system \
    --create-namespace \
    --set clusterDomain=cluster.local \
    --set image.repository=ghcr.io/fluxcd/flux2 \
    --set image.tag=v2.1.0 \
    --set image.pullPolicy=IfNotPresent \
    --set logLevel=info \
    --set resources.requests.cpu=100m \
    --set resources.requests.memory=128Mi \
    --set resources.limits.cpu=1000m \
    --set resources.limits.memory=512Mi \
    --set nodeSelector."node-role\.caas\.nci\.bt\.com/platform-worker"=true \
    --set tolerations[0].key=node-role..com/platform-worker \
    --set tolerations[0].operator=Equal \
    --set tolerations[0].value=true \
    --set tolerations[0].effect=NoExecute \
    --wait --timeout=5m
```

### 2.4 Create GitLab Authentication Secret

For each downstream cluster, create the secret with your GitLab credentials:

```bash
kubectl create secret generic gitlab-auth-tenant1 \
    --namespace=flux-system \
    --from-literal=username=your-gitlab-username \
    --from-literal=password=your-gitlab-token
```

## Step 3: Configure GitRepository for Each Environment

### 3.1 Dev Environment GitRepository

```bash
# Make sure you're on dev cluster context
kubectl config use-context <dev-cluster-context>

cat <<EOF | kubectl apply -f -
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: tenant1-dev
  namespace: flux-system
spec:
  interval: 1m
  url: https://gitlab.com/your-org/tenant1-gitops.git
  ref:
    branch: dev
  secretRef:
    name: gitlab-auth-tenant1
EOF
```

### 3.2 Preprod Environment GitRepository

```bash
# Switch to preprod cluster context
kubectl config use-context <preprod-cluster-context>

cat <<EOF | kubectl apply -f -
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: tenant1-preprod
  namespace: flux-system
spec:
  interval: 1m
  url: https://gitlab.com/your-org/tenant1-gitops.git
  ref:
    branch: preprod
  secretRef:
    name: gitlab-auth-tenant1
EOF
```

### 3.3 Prod Environment GitRepository

```bash
# Switch to prod cluster context
kubectl config use-context <prod-cluster-context>

cat <<EOF | kubectl apply -f -
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: tenant1-prod
  namespace: flux-system
spec:
  interval: 1m
  url: https://gitlab.com/your-org/tenant1-gitops.git
  ref:
    branch: prod
  secretRef:
    name: gitlab-auth-tenant1
EOF
```

## Step 4: Configure HelmRepositories

### 4.1 Create HelmRepository for Rancher Charts

For each downstream cluster:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: rancher-charts
  namespace: flux-system
spec:
  interval: 1h
  url: https://releases.rancher.com/server-charts/stable
  type: oci
EOF
```

### 4.2 Create HelmRepository for Prometheus Charts

```bash
cat <<EOF | kubectl apply -f -
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: prometheus-community
  namespace: flux-system
spec:
  interval: 1h
  url: https://prometheus-community.github.io/helm-charts
EOF
```

## Step 5: Configure Kustomizations

### 5.1 Dev Environment Kustomizations

```bash
# Make sure you're on dev cluster context
kubectl config use-context <dev-cluster-context>

# Cluster-specific resources
cat <<EOF | kubectl apply -f -
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: tenant1-dev-cluster
  namespace: flux-system
spec:
  interval: 10m
  path: ./clusters/tenant1/dev-cluster
  prune: true
  sourceRef:
    kind: GitRepository
    name: tenant1-dev
  targetNamespace: flux-system
EOF

# Shared infrastructure
cat <<EOF | kubectl apply -f -
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: tenant1-dev-shared
  namespace: flux-system
spec:
  interval: 10m
  path: ./shared
  prune: true
  sourceRef:
    kind: GitRepository
    name: tenant1-dev
  targetNamespace: flux-system
EOF

# Tenant applications
cat <<EOF | kubectl apply -f -
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: tenant1-dev-apps
  namespace: flux-system
spec:
  interval: 10m
  path: ./tenants/tenant1
  prune: true
  sourceRef:
    kind: GitRepository
    name: tenant1-dev
  targetNamespace: default
EOF
```

### 5.2 Preprod Environment Kustomizations

```bash
# Switch to preprod cluster context
kubectl config use-context <preprod-cluster-context>

# Cluster-specific resources
cat <<EOF | kubectl apply -f -
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: tenant1-preprod-cluster
  namespace: flux-system
spec:
  interval: 10m
  path: ./clusters/tenant1/preprod-cluster
  prune: true
  sourceRef:
    kind: GitRepository
    name: tenant1-preprod
  targetNamespace: flux-system
EOF

# Shared infrastructure
cat <<EOF | kubectl apply -f -
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: tenant1-preprod-shared
  namespace: flux-system
spec:
  interval: 10m
  path: ./shared
  prune: true
  sourceRef:
    kind: GitRepository
    name: tenant1-preprod
  targetNamespace: flux-system
EOF

# Tenant applications
cat <<EOF | kubectl apply -f -
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: tenant1-preprod-apps
  namespace: flux-system
spec:
  interval: 10m
  path: ./tenants/tenant1
  prune: true
  sourceRef:
    kind: GitRepository
    name: tenant1-preprod
  targetNamespace: default
EOF
```

### 5.3 Prod Environment Kustomizations

```bash
# Switch to prod cluster context
kubectl config use-context <prod-cluster-context>

# Cluster-specific resources
cat <<EOF | kubectl apply -f -
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: tenant1-prod-cluster
  namespace: flux-system
spec:
  interval: 10m
  path: ./clusters/tenant1/prod-cluster
  prune: true
  sourceRef:
    kind: GitRepository
    name: tenant1-prod
  targetNamespace: flux-system
EOF

# Shared infrastructure
cat <<EOF | kubectl apply -f -
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: tenant1-prod-shared
  namespace: flux-system
spec:
  interval: 10m
  path: ./shared
  prune: true
  sourceRef:
    kind: GitRepository
    name: tenant1-prod
  targetNamespace: flux-system
EOF

# Tenant applications
cat <<EOF | kubectl apply -f -
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: tenant1-prod-apps
  namespace: flux-system
spec:
  interval: 10m
  path: ./tenants/tenant1
  prune: true
  sourceRef:
    kind: GitRepository
    name: tenant1-prod
  targetNamespace: default
EOF
```

## Step 6: Deploy Shared Infrastructure

### 6.1 Deployment Order

The shared infrastructure is deployed in the following order to ensure proper dependency resolution:

1. **CRDs First** - Custom Resource Definitions for monitoring and logging
2. **Helm Charts** - Rancher monitoring and logging charts
3. **Custom Manifests** - Custom configurations and images from Harbor registry

### 6.2 Deploy Rancher Monitoring

The monitoring will be deployed automatically via the shared kustomization in this order:

```bash
# 1. CRDs are deployed first
kubectl get crd | grep monitoring.coreos.com

# 2. Helm chart deploys monitoring components
kubectl get helmreleases -n cattle-monitoring-system

# 3. Custom manifests from Harbor are deployed
kubectl get pods -n cattle-monitoring-system -l app=custom-dashboard-exporter
```

To check status:

```bash
# Check HelmRelease status
kubectl get helmreleases -n cattle-monitoring-system

# Check monitoring pods
kubectl get pods -n cattle-monitoring-system

# Check custom components from Harbor
kubectl get pods -n cattle-monitoring-system -l app=custom-dashboard-exporter

# Access Grafana (if LoadBalancer is configured)
kubectl get svc -n cattle-monitoring-system grafana
```

### 6.3 Deploy Rancher Logging

The logging will be deployed automatically via the shared kustomization in this order:

```bash
# 1. CRDs are deployed first
kubectl get crd | grep logging.banzaicloud.io

# 2. Helm chart deploys logging components
kubectl get helmreleases -n cattle-logging-system

# 3. Custom logging configurations are deployed
kubectl get logging -n cattle-logging-system
```

To check status:

```bash
# Check HelmRelease status
kubectl get helmreleases -n cattle-logging-system

# Check logging pods
kubectl get pods -n cattle-logging-system

# Check custom logging configuration
kubectl get logging -n cattle-logging-system

# Check custom Fluentd/Fluentbit images from Harbor
kubectl get pods -n cattle-logging-system -o jsonpath='{.items[*].spec.containers[*].image}'
```

### 6.4 Harbor Registry Integration

Custom components are pulled from your internal Harbor registry. Flux needs to authenticate with Harbor to access custom images and charts.

#### 6.4.1 Create Harbor Authentication Secrets

```bash
# Option 1: Use the provided script
./scripts/create-harbor-secrets.sh harbor.your-domain.com your-username your-password

# Option 2: Manual creation
# Create base64 encoded docker config
DOCKER_CONFIG=$(cat <<EOF
{
  "auths": {
    "harbor.your-domain.com": {
      "auth": "$(echo -n "your-username:your-password" | base64)"
    }
  }
}
EOF
)

BASE64_CONFIG=$(echo "$DOCKER_CONFIG" | base64)

# Create secret for flux-system namespace (for HelmRepository)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: harbor-auth-secret
  namespace: flux-system
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: $BASE64_CONFIG
EOF

# Create secret for cattle-monitoring-system namespace
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: harbor-registry-secret
  namespace: cattle-monitoring-system
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: $BASE64_CONFIG
EOF

# Create secret for cattle-logging-system namespace
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: harbor-registry-secret
  namespace: cattle-logging-system
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: $BASE64_CONFIG
EOF
```

#### 6.4.2 Verify Harbor Authentication

```bash
# Check if secrets were created
kubectl get secrets -n flux-system harbor-auth-secret
kubectl get secrets -n cattle-monitoring-system harbor-registry-secret
kubectl get secrets -n cattle-logging-system harbor-registry-secret

# Test Harbor chart repository access
kubectl describe helmrepository harbor-charts -n flux-system
```

#### 6.4.3 Custom Images from Harbor

The following custom images are pulled from your Harbor registry:

**Monitoring Components:**
- `harbor.your-domain.com/your-org/custom-dashboard-exporter:latest`
- `harbor.your-domain.com/your-org/custom-grafana-plugins:latest`

**Logging Components:**
- `harbor.your-domain.com/your-org/custom-fluentd:latest`
- `harbor.your-domain.com/your-org/custom-fluentbit:latest`

**Custom Charts:**
- `harbor.your-domain.com/chartrepo/your-org/custom-monitoring:latest`
- `harbor.your-domain.com/chartrepo/your-org/custom-logging:latest`
```

## Step 7: Verify Deployment

### 7.1 Check Flux Status on Each Cluster

```bash
# Check Flux pods
kubectl get pods -n flux-system

# Check GitRepositories
kubectl get gitrepositories -n flux-system

# Check Kustomizations
kubectl get kustomizations -n flux-system

# Check HelmReleases
kubectl get helmreleases -A
```

### 7.2 Check Application Status

```bash
# Check tenant applications
kubectl get pods -l tenant=tenant1

# Check services
kubectl get svc -l tenant=tenant1

# Check deployments
kubectl get deployments -l tenant=tenant1
```

### 7.3 Check Monitoring and Logging

```bash
# Check monitoring components
kubectl get pods -n cattle-monitoring-system
kubectl get svc -n cattle-monitoring-system

# Check logging components
kubectl get pods -n cattle-logging-system
kubectl get svc -n cattle-logging-system
```

## Step 8: Access Dashboards

### 8.1 Access Grafana

```bash
# Port forward to access Grafana
kubectl port-forward -n cattle-monitoring-system svc/grafana 3000:80

# Access at http://localhost:3000
# Default credentials: admin/admin123
```

### 8.2 Access Prometheus

```bash
# Port forward to access Prometheus
kubectl port-forward -n cattle-monitoring-system svc/prometheus-operated 9090:9090

# Access at http://localhost:9090
```

## Step 9: GitOps Workflow with Branch Protection

### 9.1 GitLab Repository Setup with Branch Protection

#### Create Protected Branches

Set up branch protection rules in GitLab for each environment:

**Dev Branch (`dev`)**
- Protected: ✅
- Allowed to merge: Maintainers
- Allowed to push: No one (merge requests only)
- Code owner approval required: ✅
- Require approval from code owners: 1
- Require pipeline to succeed: ✅
- Require up-to-date branch: ✅

**Preprod Branch (`preprod`)**
- Protected: ✅
- Allowed to merge: Maintainers
- Allowed to push: No one (merge requests only)
- Code owner approval required: ✅
- Require approval from code owners: 2
- Require pipeline to succeed: ✅
- Require up-to-date branch: ✅
- Require security scan to pass: ✅

**Prod Branch (`prod`)**
- Protected: ✅
- Allowed to merge: Maintainers + specific approvers
- Allowed to push: No one (merge requests only)
- Code owner approval required: ✅
- Require approval from code owners: 3
- Require pipeline to succeed: ✅
- Require up-to-date branch: ✅
- Require security scan to pass: ✅
- Require license compliance: ✅

#### Create CODEOWNERS File

Create `.gitlab/CODEOWNERS` in your repository:

```
# Global code owners
* @platform-team @devops-team

# Environment-specific owners
/clusters/tenant1/dev-cluster/ @dev-team
/clusters/tenant1/preprod-cluster/ @qa-team @dev-team
/clusters/tenant1/prod-cluster/ @platform-team @devops-team @security-team

# Shared infrastructure
/shared/ @platform-team @devops-team

# Tenant applications
/tenants/tenant1/ @app-team @dev-team
```

### 9.2 Development Workflow

#### 9.2.1 Feature Development

1. **Create feature branch from dev**
   ```bash
   git checkout dev
   git pull origin dev
   git checkout -b feature/new-app-version
   ```

2. **Make changes and commit**
   ```bash
   # Update application manifests
   vim tenants/tenant1/applications/sample-app.yaml
   
   # Commit changes
   git add tenants/tenant1/applications/sample-app.yaml
   git commit -m "feat: update app to v2.0.0"
   ```

3. **Push and create merge request**
   ```bash
   git push origin feature/new-app-version
   # Create MR in GitLab: feature/new-app-version → dev
   ```

4. **Merge request requirements**
   - ✅ Pipeline passes (linting, validation)
   - ✅ Code review approved by code owners
   - ✅ Security scan passes
   - ✅ Documentation updated (if needed)

5. **Merge to dev**
   - Flux automatically deploys to dev cluster
   - Test and validate in dev environment

#### 9.2.2 Promotion to Preprod

1. **Create merge request: dev → preprod**
   ```bash
   # In GitLab, create MR: dev → preprod
   # Title: "Promote v2.0.0 to preprod"
   # Description: Include testing results and validation checklist
   ```

2. **Preprod merge request requirements**
   - ✅ Dev environment testing completed
   - ✅ Integration tests pass
   - ✅ Performance tests pass
   - ✅ Security scan passes
   - ✅ 2 code owner approvals
   - ✅ QA team approval

3. **Merge to preprod**
   - Flux automatically deploys to preprod cluster
   - Run integration and performance tests
   - Stakeholder validation

#### 9.2.3 Promotion to Production

1. **Create merge request: preprod → prod**
   ```bash
   # In GitLab, create MR: preprod → prod
   # Title: "Deploy v2.0.0 to production"
   # Description: Include all testing results and business approval
   ```

2. **Production merge request requirements**
   - ✅ Preprod environment testing completed
   - ✅ All integration tests pass
   - ✅ Performance tests meet SLAs
   - ✅ Security scan passes
   - ✅ License compliance verified
   - ✅ 3 code owner approvals
   - ✅ Platform team approval
   - ✅ Security team approval
   - ✅ Business stakeholder approval

3. **Merge to prod**
   - Flux automatically deploys to production cluster
   - Monitor deployment and application health
   - Verify business functionality

### 9.3 GitLab CI/CD Pipeline

Create `.gitlab-ci.yml` for automated validation:

```yaml
stages:
  - validate
  - security
  - deploy

variables:
  KUBERNETES_VERSION: "1.24"

validate:
  stage: validate
  image: alpine/k8s:1.24.0
  script:
    - kubectl kustomize clusters/tenant1/dev-cluster/ > /dev/null
    - kubectl kustomize clusters/tenant1/preprod-cluster/ > /dev/null
    - kubectl kustomize clusters/tenant1/prod-cluster/ > /dev/null
    - kubectl kustomize shared/ > /dev/null
    - kubectl kustomize tenants/tenant1/ > /dev/null
    - echo "✅ All Kustomize configurations are valid"

security-scan:
  stage: security
  image: aquasec/trivy:latest
  script:
    - trivy config .
    - echo "✅ Security scan completed"

deploy-dev:
  stage: deploy
  image: alpine/k8s:1.24.0
  script:
    - echo "Deployment handled by Flux"
  only:
    - dev
  when: manual
```

### 9.4 Emergency Procedures

#### 9.4.1 Hotfix Process

For critical production issues:

1. **Create hotfix branch from prod**
   ```bash
   git checkout prod
   git pull origin prod
   git checkout -b hotfix/critical-fix
   ```

2. **Make minimal required changes**
   ```bash
   # Make only essential changes
   git commit -m "hotfix: critical security patch"
   ```

3. **Emergency merge request**
   - Bypass some approval requirements (if configured)
   - Require at least 2 senior approvers
   - Deploy directly to prod

4. **Post-deployment**
   - Backport fix to dev and preprod
   - Update documentation
   - Conduct post-mortem

#### 9.4.2 Rollback Process

1. **Revert merge request**
   ```bash
   git checkout prod
   git revert <commit-hash>
   git push origin prod
   ```

2. **Or force sync to previous commit**
   ```bash
   kubectl annotate kustomization tenant1-prod-apps -n flux-system \
     fluxcd.io/reconcile=true
   ```

### 9.5 Compliance and Audit

#### 9.5.1 Audit Trail

- All changes tracked through GitLab merge requests
- Approval history maintained
- Deployment logs available in Flux
- Security scan results archived

#### 9.5.2 Compliance Requirements

- **Dev**: Basic validation and testing
- **Preprod**: Integration testing and security scanning
- **Prod**: Full compliance including security, licensing, and business approval

#### 9.5.3 Monitoring and Alerts

- Monitor merge request approval times
- Alert on failed deployments
- Track security scan failures
- Monitor compliance violations

## Troubleshooting

### Check Flux Logs

```bash
# Check Flux controller logs
kubectl logs -n flux-system deployment/flux

# Check Flux events
kubectl get events -n flux-system --sort-by='.lastTimestamp'

# Check specific Kustomization
kubectl describe kustomization tenant1-dev-apps -n flux-system
```

### Common Issues

1. **Git authentication failed**: Check GitLab token and repository URL
2. **Kustomization not syncing**: Verify path exists in repository
3. **HelmRelease failed**: Check HelmRepository and chart version
4. **Resource limits exceeded**: Adjust resource requests/limits
5. **Wrong cluster context**: Make sure you're on the correct cluster before running commands
6. **Pods stuck in Pending**: Check if platform worker nodes are available and taints are configured correctly
7. **Merge request blocked**: Check branch protection rules and approval requirements
8. **Harbor authentication failed**: Check Harbor registry secrets and credentials

### Harbor Authentication Issues

If pods fail to pull images from Harbor:

```bash
# Check Harbor authentication secrets
kubectl get secrets -n flux-system harbor-auth-secret
kubectl get secrets -n cattle-monitoring-system harbor-registry-secret
kubectl get secrets -n cattle-logging-system harbor-registry-secret

# Check pod events for image pull errors
kubectl describe pod <pod-name> -n <namespace>

# Verify Harbor registry access
kubectl describe helmrepository harbor-charts -n flux-system

# Test Harbor credentials manually
docker login harbor.your-domain.com -u your-username -p your-password
```

Common Harbor issues:
- **Invalid credentials**: Check username/password in Harbor secrets
- **Network connectivity**: Ensure cluster can reach Harbor registry
- **Registry URL**: Verify Harbor domain is correct
- **ImagePullSecrets**: Ensure secrets are referenced in deployments

### Platform Worker Node Issues

If pods are stuck in Pending state, check:

```bash
# Check if platform worker nodes exist
kubectl get nodes -l node-role..com/platform-worker=true

# Check node taints
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints

# Check if pods can be scheduled
kubectl describe pod <pod-name> -n <namespace>

# Verify node selector and tolerations
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 10 -B 5 nodeSelector
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 10 -B 5 tolerations
```

Common platform worker issues:
- **No platform worker nodes**: Ensure platform worker nodes are provisioned
- **Incorrect taint configuration**: Verify taint key/value matches configuration
- **Resource constraints**: Check if platform worker nodes have sufficient resources
- **Storage class issues**: Ensure storage classes are available on platform worker nodes

### GitOps Workflow Issues

```bash
# Check if Flux can access the repository
kubectl describe gitrepository tenant1-dev -n flux-system

# Check if Kustomizations are syncing
kubectl get kustomizations -n flux-system -o wide

# Check Flux reconciliation status
kubectl get events -n flux-system --sort-by='.lastTimestamp' | grep -i flux
```

### Reset Flux (if needed)

```bash
# Delete all Flux resources
kubectl delete kustomizations --all -n flux-system
kubectl delete gitrepositories --all -n flux-system
kubectl delete helmrepositories --all -n flux-system
kubectl delete helmreleases --all -A

# Uninstall Flux
helm uninstall flux -n flux-system
kubectl delete namespace flux-system
```

## Environment-Specific Configurations

### Dev Environment
- Resource limits: 1 CPU, 2GB RAM
- Monitoring retention: 7 days
- Scrape interval: 30s
- Storage: 10GB

### Preprod Environment
- Resource limits: 2 CPU, 4GB RAM
- Monitoring retention: 14 days
- Scrape interval: 15s
- Storage: 20GB

### Production Environment
- Resource limits: 4 CPU, 8GB RAM
- Monitoring retention: 30 days
- Scrape interval: 10s
- Storage: 50GB
- Additional security policies enabled

## Security Considerations

- GitLab tokens should have minimal required permissions
- Use RBAC to restrict access per tenant
- Enable network policies for pod-to-pod communication
- Regularly rotate GitLab tokens
- Monitor Flux logs for security events
- Platform workers provide additional security isolation
- Branch protection prevents direct commits to protected branches
- Merge request approvals ensure code review and compliance 