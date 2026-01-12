# EIB Proxy Workarounds - Based on GitHub Issue #814

## The Problem

According to [GitHub Issue #814](https://github.com/suse-edge/edge-image-builder/issues/814), EIB performs RPM resolution in an internal container that **does not inherit proxy settings** from the host, even when Podman's proxy variables are set.

This means:
- ❌ Setting `http_proxy` environment variables may not work
- ❌ Podman's `containers.conf` proxy settings are not inherited
- ❌ The RPM resolution phase cannot reach external repositories through a corporate proxy

## Official Workarounds

The EIB maintainers have identified two workarounds:

### Workaround 1: Supply an Additional Repository

Instead of relying on proxy for external repositories, set up a local or accessible repository:

#### Option A: Local Repository Mirror

1. **Set up a local repository server** accessible without proxy
2. **Mirror required packages** from SUSE repositories
3. **Add to EIB definition file**:

```yaml
repositories:
  - name: local-suse-repo
    url: http://your-local-repo-server/suse/
    enabled: true
    gpgcheck: true
```

#### Option B: Use Accessible Repository

If you have a repository that's accessible without proxy:

```yaml
repositories:
  - name: accessible-repo
    url: http://repo-server.example.com/
    enabled: true
```

### Workaround 2: Side-load RPMs

Pre-download RPMs and provide them directly:

1. **Download RPMs manually** (using proxy on your host machine):
   ```bash
   # Download required RPMs
   wget --proxy=on http://download.opensuse.org/.../package.rpm
   ```

2. **Create RPM directory structure**:
   ```bash
   mkdir -p eib/rpms
   cp *.rpm eib/rpms/
   ```

3. **Reference in definition file** (if EIB supports this):
   - Check EIB documentation for side-loading mechanism
   - May require custom build steps

## Attempted Solutions (May Not Work)

### Try Environment Variables

While the internal container may not inherit these, you can attempt:

```bash
export http_proxy=http://proxy:8080
export https_proxy=http://proxy:8080

podman run --rm --privileged -it \
  -v $PWD/eib:/eib \
  -e http_proxy=$http_proxy \
  -e HTTP_PROXY=$http_proxy \
  -e https_proxy=$https_proxy \
  -e HTTPS_PROXY=$https_proxy \
  -e ZYPP_HTTP_PROXY=$http_proxy \
  -e ZYPP_HTTPS_PROXY=$https_proxy \
  registry.suse.com/edge/3.3/edge-image-builder:1.2.1 \
  build --definition-file downstream-cluster-config.yaml
```

**Note**: This may not work for the internal RPM resolution container.

### Try containers.conf Mount

Attempt to mount a custom `containers.conf`:

```bash
# Create containers.conf with proxy settings
cat > /tmp/containers.conf <<EOF
[containers]
http_proxy="http://proxy:8080"
https_proxy="http://proxy:8080"
no_proxy="localhost,127.0.0.1"
EOF

podman run --rm --privileged -it \
  -v $PWD/eib:/eib \
  -v /tmp/containers.conf:/etc/containers/containers.conf:ro \
  registry.suse.com/edge/3.3/edge-image-builder:1.2.1 \
  build --definition-file downstream-cluster-config.yaml
```

**Note**: This may also not work for internal containers.

## Recommended Approach

For enterprise environments with proxy restrictions:

1. **Set up a local repository mirror**:
   - Use a server accessible without proxy
   - Mirror required SUSE packages
   - Point EIB to this repository

2. **Or use air-gapped deployment**:
   - Pre-download all required RPMs
   - Use EIB's side-loading mechanism
   - Build images offline

## Future Solution

The EIB team is considering adding proxy configuration support via:
- Proxy section in `definition.yaml`
- CLI flags for proxy handling
- Custom `containers.conf` mounting

Track progress: https://github.com/suse-edge/edge-image-builder/issues/814

## Example: Local Repository Setup

```yaml
# downstream-cluster-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: eib-config
data:
  base_image: "slemicro.iso"
  
  repositories:
    - name: local-suse
      url: http://repo-server.local/suse/
      enabled: true
      gpgcheck: true
      gpgkey: http://repo-server.local/suse/repodata/repomd.xml.key
  
  packages:
    - podman
    - jq
    # ... other packages
```

## Testing Your Setup

1. **Test repository access**:
   ```bash
   curl http://your-repo-server/suse/
   ```

2. **Test without proxy**:
   ```bash
   unset http_proxy https_proxy
   # Try EIB build
   ```

3. **Check EIB logs**:
   - Look for RPM resolution errors
   - Verify which repositories are being accessed

## References

- [GitHub Issue #814](https://github.com/suse-edge/edge-image-builder/issues/814) - RFE for proxy configuration
- [GitHub Issue #327](https://github.com/suse-edge/edge-image-builder/issues/327) - Related issue
- [EIB Documentation](https://documentation.suse.com/suse-edge/3.3/html/edge/edge-image-builder.html)


