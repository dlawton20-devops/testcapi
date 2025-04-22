#!/bin/bash

# Check if required environment variables are set
if [ -z "$RANCHER_URL" ] || [ -z "$RANCHER_TOKEN" ] || [ -z "$CLUSTER_NAME" ]; then
    echo "Error: Required environment variables not set"
    echo "Please set RANCHER_URL, RANCHER_TOKEN, and CLUSTER_NAME"
    exit 1
fi

# Source environment variables
source ../openstack/credentials/.env

# Generate cluster configuration
envsubst < ../rancher/cluster-configs/cluster-template.yaml > cluster-${CLUSTER_NAME}.yaml

# Create cluster using Rancher API
curl -X POST \
  -H "Authorization: Bearer $RANCHER_TOKEN" \
  -H "Content-Type: application/json" \
  -d @cluster-${CLUSTER_NAME}.yaml \
  "$RANCHER_URL/v3/cluster"

# Monitor cluster creation
echo "Monitoring cluster creation..."
while true; do
    STATUS=$(curl -s -H "Authorization: Bearer $RANCHER_TOKEN" \
        "$RANCHER_URL/v3/cluster?name=$CLUSTER_NAME" | jq -r '.data[0].state')
    
    if [ "$STATUS" == "active" ]; then
        echo "Cluster $CLUSTER_NAME is ready!"
        break
    elif [ "$STATUS" == "error" ]; then
        echo "Error creating cluster $CLUSTER_NAME"
        exit 1
    fi
    
    echo "Cluster status: $STATUS"
    sleep 30
done 