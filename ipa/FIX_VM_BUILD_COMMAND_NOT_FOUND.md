# Fix: ironic-python-agent-builder command not found in VM

## Problem
When running the build script, you get:
```
./script.sh: line 90: ironic-python-agent-builder: command not found
```

## Solution

The PATH needs to be set correctly. Run these commands in the VM:

```bash
# Check if it's installed
python3 -c "import ironic_python_agent_builder; print('Installed')" || echo "Not installed"

# Check where it's installed
python3 -c "import ironic_python_agent_builder; import os; print(os.path.join(os.path.dirname(ironic_python_agent_builder.__file__)))"

# Find the binary
find ~/.local -name "ironic-python-agent-builder" 2>/dev/null

# Add to PATH for current session
export PATH=$PATH:$HOME/.local/bin

# Verify it's now available
which ironic-python-agent-builder
```

## Fix the Script

Update your script to ensure PATH is set correctly:

```bash
# At the top of the script, after set -eux, add:
export PATH=$PATH:$HOME/.local/bin

# Or source the bashrc
source ~/.bashrc
export PATH=$PATH:$HOME/.local/bin

# Then verify before building
which ironic-python-agent-builder || {
    echo "Error: ironic-python-agent-builder not found"
    echo "Installing..."
    pip3 install --user ironic-python-agent-builder
    export PATH=$PATH:$HOME/.local/bin
}
```

## Quick Fix

If it's not installed, install it:

```bash
pip3 install --user diskimage-builder ironic-python-agent-builder
export PATH=$PATH:$HOME/.local/bin
which ironic-python-agent-builder
```

Then re-run your script.

