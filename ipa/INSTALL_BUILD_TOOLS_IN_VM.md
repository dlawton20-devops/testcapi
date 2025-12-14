# Install Build Tools in VM

## Problem
`ironic_python_agent_builder` is not installed in the VM.

## Solution

Run these commands in the VM:

```bash
# Install the build tools
pip3 install --user diskimage-builder ironic-python-agent-builder

# Add to PATH
export PATH=$PATH:$HOME/.local/bin

# Verify installation
which ironic-python-agent-builder
which disk-image-create

# Test import
python3 -c "import ironic_python_agent_builder; print('✅ Installed')"
```

## Update .bashrc (Optional but Recommended)

To make PATH persistent across sessions:

```bash
echo 'export PATH=$PATH:$HOME/.local/bin' >> ~/.bashrc
source ~/.bashrc
```

## Then Re-run Your Script

After installation, re-run your build script:

```bash
export PATH=$PATH:$HOME/.local/bin
./script.sh
```

## Complete Installation Command

One-liner to install and verify:

```bash
pip3 install --user diskimage-builder ironic-python-agent-builder && \
export PATH=$PATH:$HOME/.local/bin && \
which ironic-python-agent-builder && \
python3 -c "import ironic_python_agent_builder; print('✅ Ready to build')"
```

