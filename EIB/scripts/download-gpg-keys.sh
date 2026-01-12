#!/bin/bash
# Download GPG keys for EIB side-loaded RPMs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EIB_DIR="$PROJECT_ROOT/eib"
GPG_KEYS_DIR="$EIB_DIR/rpms/gpg-keys"

# Create directory
mkdir -p "$GPG_KEYS_DIR"

echo "=========================================="
echo "Download GPG Keys for EIB Side-loaded RPMs"
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

echo "Downloading GPG keys for common repositories..."
echo ""

# Utilities repository key
echo "1. Utilities repository key..."
if wget --proxy=on \
  https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key \
  -O "$GPG_KEYS_DIR/utilities.key" 2>/dev/null || \
  curl --proxy "$http_proxy" \
  https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key \
  -o "$GPG_KEYS_DIR/utilities.key" 2>/dev/null || \
  curl https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key \
  -o "$GPG_KEYS_DIR/utilities.key" 2>/dev/null; then
    echo "   ✓ Downloaded: utilities.key"
    ls -lh "$GPG_KEYS_DIR/utilities.key"
else
    echo "   ✗ Failed to download utilities.key"
fi

echo ""

# Containers repository key (optional)
read -p "Download containers repository GPG key? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "2. Containers repository key..."
    if wget --proxy=on \
      https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/openSUSE_Leap_15.6/repodata/repomd.xml.key \
      -O "$GPG_KEYS_DIR/containers.key" 2>/dev/null || \
      curl --proxy "$http_proxy" \
      https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/openSUSE_Leap_15.6/repodata/repomd.xml.key \
      -o "$GPG_KEYS_DIR/containers.key" 2>/dev/null || \
      curl https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/openSUSE_Leap_15.6/repodata/repomd.xml.key \
      -o "$GPG_KEYS_DIR/containers.key" 2>/dev/null; then
        echo "   ✓ Downloaded: containers.key"
        ls -lh "$GPG_KEYS_DIR/containers.key"
    else
        echo "   ✗ Failed to download containers.key"
    fi
fi

echo ""
echo "=========================================="
echo "GPG Keys Summary"
echo "=========================================="
echo ""
echo "Keys downloaded to: $GPG_KEYS_DIR"
ls -lh "$GPG_KEYS_DIR"/*.key 2>/dev/null || echo "No keys found"
echo ""
echo "These keys will be used by EIB to validate RPM signatures."
echo ""
echo "If you have unsigned RPMs, add to your definition file:"
echo "  operatingSystem:"
echo "    packages:"
echo "      noGPGCheck: true  # Development only!"
echo ""


