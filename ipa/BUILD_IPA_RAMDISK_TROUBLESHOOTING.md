# Troubleshooting IPA Ramdisk Build

## Common Issues

### Issue: `dib_extra_packages=network-manager` Error

**Problem**: You're trying to use `DIB_EXTRA_PACKAGES` environment variable but getting an error.

**Solution**: The `ironic-python-agent-builder` tool doesn't directly support `DIB_EXTRA_PACKAGES`. Packages should be installed in the custom element's `install.d` script.

**Fix**: The build script already installs `network-manager` in the element. If you need to add more packages:

1. **Edit the element's install script**:
   ```bash
   # Edit ~/ipa-build/elements/ipa-network-config/install.d/10-ipa-network-config
   # Add your packages to the apt-get install line:
   apt-get install -y \
       jq \
       python3-yaml \
       python3-netifaces \
       network-manager \
       your-additional-package
   ```

2. **Or use disk-image-create directly** (fallback method):
   ```bash
   disk-image-create -o ipa-ramdisk \
       ubuntu \
       ironic-agent \
       ipa-network-config \
       -p network-manager \
       -p your-additional-package
   ```

### Issue: Package Not Found

**Problem**: A package you're trying to install is not available in the repositories.

**Solution**: 
- Check if the package name is correct for your Ubuntu release
- Some packages have different names in different releases
- Try installing from a different repository or use an alternative package

**Example**:
```bash
# For network-manager, the package name is consistent
# But for nmstate, you might need to check availability:
apt-cache search nmstate
```

### Issue: Build Fails with Permission Errors

**Problem**: Build fails with permission denied errors.

**Solution**: 
- Don't run the build script as root
- Ensure you have sudo access for package installation
- Check that output directory is writable

### Issue: Element Not Found

**Problem**: `ironic-python-agent-builder` can't find your custom element.

**Solution**: Ensure `ELEMENTS_PATH` includes your element directory:
```bash
export ELEMENTS_PATH=~/ipa-build/elements:${ELEMENTS_PATH:-}
```

### Issue: Network Configuration Not Applied

**Problem**: IPA boots but network configuration script doesn't run.

**Debug Steps**:
1. Check if config drive is mounted:
   ```bash
   # In IPA console
   blkid | grep config-2
   lsblk
   ```

2. Check service status:
   ```bash
   systemctl status configure-network.service
   journalctl -u configure-network.service -n 50
   ```

3. Check if network_data.json exists:
   ```bash
   mount /dev/sr0 /mnt  # or appropriate device
   ls -la /mnt/openstack/latest/
   cat /mnt/openstack/latest/network_data.json
   ```

### Issue: nmc Command Not Found

**Problem**: The `nmc` (NM Configurator) command is not available in IPA.

**Solution**: 
- The script includes a fallback method that uses Python to configure the network
- Or ensure `python3-nmstate` package is installed in the element
- Check if nmstate is available for your Ubuntu release

### Issue: Build Takes Too Long

**Problem**: Build process is very slow.

**Solution**:
- Ensure you have good internet connectivity (packages are downloaded)
- Use a faster mirror for apt repositories
- Consider using a VM with more resources
- Build process typically takes 10-20 minutes

## Environment Variables

### Supported Variables

- `DIB_RELEASE`: Ubuntu release (e.g., `jammy`, `focal`)
- `ELEMENTS_PATH`: Path to custom elements (colon-separated)
- `WITH_NMC`: Whether to include nmstate (true/false)

### Not Supported

- `DIB_EXTRA_PACKAGES`: Not directly supported by `ironic-python-agent-builder`
  - Use the element's `install.d` script instead
  - Or use `-p` flag with `disk-image-create` (fallback)

## Getting Help

If you encounter other issues:

1. Check the build logs for specific error messages
2. Verify all prerequisites are installed
3. Try the fallback method using `disk-image-create` directly
4. Check the [Ironic Python Agent documentation](https://docs.openstack.org/ironic-python-agent/latest/)
5. Review the [Diskimage Builder documentation](https://docs.openstack.org/diskimage-builder/latest/)

