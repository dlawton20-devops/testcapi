# Manual IPA Ramdisk Build Instructions

## Quick Start

1. **SSH into the VM:**
   ```bash
   multipass shell ipa-builder
   ```

2. **Run the build script:**
   ```bash
   cd ~
   ./build-ipa-manual.sh focal
   ```

   This will:
   - Create the build directory (`~/ipa-build`)
   - Set up the network configuration element
   - Fix the pip version requirement (25.1.1 → 25.0.1)
   - Build the IPA ramdisk (takes 10-20 minutes)

3. **Monitor progress:**
   The build will output progress to the terminal. You'll see:
   - Package downloads
   - Installation steps
   - Final output files: `ipa-ramdisk.kernel` and `ipa-ramdisk.initramfs`

4. **When complete, copy files back to your Mac:**
   ```bash
   # Exit the VM (Ctrl+D or 'exit')
   # Then on your Mac:
   multipass transfer ipa-builder:~/ipa-build/ipa-ramdisk.* ./
   ```

## Alternative: Run from macOS (without SSH)

You can also run it directly from your Mac terminal:

```bash
multipass exec ipa-builder -- bash ~/build-ipa-manual.sh focal
```

Or with output logging:

```bash
multipass exec ipa-builder -- bash -c "~/build-ipa-manual.sh focal 2>&1 | tee /tmp/build-manual.log"
```

## Check Build Status

To check if a build is running:
```bash
multipass exec ipa-builder -- ps aux | grep ironic-python-agent-builder
```

To check if build completed:
```bash
multipass exec ipa-builder -- ls -lh ~/ipa-build/ipa-ramdisk.*
```

## Troubleshooting

If the build fails:

1. **Check the error:**
   ```bash
   multipass exec ipa-builder -- tail -50 /tmp/build-manual.log
   ```

2. **Clean and retry:**
   ```bash
   multipass exec ipa-builder -- bash -c "rm -rf ~/ipa-build && ~/build-ipa-manual.sh focal"
   ```

3. **Verify pip version fix:**
   ```bash
   multipass exec ipa-builder -- grep REQUIRED_PIP_STR ~/.local/share/ironic-python-agent-builder/dib/ironic-python-agent-ramdisk/install.d/ironic-python-agent-ramdisk-source-install/60-ironic-python-agent-ramdisk-install
   ```
   Should show: `REQUIRED_PIP_STR="25.0.1"`

## Build Output

When successful, you'll have:
- `ipa-ramdisk.kernel` - The kernel image
- `ipa-ramdisk.initramfs` - The initramfs with IPA and network config

These files are typically 50-100MB total.

