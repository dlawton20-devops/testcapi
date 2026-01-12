#!/bin/bash
# Configure proxy settings for RPM/zypper in SL-Micro VM

set -e

echo "Proxy Configuration for SL-Micro RPM/zypper"
echo "============================================"
echo ""

# Check if running inside SL-Micro VM
if [ ! -f /etc/os-release ] || ! grep -q "SUSE Linux Micro" /etc/os-release 2>/dev/null; then
    echo "This script should be run inside the SL-Micro VM"
    echo ""
    echo "To configure proxy on the host (for podman/docker):"
    echo "  export http_proxy=http://proxy.example.com:8080"
    echo "  export https_proxy=http://proxy.example.com:8080"
    echo "  export no_proxy=localhost,127.0.0.1"
    echo ""
    read -p "Do you want to configure proxy for the VM? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

echo "Enter proxy configuration:"
read -p "HTTP Proxy (e.g., http://proxy.example.com:8080): " HTTP_PROXY
read -p "HTTPS Proxy (or press Enter to use HTTP proxy): " HTTPS_PROXY
read -p "No Proxy (comma-separated, e.g., localhost,127.0.0.1): " NO_PROXY

HTTPS_PROXY=${HTTPS_PROXY:-$HTTP_PROXY}

echo ""
echo "Configuration:"
echo "  HTTP_PROXY: $HTTP_PROXY"
echo "  HTTPS_PROXY: $HTTPS_PROXY"
echo "  NO_PROXY: $NO_PROXY"
echo ""

# For SL-Micro VM
if [ -f /etc/os-release ] && grep -q "SUSE Linux Micro" /etc/os-release 2>/dev/null; then
    echo "Configuring proxy in SL-Micro VM..."
    
    # Create proxy configuration file
    sudo mkdir -p /etc/systemd/system/transactional-update.service.d/
    sudo tee /etc/systemd/system/transactional-update.service.d/proxy.conf > /dev/null <<EOF
[Service]
Environment="http_proxy=$HTTP_PROXY"
Environment="https_proxy=$HTTPS_PROXY"
Environment="no_proxy=$NO_PROXY"
EOF

    # Configure zypper proxy
    if [ -n "$HTTP_PROXY" ]; then
        sudo zypper --non-interactive ar -f http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/SLE_Micro_6.2/ containers || true
        sudo zypper --non-interactive refresh || true
    fi
    
    echo ""
    echo "✓ Proxy configured for transactional-update"
    echo ""
    echo "To apply proxy settings for current session:"
    echo "  export http_proxy=$HTTP_PROXY"
    echo "  export https_proxy=$HTTPS_PROXY"
    echo "  export no_proxy=$NO_PROXY"
    echo ""
    echo "To install packages with proxy:"
    echo "  sudo transactional-update pkg install <package-name>"
    echo "  sudo reboot"
else
    echo "For use in SL-Micro VM, create this file:"
    echo ""
    echo "/etc/systemd/system/transactional-update.service.d/proxy.conf"
    echo "[Service]"
    echo "Environment=\"http_proxy=$HTTP_PROXY\""
    echo "Environment=\"https_proxy=$HTTPS_PROXY\""
    echo "Environment=\"no_proxy=$NO_PROXY\""
    echo ""
    echo "Then run:"
    echo "  sudo systemctl daemon-reload"
fi


