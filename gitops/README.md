# Rancher Monitoring & Logging GitOps

This repository demonstrates how to deploy Rancher monitoring and logging using GitOps principles with either Rancher Fleet or Flux.

## Overview

This setup provides:
- **Rancher Fleet** deployment examples
- **Flux** deployment examples  
- **Variable management** strategies for GitOps
- **Multi-environment** support (dev, staging, prod)
- **Secrets management** best practices

## Directory Structure

```
├── fleet/                    # Rancher Fleet examples
│   ├── bundles/
│   │   ├── monitoring/
│   │   └── logging/
│   └── gitrepos/
├── flux/                     # Flux examples
│   ├── clusters/
│   │   ├── dev/
│   │   ├── staging/
│   │   └── prod/
│   └── apps/
│       ├── monitoring/
│       └── logging/
├── charts/                   # Custom Helm charts
│   ├── monitoring-override/
│   └── logging-override/
└── docs/                     # Documentation
```

## Quick Start

### Option 1: Rancher Fleet
```bash
# Apply Fleet GitRepo
kubectl apply -f fleet/gitrepos/monitoring-gitrepo.yaml
kubectl apply -f fleet/gitrepos/logging-gitrepo.yaml
```

### Option 2: Flux
```bash
# Bootstrap Flux
flux bootstrap github --owner=your-username --repository=gitops --path=flux/clusters/prod

# Apply monitoring and logging
kubectl apply -k flux/apps/monitoring/
kubectl apply -k flux/apps/logging/
```

## Variable Management Strategies

### 1. Kustomize Overlays
- Environment-specific configurations
- Base + overlay pattern
- Easy to maintain and review

### 2. Helm Values with External Secrets
- Sensitive data in external secret stores
- Non-sensitive configs in Git
- Secure production deployments

### 3. ConfigMap/Secret References
- Centralized configuration management
- GitOps-friendly secret rotation
- Environment-specific values

## Security Considerations

- **Secrets**: Never commit secrets to Git
- **RBAC**: Proper role-based access control
- **Network Policies**: Restrict monitoring traffic
- **TLS**: Enable mTLS for all components
- **Audit Logging**: Monitor GitOps operations

## Monitoring Stack

- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards
- **AlertManager**: Alert routing and notification
- **Node Exporter**: Node-level metrics
- **Kube State Metrics**: Kubernetes state metrics

## Logging Stack

- **Fluent Bit**: Log collection and forwarding
- **Fluentd**: Log aggregation and processing
- **Elasticsearch**: Log storage and search
- **Kibana**: Log visualization and analysis

## Best Practices

1. **Immutable Tags**: Use specific versions, not latest
2. **Resource Limits**: Set appropriate CPU/memory limits
3. **Health Checks**: Implement proper readiness/liveness probes
4. **Backup Strategy**: Regular backups of monitoring data
5. **Documentation**: Keep deployment docs updated
6. **Testing**: Test in staging before production
7. **Rollback Plan**: Have clear rollback procedures 