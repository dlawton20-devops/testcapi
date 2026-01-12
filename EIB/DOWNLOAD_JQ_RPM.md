# Downloading jq RPM for Side-loading

## Repository Location

Based on [download.opensuse.org/repositories/utilities/15.6/noarch/](https://download.opensuse.org/repositories/utilities/15.6/noarch/), you can find and download the jq RPM.

## Method 1: Browse and Download Manually

1. **Visit the directory**: https://download.opensuse.org/repositories/utilities/15.6/noarch/

2. **Search for jq**: Use your browser's find function (Ctrl+F / Cmd+F) and search for "jq"

3. **Find the RPM file**: Look for a file like:
   - `jq-1.6-*.noarch.rpm`
   - Or similar version

4. **Right-click** → Copy link address

5. **Download with proxy**:
   ```bash
   export http_proxy=http://your-proxy:8080
   export https_proxy=http://your-proxy:8080
   
   # Use the exact URL you copied
   wget --proxy=on <exact-jq-rpm-url> -O eib/rpms/jq.rpm
   ```

## Method 2: Use the Download Script

I've created a script that will find and download jq automatically:

```bash
# Set proxy if needed
export http_proxy=http://your-proxy:8080
export https_proxy=http://your-proxy:8080

# Run the script
./scripts/download-jq-rpm.sh
```

## Method 3: Direct Download (if you know the exact filename)

If you can find the exact jq RPM filename from the directory listing:

```bash
export http_proxy=http://your-proxy:8080

# Replace with actual filename from the directory
wget --proxy=on \
  https://download.opensuse.org/repositories/utilities/15.6/noarch/jq-1.6-*.noarch.rpm \
  -O eib/rpms/jq.rpm
```

## Download GPG Key

After downloading the RPM, also download the GPG key:

```bash
wget --proxy=on \
  https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key \
  -O eib/rpms/gpg-keys/utilities.key
```

## Complete Example

```bash
# Set proxy
export http_proxy=http://your-proxy:8080
export https_proxy=http://your-proxy:8080

# Create directories
mkdir -p eib/rpms/gpg-keys

# Download jq RPM (find exact filename first from the directory)
wget --proxy=on \
  https://download.opensuse.org/repositories/utilities/15.6/noarch/jq-1.6-150400.1.2.noarch.rpm \
  -O eib/rpms/jq.rpm

# Download GPG key
wget --proxy=on \
  https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key \
  -O eib/rpms/gpg-keys/utilities.key

# Verify
ls -lh eib/rpms/jq.rpm
ls -lh eib/rpms/gpg-keys/utilities.key
```

## Finding the Exact jq RPM Filename

1. **Visit**: https://download.opensuse.org/repositories/utilities/15.6/noarch/
2. **Search for "jq"** in the page (Ctrl+F / Cmd+F)
3. **Look for**: `jq-*.noarch.rpm` file
4. **Note the exact filename** (e.g., `jq-1.6-150400.1.2.noarch.rpm`)

## After Downloading

1. **Verify the file**:
   ```bash
   ls -lh eib/rpms/jq.rpm
   ```

2. **Update your EIB definition file** (already configured):
   ```yaml
   operatingSystem:
     packages:
       additionalRepos:
         - url: https://download.opensuse.org/repositories/utilities/15.6/
   ```

3. **Run EIB build**:
   ```bash
   ./scripts/run-eib-build.sh downstream-cluster-config.yaml
   ```

## Troubleshooting

### "File not found" error

- Check the exact filename in the directory listing
- RPM filenames may have version numbers that change
- Use the exact URL from the directory

### "GPG signature validation failed"

- Ensure GPG key is downloaded to `eib/rpms/gpg-keys/utilities.key`
- Or set `noGPGCheck: true` in definition file (development only)

### Proxy issues

- Verify proxy is set: `echo $http_proxy`
- Test proxy: `curl -I --proxy $http_proxy https://download.opensuse.org`

## Quick Reference

**Directory**: https://download.opensuse.org/repositories/utilities/15.6/noarch/

**Download command**:
```bash
wget --proxy=on <exact-rpm-url> -O eib/rpms/jq.rpm
```

**GPG key**:
```bash
wget --proxy=on \
  https://download.opensuse.org/repositories/utilities/15.6/repodata/repomd.xml.key \
  -O eib/rpms/gpg-keys/utilities.key
```


