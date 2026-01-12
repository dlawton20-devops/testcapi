# SL-Micro VM Status

## VM is Starting

The SL-Micro VM has been launched with the following configuration:

- **Image**: `images/SL-Micro.x86_64-6.2-Default-GM.qcow2` (20GB)
- **Memory**: 2GB RAM
- **CPUs**: 2 cores
- **Network**: NAT with SSH port forwarding (host:2222 → guest:22)

## Accessing the VM

### 1. QEMU Window
A QEMU window should open showing the VM console. You can interact with it directly.

### 2. SSH Access (after boot completes)
Once the VM has finished booting (usually 30-60 seconds), you can SSH into it:

```bash
ssh root@localhost -p 2222
```

**Note**: You may need to know the root password. If this is a fresh install, check the SUSE documentation for default credentials, or use the QEMU console window to set up the password.

### 3. Check VM Status
To see if the VM is running:
```bash
ps aux | grep qemu | grep sl-micro
```

To check if SSH is ready:
```bash
lsof -i :2222
```

## Stopping the VM

To stop the VM, you can:
1. Shut down from within the VM: `sudo shutdown -h now`
2. Or find and kill the QEMU process: `pkill -f "qemu.*sl-micro"`

## Next Steps

Once the VM is running and accessible:

1. **Verify podman is installed**:
   ```bash
   podman --version
   ```

2. **Set up Edge Image Builder** (if needed):
   - The VM should have podman pre-installed (Default image)
   - You can pull EIB images and prepare downstream cluster images

3. **Configure proxy** (if you had RPM issues):
   ```bash
   ./scripts/configure-proxy.sh
   ```

## Troubleshooting

- **No QEMU window appears**: Check if QEMU is running with `ps aux | grep qemu`
- **SSH connection refused**: The VM may still be booting, wait a bit longer
- **Can't find VM process**: The background process may have exited, try running `./scripts/run-vm.sh` in a terminal


