#!/bin/bash

# Validation Script for Flux GitOps Setup
# Usage: ./validate-setup.sh

set -e

echo "Validating Flux GitOps Setup..."
echo "=================================="

# Check Flux installation
echo "1. Checking Flux installation..."
kubectl get pods -n flux-system
echo ""

# Check GitRepositories
echo "2. Checking GitRepositories..."
kubectl get gitrepositories -n flux-system
echo ""

# Check Kustomizations
echo "3. Checking Kustomizations..."
kubectl get kustomizations -n flux-system
echo ""

# Check HelmRepositories
echo "4. Checking HelmRepositories..."
kubectl get helmrepositories -n flux-system
echo ""

# Check HelmReleases
echo "5. Checking HelmReleases..."
kubectl get helmreleases -A
echo ""

# Check monitoring components
echo "6. Checking monitoring components..."
kubectl get pods -n cattle-monitoring-system 2>/dev/null || echo "Monitoring namespace not found"
echo ""

# Check logging components
echo "7. Checking logging components..."
kubectl get pods -n cattle-logging-system 2>/dev/null || echo "Logging namespace not found"
echo ""

# Check Flux events
echo "8. Recent Flux events..."
kubectl get events -n flux-system --sort-by='.lastTimestamp' | tail -10
echo ""

echo "Validation completed!"
echo ""
echo "To check specific component status:"
echo "  kubectl get gitrepositories,kustomizations,helmreleases -n flux-system"
echo "  kubectl describe kustomization <name> -n flux-system"
echo "  flux logs --all-namespaces" 