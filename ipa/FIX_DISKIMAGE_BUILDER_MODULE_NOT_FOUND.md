# Fix: ModuleNotFoundError: No module named 'diskimage_builder'

## Problem
When building, you get:
```
ModuleNotFoundError: No module named 'diskimage_builder'
```

## Solution

This is usually a Python path or installation issue. Try these steps:

### Step 1: Reinstall with force

```bash
pip3 uninstall diskimage-builder ironic-python-agent-builder -y
pip3 install --user --force-reinstall --no-cache-dir diskimage-builder ironic-python-agent-builder
```

### Step 2: Verify Python can import it

```bash
python3 -c "import diskimage_builder; print('✅ diskimage_builder found')"
python3 -c "import ironic_python_agent_builder; print('✅ ironic_python_agent_builder found')"
```

### Step 3: Check Python path

```bash
python3 -c "import site; print(site.getsitepackages())"
python3 -c "import sys; print('\n'.join(sys.path))"
```

### Step 4: Use the same Python that pip3 uses

```bash
# Find which Python pip3 uses
pip3 show diskimage-builder | grep Location

# Or use python3 -m to run the command
python3 -m diskimage_builder.cmd.main --help
```

### Step 5: Alternative - Install system-wide (if user install doesn't work)

```bash
sudo pip3 install diskimage-builder ironic-python-agent-builder
```

### Step 6: Verify commands work

```bash
export PATH=$PATH:$HOME/.local/bin
which disk-image-create
which ironic-python-agent-builder
disk-image-create --help
```

## Complete Fix Command

Run this one-liner to fix everything:

```bash
pip3 uninstall diskimage-builder ironic-python-agent-builder -y && \
pip3 install --user --force-reinstall --no-cache-dir diskimage-builder ironic-python-agent-builder && \
export PATH=$PATH:$HOME/.local/bin && \
python3 -c "import diskimage_builder; import ironic_python_agent_builder; print('✅ Both modules found')" && \
which disk-image-create && \
which ironic-python-agent-builder
```

Then re-run your build script.

