# Fix: disk-image-create ironic-agent not found

## Problem

When using `disk-image-create` directly, you get:
```
ElementNotFound: Could not find element 'ironic-agent'
```

## Quick Fix

The `ironic-agent` element comes with `ironic-python-agent-builder`. You need to add it to `ELEMENTS_PATH`:

```bash
# Find where ironic-python-agent-builder elements are installed
IRONIC_ELEMENTS=$(python3 -c "import ironic_python_agent_builder; import os; print(os.path.join(os.path.dirname(ironic_python_agent_builder.__file__), 'elements'))" 2>/dev/null)

# Find where diskimage-builder elements are installed  
DIB_ELEMENTS=$(python3 -c "import diskimage_builder; import os; print(os.path.join(os.path.dirname(diskimage_builder.__file__), 'elements'))" 2>/dev/null)

# Set ELEMENTS_PATH to include both
export ELEMENTS_PATH=${IRONIC_ELEMENTS}:${DIB_ELEMENTS}:${ELEMENTS_PATH:-}

# Verify ironic-agent element exists
if [ -d "${IRONIC_ELEMENTS}/ironic-agent" ]; then
    echo "✓ Found ironic-agent element at: ${IRONIC_ELEMENTS}/ironic-agent"
else
    echo "✗ ironic-agent element not found. Check installation."
    exit 1
fi

# Now use disk-image-create
disk-image-create -o ipa-ramdisk \
    ubuntu \
    ironic-agent \
    ipa-network-config
```

## Better Solution: Use ironic-python-agent-builder

Instead of using `disk-image-create` directly, use `ironic-python-agent-builder` which automatically includes the `ironic-agent` element:

```bash
# This automatically includes ironic-agent
ironic-python-agent-builder ubuntu -o ipa-ramdisk -e ipa-network-config
```

## One-Liner Fix

```bash
export ELEMENTS_PATH=$(python3 -c "import ironic_python_agent_builder; import os; print(os.path.join(os.path.dirname(ironic_python_agent_builder.__file__), 'elements'))"):$(python3 -c "import diskimage_builder; import os; print(os.path.join(os.path.dirname(diskimage_builder.__file__), 'elements'))"):${ELEMENTS_PATH:-} && disk-image-create -o ipa-ramdisk ubuntu ironic-agent ipa-network-config
```

