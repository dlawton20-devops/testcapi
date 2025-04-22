#!/bin/bash

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "kubectl is required but not installed"
    exit 1
fi

# Create namespace for Turtles
kubectl create namespace turtles-system

# Install Turtles
kubectl apply -f https://github.com/rancher/turtles/releases/download/v0.1.0/turtles.yaml

# Install CAPO (Cluster API Provider for OpenStack)
kubectl apply -f https://github.com/kubernetes-sigs/cluster-api-provider-openstack/releases/download/v0.7.0/infrastructure-components.yaml

# Install Cluster API core components
kubectl apply -f https://github.com/kubernetes-sigs/cluster-api/releases/download/v1.5.0/cluster-api-components.yaml

# Wait for deployments to be ready
echo "Waiting for Turtles and CAPO to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/turtles-controller-manager -n turtles-system
kubectl wait --for=condition=available --timeout=300s deployment/capo-controller-manager -n capo-system

# Create OpenStack credentials secret
kubectl create secret generic openstack-credentials \
  --from-literal=OS_AUTH_URL=${OS_AUTH_URL} \
  --from-literal=OS_USERNAME=${OS_USERNAME} \
  --from-literal=OS_PASSWORD=${OS_PASSWORD} \
  --from-literal=OS_PROJECT_NAME=${OS_PROJECT_NAME} \
  --from-literal=OS_PROJECT_DOMAIN_NAME=${OS_PROJECT_DOMAIN_NAME} \
  --from-literal=OS_USER_DOMAIN_NAME=${OS_USER_DOMAIN_NAME} \
  --from-literal=OS_REGION_NAME=${OS_REGION_NAME} \
  -n turtles-system

# Create Turtles configuration
cat <<EOF | kubectl apply -f -
apiVersion: turtles.infrastructure.cluster.x-k8s.io/v1alpha1
kind: OpenStackClusterTemplate
metadata:
  name: openstack-cluster-template
  namespace: turtles-system
spec:
  template:
    spec:
      identityRef:
        kind: Secret
        name: openstack-credentials
      cloudName: openstack
      controlPlaneEndpoint:
        host: ""
        port: 6443
      network:
        id: ${OS_NETWORK_ID}
      subnet:
        id: ${OS_SUBNET_ID}
      floatingIPNetwork:
        id: ${OS_FLOATING_IP_NETWORK}
      externalNetwork:
        id: ${OS_EXTERNAL_NETWORK_ID}
EOF

echo "Turtles and CAPO installation complete!"
echo "You can now use the cluster template with Rancher CAPI" 