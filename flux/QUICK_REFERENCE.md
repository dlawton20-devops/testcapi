# Flux GitOps Quick Reference

## GitOps Workflow Overview

```
Feature Branch → Dev Branch → Preprod Branch → Prod Branch
     ↓              ↓              ↓              ↓
   MR to Dev    MR to Preprod   MR to Prod    Production
     ↓              ↓              ↓              ↓
  Dev Cluster   Preprod Cluster  Prod Cluster   Live App
```

## Branch Protection Rules

### Dev Branch (`dev`)
- ✅ Protected branch
- ✅ Merge requests only (no direct pushes)
- ✅ 1 code owner approval required
- ✅ Pipeline must pass
- ✅ Up-to-date branch required

### Preprod Branch (`preprod`)
- ✅ Protected branch
- ✅ Merge requests only
- ✅ 2 code owner approvals required
- ✅ Pipeline must pass
- ✅ Security scan must pass
- ✅ Up-to-date branch required

### Prod Branch (`prod`)
- ✅ Protected branch
- ✅ Merge requests only
- ✅ 3 code owner approvals required
- ✅ Pipeline must pass
- ✅ Security scan must pass
- ✅ License compliance required
- ✅ Up-to-date branch required

## Cluster Context Management

### Switch Between Clusters
```bash
# List available contexts
kubectl config get-contexts

# Switch to specific cluster
kubectl config use-context <cluster-name>

# Check current context
kubectl config current-context

# Set context for specific command
kubectl --context <cluster-name> get pods
```

### Common Cluster Names
```bash
# Dev cluster
kubectl config use-context <dev-cluster-context>

# Preprod cluster
kubectl config use-context <preprod-cluster-context>

# Prod cluster
kubectl config use-context <prod-cluster-context>
```

## Daily Operations

### Check Status
```bash
# Check Flux components
kubectl get pods -n flux-system
kubectl get gitrepositories,kustomizations -n flux-system
kubectl get helmreleases -A

# Check application status
kubectl get pods -l tenant=tenant1
kubectl get svc -l tenant=tenant1
```

### Access Dashboards
```bash
# Grafana
kubectl port-forward -n cattle-monitoring-system svc/grafana 3000:80
# http://localhost:3000 (admin/admin123)

# Prometheus
kubectl port-forward -n cattle-monitoring-system svc/prometheus-operated 9090:9090
# http://localhost:9090
```

### Troubleshooting
```bash
# Check Flux logs
kubectl logs -n flux-system deployment/flux
kubectl get events -n flux-system --sort-by='.lastTimestamp'

# Check specific component
kubectl describe kustomization tenant1-dev-apps -n flux-system
kubectl describe gitrepository tenant1-dev -n flux-system
```

## GitOps Workflow Commands

### Feature Development
```bash
# Create feature branch
git checkout dev
git pull origin dev
git checkout -b feature/new-feature

# Make changes and commit
git add .
git commit -m "feat: add new feature"

# Push and create merge request
git push origin feature/new-feature
# Create MR in GitLab: feature/new-feature → dev
```

### Promotion Workflow
```bash
# Dev → Preprod promotion
# Create MR in GitLab: dev → preprod
# Requirements: 2 approvals, security scan pass

# Preprod → Prod promotion  
# Create MR in GitLab: preprod → prod
# Requirements: 3 approvals, security scan pass, license compliance
```

### Force Sync (if needed)
```bash
# Force sync a Kustomization
kubectl annotate kustomization tenant1-dev-apps -n flux-system \
  fluxcd.io/reconcile=true

# Force sync all
kubectl annotate kustomization --all -n flux-system \
  fluxcd.io/reconcile=true
```

## Pipeline Commands

### Check Pipeline Status
```bash
# View pipeline in GitLab UI
# Or use GitLab CLI
glab pipeline status

# Check pipeline logs
glab pipeline view <pipeline-id>
```

### Pipeline Stages
1. **Validate**: Kustomize configuration validation
2. **Security**: Trivy security scanning
3. **Deploy**: Deployment notification (Flux handles actual deployment)

### Manual Pipeline Triggers
```bash
# Trigger pipeline manually (emergency only)
# In GitLab UI: CI/CD → Pipelines → Run Pipeline

# Or via GitLab CLI
glab pipeline run
```

## Monitoring Commands

### Check Monitoring Status
```bash
# Check monitoring pods
kubectl get pods -n cattle-monitoring-system

# Check monitoring services
kubectl get svc -n cattle-monitoring-system

# Check Prometheus targets
kubectl port-forward -n cattle-monitoring-system svc/prometheus-operated 9090:9090
# Then visit http://localhost:9090/targets
```

### Check Logging Status
```bash
# Check logging pods
kubectl get pods -n cattle-logging-system

# Check logging configuration
kubectl get logging -n cattle-logging-system

# Check Fluentbit logs
kubectl logs -n cattle-logging-system -l app=rancher-logging-fluentbit
```

## Emergency Procedures

### Hotfix Process
```bash
# Create hotfix branch from prod
git checkout prod
git pull origin prod
git checkout -b hotfix/critical-fix

# Make minimal changes
git commit -m "hotfix: critical security patch"

# Emergency merge request (bypass some approvals if needed)
git push origin hotfix/critical-fix
# Create MR: hotfix/critical-fix → prod
```

### Rollback Deployment
```bash
# Revert merge request
git checkout prod
git revert <commit-hash>
git push origin prod

# Or force sync to previous commit
kubectl annotate kustomization <name> -n flux-system \
  fluxcd.io/reconcile=true
```

### Reset Flux (Nuclear Option)
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

## Useful Aliases

Add these to your shell profile:
```bash
# Cluster context shortcuts
alias dev-cluster='kubectl config use-context <dev-cluster-context>'
alias preprod-cluster='kubectl config use-context <preprod-cluster-context>'
alias prod-cluster='kubectl config use-context <prod-cluster-context>'

# Flux status
alias flux-status='kubectl get gitrepositories,kustomizations,helmreleases -n flux-system'

# Flux logs
alias flux-logs='kubectl logs -n flux-system deployment/flux -f'

# Check tenant apps
alias tenant-apps='kubectl get pods,svc,deployments -l tenant=tenant1'

# Port forward Grafana
alias grafana='kubectl port-forward -n cattle-monitoring-system svc/grafana 3000:80'

# Port forward Prometheus
alias prometheus='kubectl port-forward -n cattle-monitoring-system svc/prometheus-operated 9090:9090'

# Git workflow shortcuts
alias git-dev='git checkout dev && git pull origin dev'
alias git-preprod='git checkout preprod && git pull origin preprod'
alias git-prod='git checkout prod && git pull origin prod'
```

## Environment Variables

Set these for your tenant:
```bash
export TENANT=tenant1
export GITLAB_REPO=https://gitlab.com/your-org/tenant1-gitops.git
export GITLAB_TOKEN=your-token
export DEV_CLUSTER=<dev-cluster-context>
export PREPROD_CLUSTER=<preprod-cluster-context>
export PROD_CLUSTER=<prod-cluster-context>
```

## Common kubectl Commands

```bash
# Get all resources with tenant label
kubectl get all -l tenant=tenant1

# Watch pods
kubectl get pods -l tenant=tenant1 -w

# Describe resource
kubectl describe pod <pod-name>

# Exec into pod
kubectl exec -it <pod-name> -- /bin/bash

# Copy files from/to pod
kubectl cp <pod-name>:/path/to/file ./local-file
kubectl cp ./local-file <pod-name>:/path/to/file
```

## Multi-Cluster Operations

### Check All Clusters Status
```bash
# Check Flux on all clusters
for cluster in dev preprod prod; do
  echo "=== $cluster cluster ==="
  kubectl --context <${cluster}-cluster-context> get pods -n flux-system
  echo ""
done
```

### Deploy to All Clusters
```bash
# Force sync on all clusters
for cluster in dev preprod prod; do
  echo "Syncing $cluster cluster..."
  kubectl --context <${cluster}-cluster-context> annotate kustomization --all -n flux-system fluxcd.io/reconcile=true
done
```

## Platform Worker Node Commands

### Check Platform Worker Nodes
```bash
# List platform worker nodes
kubectl get nodes -l node-role.com/platform-worker=true

# Check node taints
kubectl get nodes -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints

# Check pod scheduling
kubectl describe pod <pod-name> -n <namespace>
```

### Platform Worker Issues
```bash
# Check if pods can be scheduled on platform workers
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 10 -B 5 nodeSelector
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 10 -B 5 tolerations
```

## Harbor Registry Commands

### Harbor Authentication
```bash
# Create Harbor secrets
./scripts/create-harbor-secrets.sh harbor.your-domain.com your-username your-password

# Check Harbor secrets
kubectl get secrets -n flux-system harbor-auth-secret
kubectl get secrets -n cattle-monitoring-system harbor-registry-secret
kubectl get secrets -n cattle-logging-system harbor-registry-secret

# Test Harbor registry access
kubectl describe helmrepository harbor-charts -n flux-system
```

### Harbor Image Issues
```bash
# Check for image pull errors
kubectl describe pod <pod-name> -n <namespace> | grep -A 10 -B 5 "Failed"

# Verify image references
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[*].image}'

# Test Harbor login manually
docker login harbor.your-domain.com -u your-username -p your-password
```

### Harbor Chart Repository
```bash
# List available charts from Harbor
helm repo add harbor-charts https://harbor.your-domain.com/chartrepo/your-org
helm repo update
helm search repo harbor-charts/

# Install custom chart from Harbor
helm install custom-monitoring harbor-charts/custom-monitoring -n cattle-monitoring-system
```

## Merge Request Checklist

### Dev Branch MR
- [ ] Pipeline passes (validate stage)
- [ ] Code review approved by code owners
- [ ] Security scan passes
- [ ] Documentation updated (if needed)

### Preprod Branch MR
- [ ] Dev environment testing completed
- [ ] Integration tests pass
- [ ] Performance tests pass
- [ ] Security scan passes
- [ ] 2 code owner approvals
- [ ] QA team approval

### Prod Branch MR
- [ ] Preprod environment testing completed
- [ ] All integration tests pass
- [ ] Performance tests meet SLAs
- [ ] Security scan passes
- [ ] License compliance verified
- [ ] 3 code owner approvals
- [ ] Platform team approval
- [ ] Security team approval
- [ ] Business stakeholder approval 