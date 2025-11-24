#!/bin/bash
set -e

echo "🔧 Setting up sushy-tools for BMC emulation"
echo "============================================"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SUSHY_DIR="$HOME/metal3-sushy"
SUSHY_CONFIG="$SUSHY_DIR/sushy.conf"
SUSHY_PORT=8000

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python 3 is not installed. Please install it first.${NC}"
    exit 1
fi

# Check if pip3 is installed
if ! command -v pip3 &> /dev/null; then
    echo -e "${YELLOW}⚠️  pip3 not found. Installing...${NC}"
    python3 -m ensurepip --upgrade || {
        echo -e "${RED}❌ Failed to install pip3${NC}"
        exit 1
    }
fi

# Install sushy-tools
echo "Installing sushy-tools..."
if command -v pipx &> /dev/null; then
    echo "Using pipx to install sushy-tools..."
    pipx install sushy-tools || {
        echo -e "${YELLOW}⚠️  pipx install failed, trying with --user flag...${NC}"
        pip3 install --user --break-system-packages sushy-tools || {
            echo -e "${RED}❌ Failed to install sushy-tools${NC}"
            exit 1
        }
    }
    SUSHY_EMULATOR="$HOME/.local/bin/sushy-emulator"
else
    echo "Installing sushy-tools with --user flag..."
    pip3 install --user --break-system-packages sushy-tools || {
        echo -e "${RED}❌ Failed to install sushy-tools${NC}"
        exit 1
    }
    SUSHY_EMULATOR=$(python3 -m site --user-base)/bin/sushy-emulator
fi

# Verify sushy-emulator is available
if [ ! -f "$SUSHY_EMULATOR" ]; then
    # Try alternative locations
    if [ -f "$HOME/.local/bin/sushy-emulator" ]; then
        SUSHY_EMULATOR="$HOME/.local/bin/sushy-emulator"
    elif command -v sushy-emulator &> /dev/null; then
        SUSHY_EMULATOR=$(which sushy-emulator)
    else
        echo -e "${RED}❌ sushy-emulator not found after installation${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✅ sushy-tools installed at: $SUSHY_EMULATOR${NC}"

# Create sushy directory
mkdir -p "$SUSHY_DIR"

# Check libvirt connection
if ! virsh list &>/dev/null; then
    echo -e "${YELLOW}⚠️  Cannot connect to libvirt. Make sure libvirt is running.${NC}"
    echo "   On macOS, you may need to start libvirt: brew services start libvirt"
fi

# Get libvirt URI (default for macOS)
LIBVIRT_URI="${LIBVIRT_URI:-qemu:///system}"

# Create sushy configuration
echo "Creating sushy-tools configuration..."
cat > "$SUSHY_CONFIG" <<EOF
[SUSHY_EMULATOR]
# Libvirt connection URI
LIBVIRT_URI=$LIBVIRT_URI

# Redfish emulator settings
SUSHY_EMULATOR_LISTEN_IP=0.0.0.0
SUSHY_EMULATOR_LISTEN_PORT=$SUSHY_PORT

# Authentication (default credentials)
SUSHY_EMULATOR_AUTH_FILE=$SUSHY_DIR/auth.conf

# System emulation
SUSHY_EMULATOR_SSL_CERT=
SUSHY_EMULATOR_SSL_KEY=
EOF

# Create auth configuration
cat > "$SUSHY_DIR/auth.conf" <<EOF
admin:admin
EOF

# Create systemd user service file (for Linux) or launchd plist (for macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Creating launchd service for macOS..."
    PLIST_FILE="$HOME/Library/LaunchAgents/com.metal3.sushy-emulator.plist"
    mkdir -p "$HOME/Library/LaunchAgents"
    
    cat > "$PLIST_FILE" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.metal3.sushy-emulator</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SUSHY_EMULATOR</string>
        <string>--config</string>
        <string>$SUSHY_CONFIG</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$SUSHY_DIR/sushy.log</string>
    <key>StandardErrorPath</key>
    <string>$SUSHY_DIR/sushy.error.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin</string>
    </dict>
</dict>
</plist>
PLIST
    
    echo -e "${GREEN}✅ LaunchAgent created at: $PLIST_FILE${NC}"
    echo ""
    echo "To start sushy-tools, run:"
    echo "  launchctl load $PLIST_FILE"
    echo ""
    echo "To stop sushy-tools, run:"
    echo "  launchctl unload $PLIST_FILE"
    echo ""
    echo "To check status, run:"
    echo "  launchctl list | grep sushy"
else
    echo "Creating systemd user service..."
    SYSTEMD_DIR="$HOME/.config/systemd/user"
    mkdir -p "$SYSTEMD_DIR"
    
    cat > "$SYSTEMD_DIR/sushy-emulator.service" <<EOF
[Unit]
Description=Sushy Redfish BMC Emulator
After=network.target libvirtd.service

[Service]
Type=simple
ExecStart=$SUSHY_EMULATOR --config $SUSHY_CONFIG
Restart=always
RestartSec=10
StandardOutput=file:$SUSHY_DIR/sushy.log
StandardError=file:$SUSHY_DIR/sushy.error.log

[Install]
WantedBy=default.target
EOF
    
    echo -e "${GREEN}✅ Systemd service created${NC}"
    echo ""
    echo "To start sushy-tools, run:"
    echo "  systemctl --user enable sushy-emulator"
    echo "  systemctl --user start sushy-emulator"
fi

# Create a simple start script
cat > "$SUSHY_DIR/start-sushy.sh" <<EOF
#!/bin/bash
# Start sushy-emulator in foreground for debugging
$SUSHY_EMULATOR --config $SUSHY_CONFIG
EOF
chmod +x "$SUSHY_DIR/start-sushy.sh"

echo ""
echo -e "${GREEN}✅ sushy-tools setup complete!${NC}"
echo ""
echo "Configuration files:"
echo "  Config: $SUSHY_CONFIG"
echo "  Logs: $SUSHY_DIR/sushy.log"
echo ""
echo "To start sushy-tools manually (for testing):"
echo "  $SUSHY_DIR/start-sushy.sh"
echo ""
echo "Sushy will be available at: http://localhost:$SUSHY_PORT"
echo "Default credentials: admin/admin"

