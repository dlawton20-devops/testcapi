# Quick Reference: Building IPA Ramdisk with Static Network Config

## Quick Start

```bash
# 1. Install prerequisites
sudo apt-get update
sudo apt-get install -y python3-pip python3-dev git qemu-utils kpartx debootstrap squashfs-tools dosfstools
sudo pip3 install diskimage-builder ironic-python-agent-builder

# Add pip user bin to PATH if needed
export PATH=$PATH:$HOME/.local/bin

# 2. Run the build script (uses ironic-python-agent-builder)
cd scripts/setup
./build-ipa-ramdisk.sh

# 3. Output files will be in ~/ipa-build/
ls -lh ~/ipa-build/ipa-ramdisk.*
```

## Build Options

```bash
# Use Ubuntu 20.04 (focal)
./build-ipa-ramdisk.sh --release focal

# Custom output directory
./build-ipa-ramdisk.sh --output-dir /tmp/ipa-build

# Skip nmstate (use fallback method)
./build-ipa-ramdisk.sh --no-nmc
```

## NetworkData Secret Format

The secret must use **nmstate format** (not netplan):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: provisioning-networkdata
  namespace: metal3-system
type: Opaque
stringData:
  networkData: |
    interfaces:
    - name: enp1s0
      type: ethernet
      state: up
      mac-address: "00:f3:65:8a:a3:b0"
      ipv4:
        address:
        - ip: 192.168.125.200
          prefix-length: 24
        enabled: true
        dhcp: false
    dns-resolver:
      config:
        server:
        - 192.168.125.1
    routes:
      config:
      - destination: 0.0.0.0/0
        next-hop-address: 192.168.125.1
        next-hop-interface: enp1s0
```

## BareMetalHost Configuration

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-0
  namespace: metal3-system
spec:
  preprovisioningNetworkDataName: provisioning-networkdata  # Reference the secret
  # ... rest of config
```

## How It Works

1. **IPA boots** → systemd starts `configure-network.service`
2. **Script runs** → looks for config drive (label: `config-2`)
3. **Mounts config drive** → reads `network_data.json`
4. **Applies config** → uses nmc (if available) or fallback method
5. **Network configured** → IPA can communicate with Ironic

## Troubleshooting

### Check if config drive exists in IPA:
```bash
# In IPA console
blkid | grep config-2
lsblk
```

### Check service status:
```bash
systemctl status configure-network.service
journalctl -u configure-network.service -n 50
```

### Check network_data.json:
```bash
mount /dev/sr0 /mnt  # or appropriate device
cat /mnt/openstack/latest/network_data.json
```

## Files Created

- `ipa-ramdisk.initramfs` - The ramdisk image
- `ipa-ramdisk.kernel` - The kernel

## Using with Metal3

**Quick Steps**:

1. **Copy to web server**:
   ```bash
   sudo cp ~/ipa-build/ipa-ramdisk.* /var/www/html/ipa/
   ```

2. **Update Ironic config**:
   ```bash
   export IPA_SERVER="http://your-server-ip"
   kubectl patch configmap ironic -n metal3-system --type merge -p "{
     \"data\": {
       \"IRONIC_RAMDISK_URL\": \"${IPA_SERVER}/ipa/ipa-ramdisk.initramfs\",
       \"IRONIC_KERNEL_URL\": \"${IPA_SERVER}/ipa/ipa-ramdisk.kernel\"
     }
   }"
   ```

3. **Restart Ironic**:
   ```bash
   kubectl delete pod -n metal3-system -l app.kubernetes.io/component=ironic
   ```

**For detailed instructions**: See [`CONFIGURE_METAL3_CUSTOM_IPA.md`](CONFIGURE_METAL3_CUSTOM_IPA.md)

## Full Documentation

See `docs/ipa/BUILD_IPA_RAMDISK_MANUAL.md` for complete details.

