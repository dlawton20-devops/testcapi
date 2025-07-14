# Step-by-Step Implementation: Fleet + Kustomize for Rancher Monitoring

## Prerequisites

- ✅ Kubernetes cluster with Rancher installed
- ✅ kubectl configured and connected to your cluster
- ✅ Git repository for your configurations
- ✅ Fleet already installed (comes with Rancher)

## Step 1: Create Your Git Repository Structure

```bash
# Create your GitOps repository
mkdir rancher-gitops
cd rancher-gitops

# Initialize Git repository
git init
git remote add origin https://github.com/YOUR-ORG/YOUR-GITOPS-REPO
```

## Step 2: Create the Base Configuration

```bash
# Create base directory structure
mkdir -p fleet/bundles/monitoring/base
mkdir -p fleet/bundles/monitoring/overlays/{dev,staging,prod}
mkdir -p examples
mkdir -p scripts
mkdir -p docs
```

### Step 2.1: Create Base Fleet Bundle

```bash
# Create fleet/bundles/monitoring/base/fleet.yaml
cat > fleet/bundles/monitoring/base/fleet.yaml << 'EOF'
apiVersion: fleet.cattle.io/v1alpha1
kind: Bundle
metadata:
  name: rancher-monitoring
  namespace: fleet-local
spec:
  targets:
  - clusterSelector:
      matchLabels:
        env: ${ENVIRONMENT}
    clusterGroup: ${ENVIRONMENT}-clusters
    values:
      global:
        cattle:
          systemDefaultRegistry: ""
        rke2Enabled: true
      prometheus:
        prometheusSpec:
          evaluationInterval: 30s
          scrapeInterval: 30s
          retention: ${PROMETHEUS_RETENTION}
          storageSpec:
            volumeClaimTemplate:
              spec:
                accessModes: ["ReadWriteOnce"]
                resources:
                  requests:
                    storage: ${PROMETHEUS_STORAGE_SIZE}
                storageClassName: ${STORAGE_CLASS}
          resources:
            requests:
              memory: ${PROMETHEUS_MEMORY_REQUEST}
              cpu: ${PROMETHEUS_CPU_REQUEST}
            limits:
              memory: ${PROMETHEUS_MEMORY_LIMIT}
              cpu: ${PROMETHEUS_CPU_LIMIT}
          securityContext:
            runAsNonRoot: true
            runAsUser: 65534
            fsGroup: 65534
      grafana:
        enabled: true
        persistence:
          enabled: true
          size: ${GRAFANA_PERSISTENCE_SIZE}
          storageClassName: ${STORAGE_CLASS}
        resources:
          requests:
            memory: ${GRAFANA_MEMORY_REQUEST}
            cpu: ${GRAFANA_CPU_REQUEST}
          limits:
            memory: ${GRAFANA_MEMORY_LIMIT}
            cpu: ${GRAFANA_CPU_LIMIT}
        securityContext:
          runAsNonRoot: true
          runAsUser: 472
          fsGroup: 472
        adminPassword: ${GRAFANA_ADMIN_PASSWORD}
        dashboardProviders:
          dashboardproviders.yaml:
            apiVersion: 1
            providers:
            - name: 'default'
              orgId: 1
              folder: ''
              type: file
              disableDeletion: false
              updateIntervalSeconds: 10
              allowUiUpdates: true
              options:
                path: /var/lib/grafana/dashboards/default
      alertmanager:
        alertmanagerSpec:
          retention: ${ALERTMANAGER_RETENTION}
          storage:
            volumeClaimTemplate:
              spec:
                accessModes: ["ReadWriteOnce"]
                resources:
                  requests:
                    storage: ${ALERTMANAGER_STORAGE_SIZE}
                storageClassName: ${STORAGE_CLASS}
          resources:
            requests:
              memory: ${ALERTMANAGER_MEMORY_REQUEST}
              cpu: ${ALERTMANAGER_CPU_REQUEST}
            limits:
              memory: ${ALERTMANAGER_MEMORY_LIMIT}
              cpu: ${ALERTMANAGER_CPU_LIMIT}
          securityContext:
            runAsNonRoot: true
            runAsUser: 65534
            fsGroup: 65534
      nodeExporter:
        enabled: true
        resources:
          requests:
            memory: 64Mi
            cpu: 25m
          limits:
            memory: 128Mi
            cpu: 50m
      kubeStateMetrics:
        enabled: true
        resources:
          requests:
            memory: 64Mi
            cpu: 25m
          limits:
            memory: 128Mi
            cpu: 50m
      additionalScrapeConfigs:
        - job_name: 'rancher'
          static_configs:
            - targets: ['rancher-webhook.cattle-system.svc:8443']
          metrics_path: /metrics
          scheme: https
          tls_config:
            insecure_skip_verify: true
      networkPolicy:
        enabled: true
        ingressRules:
          - from:
            - namespaceSelector:
                matchLabels:
                  name: cattle-monitoring-system
            ports:
            - port: 9090
              protocol: TCP
            - port: 9091
              protocol: TCP
            - port: 3000
              protocol: TCP
            - port: 9093
              protocol: TCP
        egressRules:
          - to:
            - namespaceSelector: {}
            ports:
            - port: 53
              protocol: UDP
            - port: 53
              protocol: TCP
            - port: 443
              protocol: TCP
            - port: 80
              protocol: TCP
  helm:
    chart: rancher-monitoring
    repo: https://releases.rancher.com/server-charts/stable
    version: 102.0.0+up40.1.2
    valuesFiles:
    - values.yaml
  resources:
  - helmrepository.yaml
EOF
```

### Step 2.2: Create Base Values File

```bash
# Create fleet/bundles/monitoring/base/values.yaml
cat > fleet/bundles/monitoring/base/values.yaml << 'EOF'
# Base values for Rancher Monitoring
# Variables will be substituted by Kustomize overlays

global:
  cattle:
    systemDefaultRegistry: ""
  rke2Enabled: true

# Prometheus configuration
prometheus:
  prometheusSpec:
    evaluationInterval: 30s
    scrapeInterval: 30s
    retention: ${PROMETHEUS_RETENTION}
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: ${PROMETHEUS_STORAGE_SIZE}
          storageClassName: ${STORAGE_CLASS}
    resources:
      requests:
        memory: ${PROMETHEUS_MEMORY_REQUEST}
        cpu: ${PROMETHEUS_CPU_REQUEST}
      limits:
        memory: ${PROMETHEUS_MEMORY_LIMIT}
        cpu: ${PROMETHEUS_CPU_LIMIT}
    securityContext:
      runAsNonRoot: true
      runAsUser: 65534
      fsGroup: 65534

# Grafana configuration
grafana:
  enabled: true
  persistence:
    enabled: true
    size: ${GRAFANA_PERSISTENCE_SIZE}
    storageClassName: ${STORAGE_CLASS}
  resources:
    requests:
      memory: ${GRAFANA_MEMORY_REQUEST}
      cpu: ${GRAFANA_CPU_REQUEST}
    limits:
      memory: ${GRAFANA_MEMORY_LIMIT}
      cpu: ${GRAFANA_CPU_LIMIT}
  securityContext:
    runAsNonRoot: true
    runAsUser: 472
    fsGroup: 472
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
      - name: 'default'
        orgId: 1
        folder: ''
        type: file
        disableDeletion: false
        updateIntervalSeconds: 10
        allowUiUpdates: true
        options:
          path: /var/lib/grafana/dashboards/default

# AlertManager configuration
alertmanager:
  alertmanagerSpec:
    retention: ${ALERTMANAGER_RETENTION}
    storage:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: ${ALERTMANAGER_STORAGE_SIZE}
          storageClassName: ${STORAGE_CLASS}
    resources:
      requests:
        memory: ${ALERTMANAGER_MEMORY_REQUEST}
        cpu: ${ALERTMANAGER_CPU_REQUEST}
      limits:
        memory: ${ALERTMANAGER_MEMORY_LIMIT}
        cpu: ${ALERTMANAGER_CPU_LIMIT}
    securityContext:
      runAsNonRoot: true
      runAsUser: 65534
      fsGroup: 65534

# Node Exporter
nodeExporter:
  enabled: true
  resources:
    requests:
      memory: 64Mi
      cpu: 25m
    limits:
      memory: 128Mi
      cpu: 50m

# Kube State Metrics
kubeStateMetrics:
  enabled: true
  resources:
    requests:
      memory: 64Mi
      cpu: 25m
    limits:
      memory: 128Mi
      cpu: 50m

# Service Monitor for Rancher
additionalScrapeConfigs:
  - job_name: 'rancher'
    static_configs:
      - targets: ['rancher-webhook.cattle-system.svc:8443']
    metrics_path: /metrics
    scheme: https
    tls_config:
      insecure_skip_verify: true

# Network Policies
networkPolicy:
  enabled: true
  ingressRules:
    - from:
      - namespaceSelector:
          matchLabels:
            name: cattle-monitoring-system
      ports:
      - port: 9090
        protocol: TCP
      - port: 9091
        protocol: TCP
      - port: 3000
        protocol: TCP
      - port: 9093
        protocol: TCP
  egressRules:
    - to:
      - namespaceSelector: {}
      ports:
      - port: 53
        protocol: UDP
      - port: 53
        protocol: TCP
      - port: 443
        protocol: TCP
      - port: 80
        protocol: TCP
EOF
```

### Step 2.3: Create Base Namespace

```bash
# Create fleet/bundles/monitoring/base/namespace.yaml
cat > fleet/bundles/monitoring/base/namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: cattle-monitoring-system
  labels:
    name: cattle-monitoring-system
    app.kubernetes.io/name: monitoring
    app.kubernetes.io/part-of: rancher
    environment: ${ENVIRONMENT}
EOF
```

### Step 2.4: Create Helm Repository

```bash
# Create fleet/bundles/monitoring/base/helmrepository.yaml
cat > fleet/bundles/monitoring/base/helmrepository.yaml << 'EOF'
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: HelmRepository
metadata:
  name: rancher
  namespace: cattle-monitoring-system
spec:
  interval: 1h
  url: https://releases.rancher.com/server-charts/stable
  type: oci
EOF
```

### Step 2.5: Create Base Kustomization

```bash
# Create fleet/bundles/monitoring/base/kustomization.yaml
cat > fleet/bundles/monitoring/base/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
metadata:
  name: monitoring-base
resources:
  - fleet.yaml
  - values.yaml
  - helmrepository.yaml
  - namespace.yaml
EOF
```

## Step 3: Create Environment Overlays

### Step 3.1: Development Environment

```bash
# Create fleet/bundles/monitoring/overlays/dev/kustomization.yaml
cat > fleet/bundles/monitoring/overlays/dev/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
metadata:
  name: monitoring-dev
resources:
  - ../../base
configMapGenerator:
  - name: monitoring-config
    literals:
      - ENVIRONMENT=development
      - PROMETHEUS_RETENTION=1d
      - PROMETHEUS_STORAGE_SIZE=10Gi
      - PROMETHEUS_MEMORY_REQUEST=512Mi
      - PROMETHEUS_MEMORY_LIMIT=1Gi
      - PROMETHEUS_CPU_REQUEST=125m
      - PROMETHEUS_CPU_LIMIT=250m
      - GRAFANA_PERSISTENCE_SIZE=1Gi
      - GRAFANA_MEMORY_REQUEST=128Mi
      - GRAFANA_MEMORY_LIMIT=256Mi
      - GRAFANA_CPU_REQUEST=62m
      - GRAFANA_CPU_LIMIT=125m
      - ALERTMANAGER_RETENTION=24h
      - ALERTMANAGER_STORAGE_SIZE=1Gi
      - ALERTMANAGER_MEMORY_REQUEST=64Mi
      - ALERTMANAGER_MEMORY_LIMIT=128Mi
      - ALERTMANAGER_CPU_REQUEST=25m
      - ALERTMANAGER_CPU_LIMIT=50m
      - STORAGE_CLASS=standard
secretGenerator:
  - name: monitoring-secrets
    envs:
      - ../../../examples/env.dev
EOF
```

### Step 3.2: Staging Environment

```bash
# Create fleet/bundles/monitoring/overlays/staging/kustomization.yaml
cat > fleet/bundles/monitoring/overlays/staging/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
metadata:
  name: monitoring-staging
resources:
  - ../../base
configMapGenerator:
  - name: monitoring-config
    literals:
      - ENVIRONMENT=staging
      - PROMETHEUS_RETENTION=7d
      - PROMETHEUS_STORAGE_SIZE=50Gi
      - PROMETHEUS_MEMORY_REQUEST=1Gi
      - PROMETHEUS_MEMORY_LIMIT=2Gi
      - PROMETHEUS_CPU_REQUEST=250m
      - PROMETHEUS_CPU_LIMIT=500m
      - GRAFANA_PERSISTENCE_SIZE=5Gi
      - GRAFANA_MEMORY_REQUEST=256Mi
      - GRAFANA_MEMORY_LIMIT=512Mi
      - GRAFANA_CPU_REQUEST=125m
      - GRAFANA_CPU_LIMIT=250m
      - ALERTMANAGER_RETENTION=48h
      - ALERTMANAGER_STORAGE_SIZE=5Gi
      - ALERTMANAGER_MEMORY_REQUEST=128Mi
      - ALERTMANAGER_MEMORY_LIMIT=256Mi
      - ALERTMANAGER_CPU_REQUEST=50m
      - ALERTMANAGER_CPU_LIMIT=100m
      - STORAGE_CLASS=standard
secretGenerator:
  - name: monitoring-secrets
    envs:
      - ../../../examples/env.staging
EOF
```

### Step 3.3: Production Environment

```bash
# Create fleet/bundles/monitoring/overlays/prod/kustomization.yaml
cat > fleet/bundles/monitoring/overlays/prod/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
metadata:
  name: monitoring-prod
resources:
  - ../../base
configMapGenerator:
  - name: monitoring-config
    literals:
      - ENVIRONMENT=production
      - PROMETHEUS_RETENTION=30d
      - PROMETHEUS_STORAGE_SIZE=100Gi
      - PROMETHEUS_MEMORY_REQUEST=2Gi
      - PROMETHEUS_MEMORY_LIMIT=4Gi
      - PROMETHEUS_CPU_REQUEST=500m
      - PROMETHEUS_CPU_LIMIT=1000m
      - GRAFANA_PERSISTENCE_SIZE=10Gi
      - GRAFANA_MEMORY_REQUEST=512Mi
      - GRAFANA_MEMORY_LIMIT=1Gi
      - GRAFANA_CPU_REQUEST=250m
      - GRAFANA_CPU_LIMIT=500m
      - ALERTMANAGER_RETENTION=120h
      - ALERTMANAGER_STORAGE_SIZE=10Gi
      - ALERTMANAGER_MEMORY_REQUEST=256Mi
      - ALERTMANAGER_MEMORY_LIMIT=512Mi
      - ALERTMANAGER_CPU_REQUEST=100m
      - ALERTMANAGER_CPU_LIMIT=200m
      - STORAGE_CLASS=fast-ssd
secretGenerator:
  - name: monitoring-secrets
    envs:
      - ../../../examples/env.prod
EOF
```

## Step 4: Create Environment Files

### Step 4.1: Development Environment

```bash
# Create examples/env.dev
cat > examples/env.dev << 'EOF'
# Development Environment Variables
ENVIRONMENT=development
PROMETHEUS_RETENTION=1d
PROMETHEUS_STORAGE_SIZE=10Gi
GRAFANA_PERSISTENCE_SIZE=1Gi
STORAGE_CLASS=standard
ELASTICSEARCH_REPLICAS=1
KIBANA_REPLICAS=1

# Replace these with your actual values
GRAFANA_ADMIN_PASSWORD=your-dev-password-here
EXTERNAL_LOGGING_ENDPOINT=https://logs.dev.example.com
EXTERNAL_LOGGING_API_KEY=your-dev-api-key-here

# Resource limits (adjust based on your cluster)
PROMETHEUS_MEMORY_REQUEST=512Mi
PROMETHEUS_MEMORY_LIMIT=1Gi
PROMETHEUS_CPU_REQUEST=125m
PROMETHEUS_CPU_LIMIT=250m
GRAFANA_MEMORY_REQUEST=128Mi
GRAFANA_MEMORY_LIMIT=256Mi
GRAFANA_CPU_REQUEST=62m
GRAFANA_CPU_LIMIT=125m
ALERTMANAGER_RETENTION=24h
ALERTMANAGER_STORAGE_SIZE=1Gi
ALERTMANAGER_MEMORY_REQUEST=64Mi
ALERTMANAGER_MEMORY_LIMIT=128Mi
ALERTMANAGER_CPU_REQUEST=25m
ALERTMANAGER_CPU_LIMIT=50m
EOF
```

### Step 4.2: Staging Environment

```bash
# Create examples/env.staging
cat > examples/env.staging << 'EOF'
# Staging Environment Variables
ENVIRONMENT=staging
PROMETHEUS_RETENTION=7d
PROMETHEUS_STORAGE_SIZE=50Gi
GRAFANA_PERSISTENCE_SIZE=5Gi
STORAGE_CLASS=standard
ELASTICSEARCH_REPLICAS=2
KIBANA_REPLICAS=1

# Replace these with your actual values
GRAFANA_ADMIN_PASSWORD=your-staging-password-here
EXTERNAL_LOGGING_ENDPOINT=https://logs.staging.example.com
EXTERNAL_LOGGING_API_KEY=your-staging-api-key-here

# Resource limits (adjust based on your cluster)
PROMETHEUS_MEMORY_REQUEST=1Gi
PROMETHEUS_MEMORY_LIMIT=2Gi
PROMETHEUS_CPU_REQUEST=250m
PROMETHEUS_CPU_LIMIT=500m
GRAFANA_MEMORY_REQUEST=256Mi
GRAFANA_MEMORY_LIMIT=512Mi
GRAFANA_CPU_REQUEST=125m
GRAFANA_CPU_LIMIT=250m
ALERTMANAGER_RETENTION=48h
ALERTMANAGER_STORAGE_SIZE=5Gi
ALERTMANAGER_MEMORY_REQUEST=128Mi
ALERTMANAGER_MEMORY_LIMIT=256Mi
ALERTMANAGER_CPU_REQUEST=50m
ALERTMANAGER_CPU_LIMIT=100m
EOF
```

### Step 4.3: Production Environment

```bash
# Create examples/env.prod
cat > examples/env.prod << 'EOF'
# Production Environment Variables
ENVIRONMENT=production
PROMETHEUS_RETENTION=30d
PROMETHEUS_STORAGE_SIZE=100Gi
GRAFANA_PERSISTENCE_SIZE=10Gi
STORAGE_CLASS=fast-ssd
ELASTICSEARCH_REPLICAS=3
KIBANA_REPLICAS=2

# Replace these with your actual values
GRAFANA_ADMIN_PASSWORD=your-secure-password-here
EXTERNAL_LOGGING_ENDPOINT=https://logs.prod.example.com
EXTERNAL_LOGGING_API_KEY=your-api-key-here

# Resource limits (adjust based on your cluster)
PROMETHEUS_MEMORY_REQUEST=2Gi
PROMETHEUS_MEMORY_LIMIT=4Gi
PROMETHEUS_CPU_REQUEST=500m
PROMETHEUS_CPU_LIMIT=1000m
GRAFANA_MEMORY_REQUEST=512Mi
GRAFANA_MEMORY_LIMIT=1Gi
GRAFANA_CPU_REQUEST=250m
GRAFANA_CPU_LIMIT=500m
ALERTMANAGER_RETENTION=120h
ALERTMANAGER_STORAGE_SIZE=10Gi
ALERTMANAGER_MEMORY_REQUEST=256Mi
ALERTMANAGER_MEMORY_LIMIT=512Mi
ALERTMANAGER_CPU_REQUEST=100m
ALERTMANAGER_CPU_LIMIT=200m
EOF
```

## Step 5: Create Deployment Script

```bash
# Create scripts/deploy.sh
cat > scripts/deploy.sh << 'EOF'
#!/bin/bash

# Fleet + Kustomize Deployment Script
# Usage: ./scripts/deploy.sh [environment]
# Environments: dev, staging, prod

set -e

ENVIRONMENT=${1:-staging}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🚀 Deploying Rancher Monitoring via Fleet + Kustomize"
echo "Environment: $ENVIRONMENT"
echo ""

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    echo "❌ Error: Environment must be dev, staging, or prod"
    exit 1
fi

# Check prerequisites
if ! command -v kubectl &> /dev/null; then
    echo "❌ Error: kubectl is not installed"
    exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Error: Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "✅ Prerequisites check passed"
echo ""

# Step 1: Create namespaces
echo "📁 Creating namespaces..."
kubectl create namespace fleet-local --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace cattle-monitoring-system --dry-run=client -o yaml | kubectl apply -f -

# Step 2: Create secrets (if environment file exists)
echo "🔐 Creating secrets..."
if [ -f "$ROOT_DIR/examples/env.$ENVIRONMENT" ]; then
    echo "Using environment file: examples/env.$ENVIRONMENT"
    kubectl create secret generic monitoring-secrets \
        --namespace=cattle-monitoring-system \
        --from-env-file="$ROOT_DIR/examples/env.$ENVIRONMENT" \
        --dry-run=client -o yaml | kubectl apply -f -
else
    echo "⚠️  Warning: Environment file examples/env.$ENVIRONMENT not found"
    echo "Creating default secret (you should update this with real values)"
    kubectl create secret generic monitoring-secrets \
        --namespace=cattle-monitoring-system \
        --from-literal=grafana-admin-password="admin" \
        --from-literal=GRAFANA_ADMIN_PASSWORD="admin" \
        --dry-run=client -o yaml | kubectl apply -f -
fi

# Step 3: Apply Kustomize overlay
echo "🔧 Applying Kustomize overlay for $ENVIRONMENT..."
cd "$ROOT_DIR/fleet/bundles/monitoring/overlays/$ENVIRONMENT"

# Check if overlay exists
if [ ! -f "kustomization.yaml" ]; then
    echo "❌ Error: Overlay for environment $ENVIRONMENT not found"
    echo "Available overlays:"
    ls -la "$ROOT_DIR/fleet/bundles/monitoring/overlays/"
    exit 1
fi

echo "Applying overlay from: $(pwd)"
kubectl apply -k .

# Step 4: Create Fleet GitRepo
echo "📦 Creating Fleet GitRepo..."
kubectl apply -f - <<EOF
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: rancher-monitoring-$ENVIRONMENT
  namespace: fleet-local
spec:
  branch: main
  repo: https://github.com/YOUR-ORG/YOUR-GITOPS-REPO
  paths:
  - fleet/bundles/monitoring/overlays/$ENVIRONMENT
  refreshInterval: 60s
  targetsNamespace: cattle-monitoring-system
EOF

# Step 5: Wait for deployment
echo "⏳ Waiting for deployment to complete..."
echo "This may take a few minutes..."

# Wait for GitRepo to be ready
echo "Waiting for GitRepo to be ready..."
kubectl wait --for=condition=Ready gitrepo/rancher-monitoring-$ENVIRONMENT -n fleet-local --timeout=300s || echo "GitRepo not ready yet, continuing..."

# Wait for Bundle to be created
echo "Waiting for Bundle to be created..."
sleep 30

# Check status
echo ""
echo "📊 Deployment Status:"
echo ""

echo "Fleet GitRepo:"
kubectl get gitrepo -n fleet-local -o wide

echo ""
echo "Fleet Bundles:"
kubectl get bundle -n fleet-local -o wide

echo ""
echo "Monitoring Pods:"
kubectl get pods -n cattle-monitoring-system

echo ""
echo "Helm Releases:"
kubectl get helmrelease -n cattle-monitoring-system 2>/dev/null || echo "No HelmReleases found yet"

echo ""
echo "🎉 Deployment initiated!"
echo ""
echo "📈 Next Steps:"
echo "1. Monitor deployment: kubectl get pods -n cattle-monitoring-system -w"
echo "2. Check Fleet status: kubectl get gitrepo,bundle -n fleet-local"
echo "3. Access Grafana: kubectl port-forward svc/rancher-monitoring-grafana 3000:80 -n cattle-monitoring-system"
echo "4. Access Prometheus: kubectl port-forward svc/rancher-monitoring-prometheus 9090:9090 -n cattle-monitoring-system"
echo ""
echo "🔧 Troubleshooting:"
echo "- Check Fleet logs: kubectl logs -n fleet-system -l app=fleet-controller"
echo "- Check bundle status: kubectl describe bundle rancher-monitoring -n fleet-local"
echo "- Check GitRepo status: kubectl describe gitrepo rancher-monitoring-$ENVIRONMENT -n fleet-local"
EOF

# Make script executable
chmod +x scripts/deploy.sh
```

## Step 6: Create .gitignore

```bash
# Create .gitignore
cat > .gitignore << 'EOF'
# Environment files with secrets (create these locally)
examples/env.*
!examples/env.example

# Secrets and sensitive data
*.key
*.pem
*.crt
*.p12
*.pfx

# SOPS encrypted files (if using SOPS)
*.sops.yaml

# Kubernetes secrets
*-secrets.yaml
*-secret.yaml

# Local configuration
.env
.env.local
.env.*.local

# IDE files
.vscode/
.idea/
*.swp
*.swo

# OS files
.DS_Store
Thumbs.db

# Logs
*.log

# Temporary files
*.tmp
*.temp
EOF
```

## Step 7: Create Example Environment File

```bash
# Create examples/env.example
cat > examples/env.example << 'EOF'
# Example Environment Variables
# Copy this file to env.dev, env.staging, or env.prod and fill in your values
# DO NOT commit the actual env files with real secrets!

ENVIRONMENT=staging
PROMETHEUS_RETENTION=7d
PROMETHEUS_STORAGE_SIZE=50Gi
GRAFANA_PERSISTENCE_SIZE=5Gi
STORAGE_CLASS=standard
ELASTICSEARCH_REPLICAS=2
KIBANA_REPLICAS=1

# Replace these with your actual values
GRAFANA_ADMIN_PASSWORD=your-secure-password-here
EXTERNAL_LOGGING_ENDPOINT=https://logs.example.com
EXTERNAL_LOGGING_API_KEY=your-api-key-here

# Resource limits (adjust based on your cluster)
PROMETHEUS_MEMORY_REQUEST=1Gi
PROMETHEUS_MEMORY_LIMIT=2Gi
PROMETHEUS_CPU_REQUEST=250m
PROMETHEUS_CPU_LIMIT=500m
GRAFANA_MEMORY_REQUEST=256Mi
GRAFANA_MEMORY_LIMIT=512Mi
GRAFANA_CPU_REQUEST=125m
GRAFANA_CPU_LIMIT=250m
ALERTMANAGER_RETENTION=48h
ALERTMANAGER_STORAGE_SIZE=5Gi
ALERTMANAGER_MEMORY_REQUEST=128Mi
ALERTMANAGER_MEMORY_LIMIT=256Mi
ALERTMANAGER_CPU_REQUEST=50m
ALERTMANAGER_CPU_LIMIT=100m
EOF
```

## Step 8: Commit and Push to Git

```bash
# Add all files
git add .

# Commit
git commit -m "Initial Fleet + Kustomize setup for Rancher monitoring"

# Push to remote repository
git push -u origin main
```

## Step 9: Deploy to Your Cluster

### Step 9.1: Update Repository URL

Edit the deployment script to use your actual repository URL:

```bash
# Edit scripts/deploy.sh and replace:
# repo: https://github.com/YOUR-ORG/YOUR-GITOPS-REPO
# with your actual repository URL
```

### Step 9.2: Create Environment Files

```bash
# Copy example and create your environment files
cp examples/env.example examples/env.dev
cp examples/env.example examples/env.staging
cp examples/env.example examples/env.prod

# Edit each file with your actual values
# DO NOT commit these files to Git!
```

### Step 9.3: Deploy

```bash
# Deploy to staging (default)
./scripts/deploy.sh

# Deploy to production
./scripts/deploy.sh prod

# Deploy to development
./scripts/deploy.sh dev
```

## Step 10: Verify Deployment

```bash
# Check Fleet status
kubectl get gitrepo,bundle -n fleet-local

# Check monitoring pods
kubectl get pods -n cattle-monitoring-system

# Check Helm releases
kubectl get helmrelease -n cattle-monitoring-system

# Access Grafana
kubectl port-forward svc/rancher-monitoring-grafana 3000:80 -n cattle-monitoring-system

# Access Prometheus
kubectl port-forward svc/rancher-monitoring-prometheus 9090:9090 -n cattle-monitoring-system
```

## Step 11: Update Configuration

To update your configuration:

1. **Edit the overlay files** in `fleet/bundles/monitoring/overlays/{env}/kustomization.yaml`
2. **Edit environment files** in `examples/env.{env}`
3. **Commit and push** to Git
4. **Fleet automatically** picks up the changes and redeploys

## Troubleshooting

### Common Issues:

1. **Kustomize processing fails**: Check your overlay configuration
2. **Fleet doesn't deploy**: Check GitRepo status and logs
3. **Pods not starting**: Check resource limits and storage classes
4. **Secrets not found**: Ensure environment files exist and are properly formatted

### Debug Commands:

```bash
# Check Kustomize output
kubectl kustomize fleet/bundles/monitoring/overlays/prod/

# Check Fleet logs
kubectl logs -n fleet-system -l app=fleet-controller

# Check bundle status
kubectl describe bundle rancher-monitoring -n fleet-local

# Check GitRepo status
kubectl describe gitrepo rancher-monitoring-prod -n fleet-local
```

## Summary

You now have a complete Fleet + Kustomize setup for Rancher monitoring with:

- ✅ **Base configuration** with variable placeholders
- ✅ **Environment-specific overlays** for dev/staging/prod
- ✅ **Secure secret management** (not in Git)
- ✅ **Automated deployment** via Fleet
- ✅ **GitOps workflow** (changes in Git trigger deployments)
- ✅ **Easy configuration updates** via overlays

The key workflow is:
1. **Edit overlays** for environment-specific changes
2. **Commit to Git** to trigger deployment
3. **Fleet automatically** deploys with your custom values 