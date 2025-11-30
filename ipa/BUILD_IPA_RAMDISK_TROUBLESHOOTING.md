# Troubleshooting IPA Ramdisk Build

## Common Issues

### Issue: `ModuleNotFoundError: no module named 'diskimage_builder'`

**Problem**: When running `ironic-python-agent-builder`, you get:
```
ModuleNotFoundError: no module named 'diskimage_builder'
```

**Root Causes**:
1. `diskimage-builder` not installed
2. Installed in different Python environment
3. Python path issues
4. Virtual environment not activated
5. Package installed with `sudo pip3` but command uses different Python

**Quick Diagnostic**:

Run this to diagnose the issue:
```bash
# Check if module can be imported
python3 -c "import diskimage_builder; print('✓ Module found at:', diskimage_builder.__file__)" 2>&1 || echo "✗ Module not found"

# Check what's installed
pip3 list | grep -i diskimage

# Check where packages are installed
pip3 show diskimage-builder 2>/dev/null | grep -E "Location|Version" || echo "✗ diskimage-builder not found"

# Check PATH
which ironic-python-agent-builder || echo "✗ ironic-python-agent-builder not in PATH"
```

**Solutions**:

#### Solution 1: Reinstall for User (Recommended - No Sudo Needed)

```bash
# Uninstall if already installed
pip3 uninstall diskimage-builder ironic-python-agent-builder -y 2>/dev/null || true

# Reinstall for user (no sudo needed)
pip3 install --user --force-reinstall --no-cache-dir diskimage-builder ironic-python-agent-builder

# Add to PATH
export PATH=$PATH:$HOME/.local/bin

# Verify installation
python3 -c "import diskimage_builder; print('✓ Module found')"
ironic-python-agent-builder --help
```

#### Solution 1b: Install System-Wide (If User Install Doesn't Work)

```bash
# Uninstall first (if installed)
sudo pip3 uninstall diskimage-builder ironic-python-agent-builder -y 2>/dev/null || true

# Install system-wide
sudo pip3 install --force-reinstall --no-cache-dir diskimage-builder ironic-python-agent-builder

# Verify
python3 -c "import diskimage_builder; print('✓ Module found')"
```

#### Solution 2: Check Python Environment

```bash
# Check which Python is being used
which python3
python3 --version

# Check if diskimage-builder is installed
python3 -c "import diskimage_builder; print(diskimage_builder.__file__)"

# If that fails, check pip packages
pip3 list | grep diskimage
```

#### Solution 3: Install in Virtual Environment (Recommended)

```bash
# Create virtual environment
python3 -m venv ~/ipa-build-env

# Activate it
source ~/ipa-build-env/bin/activate

# Install packages
pip install diskimage-builder ironic-python-agent-builder

# Verify installation
python -c "import diskimage_builder; print('OK')"
ironic-python-agent-builder --help

# Now run your build
ironic-python-agent-builder ubuntu -o ipa-ramdisk -e ipa-network-config
```

#### Solution 4: Fix Python Path

If installed but not found:

```bash
# Find where diskimage-builder is installed
python3 -m pip show diskimage-builder | grep Location

# Add to PYTHONPATH (if needed)
export PYTHONPATH=$(python3 -m pip show diskimage-builder | grep Location | cut -d' ' -f2):$PYTHONPATH

# Or reinstall ensuring it's in the right place
sudo pip3 install --force-reinstall --no-cache-dir diskimage-builder
```

#### Solution 5: Use System Package Manager (Ubuntu/Debian)

```bash
# Try installing via apt (if available)
sudo apt-get update
sudo apt-get install -y python3-diskimage-builder python3-ironic-python-agent-builder

# Or install dependencies and use pip
sudo apt-get install -y \
    python3-pip \
    python3-dev \
    python3-setuptools \
    build-essential
```

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

**Problem**: `ironic-python-agent-builder` or `disk-image-create` can't find an element.

**Error Examples**:
- `ElementNotFound: Could not find element 'ipa-network-config'`
- `ElementNotFound: Could not find element 'ironic-agent'`
- `disk-image-create ironic agent not found`

**Solutions**:

#### Solution 1: Custom Element Not Found (ipa-network-config)

Ensure `ELEMENTS_PATH` includes your element directory:
```bash
# Set ELEMENTS_PATH before building
export ELEMENTS_PATH=~/ipa-build/elements:${ELEMENTS_PATH:-}

# Or specify full path
ironic-python-agent-builder ubuntu -o ipa-ramdisk \
    -e ~/ipa-build/elements/ipa-network-config
```

#### Solution 2: ironic-agent Element Not Found (when using disk-image-create)

The `ironic-agent` element comes with `ironic-python-agent-builder`. When using `disk-image-create` directly, you need to add it to `ELEMENTS_PATH`:

```bash
# Find where ironic-python-agent-builder elements are installed
IRONIC_ELEMENTS=$(python3 -c "import ironic_python_agent_builder; import os; print(os.path.join(os.path.dirname(ironic_python_agent_builder.__file__), 'elements'))" 2>/dev/null)

# Find where diskimage-builder elements are installed
DIB_ELEMENTS=$(python3 -c "import diskimage_builder; import os; print(os.path.join(os.path.dirname(diskimage_builder.__file__), 'elements'))" 2>/dev/null)

# Set ELEMENTS_PATH to include both
export ELEMENTS_PATH=${IRONIC_ELEMENTS}:${DIB_ELEMENTS}:${ELEMENTS_PATH:-}

# Verify elements are found
disk-image-create --help | grep ironic-agent || echo "Still not found"

# Now use disk-image-create
disk-image-create -o ipa-ramdisk \
    ubuntu \
    ironic-agent \
    ipa-network-config
```

**Alternative**: Use `ironic-python-agent-builder` instead (recommended):
```bash
# ironic-python-agent-builder automatically includes ironic-agent
ironic-python-agent-builder ubuntu -o ipa-ramdisk -e ipa-network-config
```

#### Solution 3: Find All Available Elements

```bash
# List all elements in ELEMENTS_PATH
for path in $(echo $ELEMENTS_PATH | tr ':' ' '); do
    if [ -d "$path" ]; then
        echo "Elements in $path:"
        ls -1 "$path" 2>/dev/null | head -10
        echo ""
    fi
done

# Or use disk-image-create to list
disk-image-create --help 2>&1 | grep -A 100 "Available elements"
```

### Issue: Command Not Found: ironic-python-agent-builder

**Problem**: Command not found after installation.

**Solution**:
```bash
# Check if it's installed
pip3 show ironic-python-agent-builder

# Find where it's installed
pip3 show -f ironic-python-agent-builder | grep Location

# Add to PATH if installed in user directory
export PATH=$PATH:$HOME/.local/bin

# Or use python -m
python3 -m ironic_python_agent_builder --help
```

### Issue: Build Takes Too Long

**Problem**: Build process is very slow.

**Solution**:
- Ensure you have good internet connectivity (packages are downloaded)
- Use a faster mirror for apt repositories
- Consider using a VM with more resources
- Build process typically takes 10-20 minutes

### Issue: Wrong Python Version

**Problem**: Build fails due to Python version incompatibility.

**Solution**:
```bash
# Check Python version (needs 3.6+)
python3 --version

# If using wrong version, specify correct one
python3.8 -m pip install diskimage-builder ironic-python-agent-builder
python3.8 -m ironic_python_agent_builder --help
```

## Environment Variables

### Supported Variables

- `DIB_RELEASE`: Ubuntu release (e.g., `jammy`, `focal`)
- `ELEMENTS_PATH`: Path to custom elements (colon-separated)
- `WITH_NMC`: Whether to include nmstate (true/false)
- `DIB_DEBUG_TRACE`: Enable debug tracing (set to `1`)

### Not Supported

- `DIB_EXTRA_PACKAGES`: Not directly supported by `ironic-python-agent-builder`
  - Use the element's `install.d` script instead
  - Or use `-p` flag with `disk-image-create` (fallback)

## Getting Help

If you encounter other issues:

1. **Enable debug output**:
   ```bash
   export DIB_DEBUG_TRACE=1
   ironic-python-agent-builder ubuntu -o ipa-ramdisk -e ipa-network-config
   ```

2. **Check build logs**:
   ```bash
   # Logs are usually in /tmp or current directory
   ls -la /tmp/dib-*
   ```

3. **Verify all prerequisites**:
   ```bash
   # Check required tools
   which python3 pip3 git qemu-img
   
   # Check disk space
   df -h
   ```

4. **Try the fallback method** (if `ironic-python-agent-builder` doesn't work):
   ```bash
   # First, ensure ironic-agent element is available
   # The ironic-agent element comes with ironic-python-agent-builder
   # Find where it's installed:
   python3 -c "import ironic_python_agent_builder; import os; print(os.path.dirname(ironic_python_agent_builder.__file__))"
   
   # Or find diskimage-builder elements:
   python3 -c "import diskimage_builder; import os; print(os.path.dirname(diskimage_builder.__file__))"
   
   # Set ELEMENTS_PATH to include both
   export ELEMENTS_PATH=$(python3 -c "import diskimage_builder; import os; print(os.path.join(os.path.dirname(diskimage_builder.__file__), 'elements'))"):$(python3 -c "import ironic_python_agent_builder; import os; print(os.path.join(os.path.dirname(ironic_python_agent_builder.__file__), 'elements'))"):${ELEMENTS_PATH:-}
   
   # Now use disk-image-create
   disk-image-create -o ipa-ramdisk \
       ubuntu \
       ironic-agent \
       ipa-network-config
   ```

5. **Check the documentation**:
   - [Ironic Python Agent documentation](https://docs.openstack.org/ironic-python-agent/latest/)
   - [Diskimage Builder documentation](https://docs.openstack.org/diskimage-builder/latest/)

## Diagnostic Script

Here's a script to diagnose installation issues:

```bash
#!/bin/bash
set -euo pipefail

echo "Diagnosing diskimage-builder installation issue..."
echo ""

# Check Python
echo "1. Checking Python..."
which python3
python3 --version

# Check if module can be imported
echo ""
echo "2. Testing diskimage_builder import..."
python3 -c "import diskimage_builder; print('✓ Module found at:', diskimage_builder.__file__)" 2>&1 || echo "✗ Module not found"

# Check pip packages
echo ""
echo "3. Checking installed packages..."
pip3 list | grep -i diskimage || echo "✗ No diskimage packages found"

# Check where packages are installed
echo ""
echo "4. Checking package locations..."
pip3 show diskimage-builder 2>/dev/null | grep -E "Location|Version" || echo "✗ diskimage-builder not found via pip3"

# Check PATH
echo ""
echo "5. Checking PATH..."
echo "PATH: $PATH"
which ironic-python-agent-builder || echo "✗ ironic-python-agent-builder not in PATH"

echo ""
echo "=== Recommended Fix ==="
echo "Try one of these:"
echo ""
echo "Option 1: Reinstall for user (recommended)"
echo "  pip3 install --user --force-reinstall diskimage-builder ironic-python-agent-builder"
echo "  export PATH=\$PATH:\$HOME/.local/bin"
echo ""
echo "Option 2: Install system-wide"
echo "  sudo pip3 install --force-reinstall diskimage-builder ironic-python-agent-builder"
echo ""
echo "Option 3: Use virtual environment"
echo "  python3 -m venv ~/ipa-build-env"
echo "  source ~/ipa-build-env/bin/activate"
echo "  pip install diskimage-builder ironic-python-agent-builder"
```

## Quick Fix Script

Here's a script to automatically fix common installation issues:

```bash
#!/bin/bash
set -euo pipefail

echo "Fixing diskimage-builder installation..."

# Check Python
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 not found"
    exit 1
fi

# Uninstall existing (if any)
echo "Uninstalling existing packages..."
pip3 uninstall -y diskimage-builder ironic-python-agent-builder 2>/dev/null || true

# Install fresh for user (no sudo needed)
echo "Installing diskimage-builder and ironic-python-agent-builder..."
pip3 install --user --force-reinstall --no-cache-dir diskimage-builder ironic-python-agent-builder

# Add to PATH
export PATH=$PATH:$HOME/.local/bin

# Verify
echo "Verifying installation..."
python3 -c "import diskimage_builder; print('✓ diskimage_builder imported successfully')" || {
    echo "✗ Failed to import diskimage_builder"
    echo "Trying system-wide install..."
    sudo pip3 install --force-reinstall --no-cache-dir diskimage-builder ironic-python-agent-builder
    python3 -c "import diskimage_builder; print('✓ diskimage_builder imported successfully')" || {
        echo "✗ Still failed. Try virtual environment method."
        exit 1
    }
}

ironic-python-agent-builder --help > /dev/null || {
    echo "✗ ironic-python-agent-builder not found in PATH"
    echo "Try: export PATH=\$PATH:\$HOME/.local/bin"
    exit 1
}

echo "✓ Installation successful!"
echo ""
echo "You can now run:"
echo "  export PATH=\$PATH:\$HOME/.local/bin"
echo "  ironic-python-agent-builder ubuntu -o ipa-ramdisk -e ipa-network-config"
```

**Usage**:
```bash
# Save the diagnostic script
cat > /tmp/diagnose-dib.sh << 'EOF'
# [paste diagnostic script above]
EOF
chmod +x /tmp/diagnose-dib.sh
/tmp/diagnose-dib.sh

# Or save the fix script
cat > /tmp/fix-dib.sh << 'EOF'
# [paste fix script above]
EOF
chmod +x /tmp/fix-dib.sh
/tmp/fix-dib.sh
```
