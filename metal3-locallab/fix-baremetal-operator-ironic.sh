#!/bin/bash
set -e

echo "🔧 Fixing BareMetal Operator Ironic Connection"
echo "==============================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if baremetal-operator-ironic ConfigMap exists
if ! kubectl get configmap baremetal-operator-ironic -n metal3-system &>/dev/null; then
    echo -e "${YELLOW}⚠️  baremetal-operator-ironic ConfigMap not found. Creating it...${NC}"
    kubectl create configmap baremetal-operator-ironic -n metal3-system
fi

# Get Ironic service details
IRONIC_SVC="metal3-metal3-ironic"
IRONIC_NAMESPACE="metal3-system"
IRONIC_SVC_FQDN="${IRONIC_SVC}.${IRONIC_NAMESPACE}.svc.cluster.local"

echo ""
echo "1. Updating baremetal-operator-ironic ConfigMap..."
echo "   Using service URL: ${IRONIC_SVC_FQDN}"

# Update the ConfigMap with service URL and insecure flag
kubectl patch configmap baremetal-operator-ironic -n metal3-system --type merge -p '{
  "data": {
    "IRONIC_ENDPOINT": "https://'${IRONIC_SVC_FQDN}':6385/v1/",
    "CACHEURL": "https://'${IRONIC_SVC_FQDN}':6185/images",
    "IRONIC_INSECURE": "true"
  }
}'

echo -e "${GREEN}✅ ConfigMap updated${NC}"

# Check if operator deployment has IRONIC_INSECURE env var
echo ""
echo "2. Checking operator deployment for IRONIC_INSECURE..."
DEPLOYMENT=$(kubectl get deployment -n metal3-system -l app.kubernetes.io/component=baremetal-operator -o name)

if kubectl get $DEPLOYMENT -n metal3-system -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="IRONIC_INSECURE")]}' &>/dev/null; then
    echo -e "${GREEN}✅ IRONIC_INSECURE already set in deployment${NC}"
else
    echo "Adding IRONIC_INSECURE to operator deployment..."
    kubectl patch $DEPLOYMENT -n metal3-system --type='json' -p='[{"op": "add", "path": "/spec/template/spec/containers/0/env/-", "value": {"name": "IRONIC_INSECURE", "value": "true"}}]'
    echo -e "${GREEN}✅ IRONIC_INSECURE added to deployment${NC}"
fi

# Restart operator
echo ""
echo "3. Restarting baremetal operator..."
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=baremetal-operator --wait=false
sleep 3

echo ""
echo -e "${GREEN}✅ Fix applied!${NC}"
echo ""
echo "Wait a moment, then check:"
echo "  kubectl get baremetalhost -n metal3-system"
echo ""
echo "Check logs:"
echo "  kubectl logs -n metal3-system -l app.kubernetes.io/component=baremetal-operator --tail=20 | grep -i ironic"
echo ""

