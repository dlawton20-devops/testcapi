#!/bin/bash
set -e

echo "🚀 Setting up Metal3 with SUSE Edge Helm Chart"
echo "================================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check prerequisites
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}❌ $1 is not installed${NC}"
        exit 1
    else
        echo -e "${GREEN}✅ $1 is installed${NC}"
    fi
}

echo ""
echo "Checking prerequisites..."
check_command kubectl
check_command helm
check_command kind
check_command virsh
check_command qemu-system-x86_64

# Check if Docker is running
if ! docker ps &>/dev/null; then
    echo -e "${YELLOW}⚠️  Docker is not running. Please start Docker Desktop or Rancher Desktop first.${NC}"
    echo "   Then run this script again."
    exit 1
fi
echo -e "${GREEN}✅ Docker is running${NC}"

# Clean up old Metal3 cluster if it exists
echo ""
echo "Cleaning up old Metal3 cluster if it exists..."
if kind get clusters 2>/dev/null | grep -q "kind-metal3-management"; then
    echo "Deleting old kind-metal3-management cluster..."
    kind delete cluster --name kind-metal3-management 2>/dev/null || true
fi

# Create new kind cluster for Metal3
echo ""
echo "Creating new kind cluster for Metal3..."
cat <<EOF | kind create cluster --name metal3-management --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  podSubnet: "192.168.0.0/16"
  serviceSubnet: "10.96.0.0/12"
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 8080
    protocol: TCP
  - containerPort: 443
    hostPort: 8443
    protocol: TCP
  - containerPort: 30000
    hostPort: 30000
    protocol: TCP
EOF

# Set kubectl context
kubectl config use-context kind-metal3-management

# Wait for cluster to be ready
echo "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Install MetalLB for Ironic VIP using SUSE Edge OCI registry
echo ""
echo "Installing MetalLB for Ironic VIP from SUSE Edge registry..."
helm install metallb oci://registry.suse.com/edge/charts/metallb \
    --namespace metallb-system \
    --create-namespace \
    --wait \
    --timeout 5m || {
    echo -e "${YELLOW}⚠️  MetalLB install may have timed out. Checking status...${NC}"
    kubectl get pods -n metallb-system
}

# Wait for MetalLB to be ready
echo "Waiting for MetalLB to be ready..."
kubectl wait --namespace metallb-system \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/name=metallb \
    --timeout=300s || true

# Configure MetalLB IP pool (using kind network range)
echo "Configuring MetalLB IP pool..."
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 172.18.255.200-172.18.255.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
EOF

echo -e "${GREEN}✅ MetalLB installed and configured${NC}"

# Install cert-manager (required by Metal3)
echo ""
echo "Installing cert-manager (required for Metal3)..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml

# Wait for cert-manager to be ready
echo "Waiting for cert-manager to be ready..."
kubectl wait --namespace cert-manager \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/instance=cert-manager \
    --timeout=300s || {
    echo -e "${YELLOW}⚠️  Waiting for cert-manager pods...${NC}"
    kubectl get pods -n cert-manager
}

echo -e "${GREEN}✅ cert-manager installed${NC}"

# Note: SUSE Edge Metal3 chart may require authentication
# We'll use operator-based installation as fallback
echo ""
echo "Preparing Metal3 installation..."
echo "Note: SUSE Edge charts may require SUSE Customer Center access"

# Create namespace for Metal3
echo ""
echo "Creating metal3-system namespace..."
kubectl create namespace metal3-system --dry-run=client -o yaml | kubectl apply -f -

# Install Metal3 using SUSE Edge OCI registry
echo ""
echo "Installing Metal3 from SUSE Edge registry..."
echo "Note: For troubleshooting, see: https://documentation.suse.com/suse-edge/3.3/html/edge/troubleshooting-directed-network-provisioning.html"

# Set static Ironic IP (from MetalLB pool)
STATIC_IRONIC_IP="172.18.255.200"

# Install Metal3 from SUSE Edge OCI registry
helm install metal3 oci://registry.suse.com/edge/charts/metal3 \
    --namespace metal3-system \
    --create-namespace \
    --wait \
    --timeout 10m \
    --set global.ironicIP="$STATIC_IRONIC_IP" \
    --set global.ironicKernelParams="console=ttyS0" \
    --set ironic.service.type=LoadBalancer \
    --set ironic.service.loadBalancerIP="$STATIC_IRONIC_IP" \
    || {
        echo -e "${YELLOW}⚠️  Helm install may have timed out. Checking status...${NC}"
        kubectl get pods -n metal3-system
    }

# Wait for Metal3 pods to be ready
echo ""
echo "Waiting for Metal3 pods to be ready..."
kubectl wait --for=condition=Ready pods --all -n metal3-system --timeout=600s || {
    echo -e "${YELLOW}⚠️  Some pods may not be ready yet. Current status:${NC}"
    kubectl get pods -n metal3-system
}

# Show Metal3 status
echo ""
echo -e "${GREEN}✅ Metal3 installation complete!${NC}"
echo ""
echo "Metal3 pods status:"
kubectl get pods -n metal3-system

echo ""
echo "Next steps:"
echo "1. Set up libvirt bridge network: ./setup-libvirt-bridge.sh"
echo "2. Set up sushy-tools for BMC emulation: ./setup-sushy-tools.sh"
echo "3. Create a libvirt VM with Ubuntu Focal image and BareMetalHost: ./create-baremetal-host.sh"
echo ""
echo "Troubleshooting:"
echo "  - Check Metal3 logs: kubectl logs -n metal3-system -l app.kubernetes.io/component=baremetal-operator"
echo "  - Check Ironic logs: kubectl logs -n metal3-system -l app.kubernetes.io/component=ironic"
echo "  - See: https://documentation.suse.com/suse-edge/3.3/html/edge/troubleshooting-directed-network-provisioning.html"

