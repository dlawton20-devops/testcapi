# Correct Utilities Repository for SL-Micro 6.2

## Available Versions

Based on [download.opensuse.org/repositories/utilities/](https://download.opensuse.org/repositories/utilities/), the available versions are:

- **15.6/** - Latest stable
- **16.0/** - Newer version
- **openSUSE_Factory/** - Development version

**Note**: Versions 15.4 and 15.5 are not listed, which explains the 404 errors.

## Recommended Repository

For SL-Micro 6.2, try **15.6** (closest to your system):

```bash
# Add utilities repository (15.6)
sudo zypper addrepo -f \
  https://download.opensuse.org/repositories/utilities/15.6/utilities.repo \
  utilities-15.6

# Refresh
sudo zypper refresh
```

## Alternative: Try 16.0

If 15.6 doesn't work, try 16.0:

```bash
sudo zypper addrepo -f \
  https://download.opensuse.org/repositories/utilities/16.0/utilities.repo \
  utilities-16.0

sudo zypper refresh
```

## Testing Before Adding

Always test the URL first:

```bash
# Test if repository exists
curl -I https://download.opensuse.org/repositories/utilities/15.6/utilities.repo

# If returns 200 OK, it's safe to add
```

## For Side-loading RPMs

If you're using side-loading (recommended for proxy issues), you can download RPMs from:

### For jq package:

1. **Browse to find the RPM**:
   - Visit: https://download.opensuse.org/repositories/utilities/15.6/
   - Navigate to `noarch/` or `x86_64/` directory
   - Find `jq-*.rpm`

2. **Download with proxy**:
   ```bash
   export http_proxy=http://your-proxy:8080
   wget --proxy=on \
     https://download.opensuse.org/repositories/utilities/15.6/noarch/jq-*.rpm \
     -O eib/rpms/jq.rpm
   ```

3. **Download GPG key**:
   ```bash
   wget --proxy=on \
     https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key \
     -O eib/rpms/gpg-keys/utilities.key
   ```

## Complete Command Set

### Option 1: Add Repository (if accessible)

```bash
# Test first
curl -I https://download.opensuse.org/repositories/utilities/15.6/utilities.repo

# If 200 OK, add it
sudo zypper addrepo -f \
  https://download.opensuse.org/repositories/utilities/15.6/utilities.repo \
  utilities-15.6

sudo zypper refresh
sudo zypper search jq
```

### Option 2: Side-load RPMs (Recommended for Proxy)

```bash
# On your Mac, with proxy
export http_proxy=http://your-proxy:8080

# Download jq RPM (find exact URL first)
wget --proxy=on \
  https://download.opensuse.org/repositories/utilities/15.6/noarch/jq-1.6-*.noarch.rpm \
  -O eib/rpms/jq.rpm

# Download GPG key
wget --proxy=on \
  https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key \
  -O eib/rpms/gpg-keys/utilities.key
```

## Finding Exact RPM URLs

1. **Visit**: https://download.opensuse.org/repositories/utilities/15.6/
2. **Click on**: `noarch/` (for architecture-independent packages like jq)
3. **Find**: `jq-*.rpm` file
4. **Right-click** → Copy link address
5. **Use that URL** in your wget command

## Updated Definition File

For EIB side-loading, update your definition file:

```yaml
operatingSystem:
  packages:
    additionalRepos:
      - url: https://download.opensuse.org/repositories/utilities/15.6/
```

## Quick Reference

**Test repository:**
```bash
curl -I https://download.opensuse.org/repositories/utilities/15.6/utilities.repo
```

**Add repository:**
```bash
sudo zypper addrepo -f \
  https://download.opensuse.org/repositories/utilities/15.6/utilities.repo \
  utilities-15.6
```

**Download RPM for side-loading:**
```bash
wget --proxy=on <exact-rpm-url> -O eib/rpms/package.rpm
```


