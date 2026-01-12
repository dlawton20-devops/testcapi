# GPG Keys for EIB Side-loaded RPMs

## Overview

When side-loading RPMs into EIB, you need GPG keys to verify the signatures of signed RPMs. EIB validates GPG signatures by default.

## Directory Structure

GPG keys go in:
```
eib/
└── rpms/
    └── gpg-keys/          ← Place GPG keys here
        ├── utilities.key
        ├── containers.key
        └── other-repo.key
```

## How EIB Uses GPG Keys

1. **EIB automatically uses keys** from `eib/rpms/gpg-keys/` directory
2. **Validates RPM signatures** using these keys
3. **Fails build** if RPM signature doesn't match or key is missing

## Downloading GPG Keys

### For Utilities Repository

```bash
# Download GPG key for utilities repository
export http_proxy=http://your-proxy:8080
wget --proxy=on \
  https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key \
  -O eib/rpms/gpg-keys/utilities.key
```

### For Containers Repository

```bash
# Download GPG key for containers repository
wget --proxy=on \
  https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/openSUSE_Leap_15.6/repodata/repomd.xml.key \
  -O eib/rpms/gpg-keys/containers.key
```

### General Method

For any repository, the GPG key is usually at:
```
<repository-url>/repodata/repomd.xml.key
```

## Finding GPG Key URLs

### Method 1: Repository Metadata

Most repositories have the key at:
- `https://<repo-url>/repodata/repomd.xml.key`

### Method 2: Repository Info Page

Some repositories list the GPG key URL on their info page.

### Method 3: From zypper (if you can add repo)

```bash
# Add repository temporarily
sudo zypper addrepo <repo-url> temp-repo

# Get GPG key info
sudo zypper refresh temp-repo

# Check key location
cat /etc/zypp/repos.d/temp-repo.repo | grep gpgkey

# Remove temp repo
sudo zypper removerepo temp-repo
```

## Complete Example: jq with GPG Key

```bash
# Set proxy
export http_proxy=http://your-proxy:8080
export https_proxy=http://your-proxy:8080

# Create directories
mkdir -p eib/rpms/gpg-keys

# Download jq RPM
wget --proxy=on \
  https://download.opensuse.org/repositories/utilities/15.6/noarch/jq-1.6-*.noarch.rpm \
  -O eib/rpms/jq.rpm

# Download GPG key
wget --proxy=on \
  https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key \
  -O eib/rpms/gpg-keys/utilities.key

# Verify files
ls -lh eib/rpms/jq.rpm
ls -lh eib/rpms/gpg-keys/utilities.key
```

## Handling Multiple Repositories

If you're using RPMs from multiple repositories:

```bash
# Download keys for each repository
wget --proxy=on <repo1-url>/repodata/repomd.xml.key -O eib/rpms/gpg-keys/repo1.key
wget --proxy=on <repo2-url>/repodata/repomd.xml.key -O eib/rpms/gpg-keys/repo2.key
```

EIB will use all keys in the `gpg-keys/` directory.

## Unsigned RPMs (Development Only)

If your RPMs are **unsigned** or you want to **skip GPG validation**:

### Option 1: Disable GPG Check in Definition File

```yaml
operatingSystem:
  packages:
    noGPGCheck: true  # ⚠️ Development only!
    additionalRepos:
      - url: https://download.opensuse.org/repositories/utilities/15.6/
```

**Warning**: This disables all GPG validation. Only use for development!

### Option 2: Sign Your RPMs

If you have your own RPMs, sign them with your own GPG key:

```bash
# Generate GPG key (if needed)
gpg --gen-key

# Sign RPM
rpm --addsign your-package.rpm

# Export public key
gpg --export --armor > eib/rpms/gpg-keys/your-key.key
```

## Troubleshooting GPG Issues

### "GPG signature validation failed"

**Cause**: RPM signature doesn't match available keys

**Solutions**:
1. **Download correct GPG key** for the repository
2. **Verify key filename** - should be in `eib/rpms/gpg-keys/`
3. **Check key format** - should be ASCII-armored or binary GPG key
4. **Use `noGPGCheck: true`** (development only)

### "GPG key not found"

**Cause**: Key file missing or in wrong location

**Solutions**:
1. Ensure key is in `eib/rpms/gpg-keys/` directory
2. Check file permissions: `chmod 644 eib/rpms/gpg-keys/*.key`
3. Verify key file is not empty: `ls -lh eib/rpms/gpg-keys/`

### "Invalid GPG key format"

**Cause**: Key file is corrupted or wrong format

**Solutions**:
1. Re-download the key
2. Check if it's ASCII-armored (should start with `-----BEGIN PGP PUBLIC KEY BLOCK-----`)
3. Verify key is complete (not truncated)

## Verifying GPG Keys

### Check Key Format

```bash
# View key (should show PGP public key block)
head -5 eib/rpms/gpg-keys/utilities.key

# Should look like:
# -----BEGIN PGP PUBLIC KEY BLOCK-----
# Version: GnuPG v2.0.22 (GNU/Linux)
# ...
```

### Test Key with RPM

```bash
# Import key temporarily
rpm --import eib/rpms/gpg-keys/utilities.key

# Verify RPM signature
rpm --checksig eib/rpms/jq.rpm

# Should show: eib/rpms/jq.rpm: (sha256) dsa sha1 md5 gpg OK
```

## Common GPG Key Locations

### openSUSE/SUSE Repositories

- **Utilities**: `https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key`
- **Containers**: `https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/openSUSE_Leap_15.6/repodata/repomd.xml.key`
- **Package Hub**: `https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key`

### General Pattern

For most repositories:
```
<repository-base-url>/repodata/repomd.xml.key
```

## Quick Reference

**Download GPG key:**
```bash
wget --proxy=on <repo-url>/repodata/repomd.xml.key -O eib/rpms/gpg-keys/repo.key
```

**Directory structure:**
```
eib/rpms/gpg-keys/
├── utilities.key
└── containers.key
```

**Disable GPG check (dev only):**
```yaml
operatingSystem:
  packages:
    noGPGCheck: true
```

## Best Practices

1. ✅ **Always download GPG keys** for signed RPMs
2. ✅ **Use descriptive key names** (e.g., `utilities.key`, `containers.key`)
3. ✅ **Keep keys organized** in `gpg-keys/` directory
4. ✅ **Verify keys** before building
5. ❌ **Don't use `noGPGCheck`** in production
6. ❌ **Don't skip GPG validation** unless necessary

## Script to Download All Keys

```bash
#!/bin/bash
# Download GPG keys for common repositories

mkdir -p eib/rpms/gpg-keys

# Utilities repository
wget --proxy=on \
  https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key \
  -O eib/rpms/gpg-keys/utilities.key

# Containers repository (if needed)
wget --proxy=on \
  https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/openSUSE_Leap_15.6/repodata/repomd.xml.key \
  -O eib/rpms/gpg-keys/containers.key

echo "GPG keys downloaded to eib/rpms/gpg-keys/"
```


