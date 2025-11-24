#!/bin/bash
set -e

echo "🔧 Fixing Ironic Connectivity for BareMetal Operator"
echo "====================================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "1. Checking current Ironic configuration..."

# Get Ironic service details
IRONIC_SVC=$(kubectl get svc metal3-metal3-ironic -n metal3-system -o jsonpath='{.metadata.name}')
IRONIC_CLUSTER_IP=$(kubectl get svc metal3-metal3-ironic -n metal3-system -o jsonpath='{.spec.clusterIP}')
IRONIC_PORT=$(kubectl get svc metal3-metal3-ironic -n metal3-system -o jsonpath='{.spec.ports[?(@.port==6185)].port}')
if [ -z "$IRONIC_PORT" ]; then
    IRONIC_PORT=$(kubectl get svc metal3-metal3-ironic -n metal3-system -o jsonpath='{.spec.ports[0].port}')
fi

echo "  Service: $IRONIC_SVC"
echo "  ClusterIP: $IRONIC_CLUSTER_IP"
echo "  Port: $IRONIC_PORT"

# Get current Ironic URL
CURRENT_URL=$(kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_EXTERNAL_HTTP_URL}' 2>/dev/null || echo "")
echo "  Current External URL: $CURRENT_URL"

# The baremetal operator needs to reach Ironic from within the cluster
# It should use the ClusterIP, not the LoadBalancer IP
IRONIC_INTERNAL_URL="https://${IRONIC_CLUSTER_IP}:${IRONIC_PORT}"

echo ""
echo "2. The issue: BareMetal operator can't reach Ironic at LoadBalancer IP"
echo "   Solution: Configure Ironic to use ClusterIP for internal access"
echo ""

# Check if there's an IRONIC_INTERNAL_HTTP_URL setting
INTERNAL_URL=$(kubectl get configmap ironic -n metal3-system -o jsonpath='{.data.IRONIC_INTERNAL_HTTP_URL}' 2>/dev/null || echo "")

if [ -z "$INTERNAL_URL" ] || [ "$INTERNAL_URL" != "$IRONIC_INTERNAL_URL" ]; then
    echo "3. Setting IRONIC_INTERNAL_HTTP_URL to ClusterIP..."
    kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_INTERNAL_HTTP_URL\":\"${IRONIC_INTERNAL_URL}\"}}"
    echo -e "${GREEN}✅ IRONIC_INTERNAL_HTTP_URL set to ${IRONIC_INTERNAL_URL}${NC}"
else
    echo -e "${GREEN}✅ IRONIC_INTERNAL_HTTP_URL is already correct${NC}"
fi

# Also check the provisioner configuration
echo ""
echo "4. Checking baremetal operator configuration..."

# The baremetal operator should use the internal URL
# Let's check if there's a way to configure it
BMO_CONFIG=$(kubectl get deployment baremetal-operator-controller-manager -n metal3-system -o jsonpath='{.spec.template.spec.containers[0].env}' 2>/dev/null || echo "")

echo "5. Restarting Ironic pod to apply changes..."
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic --wait=false
sleep 3

echo ""
echo "6. Restarting baremetal operator to retry connection..."
kubectl delete pod -n metal3-system -l app.kubernetes.io/component=baremetal-operator --wait=false
sleep 3

echo ""
echo -e "${GREEN}✅ Configuration updated${NC}"
echo ""
echo "The baremetal operator should now be able to reach Ironic."
echo "Wait a moment and check:"
echo "  kubectl get baremetalhost -n metal3-system"
echo ""
echo "If it's still not working, check logs:"
echo "  kubectl logs -n metal3-system -l app.kubernetes.io/component=baremetal-operator | grep -i ironic"
echo ""

