# Building IPA Ramdisk in VM - Manual Steps

Since you're already in the VM (`ubuntu@ipa-builder`), here are the manual steps:

## Step 1: Create the build script

```bash
# In the VM, create the build script
cat > ~/build-ipa.sh << 'SCRIPT_EOF'
#!/bin/bash
set -eux

RELEASE="${1:-focal}"
OUTPUT_DIR="${HOME}/ipa-build"

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
[ -f /etc/debian_version ] && {
    apt-get update || true
    apt-get install -y jq python3-yaml python3-netifaces network-manager python3-nmstate || true
}
mkdir -p ${TARGET_ROOT}/usr/local/bin
cp ${ELEMENT_PATH}/configure-network.sh ${TARGET_ROOT}/usr/local/bin/
chmod +x ${TARGET_ROOT}/usr/local/bin/configure-network.sh
mkdir -p ${TARGET_ROOT}/etc/systemd/system
cat > ${TARGET_ROOT}/etc/systemd/system/configure-network.service << 'SVCEOF'
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
mkdir -p ${TARGET_ROOT}/etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/configure-network.service \
    ${TARGET_ROOT}/etc/systemd/system/multi-user.target.wants/configure-network.service
INSTEOF

chmod +x elements/ipa-network-config/install.d/10-ipa-network-config
cp configure-network.sh elements/ipa-network-config/

# Build
export DIB_RELEASE="${RELEASE}"
export ELEMENTS_PATH="${OUTPUT_DIR}/elements"
export PATH=$PATH:$HOME/.local/bin

echo "Building IPA ramdisk (10-20 minutes)..."
ironic-python-agent-builder ubuntu -r "${RELEASE}" -o ipa-ramdisk -e ipa-network-config

echo "Build complete!"
ls -lh ipa-ramdisk.*
SCRIPT_EOF

chmod +x ~/build-ipa.sh
```

## Step 2: Run the build

```bash
# Run the build (takes 10-20 minutes)
~/build-ipa.sh focal
```

## Step 3: Copy files back to macOS

From your macOS terminal (not in the VM):

```bash
# Create output directory
mkdir -p ~/ipa-build

# Copy files from VM
multipass transfer ipa-builder:~/ipa-build/ipa-ramdisk.initramfs ~/ipa-build/
multipass transfer ipa-builder:~/ipa-build/ipa-ramdisk.kernel ~/ipa-build/

# Verify
ls -lh ~/ipa-build/ipa-ramdisk.*
```

## Quick One-Liner (if you want to run it all at once)

In the VM, you can run this single command that does everything:

```bash
export PATH=$PATH:$HOME/.local/bin && \
mkdir -p ~/ipa-build && cd ~/ipa-build && \
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
chmod +x configure-network.sh && \
mkdir -p elements/ipa-network-config/install.d && \
cat > elements/ipa-network-config/element.yaml << 'EOF'
---
dependencies:
  - package-install
EOF
cat > elements/ipa-network-config/install.d/10-ipa-network-config << 'INSTEOF'
#!/bin/bash
set -eux
[ -f /etc/debian_version ] && {
    apt-get update || true
    apt-get install -y jq python3-yaml python3-netifaces network-manager python3-nmstate || true
}
mkdir -p ${TARGET_ROOT}/usr/local/bin
cp ${ELEMENT_PATH}/configure-network.sh ${TARGET_ROOT}/usr/local/bin/
chmod +x ${TARGET_ROOT}/usr/local/bin/configure-network.sh
mkdir -p ${TARGET_ROOT}/etc/systemd/system
cat > ${TARGET_ROOT}/etc/systemd/system/configure-network.service << 'SVCEOF'
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
mkdir -p ${TARGET_ROOT}/etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/configure-network.service \
    ${TARGET_ROOT}/etc/systemd/system/multi-user.target.wants/configure-network.service
INSTEOF
chmod +x elements/ipa-network-config/install.d/10-ipa-network-config && \
cp configure-network.sh elements/ipa-network-config/ && \
export DIB_RELEASE=focal && \
export ELEMENTS_PATH=~/ipa-build/elements && \
ironic-python-agent-builder ubuntu -r focal -o ipa-ramdisk -e ipa-network-config && \
ls -lh ipa-ramdisk.*
```

This will build the IPA ramdisk and show you the output files when complete.

