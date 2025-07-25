#!/bin/bash

# Quick script to label all nodes with "platformworker" in the name
# Usage: ./quick-label.sh

echo "Finding and labeling nodes with 'platformworker' in the name..."

# Find and label nodes in one command
kubectl get nodes -o jsonpath='{.items[?(@.metadata.name contains "platformworker")].metadata.name}' | tr ' ' '\n' | while read node; do
    echo "Labeling node: $node"
    kubectl label nodes "$node" ceph-storage=true --overwrite
    kubectl label nodes "$node" node-role.caas.com/platform-worker=true --overwrite
done

echo "Done! Showing labeled nodes:"
kubectl get nodes --show-labels | grep platformworker 