# Fixing SUSEConnect Proxy Issues

## Problem

SUSEConnect fails to connect to `scc.suse.com` with timeout errors:
```
SUSEConnect error: Post "https://scc.suse.com/connect/subscriptions/systems": 
dial tcp 75.2.43.231:443 i/o timeout
```

This happens when your system is behind a proxy and SUSEConnect can't reach SUSE Customer Center.

## Solution: Configure Proxy for SUSEConnect

### Method 1: Environment Variables (Temporary)

Set proxy environment variables before running SUSEConnect:

```bash
export http_proxy=http://your-proxy:8080
export https_proxy=http://your-proxy:8080
export no_proxy=localhost,127.0.0.1

sudo -E SUSEConnect --url https://scc.suse.com
```

**Note**: The `-E` flag preserves environment variables for sudo.

### Method 2: System-wide Proxy Configuration (Persistent)

Configure proxy system-wide in SL-Micro:

```bash
# Create proxy configuration
sudo mkdir -p /etc/sysconfig
sudo tee /etc/sysconfig/proxy <<EOF
PROXY_ENABLED="yes"
HTTP_PROXY="http://your-proxy:8080"
HTTPS_PROXY="http://your-proxy:8080"
NO_PROXY="localhost,127.0.0.1"
EOF

# Reload environment
source /etc/sysconfig/proxy

# Try SUSEConnect
sudo SUSEConnect --url https://scc.suse.com
```

### Method 3: SUSEConnect-specific Configuration

Create SUSEConnect proxy configuration:

```bash
sudo mkdir -p /etc/SUSEConnect
sudo tee /etc/SUSEConnect/proxy.conf <<EOF
http_proxy=http://your-proxy:8080
https_proxy=http://your-proxy:8080
no_proxy=localhost,127.0.0.1
EOF

sudo SUSEConnect --url https://scc.suse.com
```

### Method 4: Configure in /etc/environment

Add proxy to system environment:

```bash
sudo tee -a /etc/environment <<EOF
http_proxy="http://your-proxy:8080"
https_proxy="http://your-proxy:8080"
no_proxy="localhost,127.0.0.1"
EOF

# Log out and back in, or source it
source /etc/environment

sudo SUSEConnect --url https://scc.suse.com
```

## Testing Proxy Connectivity

Before running SUSEConnect, test if you can reach SCC through the proxy:

```bash
# Test with curl
curl -I --proxy http://your-proxy:8080 https://scc.suse.com

# Test with wget
wget --proxy=on https://scc.suse.com -O /dev/null

# Test DNS resolution
nslookup scc.suse.com
```

## Alternative: Skip SCC Registration

If you don't need to register with SUSE Customer Center, you can:

### Option A: Use Public Repositories Directly

Add repositories manually without registration:

```bash
# Add SUSE repositories directly
sudo zypper addrepo https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/SLE_Micro_6.2/ containers

# Refresh
sudo zypper refresh
```

### Option B: Use Local Repository Mirror

If you have a local repository server:

```bash
sudo zypper addrepo http://your-repo-server/suse/ local-suse
sudo zypper refresh
```

### Option C: Air-gapped Setup

For air-gapped environments:
1. Download RPMs on a connected machine
2. Transfer to your system
3. Install from local files

## Troubleshooting

### "i/o timeout" Error

1. **Verify proxy is accessible**:
   ```bash
   curl -I --proxy http://your-proxy:8080 http://www.google.com
   ```

2. **Check proxy authentication**:
   - If proxy requires auth: `http://username:password@proxy:8080`
   - Test: `curl -I --proxy http://user:pass@proxy:8080 https://scc.suse.com`

3. **Verify DNS resolution**:
   ```bash
   nslookup scc.suse.com
   ping -c 3 scc.suse.com
   ```

4. **Check firewall rules**:
   - Ensure port 443 (HTTPS) is allowed through proxy
   - Check if proxy allows connections to `scc.suse.com`

### "Connection refused" Error

- Proxy might not be running
- Wrong proxy address/port
- Proxy doesn't support HTTPS

### SUSEConnect Still Fails After Proxy Config

1. **Check if proxy is being used**:
   ```bash
   env | grep -i proxy
   ```

2. **Try with verbose output**:
   ```bash
   sudo SUSEConnect --url https://scc.suse.com --debug
   ```

3. **Check SUSEConnect logs**:
   ```bash
   sudo journalctl -u SUSEConnect -n 50
   ```

## Quick Reference

**Set proxy and register:**
```bash
export http_proxy=http://proxy:8080
export https_proxy=http://proxy:8080
sudo -E SUSEConnect --url https://scc.suse.com
```

**System-wide proxy:**
```bash
sudo tee /etc/sysconfig/proxy <<EOF
PROXY_ENABLED="yes"
HTTP_PROXY="http://proxy:8080"
HTTPS_PROXY="http://proxy:8080"
EOF
source /etc/sysconfig/proxy
sudo SUSEConnect --url https://scc.suse.com
```

## Related Issues

- This is similar to the EIB proxy issue (GitHub #814)
- Both involve containers/services not inheriting proxy settings
- Consider using local repositories as a workaround

## References

- [SUSEConnect Documentation](https://documentation.suse.com/sles/15-SP5/html/SLES-all/cha-register-suseconnect.html)
- [SUSE Customer Center](https://scc.suse.com)


