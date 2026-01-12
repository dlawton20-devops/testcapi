# Quick Guide: Install JQ in SL-Micro VM

## Quick Steps

### 1. Access Your VM
Open the QEMU console or SSH into the VM:
```bash
# Via QEMU console (direct interaction)
# Or via SSH if accessible
ssh dave@10.0.2.15
```

### 2. Install JQ (Simple - No Proxy)
```bash
# Check if already installed
jq --version

# Install JQ using transactional-update
sudo transactional-update pkg install jq

# Reboot (required for transactional-update)
sudo reboot
```

### 3. Verify After Reboot
```bash
jq --version
# Should output: jq-1.6 (or similar version)
```

## If You Have Proxy Issues

### Configure Proxy First:
```bash
# Create proxy configuration
sudo mkdir -p /etc/systemd/system/transactional-update.service.d/
sudo tee /etc/systemd/system/transactional-update.service.d/proxy.conf <<EOF
[Service]
Environment="http_proxy=http://your-proxy:8080"
Environment="https_proxy=http://your-proxy:8080"
Environment="no_proxy=localhost,127.0.0.1"
EOF

# Reload systemd
sudo systemctl daemon-reload

# Now install JQ
sudo transactional-update pkg install jq
sudo reboot
```

## If JQ Not Found in Repositories

Add the utilities repository:
```bash
# Add repository
sudo zypper addrepo https://download.opensuse.org/repositories/utilities/SLE_15_SP4/utilities.repo

# Refresh
sudo zypper refresh

# Install
sudo transactional-update pkg install jq
sudo reboot
```

## Test RPM/Zypper Access

Before installing, test if RPM access works:
```bash
# Search for JQ
sudo transactional-update pkg search jq

# Or check repositories
sudo zypper repos
sudo zypper refresh
```

## Next: Set Up EIB on Mac

Once JQ is installed in the VM, set up EIB on your Mac:

```bash
# Start podman machine (if not running)
podman machine start

# Set up EIB
cd /Users/dave/suse-sl-micro
./scripts/setup-eib.sh
```

## Common Issues

**"Package jq not found"**
- Add utilities repository (see above)
- Check: `sudo zypper repos`

**"Connection timeout"**
- Configure proxy (see above)
- Check network: `ping 8.8.8.8`

**"transactional-update fails"**
- Ensure you're using `transactional-update` not `zypper install`
- SL-Micro uses transactional updates, requires reboot


