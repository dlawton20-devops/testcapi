# Fixing RPM Issues with Edge Image Builder (EIB)

## Problem

When running EIB to build images, RPM package downloads fail if you're behind a proxy. The EIB container needs proxy configuration to access SUSE repositories.

**Important Note**: According to [GitHub Issue #814](https://github.com/suse-edge/edge-image-builder/issues/814), EIB performs RPM resolution in an internal container that does **not** inherit proxy settings from the host, even when Podman's proxy variables are set. This is a known limitation in EIB.

## Current Status

As of November 2025, there is no official supported mechanism to pass proxy configuration into EIB's internal RPM resolution container. The feature is requested but not yet implemented.

## Workarounds

Since EIB's internal RPM resolution container doesn't inherit proxy settings, you have these options:

### Workaround 1: Use Additional Repository (Recommended)

Instead of relying on proxy, configure EIB to use a local or accessible repository:

1. **Set up a local repository mirror** that's accessible without proxy
2. **Add repository to your definition file**:

```yaml
repositories:
  - name: local-repo
    url: http://your-accessible-repo/
    enabled: true
```

### Workaround 2: Side-load RPMs

Pre-download required RPMs and provide them to EIB:

1. **Download RPMs manually** (using proxy on your host)
2. **Place them in a directory** accessible to EIB
3. **Reference them in your definition file**

### Workaround 3: Try Environment Variables (May Not Work)

While the internal container may not inherit these, you can try passing proxy variables:

### Step 1: Set Proxy Environment Variables

Before running EIB, set your proxy environment variables:

```bash
export http_proxy=http://your-proxy-server:8080
export https_proxy=http://your-proxy-server:8080
export no_proxy=localhost,127.0.0.1,*.local
```

**Note**: Replace `your-proxy-server:8080` with your actual proxy address and port.

### Step 2: Run EIB Build with Proxy Support

Use the provided script that attempts to pass proxy settings (may not work for RPM resolution):

```bash
cd /Users/dave/suse-sl-micro
./scripts/run-eib-build.sh downstream-cluster-config.yaml
```

Or manually run with proxy:

```bash
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

## Complete Setup Process

### 1. Prepare Directory Structure

```bash
cd /Users/dave/suse-sl-micro
mkdir -p eib/base-images
```

### 2. Add Base ISO Image

Download SL-Micro Base ISO from SUSE Customer Center and place it:

```bash
cp ~/Downloads/SL-Micro*.iso eib/base-images/slemicro.iso
```

### 3. Create Definition File

A template is provided at `eib/downstream-cluster-config.yaml`. Customize it for your needs.

### 4. Configure Proxy (if needed)

```bash
export http_proxy=http://proxy.example.com:8080
export https_proxy=http://proxy.example.com:8080
export no_proxy=localhost,127.0.0.1
```

### 5. Run EIB Build

```bash
./scripts/run-eib-build.sh downstream-cluster-config.yaml
```

## Environment Variables Passed to EIB

The script passes these proxy-related environment variables to the EIB container:

- `http_proxy` / `HTTP_PROXY` - HTTP proxy URL
- `https_proxy` / `HTTPS_PROXY` - HTTPS proxy URL  
- `no_proxy` / `NO_PROXY` - Comma-separated list of hosts to bypass proxy
- `ZYPP_HTTP_PROXY` - Zypper HTTP proxy (for RPM downloads)
- `ZYPP_HTTPS_PROXY` - Zypper HTTPS proxy (for RPM downloads)

## Troubleshooting

### RPM Downloads Still Failing

1. **Verify proxy is accessible**:
   ```bash
   curl -I --proxy $http_proxy http://download.opensuse.org
   ```

2. **Check proxy authentication**:
   - If proxy requires auth, include in URL: `http://user:pass@proxy:8080`

3. **Verify no_proxy settings**:
   - Ensure localhost and local domains are excluded

4. **Check EIB container logs**:
   ```bash
   podman run --rm --privileged -it \
     -v $PWD/eib:/eib \
     -e http_proxy=$http_proxy \
     registry.suse.com/edge/3.3/edge-image-builder:1.2.1 \
     build --definition-file downstream-cluster-config.yaml
   ```
   Look for RPM/zypper error messages

### "Definition file not found"

Ensure your definition file is in the `eib/` directory:
```bash
ls -la eib/*.yaml
```

### "Base image not found"

Ensure the base ISO is in `eib/base-images/`:
```bash
ls -la eib/base-images/*.iso
```

## Expected Output

After successful build, you should see:
- `SLE-Micro-eib-output.raw` in the `eib/` directory
- This file can be used for Metal3 downstream cluster provisioning

## Next Steps

Once the image is built:

1. **Make it available via webserver**:
   - Use Metal3's media-server container, or
   - Set up a local web server accessible at `imagecache.local:8080`

2. **Reference in Metal3 configuration**:
   ```yaml
   image:
     url: http://imagecache.local:8080/SLE-Micro-eib-output.raw
     checksum: http://imagecache.local:8080/SLE-Micro-eib-output.raw.sha256
   ```

## Quick Reference

```bash
# Set proxy
export http_proxy=http://proxy:8080
export https_proxy=http://proxy:8080

# Run build
cd /Users/dave/suse-sl-micro
./scripts/run-eib-build.sh downstream-cluster-config.yaml
```

