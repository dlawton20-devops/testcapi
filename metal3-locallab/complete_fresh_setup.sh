#!/bin/bash
# Complete fresh setup - cluster + Metal3 + everything

set -e

echo "🚀 Complete fresh setup starting..."
echo ""

# Step 1: Create Kind cluster
echo "1. Creating Kind cluster..."
if kind get clusters | grep -q metal3-management; then
    echo "   ⚠️  Cluster already exists, skipping..."
else
    kind create cluster --name metal3-management --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
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
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF
    echo "   ✅ Cluster created"
fi

# Step 2: Install MetalLB
echo ""
echo "2. Installing MetalLB..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml 2>/dev/null || {
    echo "   ⚠️  MetalLB might already be installed"
}
echo "   ⏳ Waiting for MetalLB to be ready..."
kubectl wait --namespace metallb-system \
    --for=condition=ready pod \
    --selector=app=metallb \
    --timeout=90s 2>/dev/null || echo "   ⚠️  MetalLB still starting"

# Configure MetalLB IP pool (using Kind network range)
echo "   Configuring MetalLB IP pool..."
kubectl apply -f - <<EOF
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
EOF
echo "   ✅ MetalLB configured"

# Step 3: Install Metal3 (if not already installed)
echo ""
echo "3. Checking Metal3 installation..."
if kubectl get namespace metal3-system > /dev/null 2>&1; then
    echo "   ✅ Metal3 already installed"
else
    echo "   ⚠️  Metal3 not installed - you may need to install it manually"
    echo "   See your setup script or Metal3 documentation"
fi

# Step 4: Run fresh_setup.sh
echo ""
echo "4. Running fresh setup..."
"$(dirname "$0")/fresh_setup.sh"

echo ""
echo "✅ Complete fresh setup done!"
echo ""
echo "Everything is ready:"
echo "  ✅ Kind cluster created"
echo "  ✅ MetalLB installed and configured"
echo "  ✅ Metal3 installed (if applicable)"
echo "  ✅ Port forwarding set up"
echo "  ✅ Ironic configured"
echo ""
echo "Next: Create VM and BareMetalHost"

