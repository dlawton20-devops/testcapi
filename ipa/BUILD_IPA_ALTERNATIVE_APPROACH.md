# Alternative Approach: Building IPA Ramdisk

## Problem with Docker Build on macOS

The `diskimage-builder` tool has compatibility issues when running in Docker on macOS, particularly with:
- Mount operations requiring `--privileged` flag
- Shared apt cache mounting
- Tmpfs operations

## Solution Options

### Option 1: Build on a Linux Machine (Recommended)

The most reliable way to build the IPA ramdisk is on a Linux system (Ubuntu 20.04+ or 22.04):

```bash
# On a Linux machine (Ubuntu)
sudo apt-get update
sudo apt-get install -y python3-pip python3-dev git \
    qemu-utils kpartx debootstrap squashfs-tools dosfstools

pip3 install --user diskimage-builder ironic-python-agent-builder
export PATH=$PATH:$HOME/.local/bin

# Use the build script
cd scripts/setup
./build-ipa-ramdisk.sh --release focal --output-dir ~/ipa-build
```

### Option 2: Use GitHub Actions / CI/CD

Create a GitHub Actions workflow to build the IPA ramdisk:

```yaml
name: Build IPA Ramdisk

on:
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y python3-pip python3-dev git \
            qemu-utils kpartx debootstrap squashfs-tools dosfstools
          pip3 install --user diskimage-builder ironic-python-agent-builder
      - name: Build IPA
        run: |
          export PATH=$PATH:$HOME/.local/bin
          cd scripts/setup
          ./build-ipa-ramdisk.sh --release focal --output-dir ~/ipa-build
      - name: Upload artifacts
        uses: actions/upload-artifact@v3
        with:
          name: ipa-ramdisk
          path: ~/ipa-build/ipa-ramdisk.*
```

### Option 3: Use a Pre-built IPA (Quick Start)

If you just need to test the network configuration, you can:

1. **Use standard IPA with DHCP** (works without custom build)
2. **Build later** when you have access to a Linux machine

The NetworkData secret will work once you have a custom IPA, but standard IPA with DHCP should work for initial testing.

### Option 4: Use a Linux VM on macOS

Run a Linux VM (using UTM, Parallels, or VMware) and build inside it:

```bash
# Inside Linux VM
sudo apt-get update
sudo apt-get install -y python3-pip python3-dev git \
    qemu-utils kpartx debootstrap squashfs-tools dosfstools

pip3 install --user diskimage-builder ironic-python-agent-builder
export PATH=$PATH:$HOME/.local/bin

cd /path/to/project/scripts/setup
./build-ipa-ramdisk.sh --release focal --output-dir ~/ipa-build
```

## What We've Created

Even though the Docker build on macOS is problematic, we've successfully created:

1. ✅ **Complete build script**: `scripts/setup/build-ipa-simple.sh`
2. ✅ **Documentation**: `docs/ipa/BUILD_CUSTOM_IPA_STEPS.md`
3. ✅ **Network configuration element**: Custom `ipa-network-config` element
4. ✅ **configure-network.sh script**: Network configuration logic

## Next Steps

1. **For immediate testing**: Use standard IPA with DHCP (no custom build needed)
2. **For production**: Build on a Linux machine using the scripts we created
3. **For CI/CD**: Set up GitHub Actions or similar to build automatically

## Manual Build Steps (Linux)

If you have access to a Linux machine:

```bash
# 1. Install prerequisites
sudo apt-get update
sudo apt-get install -y python3-pip python3-dev git \
    qemu-utils kpartx debootstrap squashfs-tools dosfstools

# 2. Install build tools
pip3 install --user diskimage-builder ironic-python-agent-builder
export PATH=$PATH:$HOME/.local/bin

# 3. Create build directory
mkdir -p ~/ipa-build/elements/ipa-network-config/install.d
cd ~/ipa-build

# 4. Create configure-network.sh (copy from scripts/setup/build-ipa-ramdisk.sh)

# 5. Create element files (copy from scripts/setup/build-ipa-ramdisk.sh)

# 6. Build
export DIB_RELEASE=focal
export ELEMENTS_PATH=~/ipa-build/elements
ironic-python-agent-builder ubuntu -r focal -o ipa-ramdisk -e ipa-network-config

# 7. Output files
ls -lh ~/ipa-build/ipa-ramdisk.*
```

## Summary

The Docker build approach on macOS has limitations due to mount operations. The recommended approach is to:
- Build on a Linux machine (physical, VM, or CI/CD)
- Use the scripts and documentation we've created
- The custom IPA ramdisk will enable NetworkData secret support

