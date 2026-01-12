#!/bin/bash
# Download jq RPM from utilities repository for side-loading

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EIB_DIR="$PROJECT_ROOT/eib"
RPMS_DIR="$EIB_DIR/rpms"
GPG_KEYS_DIR="$RPMS_DIR/gpg-keys"

# Create directories
mkdir -p "$RPMS_DIR" "$GPG_KEYS_DIR"

echo "=========================================="
echo "Download jq RPM for EIB Side-loading"
echo "=========================================="
echo ""

# Check for proxy
if [ -z "$http_proxy" ] && [ -z "$HTTP_PROXY" ]; then
    echo "No proxy configured. If you need proxy, set:"
    echo "  export http_proxy=http://proxy:8080"
    echo "  export https_proxy=http://proxy:8080"
    echo ""
    read -p "Continue without proxy? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        exit 0
    fi
fi

# Find jq RPM version
echo "Searching for jq RPM..."
JQ_RPM=$(curl -sL "https://download.opensuse.org/repositories/utilities/15.6/noarch/" | grep -o 'href="jq-[^"]*\.rpm"' | head -1 | sed 's/href="//;s/"//')

if [ -z "$JQ_RPM" ]; then
    echo "Error: Could not find jq RPM in repository"
    echo "Please check: https://download.opensuse.org/repositories/utilities/15.6/noarch/"
    exit 1
fi

JQ_URL="https://download.opensuse.org/repositories/utilities/15.6/noarch/$JQ_RPM"
GPG_KEY_URL="https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key"

echo "Found: $JQ_RPM"
echo ""

# Download jq RPM
echo "Downloading jq RPM..."
if wget --proxy=on "$JQ_URL" -O "$RPMS_DIR/jq.rpm" 2>/dev/null || \
   curl --proxy "$http_proxy" "$JQ_URL" -o "$RPMS_DIR/jq.rpm" 2>/dev/null || \
   curl "$JQ_URL" -o "$RPMS_DIR/jq.rpm" 2>/dev/null; then
    echo "✓ Downloaded: $RPMS_DIR/jq.rpm"
    ls -lh "$RPMS_DIR/jq.rpm"
else
    echo "✗ Failed to download jq RPM"
    echo "Try manually:"
    echo "  wget --proxy=on $JQ_URL -O $RPMS_DIR/jq.rpm"
    exit 1
fi

# Download GPG key
echo ""
echo "Downloading GPG key..."
if wget --proxy=on "$GPG_KEY_URL" -O "$GPG_KEYS_DIR/utilities.key" 2>/dev/null || \
   curl --proxy "$http_proxy" "$GPG_KEY_URL" -o "$GPG_KEYS_DIR/utilities.key" 2>/dev/null || \
   curl "$GPG_KEY_URL" -o "$GPG_KEYS_DIR/utilities.key" 2>/dev/null; then
    echo "✓ Downloaded: $GPG_KEYS_DIR/utilities.key"
else
    echo "⚠ Warning: Could not download GPG key"
    echo "You may need to set noGPGCheck: true in your definition file"
fi

echo ""
echo "=========================================="
echo "✓ jq RPM ready for side-loading!"
echo "=========================================="
echo ""
echo "File location: $RPMS_DIR/jq.rpm"
echo ""
echo "Next steps:"
echo "1. Ensure your eib/downstream-cluster-config.yaml has:"
echo "   operatingSystem:"
echo "     packages:"
echo "       additionalRepos:"
echo "         - url: https://download.opensuse.org/repositories/utilities/15.6/"
echo ""
echo "2. Run EIB build:"
echo "   ./scripts/run-eib-build.sh downstream-cluster-config.yaml"
echo ""


