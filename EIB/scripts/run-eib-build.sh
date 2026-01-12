#!/bin/bash
# Run EIB build with proxy support for RPM access

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EIB_DIR="$PROJECT_ROOT/eib"

# Check if definition file is provided
DEFINITION_FILE="${1:-downstream-cluster-config.yaml}"

if [ ! -f "$EIB_DIR/$DEFINITION_FILE" ]; then
    echo "Error: Definition file not found: $EIB_DIR/$DEFINITION_FILE"
    echo ""
    echo "Usage: $0 [definition-file.yaml]"
    echo ""
    echo "Available definition files:"
    ls -1 "$EIB_DIR"/*.yaml 2>/dev/null || echo "  (none found)"
    exit 1
fi

# EIB version - using 1.2.1 as specified
EIB_VERSION="${EIB_VERSION:-1.2.1}"
EIB_IMAGE="registry.suse.com/edge/3.3/edge-image-builder:${EIB_VERSION}"

echo "=========================================="
echo "Edge Image Builder - Build Image"
echo "=========================================="
echo ""
echo "Definition file: $DEFINITION_FILE"
echo "EIB image: $EIB_IMAGE"
echo "Working directory: $EIB_DIR"
echo ""

# Build podman command (matching the exact format from documentation)
# The -v flag mounts your eib/ directory into the container at /eib/
# This allows EIB to access your side-loaded RPMs and GPG keys
PODMAN_CMD="podman run --rm --privileged -it"
PODMAN_CMD="$PODMAN_CMD -v $EIB_DIR:/eib"

# Add proxy environment variables if set
if [ -n "$http_proxy" ] || [ -n "$HTTP_PROXY" ]; then
    PROXY_VAR="${http_proxy:-$HTTP_PROXY}"
    echo "Using HTTP proxy: $PROXY_VAR"
    PODMAN_CMD="$PODMAN_CMD -e http_proxy=$PROXY_VAR -e HTTP_PROXY=$PROXY_VAR"
fi

if [ -n "$https_proxy" ] || [ -n "$HTTPS_PROXY" ]; then
    PROXY_VAR="${https_proxy:-$HTTPS_PROXY}"
    echo "Using HTTPS proxy: $PROXY_VAR"
    PODMAN_CMD="$PODMAN_CMD -e https_proxy=$PROXY_VAR -e HTTPS_PROXY=$PROXY_VAR"
fi

if [ -n "$no_proxy" ] || [ -n "$NO_PROXY" ]; then
    PROXY_VAR="${no_proxy:-$NO_PROXY}"
    echo "No proxy for: $PROXY_VAR"
    PODMAN_CMD="$PODMAN_CMD -e no_proxy=$PROXY_VAR -e NO_PROXY=$PROXY_VAR"
fi

# Add RPM proxy settings (for zypper inside EIB container)
if [ -n "$http_proxy" ] || [ -n "$HTTP_PROXY" ]; then
    PROXY_VAR="${http_proxy:-$HTTP_PROXY}"
    PODMAN_CMD="$PODMAN_CMD -e ZYPP_HTTP_PROXY=$PROXY_VAR"
    PODMAN_CMD="$PODMAN_CMD -e ZYPP_HTTPS_PROXY=$PROXY_VAR"
fi

# Add the image and build command
PODMAN_CMD="$PODMAN_CMD $EIB_IMAGE build --definition-file $DEFINITION_FILE"

echo ""
echo "Running command:"
echo "$PODMAN_CMD"
echo ""
echo "=========================================="
echo ""

# Execute
eval $PODMAN_CMD

