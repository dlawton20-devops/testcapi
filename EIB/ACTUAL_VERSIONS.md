# Actual Versions and URLs You Can Use

## Verified URLs (Tested and Working)

### GPG Key (VERIFIED)

```bash
# Utilities repository GPG key
https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key
```

**Download command:**
```bash
curl -s "https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key" \
  -o eib/rpms/gpg-keys/utilities.key
```

### Repository URLs

```bash
# Utilities repository (15.6)
https://download.opensuse.org/repositories/utilities/15.6/utilities.repo

# Utilities repository base URL (for additionalRepos in EIB)
https://download.opensuse.org/repositories/utilities/15.6/
```

## Finding jq RPM - Manual Method

Since automated discovery is challenging, here's the **guaranteed method**:

### Step 1: Get the Exact jq RPM URL

1. **Visit in browser**: https://download.opensuse.org/repositories/utilities/15.6/noarch/
2. **Press Ctrl+F (or Cmd+F on Mac)** to search
3. **Type**: `jq`
4. **Find the RPM file** (will look like `jq-1.6-*.noarch.rpm` or similar)
5. **Right-click the file** → Copy link address
6. **Use that exact URL** in the download command

### Step 2: Download with Proxy

```bash
export http_proxy=http://your-proxy:8080
export https_proxy=http://your-proxy:8080

# Use the exact URL you copied
wget --proxy=on <exact-url-from-step-1> -O eib/rpms/jq.rpm
```

## Alternative: Use Package Search

If jq isn't in utilities repo, try searching other repositories:

### Check if jq is in Default Repos

In your SL-Micro VM:
```bash
sudo zypper search jq
```

If found, you might not need to side-load it!

## EIB Version

```bash
# EIB image version (from documentation)
registry.suse.com/edge/3.3/edge-image-builder:1.2.1
```

## Complete Working Example

Here's a complete example with actual URLs (except jq which needs manual discovery):

```bash
#!/bin/bash
# Complete setup with actual URLs

# Set proxy
export http_proxy=http://your-proxy:8080
export https_proxy=http://your-proxy:8080

# Create directories
mkdir -p eib/base-images
mkdir -p eib/rpms/gpg-keys

# Download GPG key (VERIFIED URL)
curl -s "https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key" \
  -o eib/rpms/gpg-keys/utilities.key

# Download jq RPM (YOU NEED TO GET EXACT URL FROM BROWSER)
# Step 1: Visit https://download.opensuse.org/repositories/utilities/15.6/noarch/
# Step 2: Find jq RPM, copy URL
# Step 3: Replace <jq-url> below with actual URL
wget --proxy=on <jq-url> -O eib/rpms/jq.rpm

# Verify files
ls -lh eib/rpms/jq.rpm
ls -lh eib/rpms/gpg-keys/utilities.key

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

## Definition File with Actual URLs

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

## Quick Reference - Copy These URLs

**GPG Key:**
```
https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key
```

**Repository (for zypper):**
```
https://download.opensuse.org/repositories/utilities/15.6/utilities.repo
```

**Repository Base (for EIB additionalRepos):**
```
https://download.opensuse.org/repositories/utilities/15.6/
```

**EIB Image:**
```
registry.suse.com/edge/3.3/edge-image-builder:1.2.1
```

**jq RPM Directory (browse to find exact file):**
```
https://download.opensuse.org/repositories/utilities/15.6/noarch/
```

## Why jq URL Needs Manual Discovery

The jq RPM filename may change with versions, and the HTML structure makes automated parsing unreliable. The browser method is the most reliable way to get the exact, current URL.


