# Variable Management in GitOps

This document outlines various strategies for managing variables and configuration in GitOps deployments for Rancher monitoring and logging.

## 1. Kustomize Overlays

### Overview
Kustomize overlays provide environment-specific configurations while maintaining a base configuration.

### Structure
```
apps/
├── monitoring/
│   ├── base/
│   │   ├── kustomization.yaml
│   │   ├── helmrelease.yaml
│   │   └── values.yaml
│   ├── overlays/
│   │   ├── dev/
│   │   │   ├── kustomization.yaml
│   │   │   └── values-patch.yaml
│   │   ├── staging/
│   │   │   ├── kustomization.yaml
│   │   │   └── values-patch.yaml
│   │   └── prod/
│   │       ├── kustomization.yaml
│   │       └── values-patch.yaml
```

### Example: Environment-Specific Values

**Base kustomization.yaml:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmrelease.yaml
  - namespace.yaml
```

**Production overlay kustomization.yaml:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
patches:
  - target:
      kind: HelmRelease
      name: rancher-monitoring
    patch: |-
      - op: replace
        path: /spec/values/prometheus/prometheusSpec/retention
        value: 30d
      - op: replace
        path: /spec/values/grafana/persistence/size
        value: 10Gi
      - op: replace
        path: /spec/values/prometheus/prometheusSpec/storageSpec/volumeClaimTemplate/spec/storageClassName
        value: fast-ssd
configMapGenerator:
  - name: monitoring-config
    literals:
      - environment=production
      - prometheus-retention=30d
      - storage-class=fast-ssd
```

## 2. External Secrets Operator

### Overview
External Secrets Operator integrates with external secret management systems like AWS Secrets Manager, HashiCorp Vault, or Azure Key Vault.

### Example: AWS Secrets Manager Integration

**ExternalSecret:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: monitoring-secrets
  namespace: cattle-monitoring-system
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: monitoring-secrets
    type: Opaque
  data:
    - secretKey: grafana-admin-password
      remoteRef:
        key: monitoring/grafana/admin-password
    - secretKey: alertmanager-slack-webhook
      remoteRef:
        key: monitoring/alertmanager/slack-webhook
    - secretKey: elasticsearch-password
      remoteRef:
        key: logging/elasticsearch/password
```

**SecretStore:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: cattle-monitoring-system
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-west-2
      auth:
        serviceAccount:
          name: external-secrets-sa
```

## 3. ConfigMap and Secret References

### Overview
Use ConfigMaps and Secrets to store configuration values and reference them in Helm charts.

### Example: Centralized Configuration

**ConfigMap for monitoring:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: monitoring-config
  namespace: cattle-monitoring-system
data:
  prometheus-retention: "7d"
  grafana-persistence-size: "5Gi"
  storage-class: "standard"
  environment: "staging"
  alertmanager-config: |
    global:
      slack_api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
    route:
      group_by: ['alertname']
      group_wait: 10s
      group_interval: 10s
      repeat_interval: 1h
      receiver: 'slack-notifications'
    receivers:
    - name: 'slack-notifications'
      slack_configs:
      - channel: '#alerts'
        send_resolved: true
```

**Secret for sensitive data:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: monitoring-secrets
  namespace: cattle-monitoring-system
type: Opaque
data:
  grafana-admin-password: <base64-encoded-password>
  elasticsearch-password: <base64-encoded-password>
  alertmanager-slack-webhook: <base64-encoded-webhook-url>
```

## 4. Helm Values with Variable Substitution

### Overview
Use environment variables and templating to inject values into Helm charts.

### Example: Environment Variable Substitution

**HelmRelease with variable substitution:**
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: rancher-monitoring
  namespace: cattle-monitoring-system
spec:
  interval: 5m
  chart:
    spec:
      chart: rancher-monitoring
      version: 102.0.0+up40.1.2
      sourceRef:
        kind: HelmRepository
        name: rancher
        namespace: flux-system
  values:
    global:
      cattle:
        systemDefaultRegistry: ""
      rke2Enabled: true
    
    prometheus:
      prometheusSpec:
        retention: ${PROMETHEUS_RETENTION}
        storageSpec:
          volumeClaimTemplate:
            spec:
              resources:
                requests:
                  storage: ${PROMETHEUS_STORAGE_SIZE}
              storageClassName: ${STORAGE_CLASS}
    
    grafana:
      persistence:
        size: ${GRAFANA_PERSISTENCE_SIZE}
        storageClassName: ${STORAGE_CLASS}
      adminPassword: ${GRAFANA_ADMIN_PASSWORD}
```

**Kustomization with variable injection:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmrelease.yaml
configMapGenerator:
  - name: monitoring-config
    literals:
      - PROMETHEUS_RETENTION=7d
      - PROMETHEUS_STORAGE_SIZE=10Gi
      - GRAFANA_PERSISTENCE_SIZE=5Gi
      - STORAGE_CLASS=standard
secretGenerator:
  - name: monitoring-secrets
    envs:
      - .env.monitoring
```

## 5. SOPS for Encrypted Secrets

### Overview
SOPS (Secrets OPerationS) allows you to encrypt secrets in Git while maintaining GitOps principles.

### Example: SOPS Encrypted Secret

**Encrypted secret file (.sops.yaml):**
```yaml
creation_rules:
  - path_regex: \.sops\.yaml$
    age: >-
      age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

**Encrypted secret:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: monitoring-secrets
  namespace: cattle-monitoring-system
type: Opaque
sops:
  kms: []
  gcp_kms: []
  azure_kv: []
  hc_vault: []
  age:
    - recipient: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
      enc: |
        -----BEGIN AGE ENCRYPTED FILE-----
        YWdlLWVuY3J5cHRpb24ub3JnL3YxCi0+IFgyNTUxOSBKV0tKb0tQY0tQY0tQY0tQ
        Y0tQY0tQY0tQY0tQY0tQY0tQY0tQY0tQY0tQY0tQY0tQY0tQY0tQY0tQY0tQY0tQ
        Y0tQY0tQY0tQY0tQY0tQY0tQY0tQY0tQY0tQY0tQY0tQY0tQY0tQY0tQY0tQY0tQ
        -----END AGE ENCRYPTED FILE-----
data:
  grafana-admin-password: <encrypted-password>
  elasticsearch-password: <encrypted-password>
```

## 6. ArgoCD ApplicationSet with Values

### Overview
ArgoCD ApplicationSet allows you to generate multiple applications with different values.

### Example: Multi-Environment Deployment

**ApplicationSet:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: monitoring-appset
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - env: dev
            prometheusRetention: 1d
            grafanaPersistenceSize: 1Gi
            storageClass: standard
            replicas: 1
          - env: staging
            prometheusRetention: 7d
            grafanaPersistenceSize: 5Gi
            storageClass: standard
            replicas: 2
          - env: prod
            prometheusRetention: 30d
            grafanaPersistenceSize: 10Gi
            storageClass: fast-ssd
            replicas: 3
  template:
    metadata:
      name: 'monitoring-{{env}}'
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: https://github.com/your-org/gitops
        targetRevision: HEAD
        path: apps/monitoring
        helm:
          valueFiles:
            - values.yaml
          values: |
            environment: {{env}}
            prometheus:
              prometheusSpec:
                retention: {{prometheusRetention}}
                storageSpec:
                  volumeClaimTemplate:
                    spec:
                      storageClassName: {{storageClass}}
            grafana:
              persistence:
                size: {{grafanaPersistenceSize}}
                storageClassName: {{storageClass}}
            elasticsearch:
              replicas: {{replicas}}
      destination:
        server: https://kubernetes.default.svc
        namespace: cattle-monitoring-system
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

## 7. Best Practices

### Security
1. **Never commit secrets to Git** - Use external secret management
2. **Use RBAC** - Restrict access to sensitive configurations
3. **Rotate secrets regularly** - Implement automated secret rotation
4. **Audit access** - Monitor who accesses sensitive data

### Maintainability
1. **Use consistent naming** - Follow naming conventions
2. **Document configurations** - Keep configuration docs updated
3. **Version control** - Tag and version your configurations
4. **Test changes** - Validate configurations before production

### Scalability
1. **Use templates** - Create reusable configuration templates
2. **Environment parity** - Keep environments as similar as possible
3. **Configuration drift** - Monitor and prevent configuration drift
4. **Rollback capability** - Ensure quick rollback procedures

### Monitoring
1. **Configuration validation** - Validate configurations before deployment
2. **Health checks** - Monitor application health after configuration changes
3. **Alerting** - Set up alerts for configuration issues
4. **Metrics** - Track configuration deployment metrics 