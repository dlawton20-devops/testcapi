# Side-loading RPMs in EIB - Workaround for Proxy Issues

## Overview

Side-loading RPMs is an excellent workaround for the EIB proxy issue (GitHub #814). Instead of EIB downloading packages through a proxy, you:
1. Download RPMs on your host machine (where proxy works)
2. Place them in EIB's `rpms/` directory
3. EIB installs them during the build process

This bypasses the internal RPM resolution container that doesn't inherit proxy settings.

## Directory Structure

Create this structure in your `eib/` directory:

```
eib/
├── downstream-cluster-config.yaml
├── base-images/
│   └── slemicro.iso
└── rpms/
    ├── gpg-keys/          # GPG keys for signed RPMs (optional)
    │   └── package.key
    └── package.rpm        # Your RPM files
```

## Step-by-Step Setup

### Step 1: Create Directory Structure

```bash
cd /Users/dave/suse-sl-micro
mkdir -p eib/rpms/gpg-keys
```

### Step 2: Download RPMs (with Proxy on Your Mac)

On your Mac, download the RPMs you need:

```bash
# Set proxy (if needed)
export http_proxy=http://your-proxy:8080
export https_proxy=http://your-proxy:8080

# Download jq RPM (example)
wget --proxy=on \
  https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/noarch/jq-1.6-150400.1.2.noarch.rpm \
  -O eib/rpms/jq.rpm

# Download podman RPMs (if needed)
# Note: podman may have dependencies, download those too
```

### Step 3: Handle GPG Keys (if RPMs are signed)

If your RPMs are GPG-signed, download the GPG keys:

```bash
# Download GPG key for the repository
wget --proxy=on \
  https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/repodata/repomd.xml.key \
  -O eib/rpms/gpg-keys/utilities.key
```

### Step 4: Configure EIB Definition File

Update your `eib/downstream-cluster-config.yaml`:

#### Option A: With Additional Repository (for dependencies)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: eib-downstream-cluster
data:
  base_image: "slemicro.iso"
  
  operatingSystem:
    packages:
      # Additional repository for dependency resolution
      additionalRepos:
        - url: https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/
      # Or use SUSE Customer Center registration
      # sccRegistrationCode: <your-reg-code>
```

#### Option B: With SUSE Customer Center (if you have credentials)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: eib-downstream-cluster
data:
  base_image: "slemicro.iso"
  
  operatingSystem:
    packages:
      sccRegistrationCode: <your-scc-registration-code>
```

#### Option C: Unsigned RPMs (development only)

If your RPMs are unsigned or you want to skip GPG validation:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: eib-downstream-cluster
data:
  base_image: "slemicro.iso"
  
  operatingSystem:
    packages:
      noGPGCheck: true  # Disables GPG validation (dev only!)
      additionalRepos:
        - url: https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/
```

### Step 5: Run EIB Build

```bash
cd /Users/dave/suse-sl-micro
./scripts/run-eib-build.sh downstream-cluster-config.yaml
```

## Complete Example

### Directory Structure

```bash
cd /Users/dave/suse-sl-micro
mkdir -p eib/rpms/gpg-keys

# Download jq RPM
export http_proxy=http://your-proxy:8080
wget --proxy=on \
  https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/noarch/jq-1.6-150400.1.2.noarch.rpm \
  -O eib/rpms/jq.rpm

# Download GPG key
wget --proxy=on \
  https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/repodata/repomd.xml.key \
  -O eib/rpms/gpg-keys/utilities.key
```

### Definition File

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
        - url: https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/
```

### Build

```bash
./scripts/run-eib-build.sh downstream-cluster-config.yaml
```

## Finding RPM URLs

### Method 1: Browse Repository

1. Visit: https://download.opensuse.org/repositories/
2. Navigate to your repository
3. Go to `noarch/` or `x86_64/` directory
4. Find the RPM file
5. Right-click → Copy link address

### Method 2: Use zypper on Your Mac (if you have SL-Micro installed)

```bash
# On a system with zypper
zypper search --provides jq
zypper info jq
# Note the repository URL and package name
```

### Method 3: Search on download.opensuse.org

Use the search functionality on the download site to find packages.

## Handling Dependencies

### Option 1: Download All Dependencies

```bash
# Download main package
wget --proxy=on <rpm-url> -O eib/rpms/package.rpm

# Check dependencies
rpm -qpR eib/rpms/package.rpm

# Download each dependency
# (repeat for each dependency)
```

### Option 2: Use Additional Repository

Provide an `additionalRepos` entry in your definition file. EIB will resolve dependencies from that repository (if accessible without proxy from EIB's internal container).

### Option 3: Use SCC Registration Code

If you have SUSE Customer Center credentials, use `sccRegistrationCode` in your definition file.

## GPG Key Management

### For Signed RPMs

1. **Download GPG key** from the repository:
   ```bash
   wget --proxy=on \
     https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/repodata/repomd.xml.key \
     -O eib/rpms/gpg-keys/utilities.key
   ```

2. **Place in `rpms/gpg-keys/`** directory

3. **EIB will automatically use it** to validate RPM signatures

### For Unsigned RPMs

If RPMs are unsigned, add to definition file:

```yaml
operatingSystem:
  packages:
    noGPGCheck: true  # Development only!
```

## Troubleshooting

### "GPG signature validation failed"

- Ensure GPG key is in `rpms/gpg-keys/`
- Key filename should match the repository
- Or use `noGPGCheck: true` (dev only)

### "Package dependencies not satisfied"

- Add `additionalRepos` to definition file
- Or use `sccRegistrationCode`
- Or download all dependency RPMs

### "RPM file not found"

- Check file is in `eib/rpms/` directory
- Verify filename is correct
- Check file permissions

## Advantages of Side-loading

✅ **Bypasses proxy issues** - Download on host, install in EIB  
✅ **Works offline** - Once RPMs are downloaded  
✅ **Faster builds** - No waiting for repository downloads  
✅ **Reproducible** - Same RPMs every time  
✅ **Air-gapped friendly** - Perfect for restricted networks  

## Quick Reference

**Directory structure:**
```
eib/
├── downstream-cluster-config.yaml
├── base-images/
│   └── slemicro.iso
└── rpms/
    ├── gpg-keys/
    └── *.rpm
```

**Definition file:**
```yaml
operatingSystem:
  packages:
    additionalRepos:
      - url: <repository-url>
```

**Download RPM:**
```bash
wget --proxy=on <rpm-url> -O eib/rpms/package.rpm
```

## Next Steps

1. Create `eib/rpms/` directory structure
2. Download required RPMs on your Mac (with proxy)
3. Update definition file with `additionalRepos` or `sccRegistrationCode`
4. Run EIB build

This is the recommended workaround for the EIB proxy issue!


