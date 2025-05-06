#!/bin/bash
set -e
kubectl apply -f "$(cd "$(dirname "${BASH_SOURCE[0]}")/../manifests" && pwd)/turtles-install.yaml" 