# Authentication Setup for Harbor and GitLab

## Overview

This guide covers setting up authentication for:
1. **Harbor** - For pulling private Helm charts
2. **GitLab** - For accessing private Git repositories

## 1. Harbor Authentication Setup

### Step 1: Create Harbor Robot Account (Recommended)

1. **Login to Harbor UI**
2. **Go to Administration → Robot Accounts**
3. **Create new robot account:**
   - Name: `fleet-robot`
   - Description: `Fleet GitOps robot account`
   - Expiration: Set appropriate expiration
   - Permissions: Select projects that contain your Helm charts

4. **Copy the robot account credentials:**
   - Username: `robot$project-name$fleet-robot`
   - Token: `your-robot-token`

### Step 2: Create Harbor Secret

```bash
# Create Harbor secret in fleet-local namespace
kubectl create secret docker-registry harbor-secret \
  --docker-server=harbor.your-domain.com \
  --docker-username=robot$project-name$fleet-robot \
  --docker-password=your-robot-token \
  --docker-email=robot@your-domain.com \
  -n fleet-local
```

### Step 3: Verify Harbor Secret

```bash
# Check secret was created
kubectl get secret harbor-secret -n fleet-local

# Verify secret details
kubectl describe secret harbor-secret -n fleet-local
```

## 2. GitLab Authentication Setup

### Step 1: Create GitLab Personal Access Token

1. **Login to GitLab**
2. **Go to User Settings → Access Tokens**
3. **Create new token:**
   - Token name: `fleet-gitops`
   - Expiration date: Set appropriate expiration
   - Scopes: Select `read_repository` (minimum required)

4. **Copy the token** (you won't see it again)

### Step 2: Create GitLab Secret

```bash
# Create GitLab secret in fleet-local namespace
kubectl create secret generic gitlab-secret \
  --from-literal=username=your-gitlab-username \
  --from-literal=password=your-gitlab-token \
  -n fleet-local
```

### Step 3: Verify GitLab Secret

```bash
# Check secret was created
kubectl get secret gitlab-secret -n fleet-local

# Verify secret details
kubectl describe secret gitlab-secret -n fleet-local
```

## 3. Update Fleet Configuration

### Step 1: Update Main Fleet GitRepo

```yaml
# fleet.yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: monitoring-dev
  namespace: fleet-local
spec:
  repo: https://gitlab.com/your-username/your-repo.git
  branch: dev
  paths:
    - monitoring
  # GitLab authentication
  clientSecretName: gitlab-secret
  # Harbor authentication for Helm charts
  helmSecretName: harbor-secret
  targets:
    - name: dev-clusters
      clusterSelector:
        matchLabels:
          env: dev
```

### Step 2: Update Bundle Configurations

```yaml
# monitoring/03-monitoring-stack/fleet.yaml
defaultNamespace: monitoring
targetNamespace: monitoring

helm:
  repo: oci://harbor.your-domain.com/monitoring
  chart: kube-prometheus-stack
  version: 55.5.0
  helmSecretName: harbor-secret
  valuesFiles:
    - values.yaml
    - values-custom.yaml

targets:
- clusterSelector:
    matchLabels:
      env: dev
```

## 4. Complete Setup Script

```bash
#!/bin/bash

# Configuration variables
HARBOR_URL="harbor.your-domain.com"
HARBOR_USERNAME="robot$project-name$fleet-robot"
HARBOR_PASSWORD="your-robot-token"
HARBOR_EMAIL="robot@your-domain.com"

GITLAB_USERNAME="your-gitlab-username"
GITLAB_TOKEN="your-gitlab-token"

# Create Harbor secret
echo "Creating Harbor secret..."
kubectl create secret docker-registry harbor-secret \
  --docker-server=$HARBOR_URL \
  --docker-username=$HARBOR_USERNAME \
  --docker-password=$HARBOR_PASSWORD \
  --docker-email=$HARBOR_EMAIL \
  -n fleet-local

# Create GitLab secret
echo "Creating GitLab secret..."
kubectl create secret generic gitlab-secret \
  --from-literal=username=$GITLAB_USERNAME \
  --from-literal=password=$GITLAB_TOKEN \
  -n fleet-local

# Verify secrets
echo "Verifying secrets..."
kubectl get secret harbor-secret -n fleet-local
kubectl get secret gitlab-secret -n fleet-local

# Apply Fleet configuration
echo "Applying Fleet configuration..."
kubectl apply -f fleet.yaml

# Verify deployment
echo "Verifying deployment..."
kubectl get gitrepo -A
kubectl get bundle -A
```

## 5. Test Authentication

### Test Harbor Connection

```bash
# Test Harbor login
docker login $HARBOR_URL -u $HARBOR_USERNAME -p $HARBOR_PASSWORD

# Test chart pull
helm pull oci://$HARBOR_URL/monitoring/kube-prometheus-stack --version 55.5.0
```

### Test GitLab Connection

```bash
# Test GitLab access
curl -H "Authorization: Bearer $GITLAB_TOKEN" \
  "https://gitlab.com/api/v4/projects/your-project-id"

# Test repository access
git clone https://oauth2:$GITLAB_TOKEN@gitlab.com/your-username/your-repo.git
```

## 6. Troubleshooting

### Check Secret Status

```bash
# Check Harbor secret
kubectl get secret harbor-secret -n fleet-local -o yaml

# Check GitLab secret
kubectl get secret gitlab-secret -n fleet-local -o yaml
```

### Check Fleet Logs

```bash
# Check Fleet controller logs
kubectl logs -n fleet-system deployment/fleet-controller

# Check Fleet agent logs
kubectl logs -n cattle-fleet-system deployment/fleet-agent
```

### Common Issues

1. **Harbor Authentication Failed**
   ```bash
   # Check robot account permissions
   # Verify token hasn't expired
   # Test manual login
   docker login harbor.your-domain.com
   ```

2. **GitLab Authentication Failed**
   ```bash
   # Check token permissions
   # Verify token hasn't expired
   # Test repository access
   curl -H "Authorization: Bearer $GITLAB_TOKEN" \
     "https://gitlab.com/api/v4/projects/your-project-id"
   ```

3. **Chart Pull Failed**
   ```bash
   # Check chart exists in Harbor
   helm search repo oci://harbor.your-domain.com/monitoring
   
   # Check robot account has pull permissions
   ```

## 7. Security Best Practices

### Harbor Security
- ✅ Use robot accounts instead of user accounts
- ✅ Limit permissions to specific projects
- ✅ Set appropriate token expiration
- ✅ Rotate tokens regularly
- ✅ Monitor access logs

### GitLab Security
- ✅ Use personal access tokens with minimal scope
- ✅ Set appropriate token expiration
- ✅ Use project-specific tokens when possible
- ✅ Rotate tokens regularly
- ✅ Monitor token usage

### General Security
- ✅ Store secrets in appropriate namespaces
- ✅ Use RBAC to control access to secrets
- ✅ Monitor secret access
- ✅ Use encrypted secrets when possible
- ✅ Regular security audits

## 8. Environment-Specific Configuration

### Dev Environment
```yaml
# fleet-dev.yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: monitoring-dev
  namespace: fleet-local
spec:
  repo: https://gitlab.com/your-username/your-repo.git
  branch: dev
  paths:
    - monitoring
  clientSecretName: gitlab-secret
  helmSecretName: harbor-secret
  targets:
    - clusterSelector:
        matchLabels:
          env: dev
```

### Prod Environment
```yaml
# fleet-prod.yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: monitoring-prod
  namespace: fleet-local
spec:
  repo: https://gitlab.com/your-username/your-repo.git
  branch: prod
  paths:
    - monitoring
  clientSecretName: gitlab-secret
  helmSecretName: harbor-secret
  targets:
    - clusterSelector:
        matchLabels:
          env: prod
```

## 9. Verification Commands

```bash
# Check all secrets
kubectl get secrets -n fleet-local

# Check GitRepo status
kubectl get gitrepo -A -o wide

# Check Bundle status
kubectl get bundle -A

# Check BundleDeployment status
kubectl get bundledeployment -A

# Check monitoring pods
kubectl get pods -n monitoring
``` 