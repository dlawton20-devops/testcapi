#!/bin/bash

# Harbor Authentication Secret Creation Script
# Usage: ./create-harbor-secrets.sh <harbor-domain> <username> <password>

set -e

HARBOR_DOMAIN=${1:-"harbor.your-domain.com"}
HARBOR_USERNAME=${2:-"your-harbor-username"}
HARBOR_PASSWORD=${3:-"your-harbor-password"}

if [ -z "$HARBOR_PASSWORD" ]; then
    echo "Error: Harbor password is required"
    echo "Usage: $0 <harbor-domain> <username> <password>"
    exit 1
fi

echo "Creating Harbor authentication secrets..."
echo "Domain: $HARBOR_DOMAIN"
echo "Username: $HARBOR_USERNAME"

# Create base64 encoded docker config
DOCKER_CONFIG=$(cat <<EOF
{
  "auths": {
    "$HARBOR_DOMAIN": {
      "auth": "$(echo -n "$HARBOR_USERNAME:$HARBOR_PASSWORD" | base64)"
    }
  }
}
EOF
)

BASE64_CONFIG=$(echo "$DOCKER_CONFIG" | base64)

echo "Creating secrets..."

# Create secret for flux-system namespace (for HelmRepository)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: harbor-auth-secret
  namespace: flux-system
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: $BASE64_CONFIG
EOF

# Create secret for cattle-monitoring-system namespace
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: harbor-registry-secret
  namespace: cattle-monitoring-system
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: $BASE64_CONFIG
EOF

# Create secret for cattle-logging-system namespace
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: harbor-registry-secret
  namespace: cattle-logging-system
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: $BASE64_CONFIG
EOF

echo "✅ Harbor authentication secrets created successfully!"
echo ""
echo "Secrets created:"
echo "  - flux-system/harbor-auth-secret (for HelmRepository)"
echo "  - cattle-monitoring-system/harbor-registry-secret (for monitoring images)"
echo "  - cattle-logging-system/harbor-registry-secret (for logging images)"
echo ""
echo "To verify:"
echo "  kubectl get secrets -n flux-system harbor-auth-secret"
echo "  kubectl get secrets -n cattle-monitoring-system harbor-registry-secret"
echo "  kubectl get secrets -n cattle-logging-system harbor-registry-secret" 