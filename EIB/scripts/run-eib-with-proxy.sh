#!/bin/bash
# Run EIB with proxy configuration to avoid RPM issues

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EIB_DIR="$PROJECT_ROOT/eib"

# Check for proxy environment variables
if [ -z "$http_proxy" ] && [ -z "$HTTP_PROXY" ]; then
    echo "No proxy configured. If you need proxy, set:"
    echo "  export http_proxy=http://proxy.example.com:8080"
    echo "  export https_proxy=http://proxy.example.com:8080"
    echo "  export no_proxy=localhost,127.0.0.1"
    echo ""
    read -p "Continue without proxy? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        exit 0
    fi
fi

# EIB version
EIB_VERSION="${EIB_VERSION:-1.1.1}"
EIB_IMAGE="registry.suse.com/edge/3.3/edge-image-builder:${EIB_VERSION}"

echo "Running Edge Image Builder with proxy support..."
echo "EIB directory: $EIB_DIR"
echo ""

# Build podman run command with proxy environment
PODMAN_CMD="podman run --rm -v $EIB_DIR:/config"

# Add proxy environment variables if set
if [ -n "$http_proxy" ] || [ -n "$HTTP_PROXY" ]; then
    PROXY_VAR="${http_proxy:-$HTTP_PROXY}"
    PODMAN_CMD="$PODMAN_CMD -e http_proxy=$PROXY_VAR -e HTTP_PROXY=$PROXY_VAR"
fi

if [ -n "$https_proxy" ] || [ -n "$HTTPS_PROXY" ]; then
    PROXY_VAR="${https_proxy:-$HTTPS_PROXY}"
    PODMAN_CMD="$PODMAN_CMD -e https_proxy=$PROXY_VAR -e HTTPS_PROXY=$PROXY_VAR"
fi

if [ -n "$no_proxy" ] || [ -n "$NO_PROXY" ]; then
    PROXY_VAR="${no_proxy:-$NO_PROXY}"
    PODMAN_CMD="$PODMAN_CMD -e no_proxy=$PROXY_VAR -e NO_PROXY=$PROXY_VAR"
fi

# Add the image
PODMAN_CMD="$PODMAN_CMD $EIB_IMAGE"

echo "Command: $PODMAN_CMD"
echo ""

# Execute
eval $PODMAN_CMD


