#!/bin/bash

# Install Rancher Operator Script
# Part of the Rancher CAPI Bootstrap environment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[RANCHER]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[RANCHER]${NC} $1"
}

print_error() {
    echo -e "${RED}[RANCHER]${NC} $1"
}

# Check if values file is provided
if [ $# -eq 0 ]; then
    print_error "Usage: $0 <values-file>"
    exit 1
fi

VALUES_FILE="$1"

# Extract Rancher configuration
RANCHER_NAMESPACE=$(yq eval '.rancher.operator.namespace' "$VALUES_FILE")
RANCHER_VERSION=$(yq eval '.rancher.operator.version' "$VALUES_FILE")

print_status "Installing Rancher Operator version: $RANCHER_VERSION"
print_status "Namespace: $RANCHER_NAMESPACE"

# Check if cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to cluster. Please ensure kubectl is configured."
    exit 1
fi

# Create namespace
print_status "Creating namespace '$RANCHER_NAMESPACE'..."
kubectl create namespace "$RANCHER_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Create custom Rancher operator for managing Rancher resources
print_status "Creating Rancher operator..."

# Create CRDs for Rancher resources
cat << 'EOF' | kubectl apply -f -
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: rancherusers.rancher.io
spec:
  group: rancher.io
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              username:
                type: string
              password:
                type: string
              displayName:
                type: string
              email:
                type: string
              enabled:
                type: boolean
              rancherApiUrl:
                type: string
              rancherToken:
                type: string
              clusterId:
                type: string
              createLmaProject:
                type: boolean
              lmaProjectName:
                type: string
          status:
            type: object
            properties:
              userId:
                type: string
              projectId:
                type: string
              conditions:
                type: array
                items:
                  type: object
                  properties:
                    type:
                      type: string
                    status:
                      type: string
                    lastTransitionTime:
                      type: string
                    reason:
                      type: string
                    message:
                      type: string
    subresources:
      status: {}
  scope: Namespaced
  names:
    plural: rancherusers
    singular: rancheruser
    kind: RancherUser
    shortNames:
    - ru
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: rancherprojects.rancher.io
spec:
  group: rancher.io
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              name:
                type: string
              clusterId:
                type: string
              description:
                type: string
              rancherApiUrl:
                type: string
              rancherToken:
                type: string
              namespaces:
                type: array
                items:
                  type: object
                  properties:
                    name:
                      type: string
                    labels:
                      type: object
          status:
            type: object
            properties:
              projectId:
                type: string
              namespaceIds:
                type: object
              conditions:
                type: array
                items:
                  type: object
                  properties:
                    type:
                      type: string
                    status:
                      type: string
                    lastTransitionTime:
                      type: string
                    reason:
                      type: string
                    message:
                      type: string
    subresources:
      status: {}
  scope: Namespaced
  names:
    plural: rancherprojects
    singular: rancherproject
    kind: RancherProject
    shortNames:
    - rp
EOF

# Create Rancher operator deployment
cat << EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rancher-operator
  namespace: $RANCHER_NAMESPACE
  labels:
    app.kubernetes.io/name: rancher-operator
    app.kubernetes.io/version: "$RANCHER_VERSION"
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: rancher-operator
  template:
    metadata:
      labels:
        app.kubernetes.io/name: rancher-operator
        app.kubernetes.io/version: "$RANCHER_VERSION"
    spec:
      serviceAccountName: rancher-operator
      containers:
      - name: rancher-operator
        image: rancher/rancher-operator:latest
        imagePullPolicy: Always
        env:
        - name: RANCHER_API_URL
          value: "https://rancher.example.com"
        - name: RANCHER_TOKEN
          valueFrom:
            secretKeyRef:
              name: rancher-credentials
              key: token
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 20
        readinessProbe:
          httpGet:
            path: /readyz
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: rancher-operator
  namespace: $RANCHER_NAMESPACE
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: rancher-operator
rules:
- apiGroups: ["rancher.io"]
  resources: ["rancherusers", "rancherprojects"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["rancher.io"]
  resources: ["rancherusers/status", "rancherprojects/status"]
  verbs: ["get", "update", "patch"]
- apiGroups: [""]
  resources: ["secrets", "configmaps"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: rancher-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: rancher-operator
subjects:
- kind: ServiceAccount
  name: rancher-operator
  namespace: $RANCHER_NAMESPACE
EOF

# Wait for Rancher operator to be ready
print_status "Waiting for Rancher operator to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=rancher-operator -n "$RANCHER_NAMESPACE" --timeout=300s

# Verify installation
print_status "Verifying Rancher operator installation..."

# Check if CRDs are installed
if kubectl get crd rancherusers.rancher.io &> /dev/null; then
    print_success "RancherUser CRD is installed"
else
    print_error "RancherUser CRD is not installed"
    exit 1
fi

if kubectl get crd rancherprojects.rancher.io &> /dev/null; then
    print_success "RancherProject CRD is installed"
else
    print_error "RancherProject CRD is not installed"
    exit 1
fi

# Check if operator pod is running
if kubectl get pods -n "$RANCHER_NAMESPACE" | grep -q "rancher-operator.*Running"; then
    print_success "Rancher operator is running"
else
    print_error "Rancher operator is not running"
    kubectl get pods -n "$RANCHER_NAMESPACE"
    exit 1
fi

# Display Rancher operator status
print_status "Rancher operator installation status:"
kubectl get pods -n "$RANCHER_NAMESPACE"
kubectl get crd | grep rancher

print_success "Rancher operator installation completed successfully!"

# Display useful commands
print_status "Useful commands:"
print_status "  kubectl get rancherusers -A                    # View Rancher users"
print_status "  kubectl get rancherprojects -A                 # View Rancher projects"
print_status "  kubectl describe rancheruser <name> -n <ns>   # View Rancher user details"
print_status "  kubectl logs -n $RANCHER_NAMESPACE -l app.kubernetes.io/name=rancher-operator  # View logs"
