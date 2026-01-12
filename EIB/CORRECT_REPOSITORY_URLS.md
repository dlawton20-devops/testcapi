# Correct Repository URLs for SL-Micro 6.2

## The Problem

Many repository URLs return 404 errors. We need to find the correct, working repository paths.

## Finding Correct Repositories

### Method 1: Use SUSEConnect (Recommended if you have credentials)

If you have SUSE Customer Center credentials, register your system:

```bash
# With proxy if needed
export http_proxy=http://your-proxy:8080
export https_proxy=http://your-proxy:8080
sudo -E SUSEConnect --url https://scc.suse.com

# This automatically adds official repositories
sudo zypper refresh
```

### Method 2: Check What's Already Available

First, see what repositories are already configured:

```bash
# List current repositories
sudo zypper repos

# Check if packages are available
sudo zypper search podman
sudo zypper search jq
```

### Method 3: Use Package Hub

SUSE Package Hub provides additional packages:

```bash
# Add Package Hub repository
sudo zypper addrepo -f \
  https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/utilities.repo \
  packagehub-utilities
```

### Method 4: Try Different Repository Paths

The repository structure may vary. Try these:

#### For Podman/Containers:

```bash
# Option 1: Try with .repo file extension
sudo zypper addrepo -f \
  https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/openSUSE_Leap_15.4/devel:kubic:libcontainers:stable.repo \
  containers-stable

# Option 2: Try different base
sudo zypper addrepo -f \
  https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/openSUSE_Leap_15.5/devel:kubic:libcontainers:stable.repo \
  containers-stable

# Option 3: Try without .repo (directory)
sudo zypper addrepo -f \
  https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/openSUSE_Leap_15.4/ \
  containers-stable
```

#### For Utilities (jq):

```bash
# Option 1: openSUSE Leap (SL-Micro is based on this)
sudo zypper addrepo -f \
  https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/utilities.repo \
  utilities-leap

# Option 2: Try without .repo
sudo zypper addrepo -f \
  https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/ \
  utilities-leap
```

## Testing Repository URLs

Before adding, test if the URL exists:

```bash
# Test if repository exists
curl -I https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/

# Check for .repo file
curl -I https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/utilities.repo
```

## Alternative: Install from RPM Files

If repositories don't work, download RPMs directly:

```bash
# Download jq RPM manually (with proxy if needed)
wget --proxy=on https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/noarch/jq-1.6-150400.1.2.noarch.rpm

# Install
sudo transactional-update pkg install ./jq-1.6-150400.1.2.noarch.rpm
sudo reboot
```

## Recommended Approach

1. **First, check existing repos**:
   ```bash
   sudo zypper repos
   sudo zypper search podman jq
   ```

2. **If not found, try Package Hub**:
   ```bash
   sudo zypper addrepo -f \
     https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/utilities.repo
   ```

3. **If still not working, use SUSEConnect** (if you have credentials)

4. **Last resort**: Download RPMs manually and install

## Quick Test Script

Run this in your VM to test repositories:

```bash
# Test utilities repo
curl -I https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/utilities.repo

# If 200 OK, add it
sudo zypper addrepo -f \
  https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/utilities.repo \
  utilities

sudo zypper refresh
sudo zypper search jq
```

## Notes

- SL-Micro 6.2 is based on SUSE Linux Enterprise, which is compatible with openSUSE Leap 15.4/15.5
- Repository paths may need `.repo` file extension
- Some repositories use directory structure, others use `.repo` files
- Always test URLs with `curl -I` before adding


