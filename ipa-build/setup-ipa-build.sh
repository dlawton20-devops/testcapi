#!/bin/bash
# IPA Ramdisk Build Environment Setup Script
# Converts cloud-init YAML to executable shell script for Ubuntu 20.04+
# 
# Usage: sudo bash setup-ipa-build.sh
# Or:    chmod +x setup-ipa-build.sh && sudo ./setup-ipa-build.sh

set -eux

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
    exit 1
fi

# Detect Ubuntu version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    UBUNTU_VERSION=$VERSION_ID
    UBUNTU_CODENAME=$VERSION_CODENAME
else
    echo -e "${RED}Error: Cannot detect Ubuntu version${NC}"
    exit 1
fi

echo -e "${GREEN}Setting up IPA ramdisk build environment...${NC}"
echo "Detected Ubuntu ${UBUNTU_VERSION} (${UBUNTU_CODENAME})"

# Check Python version
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}' | cut -d. -f1,2)
PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d. -f1)
PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d. -f2)

echo "Python version: $PYTHON_VERSION"

# Determine home directory (prefer ubuntu user, fallback to current user)
if id "ubuntu" &>/dev/null; then
    HOME_DIR="/home/ubuntu"
    USER_NAME="ubuntu"
elif [ -n "${SUDO_USER:-}" ]; then
    HOME_DIR=$(eval echo ~$SUDO_USER)
    USER_NAME=$SUDO_USER
else
    HOME_DIR="/root"
    USER_NAME="root"
fi

echo "Using home directory: $HOME_DIR for user: $USER_NAME"

# Update package list
echo -e "${GREEN}Updating package list...${NC}"
apt-get update

# Install system packages
echo -e "${GREEN}Installing system packages...${NC}"
apt-get install -y \
    python3-pip \
    python3-dev \
    git \
    qemu-utils \
    kpartx \
    debootstrap \
    squashfs-tools \
    dosfstools \
    curl \
    wget

# Install Python packages as the user (not root)
echo -e "${GREEN}Installing Python packages for user ${USER_NAME}...${NC}"
sudo -u $USER_NAME pip3 install --user diskimage-builder ironic-python-agent-builder

# Add to PATH in bashrc
echo -e "${GREEN}Adding ~/.local/bin to PATH...${NC}"
if ! grep -q 'export PATH=\$PATH:\$HOME/.local/bin' "$HOME_DIR/.bashrc"; then
    echo 'export PATH=$PATH:$HOME/.local/bin' >> "$HOME_DIR/.bashrc"
fi

# Export PATH for current session
export PATH=$PATH:$HOME_DIR/.local/bin

# Apply Fix 1: Fix pip version requirement (25.1.1 -> 25.0.1)
echo -e "${GREEN}Applying Fix 1: Adjusting pip version requirement...${NC}"
INSTALL_SCRIPT="$HOME_DIR/.local/share/ironic-python-agent-builder/dib/ironic-python-agent-ramdisk/install.d/ironic-python-agent-ramdisk-source-install/60-ironic-python-agent-ramdisk-install"

if [ -f "$INSTALL_SCRIPT" ]; then
    sed -i 's/REQUIRED_PIP_STR="25\.1\.1"/REQUIRED_PIP_STR="25.0.1"/' "$INSTALL_SCRIPT" || true
    sed -i 's/REQUIRED_PIP_TUPLE="(25, 1, 1)"/REQUIRED_PIP_TUPLE="(25, 0, 1)"/' "$INSTALL_SCRIPT" || true
    echo "Fix 1 applied successfully"
else
    echo -e "${YELLOW}Warning: Install script not found at $INSTALL_SCRIPT${NC}"
    echo "Fix 1 will be applied when the script is created"
fi

# Apply Fix 2: Fix constraint conflict (add fallback)
echo -e "${GREEN}Applying Fix 2: Adding constraint conflict fallback...${NC}"
if [ -f "$INSTALL_SCRIPT" ]; then
    sed -i 's|\$VENVDIR/bin/pip install -c \$UPPER_CONSTRAINTS \$IPADIR|\$VENVDIR/bin/pip install -c \$UPPER_CONSTRAINTS \$IPADIR || \$VENVDIR/bin/pip install \$IPADIR|' "$INSTALL_SCRIPT" || true
    echo "Fix 2 applied successfully"
else
    echo -e "${YELLOW}Warning: Install script not found, Fix 2 will be applied when script is created${NC}"
fi

# Create build script
echo -e "${GREEN}Creating build script...${NC}"
sudo -u $USER_NAME bash << SCRIPT_EOF
cat > "$HOME_DIR/build-ipa-ramdisk.sh" << 'BUILD_SCRIPT'
#!/bin/bash
set -eux

RELEASE="${1:-focal}"
OUTPUT_DIR="${HOME}/ipa-build"

# Check Python version requirement
PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}' | cut -d. -f1,2)
PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d. -f1)
PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d. -f2)

if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 10 ]); then
    echo "ERROR: Python 3.10+ required, but found Python $PYTHON_VERSION"
    echo "ironic-python-agent requires Python >=3.10"
    echo ""
    echo "Solutions:"
    echo "  1. Use Ubuntu 22.04 (jammy) which has Python 3.10"
    echo "  2. Build on jammy VM, then use the ramdisk with focal target"
    echo "  3. Install Python 3.10+ manually (e.g., from deadsnakes PPA)"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

# Create configure-network.sh
cat > configure-network.sh << 'NET_EOF'
#!/bin/bash
set -eux
CONFIG_DRIVE=$(blkid --label config-2 || true)
[ -z "${CONFIG_DRIVE}" ] && exit 0
mount -o ro $CONFIG_DRIVE /mnt
[ ! -f /mnt/openstack/latest/network_data.json ] && { umount /mnt; exit 0; }
mkdir -p /tmp/nmc/{desired,generated}
cp /mnt/openstack/latest/network_data.json /tmp/nmc/desired/_all.yaml
umount /mnt
if command -v nmc &> /dev/null; then
  nmc generate --config-dir /tmp/nmc/desired --output-dir /tmp/nmc/generated
  nmc apply --config-dir /tmp/nmc/generated
else
  python3 << PYEOF
import json, subprocess, sys
with open('/tmp/nmc/desired/_all.yaml') as f:
    d = json.load(f)
for iface in d.get('interfaces', []):
    name = iface.get('name')
    if not name: continue
    ipv4 = iface.get('ipv4', {})
    if ipv4.get('enabled') and not ipv4.get('dhcp'):
        addrs = ipv4.get('address', [])
        if addrs:
            ip = addrs[0].get('ip')
            prefix = addrs[0].get('prefix-length', 24)
            subprocess.run(['ip', 'addr', 'add', f'{ip}/{prefix}', 'dev', name], check=False)
            subprocess.run(['ip', 'link', 'set', 'up', 'dev', name], check=False)
PYEOF
fi
NET_EOF
chmod +x configure-network.sh

# Create element
mkdir -p elements/ipa-network-config/install.d
cat > elements/ipa-network-config/element.yaml << 'EOF'
---
dependencies:
  - package-install
EOF

cat > elements/ipa-network-config/install.d/10-ipa-network-config << 'INSTEOF'
#!/bin/bash
set -eux
TARGET_ROOT="${TARGET_ROOT:-/}"
ELEMENT_PATH="${ELEMENT_PATH:-.}"

[ -f /etc/debian_version ] && {
    apt-get update || true
    apt-get install -y jq python3-yaml python3-netifaces network-manager || true
    apt-get install -y python3-nmstate || echo "Warning: python3-nmstate not available, will use fallback"
}
mkdir -p "${TARGET_ROOT}/usr/local/bin"

# Find configure-network.sh - try ELEMENT_PATH first, then script location
if [ -f "${ELEMENT_PATH}/configure-network.sh" ]; then
    CONFIG_SCRIPT="${ELEMENT_PATH}/configure-network.sh"
elif [ -f "$(dirname "$0")/../configure-network.sh" ]; then
    CONFIG_SCRIPT="$(dirname "$0")/../configure-network.sh"
else
    echo "Error: configure-network.sh not found in ${ELEMENT_PATH} or element directory"
    exit 1
fi

cp "${CONFIG_SCRIPT}" "${TARGET_ROOT}/usr/local/bin/configure-network.sh"
chmod +x "${TARGET_ROOT}/usr/local/bin/configure-network.sh"
mkdir -p "${TARGET_ROOT}/etc/systemd/system"
cat > "${TARGET_ROOT}/etc/systemd/system/configure-network.service" << 'SVCEOF'
[Unit]
Description=Configure Network from Config Drive
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/configure-network.sh
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
SVCEOF
mkdir -p "${TARGET_ROOT}/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/configure-network.service \
    "${TARGET_ROOT}/etc/systemd/system/multi-user.target.wants/configure-network.service"
INSTEOF

chmod +x elements/ipa-network-config/install.d/10-ipa-network-config
cp configure-network.sh elements/ipa-network-config/

# Apply fixes to install script if it exists
INSTALL_SCRIPT="$HOME/.local/share/ironic-python-agent-builder/dib/ironic-python-agent-ramdisk/install.d/ironic-python-agent-ramdisk-source-install/60-ironic-python-agent-ramdisk-install"
if [ -f "$INSTALL_SCRIPT" ]; then
    # Fix 1: Fix pip version requirement
    sed -i 's/REQUIRED_PIP_STR="25\.1\.1"/REQUIRED_PIP_STR="25.0.1"/' "$INSTALL_SCRIPT" || true
    sed -i 's/REQUIRED_PIP_TUPLE="(25, 1, 1)"/REQUIRED_PIP_TUPLE="(25, 0, 1)"/' "$INSTALL_SCRIPT" || true
    
    # Fix 2: Fix constraint conflict
    sed -i 's|\$VENVDIR/bin/pip install -c \$UPPER_CONSTRAINTS \$IPADIR|\$VENVDIR/bin/pip install -c \$UPPER_CONSTRAINTS \$IPADIR || \$VENVDIR/bin/pip install \$IPADIR|' "$INSTALL_SCRIPT" || true
fi

# Build
export DIB_RELEASE="${RELEASE}"
export ELEMENTS_PATH="${OUTPUT_DIR}/elements"
export PATH=$PATH:$HOME/.local/bin

# Set PYTHONPATH based on actual Python version
PYTHON_VER=$(python3 --version 2>&1 | awk '{print $2}' | cut -d. -f1,2)
export PYTHONPATH=$HOME/.local/lib/python${PYTHON_VER}/site-packages:${PYTHONPATH:-}

echo "Building IPA ramdisk for Ubuntu ${RELEASE} (10-20 minutes)..."
echo "Note: Building on $(lsb_release -cs) with Python $(python3 --version)"
ironic-python-agent-builder ubuntu -r "${RELEASE}" -o ipa-ramdisk -e ipa-network-config

echo "Build complete!"
ls -lh ipa-ramdisk.*
BUILD_SCRIPT

chmod +x "$HOME_DIR/build-ipa-ramdisk.sh"
chown $USER_NAME:$USER_NAME "$HOME_DIR/build-ipa-ramdisk.sh"
SCRIPT_EOF

# Create BUILD_README.txt
echo -e "${GREEN}Creating BUILD_README.txt...${NC}"
sudo -u $USER_NAME bash << README_EOF
cat > "$HOME_DIR/BUILD_README.txt" << 'README_CONTENT'
IPA Ramdisk Build Script Ready
===============================

The build script has been set up with all necessary fixes.

To build the IPA ramdisk:
  cd ~
  ./build-ipa-ramdisk.sh focal   # For Ubuntu 20.04 target
  # or
  ./build-ipa-ramdisk.sh jammy   # For Ubuntu 22.04 target

Note: Build VM must have Python 3.10+ (Ubuntu 22.04+ recommended)
Target OS can be focal or jammy - specified when building

This will take 10-20 minutes.

Output files will be in ~/ipa-build/:
  - ipa-ramdisk.kernel
  - ipa-ramdisk.initramfs

Fixes Applied:
  - Pip version requirement (25.1.1 -> 25.0.1)
  - Constraint conflict fallback
  - PYTHONPATH configuration
  - ELEMENT_PATH handling in install script

Python Version Check:
  The build script will check for Python 3.10+ before building.
  If you're on Ubuntu 20.04, you may need to:
  1. Upgrade to Ubuntu 22.04, OR
  2. Install Python 3.10+ from deadsnakes PPA:
     sudo add-apt-repository ppa:deadsnakes/ppa
     sudo apt-get update
     sudo apt-get install python3.10 python3.10-venv python3.10-dev
     # Then use python3.10 instead of python3
README_CONTENT
chown $USER_NAME:$USER_NAME "$HOME_DIR/BUILD_README.txt"
README_EOF

# Final message
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IPA ramdisk build environment ready!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Setup complete for user: $USER_NAME"
echo ""
echo "Next steps:"
echo "  1. Switch to user: sudo su - $USER_NAME"
echo "  2. Run: ~/build-ipa-ramdisk.sh focal   (for Ubuntu 20.04 target)"
echo "     Or:  ~/build-ipa-ramdisk.sh jammy   (for Ubuntu 22.04 target)"
echo ""
if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 10 ]); then
    echo -e "${YELLOW}WARNING: Current Python version ($PYTHON_VERSION) is less than 3.10${NC}"
    echo -e "${YELLOW}The build script will check and fail if Python 3.10+ is not available${NC}"
    echo -e "${YELLOW}Consider upgrading to Ubuntu 22.04 or installing Python 3.10+${NC}"
    echo ""
fi
echo "See ~/BUILD_README.txt for more information"
echo ""
