# Secure Secret Management in GitOps

## ❌ What NOT to Store in Git

Never commit these to your repository:
- Passwords
- API Keys
- Private Keys
- Database Credentials
- OAuth Tokens
- Slack Webhooks

## ✅ Secure Approaches

### 1. External Secrets Operator (Recommended)

**Install External Secrets Operator:**
```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace
```

**Create SecretStore for AWS Secrets Manager:**
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

**Create ExternalSecret:**
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
```

### 2. SOPS with Age (Local Encryption)

**Install SOPS and Age:**
```bash
# macOS
brew install sops age

# Generate Age key
age-keygen -o key.txt
```

**Create .sops.yaml:**
```yaml
creation_rules:
  - path_regex: \.sops\.yaml$
    age: >-
      age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
```

**Encrypt secrets:**
```bash
# Create secret file
cat > monitoring-secrets.sops.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: monitoring-secrets
  namespace: cattle-monitoring-system
type: Opaque
data:
  grafana-admin-password: <base64-encoded-password>
  alertmanager-slack-webhook: <base64-encoded-webhook>
EOF

# Encrypt with SOPS
sops -e -i monitoring-secrets.sops.yaml
```

### 3. Kubernetes Secrets (Manual Creation)

**Create secrets manually (not in Git):**
```bash
# Create secret locally
kubectl create secret generic monitoring-secrets \
  --namespace=cattle-monitoring-system \
  --from-literal=grafana-admin-password="your-password" \
  --from-literal=alertmanager-slack-webhook="your-webhook" \
  --dry-run=client -o yaml > monitoring-secrets.yaml

# Apply manually (don't commit this file)
kubectl apply -f monitoring-secrets.yaml
```

### 4. HashiCorp Vault

**Install Vault:**
```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault --namespace vault --create-namespace
```

**Create Vault SecretStore:**
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: cattle-monitoring-system
spec:
  provider:
    vault:
      server: "http://vault.vault:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "external-secrets"
```

## 🔧 Integration with Fleet/Flux

### Fleet Bundle with External Secrets
```yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: Bundle
metadata:
  name: rancher-monitoring
spec:
  targets:
  - clusterSelector:
      matchLabels:
        env: production
    values:
      grafana:
        adminPassword: ${GRAFANA_ADMIN_PASSWORD}
  helm:
    chart: rancher-monitoring
    repo: https://releases.rancher.com/server-charts/stable
    version: 102.0.0+up40.1.2
  resources:
  - external-secret.yaml  # References external secret
```

### Flux HelmRelease with External Secrets
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: rancher-monitoring
spec:
  chart:
    spec:
      chart: rancher-monitoring
      version: 102.0.0+up40.1.2
      sourceRef:
        kind: HelmRepository
        name: rancher
  values:
    grafana:
      adminPassword: ${GRAFANA_ADMIN_PASSWORD}
```

## 🛡️ Security Best Practices

### 1. Repository Security
- **Private repositories** for production configs
- **Branch protection** rules
- **Required reviews** for production changes
- **Audit logging** for all changes

### 2. Access Control
- **RBAC** for Kubernetes resources
- **Service accounts** with minimal permissions
- **Network policies** to restrict access
- **Pod security standards**

### 3. Secret Rotation
- **Automated rotation** of secrets
- **Monitoring** for secret expiration
- **Backup** of secret management systems
- **Recovery procedures**

### 4. Monitoring and Alerting
- **Secret access monitoring**
- **Failed secret retrieval alerts**
- **Configuration drift detection**
- **Security event logging**

## 📋 Checklist for Secure GitOps

- [ ] No secrets committed to Git
- [ ] External secret management configured
- [ ] Repository is private
- [ ] Branch protection enabled
- [ ] RBAC configured
- [ ] Network policies applied
- [ ] Audit logging enabled
- [ ] Secret rotation automated
- [ ] Monitoring and alerting configured
- [ ] Recovery procedures documented 