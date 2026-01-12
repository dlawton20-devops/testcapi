#!/bin/bash
# Set up Edge Image Builder (EIB) for preparing downstream cluster images

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EIB_DIR="$PROJECT_ROOT/eib"
BASE_IMAGES_DIR="$EIB_DIR/base-images"

# Create EIB directory structure
mkdir -p "$BASE_IMAGES_DIR"

echo "Setting up Edge Image Builder..."
echo "EIB directory: $EIB_DIR"
echo ""

# Check if podman is available
if ! command -v podman &> /dev/null; then
    echo "Error: podman is not installed"
    echo "Install with: brew install podman"
    exit 1
fi

# EIB version - adjust as needed
EIB_VERSION="${EIB_VERSION:-1.1.1}"
EIB_IMAGE="registry.suse.com/edge/3.3/edge-image-builder:${EIB_VERSION}"

echo "Pulling EIB image: $EIB_IMAGE"
podman pull "$EIB_IMAGE"

echo ""
echo "✓ EIB setup complete!"
echo ""
echo "Next steps:"
echo "1. Copy your base SL-Micro ISO to: $BASE_IMAGES_DIR/"
echo "   Example: cp ~/Downloads/SL-Micro*.iso $BASE_IMAGES_DIR/slemicro.iso"
echo ""
echo "2. Create your EIB configuration (see examples in eib/ directory)"
echo ""
echo "3. Run EIB:"
echo "   podman run --rm -v $EIB_DIR:/config $EIB_IMAGE"
echo ""
echo "For Metal3 downstream cluster images, you'll need to:"
echo "- Prepare the image with RKE2 configuration"
echo "- Include network configuration"
echo "- Set up image cache server"
echo ""
echo "See: https://documentation.suse.com/suse-edge/3.3/html/edge/quickstart-metal3.html"


