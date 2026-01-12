#!/bin/bash
# Configure SUSEConnect to work through a proxy

echo "=========================================="
echo "Configure SUSEConnect Proxy Settings"
echo "=========================================="
echo ""
echo "SUSEConnect needs proxy configuration to reach scc.suse.com"
echo ""

# Get proxy settings
if [ -z "$http_proxy" ] && [ -z "$HTTP_PROXY" ]; then
    echo "Enter proxy configuration:"
    read -p "HTTP Proxy (e.g., http://proxy.example.com:8080): " HTTP_PROXY_INPUT
    read -p "HTTPS Proxy (or press Enter to use HTTP proxy): " HTTPS_PROXY_INPUT
    read -p "No Proxy (comma-separated, e.g., localhost,127.0.0.1): " NO_PROXY_INPUT
    
    HTTP_PROXY_INPUT=${HTTP_PROXY_INPUT:-""}
    HTTPS_PROXY_INPUT=${HTTPS_PROXY_INPUT:-$HTTP_PROXY_INPUT}
else
    HTTP_PROXY_INPUT="${http_proxy:-$HTTP_PROXY}"
    HTTPS_PROXY_INPUT="${https_proxy:-$HTTPS_PROXY}"
    NO_PROXY_INPUT="${no_proxy:-$NO_PROXY}"
fi

echo ""
echo "Configuration:"
echo "  HTTP_PROXY: $HTTP_PROXY_INPUT"
echo "  HTTPS_PROXY: $HTTPS_PROXY_INPUT"
echo "  NO_PROXY: $NO_PROXY_INPUT"
echo ""

echo "=========================================="
echo "Run these commands INSIDE your SL-Micro VM:"
echo "=========================================="
echo ""

if [ -n "$HTTP_PROXY_INPUT" ]; then
    echo "# Set proxy environment variables"
    echo "export http_proxy=$HTTP_PROXY_INPUT"
    echo "export https_proxy=${HTTPS_PROXY_INPUT:-$HTTP_PROXY_INPUT}"
    if [ -n "$NO_PROXY_INPUT" ]; then
        echo "export no_proxy=$NO_PROXY_INPUT"
    fi
    echo ""
    echo "# Configure SUSEConnect to use proxy"
    echo "sudo mkdir -p /etc/SUSEConnect"
    echo "sudo tee /etc/SUSEConnect/proxy.conf <<EOF"
    echo "http_proxy=$HTTP_PROXY_INPUT"
    echo "https_proxy=${HTTPS_PROXY_INPUT:-$HTTP_PROXY_INPUT}"
    if [ -n "$NO_PROXY_INPUT" ]; then
        echo "no_proxy=$NO_PROXY_INPUT"
    fi
    echo "EOF"
    echo ""
    echo "# Or set system-wide proxy"
    echo "sudo mkdir -p /etc/sysconfig/proxy"
    echo "sudo tee /etc/sysconfig/proxy <<EOF"
    echo "PROXY_ENABLED=\"yes\""
    echo "HTTP_PROXY=\"$HTTP_PROXY_INPUT\""
    echo "HTTPS_PROXY=\"${HTTPS_PROXY_INPUT:-$HTTP_PROXY_INPUT}\""
    if [ -n "$NO_PROXY_INPUT" ]; then
        echo "NO_PROXY=\"$NO_PROXY_INPUT\""
    fi
    echo "EOF"
    echo ""
    echo "# Now try SUSEConnect again"
    echo "sudo SUSEConnect --url https://scc.suse.com"
else
    echo "No proxy provided. If you need to configure proxy manually:"
    echo ""
    echo "1. Set environment variables:"
    echo "   export http_proxy=http://proxy:8080"
    echo "   export https_proxy=http://proxy:8080"
    echo ""
    echo "2. Or configure in /etc/sysconfig/proxy"
    echo ""
    echo "3. Then run SUSEConnect:"
    echo "   sudo SUSEConnect --url https://scc.suse.com"
fi

echo ""
echo "=========================================="
echo "Alternative: Skip Registration (if not needed)"
echo "=========================================="
echo ""
echo "If you don't need SCC registration, you can:"
echo "1. Use public repositories directly"
echo "2. Add repositories manually with zypper"
echo "3. Use local repository mirrors"


