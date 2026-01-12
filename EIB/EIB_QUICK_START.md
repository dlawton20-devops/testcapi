# EIB Quick Start - Building Images with Proxy Support

## The Problem

EIB needs to download RPM packages during image builds. If you're behind a proxy, these downloads fail without proper configuration.

## Quick Solution

### 1. Set Your Proxy (if needed)

```bash
export http_proxy=http://your-proxy:8080
export https_proxy=http://your-proxy:8080
export no_proxy=localhost,127.0.0.1
```

### 2. Run the Build Script

```bash
cd /Users/dave/suse-sl-micro
./scripts/run-eib-build.sh downstream-cluster-config.yaml
```

That's it! The script automatically passes all proxy settings to the EIB container.

## What the Script Does

The `run-eib-build.sh` script:

1. ✅ Checks for your definition file
2. ✅ Automatically passes proxy environment variables to the container
3. ✅ Sets `ZYPP_HTTP_PROXY` and `ZYPP_HTTPS_PROXY` for RPM/zypper inside the container
4. ✅ Runs the exact command format from the documentation:
   ```bash
   podman run --rm --privileged -it -v $PWD/eib:/eib \
     registry.suse.com/edge/3.3/edge-image-builder:1.2.1 \
     build --definition-file downstream-cluster-config.yaml
   ```

## Prerequisites

1. **Base ISO image** in `eib/base-images/slemicro.iso`
   ```bash
   cp ~/Downloads/SL-Micro*.iso eib/base-images/slemicro.iso
   ```

2. **Definition file** in `eib/downstream-cluster-config.yaml`
   - Template provided, customize as needed

3. **Podman running**:
   ```bash
   podman machine start
   ```

## Manual Command (if you prefer)

If you want to run manually with proxy:

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

## Expected Output

After successful build:
- `SLE-Micro-eib-output.raw` in the `eib/` directory
- Ready to use with Metal3

## Troubleshooting

**RPM errors during build:**
- Verify proxy is set: `echo $http_proxy`
- Test proxy: `curl -I --proxy $http_proxy http://download.opensuse.org`
- Check if proxy requires authentication

**"Definition file not found":**
- Ensure file is in `eib/` directory
- Check filename matches: `ls eib/*.yaml`

**"Base image not found":**
- Ensure ISO is in `eib/base-images/`
- Check filename: `ls eib/base-images/*.iso`

## Full Documentation

See `EIB_RPM_PROXY_FIX.md` for detailed troubleshooting and configuration options.


