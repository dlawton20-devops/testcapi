# How EIB Side-loading Works with Podman Container

## The Key: Volume Mount

The EIB container accesses your side-loaded RPMs through a **volume mount** that maps your local `eib/` directory into the container.

## Directory Mapping

When you run EIB, the volume mount works like this:

```
Your Machine                    EIB Container (inside podman)
─────────────────              ──────────────────────────────
eib/                           /eib/  (mounted here)
├── base-images/        →      /eib/base-images/
│   └── slemicro.iso           └── slemicro.iso
├── rpms/                →      /eib/rpms/
│   ├── jq.rpm                  ├── jq.rpm
│   └── gpg-keys/               └── gpg-keys/
│       └── utilities.key            └── utilities.key
└── downstream-cluster-  →      └── downstream-cluster-
    config.yaml                     config.yaml
```

## The Volume Mount Command

The `-v $PWD/eib:/eib` flag does this:

- **`$PWD/eib`** = Your local `eib/` directory on your machine
- **`:/eib`** = Mounts it as `/eib/` inside the container
- **Result**: Everything in your `eib/` directory is accessible to EIB at `/eib/`

## How EIB Finds Side-loaded RPMs

EIB automatically looks for RPMs in `/eib/rpms/` (which is your `eib/rpms/` directory):

1. **EIB scans** `/eib/rpms/` for `.rpm` files
2. **EIB validates** them using GPG keys from `/eib/rpms/gpg-keys/`
3. **EIB installs** them during the build process
4. **No proxy needed** - files are already in the container!

## Complete Working Command

Here's the complete command that makes it all work:

```bash
export http_proxy=http://your-proxy:8080
export https_proxy=http://your-proxy:8080

podman run --rm --privileged -it \
  -v $PWD/eib:/eib \
  -e http_proxy=$http_proxy \
  -e https_proxy=$https_proxy \
  -e ZYPP_HTTP_PROXY=$http_proxy \
  -e ZYPP_HTTPS_PROXY=$https_proxy \
  registry.suse.com/edge/3.3/edge-image-builder:1.2.1 \
  build --definition-file downstream-cluster-config.yaml
```

**Key parts:**
- `-v $PWD/eib:/eib` ← **This mounts your eib/ directory into the container**
- `build --definition-file downstream-cluster-config.yaml` ← EIB reads this from `/eib/` (your `eib/`)

## Step-by-Step Flow

### 1. Prepare Files on Your Machine

```bash
# On your machine (where proxy works)
mkdir -p eib/rpms/gpg-keys

# Download GPG key
curl -s "https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key" \
  -o eib/rpms/gpg-keys/utilities.key

# Download jq RPM
wget --proxy=on <jq-url> -O eib/rpms/jq.rpm
```

**Result**: Files are now in `eib/rpms/` on your machine

### 2. Run EIB Container

```bash
podman run --rm --privileged -it \
  -v $PWD/eib:/eib \
  ...
```

**What happens**:
- Podman mounts `eib/` → `/eib/` in container
- Container can now see: `/eib/rpms/jq.rpm`
- Container can now see: `/eib/rpms/gpg-keys/utilities.key`

### 3. EIB Build Process

When EIB runs `build`:
1. Reads `/eib/downstream-cluster-config.yaml` (your definition file)
2. Scans `/eib/rpms/` for RPM files
3. Validates RPMs using keys from `/eib/rpms/gpg-keys/`
4. Installs RPMs during image build
5. **No internet download needed** - files are already there!

## Why This Bypasses Proxy Issues

**Normal EIB flow (fails with proxy):**
```
EIB Container → Tries to download RPMs from internet → ❌ Proxy fails
```

**Side-loading flow (works!):**
```
Your Machine → Downloads RPMs (proxy works) → Files in eib/rpms/
                                                      ↓
EIB Container → Reads from /eib/rpms/ (via volume mount) → ✅ Installs directly
```

The container never needs to download - it just reads files you already provided!

## Directory Structure Requirements

EIB expects this structure (which becomes `/eib/` in container):

```
eib/
├── base-images/
│   └── slemicro.iso          ← Base image
├── rpms/                     ← Side-loaded RPMs go here
│   ├── jq.rpm                ← EIB finds these automatically
│   └── gpg-keys/             ← GPG keys for validation
│       └── utilities.key
└── downstream-cluster-config.yaml  ← Definition file
```

## Verification

You can verify the mount works:

```bash
# Run a test container to see the mount
podman run --rm -it \
  -v $PWD/eib:/eib \
  registry.suse.com/edge/3.3/edge-image-builder:1.2.1 \
  ls -la /eib/rpms/

# Should show your jq.rpm and gpg-keys/ directory
```

## Complete Example

```bash
#!/bin/bash
# Complete example showing how it all works together

# 1. Prepare files on your machine (where proxy works)
export http_proxy=http://your-proxy:8080
mkdir -p eib/rpms/gpg-keys

# Download GPG key
curl -s --proxy "$http_proxy" \
  "https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key" \
  -o eib/rpms/gpg-keys/utilities.key

# Download jq RPM
wget --proxy=on <jq-url> -O eib/rpms/jq.rpm

# 2. Run EIB (volume mount makes eib/ accessible to container)
podman run --rm --privileged -it \
  -v $PWD/eib:/eib \
  -e http_proxy=$http_proxy \
  -e https_proxy=$https_proxy \
  -e ZYPP_HTTP_PROXY=$http_proxy \
  -e ZYPP_HTTPS_PROXY=$https_proxy \
  registry.suse.com/edge/3.3/edge-image-builder:1.2.1 \
  build --definition-file downstream-cluster-config.yaml

# EIB automatically:
# - Finds /eib/rpms/jq.rpm (your eib/rpms/jq.rpm)
# - Uses /eib/rpms/gpg-keys/utilities.key (your eib/rpms/gpg-keys/utilities.key)
# - Installs jq during build
# - No proxy needed for RPMs (already in container via mount!)
```

## Key Points

1. ✅ **Volume mount** (`-v $PWD/eib:/eib`) makes your files accessible
2. ✅ **EIB automatically** finds RPMs in `/eib/rpms/`
3. ✅ **No download needed** - files are already in the container
4. ✅ **Proxy bypassed** - download happens on your machine, not in container
5. ✅ **GPG validation** works - keys are also mounted

## Troubleshooting

### "RPM not found"

Check the volume mount:
```bash
# Verify files exist on your machine
ls -la eib/rpms/jq.rpm

# Verify container can see them
podman run --rm -v $PWD/eib:/eib \
  registry.suse.com/edge/3.3/edge-image-builder:1.2.1 \
  ls -la /eib/rpms/
```

### "GPG key not found"

Ensure GPG keys are in the right place:
```bash
# On your machine
ls -la eib/rpms/gpg-keys/

# Should show utilities.key
```

## Summary

**The magic is the volume mount**: `-v $PWD/eib:/eib`

This makes everything in your `eib/` directory available to EIB at `/eib/`, so:
- Your `eib/rpms/jq.rpm` → Container's `/eib/rpms/jq.rpm`
- Your `eib/rpms/gpg-keys/utilities.key` → Container's `/eib/rpms/gpg-keys/utilities.key`
- EIB finds and uses them automatically!

No proxy needed in the container - you download on your machine, EIB uses via the mount!


