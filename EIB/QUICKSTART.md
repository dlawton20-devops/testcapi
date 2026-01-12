# Quick Start Guide

## Step 1: Extract the SL-Micro Image

If you have `SL-Micro.x86_64-6.2-Default-GM.raw.xz` in your Downloads folder:

```bash
./scripts/extract-image.sh
```

This will extract the image to `images/` directory.

## Step 2: Run SL-Micro as a VM

Start the VM using QEMU:

```bash
./scripts/run-vm.sh
```

The VM will:
- Boot with 2GB RAM and 2 CPUs
- Have network access (NAT)
- SSH available on `localhost:2222` after boot

**Default credentials**: Check SUSE documentation for default root password or use the console.

## Step 3: Configure Proxy (if needed)

If you're experiencing RPM issues through a proxy:

### Option A: Configure in the VM
SSH into the VM and run:
```bash
./scripts/configure-proxy.sh
```

### Option B: Configure for EIB (host)
Set environment variables before running EIB:
```bash
export http_proxy=http://proxy.example.com:8080
export https_proxy=http://proxy.example.com:8080
export no_proxy=localhost,127.0.0.1
```

## Step 4: Set Up Edge Image Builder

```bash
./scripts/setup-eib.sh
```

This will:
- Pull the EIB container image
- Create the necessary directory structure

## Step 5: Prepare Downstream Cluster Image

For Metal3 downstream cluster images, you need:

1. **Base ISO image** (not the raw image):
   - Download SL-Micro Base ISO from SUSE Customer Center
   - Place it in `eib/base-images/slemicro.iso`

2. **Run EIB with proxy support** (if needed):
   ```bash
   ./scripts/run-eib-with-proxy.sh
   ```

3. **Or run EIB directly**:
   ```bash
   podman run --rm -v $(pwd)/eib:/config \
     registry.suse.com/edge/3.3/edge-image-builder:1.1.1
   ```

## Troubleshooting

### RPM Proxy Issues

If you're getting RPM errors through a proxy:

1. **In the VM**: Configure proxy for `transactional-update`:
   ```bash
   sudo mkdir -p /etc/systemd/system/transactional-update.service.d/
   sudo tee /etc/systemd/system/transactional-update.service.d/proxy.conf <<EOF
   [Service]
   Environment="http_proxy=http://proxy.example.com:8080"
   Environment="https_proxy=http://proxy.example.com:8080"
   EOF
   sudo systemctl daemon-reload
   ```

2. **For EIB**: Use `run-eib-with-proxy.sh` which passes proxy env vars to the container

### Image Not Found

If scripts can't find your image:
- Check the path in `extract-image.sh`
- Or manually specify the path when prompted

### QEMU Issues on Mac

If QEMU fails to start:
- Ensure you have the latest QEMU: `brew upgrade qemu`
- Try without hardware acceleration (edit `run-vm.sh` to remove `accel=hvf`)

## Next Steps

Once you have your custom image:
- Set up an image cache server (as per Metal3 documentation)
- Configure Metal3 on your management cluster
- Register BareMetalHost resources
- Create downstream clusters

See the [Metal3 Quickstart Guide](https://documentation.suse.com/suse-edge/3.3/html/edge/quickstart-metal3.html) for details.


