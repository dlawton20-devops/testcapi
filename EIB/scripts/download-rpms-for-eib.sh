#!/bin/bash
# Download RPMs for side-loading into EIB

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EIB_DIR="$PROJECT_ROOT/eib"
RPMS_DIR="$EIB_DIR/rpms"
GPG_KEYS_DIR="$RPMS_DIR/gpg-keys"

# Create directory structure
mkdir -p "$RPMS_DIR" "$GPG_KEYS_DIR"

echo "=========================================="
echo "Download RPMs for EIB Side-loading"
echo "=========================================="
echo ""
echo "This script helps you download RPMs on your Mac"
echo "and place them in eib/rpms/ for EIB to use."
echo ""
echo "Directory: $RPMS_DIR"
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

echo "Example downloads:"
echo ""
echo "# Download jq RPM"
echo "wget --proxy=on \\"
echo "  https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/noarch/jq-1.6-150400.1.2.noarch.rpm \\"
echo "  -O $RPMS_DIR/jq.rpm"
echo ""
echo "# Download GPG key"
echo "wget --proxy=on \\"
echo "  https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/repodata/repomd.xml.key \\"
echo "  -O $GPG_KEYS_DIR/utilities.key"
echo ""

echo "=========================================="
echo "Common Packages"
echo "=========================================="
echo ""

# Function to download if URL provided
download_rpm() {
    local url=$1
    local filename=$2
    
    if [ -z "$url" ] || [ -z "$filename" ]; then
        return
    fi
    
    echo "Downloading $filename..."
    if wget --proxy=on "$url" -O "$RPMS_DIR/$filename" 2>/dev/null; then
        echo "✓ Downloaded: $filename"
    else
        echo "✗ Failed to download: $filename"
    fi
}

# Interactive mode
echo "Would you like to download common packages? (y/N)"
read -p "> " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Note: You'll need to provide the exact RPM URLs."
    echo "Find them at: https://download.opensuse.org/repositories/"
    echo ""
    echo "Enter RPM URLs (one per line, empty to finish):"
    
    while true; do
        read -p "RPM URL: " rpm_url
        if [ -z "$rpm_url" ]; then
            break
        fi
        
        filename=$(basename "$rpm_url")
        download_rpm "$rpm_url" "$filename"
    done
fi

echo ""
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Update eib/downstream-cluster-config.yaml:"
echo "   Add 'additionalRepos' or 'sccRegistrationCode'"
echo ""
echo "2. Run EIB build:"
echo "   ./scripts/run-eib-build.sh downstream-cluster-config.yaml"
echo ""
echo "See EIB_SIDELOAD_RPMS.md for complete guide"


