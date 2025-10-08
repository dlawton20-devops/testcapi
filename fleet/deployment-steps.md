# Deployment Steps for Harbor and GitLab Authentication

## Step 1: Generate the Secret Manifests

### Generate Harbor Secret
```bash
# Replace with your actual Harbor credentials
kubectl create secret docker-registry harbor-secret \
  --docker-server=harbor.your-domain.com \
  --docker-username=robot$project-name$fleet-robot \
  --docker-password=your-robot-token \
  --docker-email=robot@your-domain.com \
  -n fleet-local \
  --dry-run=client -o yaml > harbor-secret.yaml
```

### Generate GitLab Secret
```bash
# Replace with your actual GitLab credentials
kubectl create secret generic gitlab-secret \
  --from-literal=username=your-gitlab-username \
  --from-literal=password=your-gitlab-token \
  -n fleet-local \
  --dry-run=client -o yaml > gitlab-secret.yaml
```

## Step 2: Apply the Secrets

```bash
# Apply Harbor secret
kubectl apply -f harbor-secret.yaml

# Apply GitLab secret
kubectl apply -f gitlab-secret.yaml

# Verify secrets
kubectl get secrets -n fleet-local
```

## Step 3: Update Fleet Configuration

1. **Update `fleet-with-auth.yaml`** with your actual repository URL
2. **Update `monitoring-bundle-with-harbor.yaml`** with your Harbor repository URL

## Step 4: Apply Fleet Configuration

```bash
# Apply Fleet GitRepo with authentication
kubectl apply -f fleet-with-auth.yaml

# Verify deployment
kubectl get gitrepo -A
kubectl get bundle -A
```

## Step 5: Verify Authentication

```bash
# Check GitRepo status
kubectl describe gitrepo monitoring-dev -n fleet-local

# Check Bundle status
kubectl describe bundle monitoring-stack -n fleet-local

# Check Fleet logs
kubectl logs -n fleet-system deployment/fleet-controller
```

## Troubleshooting

### Check Secret Status
```bash
kubectl get secret harbor-secret -n fleet-local -o yaml
kubectl get secret gitlab-secret -n fleet-local -o yaml
```

### Test Harbor Connection
```bash
docker login harbor.your-domain.com -u robot$project-name$fleet-robot -p your-robot-token
```

### Test GitLab Connection
```bash
curl -H "Authorization: Bearer your-gitlab-token" \
  "https://gitlab.com/api/v4/user"
```

### Reset if Needed
```bash
kubectl delete gitrepo monitoring-dev -n fleet-local
kubectl delete secret harbor-secret -n fleet-local
kubectl delete secret gitlab-secret -n fleet-local
``` 