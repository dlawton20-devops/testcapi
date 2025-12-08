# Cloud-Init Usage Examples

Examples of using the IPA build cloud-init script with different virtualization platforms.

## libvirt/virt-manager

### Method 1: Using cloud-localds

```bash
# Create cloud-init seed ISO
cloud-localds /tmp/ipa-build-seed.iso build-ipa-cloudinit.yaml

# Create VM with cloud-init
virt-install \
  --name ipa-builder \
  --ram 4096 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/ipa-builder.qcow2,size=20 \
  --os-variant ubuntu22.04 \
  --network network=default \
  --graphics none \
  --console pty,target_type=serial \
  --cdrom /tmp/ipa-build-seed.iso \
  --location http://archive.ubuntu.com/ubuntu/dists/jammy/main/installer-amd64/ \
  --extra-args "console=ttyS0"
```

### Method 2: Using virt-manager GUI

1. Create new VM in virt-manager
2. Select Ubuntu 22.04 ISO
3. Before finishing, check "Customize configuration before install"
4. Add hardware → Storage → Add new disk
5. Select "CDROM" type
6. Create cloud-init ISO:
   ```bash
   cloud-localds /tmp/ipa-build-seed.iso build-ipa-cloudinit.yaml
   ```
7. Browse to `/tmp/ipa-build-seed.iso` in the disk path
8. Finish and install

## QEMU/KVM (Direct)

```bash
# Create cloud-init ISO
cloud-localds seed.iso build-ipa-cloudinit.yaml

# Run QEMU with cloud-init
qemu-system-x86_64 \
  -name ipa-builder \
  -m 4096 \
  -smp 2 \
  -drive file=ubuntu-22.04-server-cloudimg-amd64.img,format=qcow2 \
  -drive file=seed.iso,format=raw \
  -netdev user,id=net0 \
  -device virtio-net,netdev=net0 \
  -serial stdio
```

## Proxmox

1. Create VM in Proxmox web UI
2. Use Ubuntu 22.04 cloud image
3. Go to VM → Hardware → Add → Cloud-Init Drive
4. Go to VM → Cloud-Init
5. Paste contents of `build-ipa-cloudinit.yaml` into "User" field
6. Start VM
7. SSH in and run: `./build-ipa-ramdisk.sh focal`

## VMware vSphere

1. Create VM with Ubuntu 22.04
2. Install cloud-init:
   ```bash
   sudo apt-get install cloud-init
   ```
3. Create `/etc/cloud/cloud.cfg.d/99-ipa-build.cfg`:
   ```bash
   # Copy contents of build-ipa-cloudinit.yaml
   ```
4. Reboot or run:
   ```bash
   sudo cloud-init init --local
   sudo cloud-init init
   sudo cloud-init modules --mode config
   sudo cloud-init modules --mode final
   ```

## OpenStack

1. Create instance with Ubuntu 22.04 image
2. Use user-data when launching:
   ```bash
   openstack server create \
     --image ubuntu-22.04 \
     --flavor m1.medium \
     --user-data build-ipa-cloudinit.yaml \
     ipa-builder
   ```

## Verification

After VM boots, verify cloud-init ran:

```bash
# Check cloud-init logs
sudo cat /var/log/cloud-init-output.log

# Check if script exists
ls -la ~/build-ipa-ramdisk.sh

# Check if fixes were applied
grep "25.0.1" ~/.local/share/ironic-python-agent-builder/dib/ironic-python-agent-ramdisk/install.d/ironic-python-agent-ramdisk-source-install/60-ironic-python-agent-ramdisk-install
```

## Troubleshooting Cloud-Init

If cloud-init didn't run:

```bash
# Check cloud-init status
sudo cloud-init status

# Re-run cloud-init
sudo cloud-init clean
sudo cloud-init init
sudo cloud-init modules --mode config
sudo cloud-init modules --mode final

# Or manually run the setup
sudo bash -c "$(cat build-ipa-cloudinit.yaml | grep -A 100 'runcmd:')"
```

