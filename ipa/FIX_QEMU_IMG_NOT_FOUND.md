# Fix: qemu-img executable not found

## Problem
When building the IPA ramdisk, you get:
```
qcow2 output format specified but qemu-img executable not found.
Command '['disk-image-create', '-o', 'ipa-ramdisk', ...]' returned non-zero exit status 1.
```

## Solution

Install `qemu-utils` which contains `qemu-img`:

```bash
sudo apt-get update
sudo apt-get install -y qemu-utils
```

## Verify Installation

```bash
which qemu-img
qemu-img --version
```

## Complete Prerequisites Check

To ensure all prerequisites are installed:

```bash
sudo apt-get update
sudo apt-get install -y \
    python3-pip \
    python3-dev \
    git \
    qemu-utils \
    kpartx \
    debootstrap \
    squashfs-tools \
    dosfstools \
    curl

pip3 install --user diskimage-builder ironic-python-agent-builder
export PATH=$PATH:$HOME/.local/bin
```

## Then Re-run Build

After installing qemu-utils:

```bash
export PATH=$PATH:$HOME/.local/bin
./script.sh
```

