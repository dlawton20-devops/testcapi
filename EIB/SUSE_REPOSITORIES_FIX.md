# Fixing SUSE Repository Issues

## Problem

When adding repositories, you might get errors like:
- `containers is invalid`
- Repository name conflicts
- URL not found

## Solution: Use Valid Repository Names

Repository names must be valid identifiers:
- ✅ Use lowercase, numbers, hyphens, underscores
- ❌ No spaces, special characters, or reserved words
- ❌ Don't use single words that might conflict

## Correct Commands for SL-Micro 6.2

### Option 1: Utilities Repository (for jq and common tools)

```bash
sudo zypper addrepo -f \
  https://download.opensuse.org/repositories/utilities/SLE_15_SP4/utilities.repo

sudo zypper refresh
```

### Option 2: Containers Repository (for podman)

**Important**: Use a descriptive name, not just "containers":

```bash
# Try SLE Micro specific repository
sudo zypper addrepo -f \
  https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/SLE_Micro_6.2/ \
  containers-slemicro

sudo zypper refresh
```

If that doesn't work, try SLE 15 SP4 (which SL-Micro 6.2 is based on):

```bash
sudo zypper addrepo -f \
  https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/SLE_15_SP4/ \
  containers-stable

sudo zypper refresh
```

### Option 3: Check Available Repositories First

Before adding, check what's available:

```bash
# List current repositories
sudo zypper repos

# Search for podman in available repos
sudo zypper search podman

# If podman is available, you might not need to add a repo
```

## Valid Repository Name Examples

✅ **Good names:**
- `containers-stable`
- `containers-slemicro`
- `podman-repo`
- `suse-containers`
- `utilities-repo`

❌ **Bad names:**
- `containers` (too generic, might conflict)
- `containers repo` (has space)
- `containers@stable` (special character)
- `devel:kubic` (colon in name)

## Complete Setup Example

```bash
# 1. Add utilities repository (for jq, curl, etc.)
sudo zypper addrepo -f \
  https://download.opensuse.org/repositories/utilities/SLE_15_SP4/utilities.repo

# 2. Add containers repository with proper name
sudo zypper addrepo -f \
  https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/SLE_15_SP4/ \
  containers-stable

# 3. Refresh
sudo zypper refresh

# 4. Verify repositories
sudo zypper repos

# 5. Search for packages
sudo zypper search podman
sudo zypper search jq

# 6. Install packages
sudo transactional-update pkg install podman jq
sudo reboot
```

## Troubleshooting

### "Repository not found" or "404"

The repository URL might be incorrect. Try:

1. **Check if repository exists**:
   ```bash
   curl -I https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/SLE_Micro_6.2/
   ```

2. **Try different base versions**:
   - SLE_Micro_6.2
   - SLE_15_SP4
   - openSUSE_Leap_15.4

3. **Use SUSEConnect** (if you have credentials):
   ```bash
   sudo SUSEConnect --url https://scc.suse.com
   ```

### "Repository name already exists"

Remove the existing repository first:

```bash
# List repositories
sudo zypper repos

# Remove conflicting repository
sudo zypper removerepo containers

# Add with new name
sudo zypper addrepo -f <URL> containers-stable
```

### "Invalid repository name"

Make sure the name:
- Has no spaces
- Has no special characters (except hyphens/underscores)
- Is not a reserved word
- Is descriptive and unique

### Packages Still Not Found

1. **Check if package exists in repository**:
   ```bash
   sudo zypper search -r containers-stable podman
   ```

2. **Try different repository**:
   - Package Hub
   - SUSEConnect registered repos
   - Local repository mirror

3. **Use transactional-update** (SL-Micro specific):
   ```bash
   sudo transactional-update pkg search podman
   sudo transactional-update pkg install podman
   ```

## Alternative: Use SUSEConnect

If you have SUSE Customer Center credentials:

```bash
# Register system (with proxy if needed)
export http_proxy=http://proxy:8080
export https_proxy=http://proxy:8080
sudo -E SUSEConnect --url https://scc.suse.com

# This will automatically add official repositories
sudo zypper refresh
```

## Quick Reference

**Add utilities repo:**
```bash
sudo zypper addrepo -f \
  https://download.opensuse.org/repositories/utilities/SLE_15_SP4/utilities.repo
```

**Add containers repo (with proper name):**
```bash
sudo zypper addrepo -f \
  https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/SLE_15_SP4/ \
  containers-stable
```

**Refresh and search:**
```bash
sudo zypper refresh
sudo zypper search podman
```


