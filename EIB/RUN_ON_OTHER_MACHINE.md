# Commands to Run on Your Other Machine

## Overview

This guide shows exactly what to run on your other machine/environment where you'll actually build images with EIB.

## Prerequisites

1. **EIB directory structure** set up
2. **Base ISO image** in `eib/base-images/`
3. **Proxy access** (if behind proxy)

## Step-by-Step Commands

### Step 1: Set Up Directory Structure

```bash
# Create EIB directory structure
mkdir -p eib/base-images
mkdir -p eib/rpms/gpg-keys
```

### Step 2: Download GPG Key (Verified Working)

```bash
# Set proxy if needed
export http_proxy=http://your-proxy:8080
export https_proxy=http://your-proxy:8080

# Download GPG key for utilities repository
curl -s "https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key" \
  -o eib/rpms/gpg-keys/utilities.key

# Verify it downloaded
ls -lh eib/rpms/gpg-keys/utilities.key
```

### Step 3: Download jq RPM (Side-loading)

**Option A: If you found the jq RPM URL**

```bash
# Download jq RPM (replace with actual URL from directory)
wget --proxy=on \
  https://download.opensuse.org/repositories/utilities/15.6/noarch/jq-<version>.noarch.rpm \
  -O eib/rpms/jq.rpm

# Or with curl
curl --proxy "$http_proxy" \
  https://download.opensuse.org/repositories/utilities/15.6/noarch/jq-<version>.noarch.rpm \
  -o eib/rpms/jq.rpm
```

**Option B: Browse and copy URL**

1. Visit: https://download.opensuse.org/repositories/utilities/15.6/noarch/
2. Search for "jq" (Ctrl+F / Cmd+F)
3. Right-click the jq RPM → Copy link address
4. Download:
   ```bash
   wget --proxy=on <pasted-url> -O eib/rpms/jq.rpm
   ```

### Step 4: Verify Files

```bash
# Check all files are in place
ls -lh eib/rpms/jq.rpm
ls -lh eib/rpms/gpg-keys/utilities.key
ls -lh eib/base-images/*.iso
```

### Step 5: Update Definition File

Ensure your `eib/downstream-cluster-config.yaml` has:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: eib-downstream-cluster
data:
  base_image: "slemicro.iso"
  
  operatingSystem:
    packages:
      additionalRepos:
        - url: https://download.opensuse.org/repositories/utilities/15.6/
```

### Step 6: Run EIB Build

```bash
# Set proxy if needed (for EIB container)
export http_proxy=http://your-proxy:8080
export https_proxy=http://your-proxy:8080
export no_proxy=localhost,127.0.0.1

# Run EIB build
podman run --rm --privileged -it \
  -v $PWD/eib:/eib \
  -e http_proxy=$http_proxy \
  -e HTTP_PROXY=$http_proxy \
  -e https_proxy=$https_proxy \
  -e HTTPS_PROXY=$https_proxy \
  -e no_proxy=$no_proxy \
  -e NO_PROXY=$no_proxy \
  -e ZYPP_HTTP_PROXY=$http_proxy \
  -e ZYPP_HTTPS_PROXY=$https_proxy \
  registry.suse.com/edge/3.3/edge-image-builder:1.2.1 \
  build --definition-file downstream-cluster-config.yaml
```

**Or use the script** (if you copy it to the other machine):

```bash
./scripts/run-eib-build.sh downstream-cluster-config.yaml
```

## Complete Example (Copy-Paste Ready)

```bash
#!/bin/bash
# Complete setup for EIB on other machine

# Set proxy (adjust as needed)
export http_proxy=http://your-proxy:8080
export https_proxy=http://your-proxy:8080

# Create directories
mkdir -p eib/base-images
mkdir -p eib/rpms/gpg-keys

# Download GPG key
curl -s "https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key" \
  -o eib/rpms/gpg-keys/utilities.key

# Download jq RPM (replace URL with actual from directory)
# First, browse: https://download.opensuse.org/repositories/utilities/15.6/noarch/
# Find jq RPM, copy URL, then:
wget --proxy=on <jq-rpm-url> -O eib/rpms/jq.rpm

# Verify files
ls -lh eib/rpms/
ls -lh eib/rpms/gpg-keys/

# Run EIB build
podman run --rm --privileged -it \
  -v $PWD/eib:/eib \
  -e http_proxy=$http_proxy \
  -e https_proxy=$https_proxy \
  -e ZYPP_HTTP_PROXY=$http_proxy \
  -e ZYPP_HTTPS_PROXY=$https_proxy \
  registry.suse.com/edge/3.3/edge-image-builder:1.2.1 \
  build --definition-file downstream-cluster-config.yaml
```

## Quick Reference

### Essential Commands

1. **Download GPG key**:
   ```bash
   curl -s "https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key" \
     -o eib/rpms/gpg-keys/utilities.key
   ```

2. **Download jq RPM** (after finding URL):
   ```bash
   wget --proxy=on <jq-rpm-url> -O eib/rpms/jq.rpm
   ```

3. **Run EIB build**:
   ```bash
   podman run --rm --privileged -it -v $PWD/eib:/eib \
     -e http_proxy=$http_proxy \
     -e https_proxy=$https_proxy \
     -e ZYPP_HTTP_PROXY=$http_proxy \
     -e ZYPP_HTTPS_PROXY=$https_proxy \
     registry.suse.com/edge/3.3/edge-image-builder:1.2.1 \
     build --definition-file downstream-cluster-config.yaml
   ```

## File Checklist

Before running EIB, ensure you have:

- [ ] `eib/base-images/slemicro.iso` - Base SL-Micro ISO
- [ ] `eib/rpms/jq.rpm` - jq RPM (side-loaded)
- [ ] `eib/rpms/gpg-keys/utilities.key` - GPG key
- [ ] `eib/downstream-cluster-config.yaml` - Definition file

## Troubleshooting

### "GPG signature validation failed"
- Ensure GPG key is in `eib/rpms/gpg-keys/utilities.key`
- Or add `noGPGCheck: true` to definition file (dev only)

### "RPM not found"
- Verify jq.rpm is in `eib/rpms/`
- Check filename is correct

### "Base image not found"
- Ensure ISO is in `eib/base-images/`
- Check filename matches definition file

## What We Tested Here

✅ GPG key download - **VERIFIED WORKING**  
✅ Repository access - **VERIFIED WORKING**  
✅ Directory structure - **CREATED**  
⚠️ jq RPM - **NEEDS MANUAL DISCOVERY** (browse directory)

## Summary

**On your other machine, run:**

1. Download GPG key (verified command above)
2. Find and download jq RPM (browse directory)
3. Run EIB build command (with proxy env vars)

That's it! The GPG key download is verified and ready to use.


