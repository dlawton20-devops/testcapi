# Installing Edge Image Builder via Helm Chart

## Prerequisites

### 1. Kubernetes Cluster

- **Running Kubernetes cluster** (RKE2, K3s, or standard Kubernetes)
- **kubectl** configured and accessible
- **Helm 3.x** installed

### 2. Access to SUSE Edge Registry

- **SUSE Customer Center credentials** (if required)
- **Network access** to `registry.suse.com`
- **Proxy configuration** (if behind corporate proxy)

### 3. Storage Requirements

- **Persistent storage** for:
  - Base images (SL-Micro.x86_64-6.1-Base-GM.raw - ~500MB-1GB)
  - Built images (output images - several GB each)
  - Build workspace (temporary files during build)
- **StorageClass** configured (or use local storage)

### 4. Resource Requirements

- **CPU**: Minimum 2 cores, recommended 4+ cores
- **Memory**: Minimum 4GB, recommended 8GB+
- **Disk space**: 20GB+ for base image and builds

### 5. Container Runtime

- **Podman** or **Docker/containerd**
- Must support running privileged containers (for image building)

### 6. Base Image

- **SL-Micro.x86_64-6.1-Base-GM.raw** downloaded
- Must be accessible to Edge Image Builder (via PVC, HTTP, or local path)

## Step 1: Configure Proxy Settings

### For Helm Installation

If you need proxy access to download charts and images:

```bash
# Set proxy environment variables
export HTTP_PROXY="http://proxy.example.com:8080"
export HTTPS_PROXY="http://proxy.example.com:8080"
export NO_PROXY="localhost,127.0.0.1,.svc,.svc.cluster.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"

# Or for authentication
export HTTP_PROXY="http://user:pass@proxy.example.com:8080"
export HTTPS_PROXY="http://user:pass@proxy.example.com:8080"
```

### For Kubernetes Pods

Create a ConfigMap for proxy settings:

```bash
kubectl create configmap proxy-config \
  --from-literal=HTTP_PROXY="http://proxy.example.com:8080" \
  --from-literal=HTTPS_PROXY="http://proxy.example.com:8080" \
  --from-literal=NO_PROXY="localhost,127.0.0.1,.svc,.svc.cluster.local" \
  -n edge-image-builder
```

## Step 2: Install Edge Image Builder with Proxy

### Basic Installation

```bash
# Add SUSE Edge Helm repository
helm repo add suse-edge oci://registry.suse.com/edge/charts
helm repo update

# Install Edge Image Builder
helm install edge-image-builder oci://registry.suse.com/edge/charts/edge-image-builder \
  --namespace edge-image-builder \
  --create-namespace
```

### Installation with Proxy Configuration

Create a `values.yaml` file for proxy settings:

```yaml
# Edge Image Builder values with proxy
global:
  # Proxy settings for pulling images
  httpProxy: "http://proxy.example.com:8080"
  httpsProxy: "http://proxy.example.com:8080"
  noProxy: "localhost,127.0.0.1,.svc,.svc.cluster.local,10.0.0.0/8"

# If Edge Image Builder chart supports proxy env vars
env:
  - name: HTTP_PROXY
    value: "http://proxy.example.com:8080"
  - name: HTTPS_PROXY
    value: "http://proxy.example.com:8080"
  - name: NO_PROXY
    value: "localhost,127.0.0.1,.svc,.svc.cluster.local"

# Storage configuration
persistence:
  enabled: true
  storageClass: "local-path"  # Or your StorageClass
  size: 50Gi
```

Install with values:

```bash
helm install edge-image-builder oci://registry.suse.com/edge/charts/edge-image-builder \
  --namespace edge-image-builder \
  --create-namespace \
  --values values.yaml
```

### Alternative: Patch After Installation

If proxy settings need to be added after installation:

```bash
# Create ConfigMap with proxy settings
kubectl create configmap proxy-config \
  --from-literal=HTTP_PROXY="http://proxy.example.com:8080" \
  --from-literal=HTTPS_PROXY="http://proxy.example.com:8080" \
  --from-literal=NO_PROXY="localhost,127.0.0.1,.svc,.svc.cluster.local" \
  -n edge-image-builder

# Patch deployment to use proxy
kubectl patch deployment edge-image-builder -n edge-image-builder --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/envFrom",
    "value": [
      {
        "configMapRef": {
          "name": "proxy-config"
        }
      }
    ]
  }
]'
```

## Step 3: Configure Container Runtime Proxy

### For containerd

If using containerd, configure proxy in `/etc/containerd/config.toml`:

```toml
[plugins."io.containerd.grpc.v1.cri".registry]
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry.suse.com"]
      endpoint = ["https://registry.suse.com"]

[plugins."io.containerd.grpc.v1.cri".registry.configs."registry.suse.com".tls]
  insecure_skip_verify = false

# Proxy configuration
[plugins."io.containerd.grpc.v1.cri".proxy_plugins]
  [plugins."io.containerd.grpc.v1.cri".proxy_plugins."http"]
    endpoint = "http://proxy.example.com:8080"
  [plugins."io.containerd.grpc.v1.cri".proxy_plugins."https"]
    endpoint = "http://proxy.example.com:8080"
```

### For Docker

Configure Docker proxy in `/etc/systemd/system/docker.service.d/http-proxy.conf`:

```ini
[Service]
Environment="HTTP_PROXY=http://proxy.example.com:8080"
Environment="HTTPS_PROXY=http://proxy.example.com:8080"
Environment="NO_PROXY=localhost,127.0.0.1,.svc,.svc.cluster.local"
```

Then restart Docker:
```bash
sudo systemctl daemon-reload
sudo systemctl restart docker
```

## Step 4: Verify Installation

### Check Pods

```bash
# Check Edge Image Builder pods
kubectl get pods -n edge-image-builder

# Should show pods in Running state
```

### Check Proxy is Working

```bash
# Test from within a pod
kubectl run -it --rm test-proxy --image=curlimages/curl --restart=Never -n edge-image-builder -- \
  curl -I https://registry.suse.com

# Or test from Edge Image Builder pod
kubectl exec -it -n edge-image-builder deployment/edge-image-builder -- \
  curl -I https://registry.suse.com
```

### Check Logs

```bash
# Check Edge Image Builder logs
kubectl logs -n edge-image-builder -l app=edge-image-builder

# Look for proxy-related errors or connection issues
```

## Step 5: Configure Storage

### Create PersistentVolumeClaim

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: eib-storage
  namespace: edge-image-builder
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path  # Or your StorageClass
  resources:
    requests:
      storage: 50Gi
```

Apply:

```bash
kubectl apply -f pvc.yaml
```

### Update Edge Image Builder to Use PVC

```bash
# Patch deployment to use PVC
kubectl patch deployment edge-image-builder -n edge-image-builder --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/volumeMounts",
    "value": [
      {
        "name": "storage",
        "mountPath": "/workspace"
      }
    ]
  },
  {
    "op": "add",
    "path": "/spec/template/spec/volumes",
    "value": [
      {
        "name": "storage",
        "persistentVolumeClaim": {
          "claimName": "eib-storage"
        }
      }
    ]
  }
]'
```

## Complete Installation Script with Proxy

```bash
#!/bin/bash
set -e

echo "🔧 Installing Edge Image Builder with Proxy Support"
echo "==================================================="

# Proxy configuration
HTTP_PROXY="${HTTP_PROXY:-http://proxy.example.com:8080}"
HTTPS_PROXY="${HTTPS_PROXY:-http://proxy.example.com:8080}"
NO_PROXY="${NO_PROXY:-localhost,127.0.0.1,.svc,.svc.cluster.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16}"

# Set proxy for current session
export HTTP_PROXY
export HTTPS_PROXY
export NO_PROXY

echo "Proxy Configuration:"
echo "  HTTP_PROXY: $HTTP_PROXY"
echo "  HTTPS_PROXY: $HTTPS_PROXY"
echo "  NO_PROXY: $NO_PROXY"

# Create namespace
kubectl create namespace edge-image-builder --dry-run=client -o yaml | kubectl apply -f -

# Create proxy ConfigMap
kubectl create configmap proxy-config \
  --from-literal=HTTP_PROXY="$HTTP_PROXY" \
  --from-literal=HTTPS_PROXY="$HTTPS_PROXY" \
  --from-literal=NO_PROXY="$NO_PROXY" \
  -n edge-image-builder \
  --dry-run=client -o yaml | kubectl apply -f -

# Create values file
cat > /tmp/eib-values.yaml <<EOF
env:
  - name: HTTP_PROXY
    value: "${HTTP_PROXY}"
  - name: HTTPS_PROXY
    value: "${HTTPS_PROXY}"
  - name: NO_PROXY
    value: "${NO_PROXY}"

persistence:
  enabled: true
  storageClass: "local-path"
  size: 50Gi
EOF

# Add Helm repository
echo "Adding SUSE Edge Helm repository..."
helm repo add suse-edge oci://registry.suse.com/edge/charts
helm repo update

# Install Edge Image Builder
echo "Installing Edge Image Builder..."
helm install edge-image-builder oci://registry.suse.com/edge/charts/edge-image-builder \
  --namespace edge-image-builder \
  --create-namespace \
  --values /tmp/eib-values.yaml \
  --wait \
  --timeout 10m

# Wait for pods to be ready
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n edge-image-builder --timeout=600s

echo "✅ Edge Image Builder installed!"
echo ""
echo "Check status:"
kubectl get pods -n edge-image-builder
```

## Proxy Configuration for Image Building

### During Build Process

When building images, the build process may need to:
- Download packages from SUSE repositories
- Pull container images
- Access external resources

Configure proxy in build configuration:

```yaml
apiVersion: v1
kind: ElementalImage
metadata:
  name: metal3-image
spec:
  # ... other config ...
  
  # Proxy settings for package installation
  repositories:
    - name: suse-repo
      uri: "https://download.suse.com/..."
      proxy: "http://proxy.example.com:8080"  # If supported
  
  # Or via environment
  env:
    - name: HTTP_PROXY
      value: "http://proxy.example.com:8080"
    - name: HTTPS_PROXY
      value: "http://proxy.example.com:8080"
```

### For Package Installation

If building images that install packages, ensure zypper uses proxy:

```yaml
files:
  - path: /etc/zypp/zypp.conf
    contents: |
      # Proxy configuration for zypper
      proxy = http://proxy.example.com:8080
```

## Troubleshooting Proxy Issues

### Issue: Cannot Pull Images

```bash
# Check if proxy is set in pod
kubectl exec -n edge-image-builder deployment/edge-image-builder -- env | grep -i proxy

# Test connectivity
kubectl exec -n edge-image-builder deployment/edge-image-builder -- \
  curl -v --proxy "$HTTP_PROXY" https://registry.suse.com
```

### Issue: Build Fails to Download Packages

```bash
# Check build logs
kubectl logs -n edge-image-builder job/build-image -f

# Verify proxy is accessible
kubectl run -it --rm test-proxy --image=curlimages/curl --restart=Never -- \
  curl -v --proxy "$HTTP_PROXY" https://download.suse.com
```

### Issue: Certificate Errors with Proxy

If using HTTPS proxy with self-signed certificates:

```bash
# Add certificate to trust store (if needed)
# Or configure to skip verification (not recommended for production)
```

## Verification Checklist

After installation:

- [ ] Edge Image Builder pods are Running
- [ ] Proxy environment variables are set in pods
- [ ] Can pull images from registry.suse.com
- [ ] Storage is configured and accessible
- [ ] Build jobs can access external repositories
- [ ] No proxy-related errors in logs

## Key Points

1. **Proxy must be configured** at multiple levels:
   - Helm/container runtime (for pulling charts/images)
   - Kubernetes pods (for build process)
   - Package managers (for installing packages during build)

2. **NO_PROXY should include**:
   - Localhost
   - Kubernetes service DNS (.svc, .svc.cluster.local)
   - Internal network ranges

3. **Storage is critical** - Ensure sufficient space for base images and builds

4. **Container runtime proxy** - May need separate configuration for containerd/Docker

## References

- [SUSE Edge Image Builder Documentation](https://documentation.suse.com/suse-edge/3.3/html/edge/edge-image-builder.html)
- [Helm Proxy Configuration](https://helm.sh/docs/using_helm/#using-helm-behind-a-proxy)
- [Kubernetes Proxy Configuration](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/#set-up-kubectl-to-use-a-proxy)

