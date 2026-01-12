# SUSE Linux Micro (SL-Micro) Setup for Mac with Edge Image Builder

This setup helps you run SL-Micro as a VM on your Mac and use Edge Image Builder (EIB) to prepare downstream cluster images.

## Prerequisites

- Podman installed (✓ detected)
- QEMU installed (✓ detected)
- SL-Micro image: `SL-Micro.x86_64-6.2-Default-GM.raw.xz`

**Note**: The `.raw.xz` file is for running as a VM. For EIB to prepare downstream cluster images, you may also need the Base ISO image (`SL-Micro*.iso`) from SUSE Customer Center.

## Quick Start

1. **Extract the image** (if not already done):
   ```bash
   ./scripts/extract-image.sh
   ```

2. **Run SL-Micro VM**:
   ```bash
   ./scripts/run-vm.sh
   ```

3. **Set up EIB**:
   ```bash
   ./scripts/setup-eib.sh
   ```

## Directory Structure

```
suse-sl-micro/
├── README.md
├── scripts/
│   ├── extract-image.sh      # Extract raw image from xz
│   ├── run-vm.sh              # Launch SL-Micro VM with QEMU
│   ├── setup-eib.sh           # Set up Edge Image Builder
│   └── configure-proxy.sh     # Configure proxy for RPM
├── eib/
│   └── base-images/           # Place base images here
└── images/                    # Extracted VM images
```

## Proxy Configuration

If you're experiencing RPM issues through a proxy, see `scripts/configure-proxy.sh` for configuration options.

## References

- [Metal3 Quickstart Guide](https://documentation.suse.com/suse-edge/3.3/html/edge/quickstart-metal3.html)
- [Edge Image Builder Documentation](https://documentation.suse.com/suse-edge/3.3/html/edge/edge-image-builder.html)

