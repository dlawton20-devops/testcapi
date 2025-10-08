# Harbor Authentication Setup for Fleet

## Overview

When using private Harbor repositories with Fleet, you need to configure authentication. Fleet supports several methods for Harbor authentication.

## Method 1: Using GitRepo with Secret Reference

### Step 1: Create Harbor Credentials Secret

```bash
# Create a secret with Harbor credentials
kubectl create secret docker-registry harbor-secret \
  --docker-server=harbor.your-domain.com \
  --docker-username=your-username \
  --docker-password=your-password \
  --docker-email=your-email@domain.com \
  -n fleet-local
```

### Step 2: Update Fleet GitRepo to Reference Secret

```yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: monitoring-dev
  namespace: fleet-local
spec:
  repo: https://github.com/your-username/your-repo
  branch: dev
  paths:
  - monitoring
  helmSecretName: harbor-secret  # Reference the secret
  targets:
  - clusterSelector:
      matchLabels:
        env: dev
```

## Method 2: Using Fleet Bundle with Helm Secret

### Step 1: Create Harbor Secret in Target Cluster

```bash
# Create secret in the target cluster (not fleet-local)
kubectl create secret docker-registry harbor-secret \
  --docker-server=harbor.your-domain.com \
  --docker-username=your-username \
  --docker-password=your-password \
  --docker-email=your-email@domain.com \
  -n monitoring
```

### Step 2: Reference Secret in Fleet Bundle

```yaml
# monitoring/03-monitoring-stack/fleet.yaml
defaultNamespace: monitoring
targetNamespace: monitoring

helm:
  repo: oci://harbor.your-domain.com/project-name
  chart: my-custom-chart
  version: 1.0.0
  helmSecretName: harbor-secret  # Reference the secret

targets:
- clusterSelector:
    matchLabels:
      env: dev
```

## Method 3: Using Service Account with Harbor

### Step 1: Create Service Account

```yaml
# harbor-service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fleet-harbor-sa
  namespace: fleet-local
---
apiVersion: v1
kind: Secret
metadata:
  name: fleet-harbor-secret
  namespace: fleet-local
  annotations:
    kubernetes.io/service-account.name: fleet-harbor-sa
type: kubernetes.io/service-account-token
```

### Step 2: Apply Service Account

```bash
kubectl apply -f harbor-service-account.yaml
```

### Step 3: Configure Harbor to Trust Service Account

Configure Harbor to accept the service account token for authentication.

## Method 4: Using Harbor Robot Account (Recommended)

### Step 1: Create Harbor Robot Account

1. **Login to Harbor UI**
2. **Go to Administration → Robot Accounts**
3. **Create new robot account**
4. **Set permissions** for the project
5. **Copy the robot account credentials**

### Step 2: Create Secret with Robot Account

```bash
# Create secret with robot account credentials
kubectl create secret docker-registry harbor-robot-secret \
  --docker-server=harbor.your-domain.com \
  --docker-username=robot$your-project$your-robot-name \
  --docker-password=your-robot-token \
  --docker-email=robot@your-domain.com \
  -n fleet-local
```

### Step 3: Use in Fleet Configuration

```yaml
# fleet.yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: monitoring-dev
  namespace: fleet-local
spec:
  repo: https://github.com/your-username/your-repo
  branch: dev
  paths:
  - monitoring
  helmSecretName: harbor-robot-secret
  targets:
  - clusterSelector:
      matchLabels:
        env: dev
```

## Method 5: Using Harbor API Token

### Step 1: Generate Harbor API Token

```bash
# Get Harbor API token
curl -X POST "https://harbor.your-domain.com/api/v2.0/users/current/token" \
  -H "Content-Type: application/json" \
  -u "your-username:your-password" \
  -d '{"name":"fleet-token"}'
```

### Step 2: Create Secret with API Token

```bash
kubectl create secret docker-registry harbor-api-secret \
  --docker-server=harbor.your-domain.com \
  --docker-username=your-username \
  --docker-password=your-api-token \
  --docker-email=your-email@domain.com \
  -n fleet-local
```

## Example: Complete Harbor Setup

### 1. Harbor Repository Structure

```
harbor.your-domain.com/
└── monitoring/
    ├── prometheus-custom/
    │   └── 1.0.0/
    ├── grafana-dashboards/
    │   └── 2.0.0/
    └── alertmanager-rules/
        └── 1.5.0/
```

### 2. Fleet Bundle Configuration

```yaml
# monitoring/03-monitoring-stack/fleet.yaml
defaultNamespace: monitoring
targetNamespace: monitoring

helm:
  repo: oci://harbor.your-domain.com/monitoring
  chart: prometheus-custom
  version: 1.0.0
  helmSecretName: harbor-secret
  valuesFiles:
    - values.yaml
    - values-custom.yaml

targets:
- clusterSelector:
    matchLabels:
      env: dev
```

### 3. Custom Chart from Harbor

```yaml
# monitoring/custom-chart/fleet.yaml
defaultNamespace: monitoring
targetNamespace: monitoring

helm:
  repo: oci://harbor.your-domain.com/monitoring
  chart: grafana-dashboards
  version: 2.0.0
  helmSecretName: harbor-secret
  values:
    dashboards:
      - name: custom-dashboard
        url: https://grafana.com/api/dashboards/1860/revisions/22/download

targets:
- clusterSelector:
    matchLabels:
      env: dev
```

## Troubleshooting Harbor Authentication

### Check Secret Status

```bash
# Verify secret exists
kubectl get secret harbor-secret -n fleet-local

# Check secret details
kubectl describe secret harbor-secret -n fleet-local
```

### Test Harbor Connection

```bash
# Test Harbor login
docker login harbor.your-domain.com -u your-username -p your-password

# Test chart pull
helm pull oci://harbor.your-domain.com/monitoring/prometheus-custom --version 1.0.0
```

### Check Fleet Logs

```bash
# Check Fleet controller logs
kubectl logs -n fleet-system deployment/fleet-controller

# Check Fleet agent logs
kubectl logs -n cattle-fleet-system deployment/fleet-agent
```

### Common Issues

1. **Authentication Failed**
   ```bash
   # Check secret format
   kubectl get secret harbor-secret -n fleet-local -o yaml
   ```

2. **Chart Not Found**
   ```bash
   # Verify chart exists in Harbor
   helm search repo oci://harbor.your-domain.com/monitoring
   ```

3. **Permission Denied**
   ```bash
   # Check Harbor project permissions
   # Ensure robot account has proper access
   ```

## Security Best Practices

1. **Use Robot Accounts** instead of user accounts
2. **Limit Permissions** to specific projects
3. **Rotate Credentials** regularly
4. **Use Namespace-Specific Secrets** when possible
5. **Monitor Access Logs** in Harbor

## Example: Complete Setup Script

```bash
#!/bin/bash

# Harbor configuration
HARBOR_URL="harbor.your-domain.com"
HARBOR_USERNAME="your-username"
HARBOR_PASSWORD="your-password"
HARBOR_EMAIL="your-email@domain.com"

# Create Harbor secret
kubectl create secret docker-registry harbor-secret \
  --docker-server=$HARBOR_URL \
  --docker-username=$HARBOR_USERNAME \
  --docker-password=$HARBOR_PASSWORD \
  --docker-email=$HARBOR_EMAIL \
  -n fleet-local

# Apply Fleet configuration
kubectl apply -f fleet.yaml

# Verify setup
kubectl get secret harbor-secret -n fleet-local
kubectl get gitrepo -A
``` 