# Setting Up JQ for Edge Image Builder

## Overview

Edge Image Builder (EIB) requires the `jq` package for JSON processing when building images. This guide shows you how to install JQ in your SL-Micro VM and configure RPM/zypper access.

## Step 1: Access Your SL-Micro VM

You can access the VM via:
- **QEMU Console**: Direct interaction in the QEMU window
- **SSH**: `ssh dave@10.0.2.15` (if network allows)
- **Port Forward**: `ssh dave@localhost -p 2222` (if configured)

## Step 2: Install JQ in SL-Micro

### Option A: Direct Installation (No Proxy)

```bash
# Check if already installed
jq --version

# If not installed, use transactional-update (SL-Micro's package manager)
sudo transactional-update pkg install jq

# Reboot to apply changes (required for transactional-update)
sudo reboot
```

### Option B: With Proxy Configuration

If you're behind a proxy, configure it first:

```bash
# 1. Configure proxy for transactional-update
sudo mkdir -p /etc/systemd/system/transactional-update.service.d/
sudo tee /etc/systemd/system/transactional-update.service.d/proxy.conf <<EOF
[Service]
Environment="http_proxy=http://your-proxy:8080"
Environment="https_proxy=http://your-proxy:8080"
Environment="no_proxy=localhost,127.0.0.1"
EOF

# 2. Reload systemd
sudo systemctl daemon-reload

# 3. Install JQ
sudo transactional-update pkg install jq

# 4. Reboot
sudo reboot
```

### Option C: Add Package Hub Repository (if JQ not in default repos)

```bash
# Add utilities repository
sudo zypper addrepo https://download.opensuse.org/repositories/utilities/SLE_15_SP4/utilities.repo

# Refresh repositories
sudo zypper refresh

# Install JQ
sudo transactional-update pkg install jq
sudo reboot
```

## Step 3: Verify Installation

After reboot, verify JQ is installed:

```bash
jq --version
# Should show: jq-1.6 or similar
```

## Step 4: Set Up Podman on Mac (for EIB)

EIB runs in a container, so you need podman working on your Mac:

```bash
# Check if podman machine is running
podman machine list

# If not running, start it
podman machine start

# Or create a new machine if needed
podman machine init
podman machine start
```

## Step 5: Run EIB

Once JQ is installed in the VM and podman is ready on Mac:

```bash
# From your Mac (not in VM)
cd /Users/dave/suse-sl-micro

# Set up EIB
./scripts/setup-eib.sh

# Run EIB (with proxy if needed)
./scripts/run-eib-with-proxy.sh
```

## Troubleshooting

### JQ Installation Fails

1. **Check network connectivity**:
   ```bash
   ping 8.8.8.8
   ```

2. **Check repository access**:
   ```bash
   sudo zypper repos
   sudo zypper refresh
   ```

3. **Check proxy settings**:
   ```bash
   echo $http_proxy
   echo $https_proxy
   ```

### RPM/Zypper Proxy Issues

If you get connection errors:
- Verify proxy URL and port
- Check if proxy requires authentication
- Ensure `no_proxy` includes localhost
- Test with: `curl -I http://download.opensuse.org`

### Podman Connection Issues

If podman can't connect:
```bash
# Check podman machine status
podman machine list

# Restart podman machine
podman machine stop
podman machine start

# Check connection
podman system connection list
```

## Quick Reference

**In VM (SL-Micro):**
```bash
sudo transactional-update pkg install jq
sudo reboot
jq --version
```

**On Mac (for EIB):**
```bash
podman machine start
./scripts/setup-eib.sh
./scripts/run-eib-with-proxy.sh
```


