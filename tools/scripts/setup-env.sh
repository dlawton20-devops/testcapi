#!/bin/bash

# Check if .env file exists
if [ ! -f "../openstack/credentials/.env" ]; then
    echo "Creating .env file from template..."
    cp ../openstack/credentials/template.env ../openstack/credentials/.env
    echo "Please edit ../openstack/credentials/.env with your actual values"
    exit 1
fi

# Source the environment variables
source ../openstack/credentials/.env

# Create OpenStack credentials secret
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: openstack-credentials
  namespace: default
type: Opaque
stringData:
  OS_AUTH_URL: ${OS_AUTH_URL}
  OS_USERNAME: ${OS_USERNAME}
  OS_PASSWORD: ${OS_PASSWORD}
  OS_PROJECT_NAME: ${OS_PROJECT_NAME}
  OS_PROJECT_DOMAIN_NAME: ${OS_PROJECT_DOMAIN_NAME}
  OS_USER_DOMAIN_NAME: ${OS_USER_DOMAIN_NAME}
  OS_REGION_NAME: ${OS_REGION_NAME}
EOF

# Create cluster configuration
cat <<EOF > ../capi/cluster-templates/${CLUSTER_NAME}-cluster.yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: ${CLUSTER_NAME}
spec:
  clusterNetwork:
    pods:
      cidrBlocks: ["192.168.0.0/16"]
    services:
      cidrBlocks: ["10.128.0.0/12"]
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: KubeadmControlPlane
    name: ${CLUSTER_NAME}-control-plane
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: OpenStackCluster
    name: ${CLUSTER_NAME}
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: OpenStackCluster
metadata:
  name: ${CLUSTER_NAME}
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

echo "Environment setup complete!"
echo "Please review the generated cluster configuration in ../capi/cluster-templates/${CLUSTER_NAME}-cluster.yaml" 