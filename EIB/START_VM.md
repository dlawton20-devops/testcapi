# Starting the SL-Micro VM

## Quick Start

The SL-Micro image has been prepared and is ready to run. To start the VM, run:

```bash
./scripts/start-vm.sh
```

This will:
- Open a QEMU window showing the VM console
- Start the VM with 2GB RAM, 2 CPUs
- Enable SSH access on `localhost:2222`

## What's Been Set Up

✅ **Image prepared**: `images/SL-Micro.x86_64-6.2-Default-GM.qcow2` (20GB)
✅ **QEMU installed**: Version 9.2.3
✅ **Scripts ready**: All helper scripts are in place

## Accessing the VM

### During Boot
- Watch the QEMU window to see the boot process
- The VM will boot into SL-Micro

### After Boot (SSH)
Once the VM has finished booting (30-60 seconds), connect via SSH:

```bash
ssh root@localhost -p 2222
```

**Note**: You may need to set/confirm the root password. Use the QEMU console if needed.

### Releasing Mouse/Keyboard
If your mouse/keyboard get captured by QEMU:
- Press `Ctrl+Alt+G` to release them

## Alternative: Run in Background (No GUI)

If you prefer to run without a GUI window, you can use:

```bash
./scripts/run-vm.sh &
```

Then access via SSH only.

## Next Steps After VM is Running

1. **Verify podman** (should be pre-installed in Default image):
   ```bash
   podman --version
   ```

2. **Set up Edge Image Builder**:
   ```bash
   # From your Mac (not in VM)
   ./scripts/setup-eib.sh
   ```

3. **Configure proxy** (if you had RPM issues):
   - Inside VM: Use the console or SSH to configure proxy settings
   - See `scripts/configure-proxy.sh` for guidance

## Stopping the VM

- From inside VM: `sudo shutdown -h now`
- From Mac: `pkill -f "qemu.*sl-micro"` or close the QEMU window


