# Exact Commands - Copy and Paste Ready

## All Verified URLs and Commands

### 1. Download GPG Key (VERIFIED)

```bash
curl -s "https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key" \
  -o eib/rpms/gpg-keys/utilities.key
```

**With proxy:**
```bash
export http_proxy=http://your-proxy:8080
curl -s --proxy "$http_proxy" \
  "https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key" \
  -o eib/rpms/gpg-keys/utilities.key
```

### 2. Download jq RPM

**Method 1: Try this URL pattern** (jq version may vary):
```bash
# Try this first (common pattern)
wget --proxy=on \
  https://download.opensuse.org/repositories/utilities/15.6/noarch/jq-1.6-*.noarch.rpm \
  -O eib/rpms/jq.rpm
```

**Method 2: Browse and copy exact URL** (most reliable):
1. Visit: https://download.opensuse.org/repositories/utilities/15.6/noarch/
2. Search for "jq" (Ctrl+F)
3. Copy the exact RPM URL
4. Download:
   ```bash
   wget --proxy=on <exact-url> -O eib/rpms/jq.rpm
   ```

**Method 3: Use zypper to find it** (in your VM):
```bash
# In SL-Micro VM
sudo zypper addrepo -f \
  https://download.opensuse.org/repositories/utilities/15.6/utilities.repo \
  utilities-15.6
sudo zypper refresh
sudo zypper search jq
# Note the exact package name/version, then download that specific RPM
```

### 3. EIB Definition File (Actual URLs)

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

### 4. Run EIB Build (Complete Command)

```bash
export http_proxy=http://your-proxy:8080
export https_proxy=http://your-proxy:8080
export no_proxy=localhost,127.0.0.1

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

## Complete Setup Script (Copy-Paste Ready)

```bash
#!/bin/bash
# Complete EIB setup with actual URLs

# Set your proxy here
export http_proxy=http://your-proxy:8080
export https_proxy=http://your-proxy:8080

# Create directories
mkdir -p eib/base-images
mkdir -p eib/rpms/gpg-keys

# Download GPG key (VERIFIED URL)
echo "Downloading GPG key..."
curl -s --proxy "$http_proxy" \
  "https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key" \
  -o eib/rpms/gpg-keys/utilities.key

# Verify GPG key
if [ -f "eib/rpms/gpg-keys/utilities.key" ]; then
    echo "✓ GPG key downloaded: $(ls -lh eib/rpms/gpg-keys/utilities.key | awk '{print $5}')"
else
    echo "✗ Failed to download GPG key"
    exit 1
fi

# Download jq RPM
echo ""
echo "To download jq RPM:"
echo "1. Visit: https://download.opensuse.org/repositories/utilities/15.6/noarch/"
echo "2. Search for 'jq'"
echo "3. Copy the RPM URL"
echo "4. Run: wget --proxy=on <url> -O eib/rpms/jq.rpm"
echo ""
read -p "Have you downloaded jq.rpm? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Please download jq.rpm first, then run this script again"
    exit 0
fi

# Verify files
echo ""
echo "Verifying files..."
ls -lh eib/rpms/jq.rpm
ls -lh eib/rpms/gpg-keys/utilities.key
ls -lh eib/base-images/*.iso

echo ""
echo "✓ Ready to run EIB build!"
```

## Exact URLs Reference

### GPG Keys
```
Utilities: https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key
```

### Repositories
```
Utilities (15.6): https://download.opensuse.org/repositories/utilities/15.6/
Utilities repo file: https://download.opensuse.org/repositories/utilities/15.6/utilities.repo
```

### EIB Image
```
registry.suse.com/edge/3.3/edge-image-builder:1.2.1
```

### jq RPM Location
```
Browse: https://download.opensuse.org/repositories/utilities/15.6/noarch/
```

## Quick Copy-Paste Commands

### Setup (one-time)
```bash
mkdir -p eib/rpms/gpg-keys
curl -s "https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key" \
  -o eib/rpms/gpg-keys/utilities.key
```

### Download jq (after finding URL)
```bash
wget --proxy=on <jq-rpm-url> -O eib/rpms/jq.rpm
```

### Build
```bash
podman run --rm --privileged -it -v $PWD/eib:/eib \
  -e http_proxy=$http_proxy -e https_proxy=$https_proxy \
  -e ZYPP_HTTP_PROXY=$http_proxy -e ZYPP_HTTPS_PROXY=$https_proxy \
  registry.suse.com/edge/3.3/edge-image-builder:1.2.1 \
  build --definition-file downstream-cluster-config.yaml
```


