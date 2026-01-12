#!/bin/bash
# Test downloading RPMs and GPG keys before using in VM

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EIB_DIR="$PROJECT_ROOT/eib"
RPMS_DIR="$EIB_DIR/rpms"
GPG_KEYS_DIR="$RPMS_DIR/gpg-keys"

# Create directories
mkdir -p "$RPMS_DIR" "$GPG_KEYS_DIR"

echo "=========================================="
echo "Testing Downloads for EIB Side-loading"
echo "=========================================="
echo ""

# Test 1: Check repository accessibility
echo "1. Testing repository accessibility..."
if curl -sI "https://download.opensuse.org/repositories/utilities/15.6/utilities.repo" | grep -q "200\|301\|302"; then
    echo "   ✓ Utilities repository is accessible"
else
    echo "   ✗ Utilities repository not accessible"
    exit 1
fi

# Test 2: Find jq RPM
echo ""
echo "2. Finding jq RPM..."
JQ_RPM=$(curl -sL "https://download.opensuse.org/repositories/utilities/15.6/noarch/" | grep -oE 'jq-[0-9][^"]*\.rpm' | head -1)

if [ -z "$JQ_RPM" ]; then
    echo "   ✗ Could not find jq RPM"
    echo "   Searching in directory listing..."
    curl -sL "https://download.opensuse.org/repositories/utilities/15.6/noarch/" | grep -i "jq" | head -5
    exit 1
else
    echo "   ✓ Found: $JQ_RPM"
    JQ_URL="https://download.opensuse.org/repositories/utilities/15.6/noarch/$JQ_RPM"
fi

# Test 3: Test GPG key URL
echo ""
echo "3. Testing GPG key URL..."
GPG_KEY_URL="https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key"
if curl -sI "$GPG_KEY_URL" | grep -q "200\|301\|302"; then
    echo "   ✓ GPG key URL is accessible"
else
    echo "   ✗ GPG key URL not accessible"
    exit 1
fi

# Test 4: Download GPG key (small file, safe to download)
echo ""
echo "4. Downloading GPG key (test)..."
if curl -s "$GPG_KEY_URL" -o "$GPG_KEYS_DIR/utilities.key.test" 2>/dev/null; then
    KEY_SIZE=$(stat -f%z "$GPG_KEYS_DIR/utilities.key.test" 2>/dev/null || stat -c%s "$GPG_KEYS_DIR/utilities.key.test" 2>/dev/null)
    if [ "$KEY_SIZE" -gt 100 ]; then
        echo "   ✓ GPG key downloaded successfully ($KEY_SIZE bytes)"
        mv "$GPG_KEYS_DIR/utilities.key.test" "$GPG_KEYS_DIR/utilities.key"
        echo "   ✓ Saved to: $GPG_KEYS_DIR/utilities.key"
    else
        echo "   ✗ GPG key file too small (may be corrupted)"
        rm -f "$GPG_KEYS_DIR/utilities.key.test"
        exit 1
    fi
else
    echo "   ✗ Failed to download GPG key"
    exit 1
fi

# Test 5: Verify GPG key format
echo ""
echo "5. Verifying GPG key format..."
if head -1 "$GPG_KEYS_DIR/utilities.key" | grep -q "BEGIN PGP"; then
    echo "   ✓ GPG key format is valid (PGP public key block)"
else
    echo "   ⚠ Warning: GPG key may not be in expected format"
    echo "   First line: $(head -1 "$GPG_KEYS_DIR/utilities.key")"
fi

# Test 6: Test jq RPM URL (don't download, just test)
echo ""
echo "6. Testing jq RPM URL..."
if curl -sI "$JQ_URL" | grep -q "200\|301\|302"; then
    RPM_SIZE=$(curl -sI "$JQ_URL" | grep -i "content-length" | awk '{print $2}' | tr -d '\r')
    echo "   ✓ jq RPM URL is accessible"
    if [ -n "$RPM_SIZE" ]; then
        echo "   ✓ RPM size: $(numfmt --to=iec-i --suffix=B $RPM_SIZE 2>/dev/null || echo "${RPM_SIZE} bytes")"
    fi
    echo "   URL: $JQ_URL"
else
    echo "   ✗ jq RPM URL not accessible"
    exit 1
fi

echo ""
echo "=========================================="
echo "✓ All Tests Passed!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  ✓ Repository accessible"
echo "  ✓ jq RPM found: $JQ_RPM"
echo "  ✓ GPG key downloaded: $GPG_KEYS_DIR/utilities.key"
echo ""
echo "Next steps:"
echo "  1. Download jq RPM (when ready):"
echo "     wget --proxy=on $JQ_URL -O $RPMS_DIR/jq.rpm"
echo ""
echo "  2. Or use the download script:"
echo "     ./scripts/download-jq-rpm.sh"
echo ""
echo "  3. Run EIB build:"
echo "     ./scripts/run-eib-build.sh downstream-cluster-config.yaml"
echo ""


