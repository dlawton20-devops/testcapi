# Quick Start: Setup IPA Network Configuration

## Prerequisites

1. **Kubernetes cluster running** with Metal3 installed
2. **kubectl configured** and able to access the cluster
3. **BareMetalHost exists** (metal3-node-0 in metal3-system namespace)

## Quick Setup (Option 1: Interactive)

When your cluster is running, simply run:

```bash
cd "/Users/dave/untitled folder 3/scripts/setup"
./setup-ipa-network-config.sh
```

The script will:
- Prompt you for network configuration
- Create the NetworkData secret
- Update your BareMetalHost

## Quick Setup (Option 2: Pre-configured)

Based on your existing configuration, here's a ready-to-use command:

### For User-Mode Network (10.0.2.x)

If your VM uses the user-mode network (common for libvirt VMs on macOS):

```bash
cd "/Users/dave/untitled folder 3/scripts/setup"
./setup-ipa-network-config.sh \
  --interface eth0 \
  --ip 10.0.2.100 \
  --gateway 10.0.2.2 \
  --mac "52:54:00:f5:26:5e" \
  --skip-build
```

### For Bridge Network (192.168.124.x)

If your VM uses a bridge network:

```bash
cd "/Users/dave/untitled folder 3/scripts/setup"
./setup-ipa-network-config.sh \
  --interface ens3 \
  --ip 192.168.124.100 \
  --gateway 192.168.124.1 \
  --mac "52:54:00:f5:26:5e" \
  --skip-build
```

## Manual Setup (If Script Doesn't Work)

If you prefer to create the secret manually:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: provisioning-networkdata
  namespace: metal3-system
type: Opaque
stringData:
  networkData: |
    interfaces:
    - name: eth0
      type: ethernet
      state: up
      mac-address: "52:54:00:f5:26:5e"
      ipv4:
        address:
        - ip: 10.0.2.100
          prefix-length: 24
        enabled: true
        dhcp: false
    dns-resolver:
      config:
        server:
        - 8.8.8.8
    routes:
      config:
      - destination: 0.0.0.0/0
        next-hop-address: 10.0.2.2
        next-hop-interface: eth0
EOF
```

Then verify your BareMetalHost references it:

```bash
kubectl get baremetalhost metal3-node-0 -n metal3-system -o yaml | grep preprovisioningNetworkDataName
```

If it's not set, update it:

```bash
kubectl patch baremetalhost metal3-node-0 -n metal3-system --type merge -p '{
  "spec": {
    "preprovisioningNetworkDataName": "provisioning-networkdata"
  }
}'
```

## Verify Setup

1. **Check the secret exists:**
   ```bash
   kubectl get secret provisioning-networkdata -n metal3-system
   ```

2. **Check BareMetalHost references it:**
   ```bash
   kubectl get baremetalhost metal3-node-0 -n metal3-system -o jsonpath='{.spec.preprovisioningNetworkDataName}'
   ```
   Should output: `provisioning-networkdata`

3. **View the network configuration:**
   ```bash
   kubectl get secret provisioning-networkdata -n metal3-system -o jsonpath='{.data.networkData}' | base64 -d
   ```

## What Happens Next

1. When IPA boots, Metal3 will:
   - Read the `provisioning-networkdata` secret
   - Create a config drive (ISO with label `config-2`)
   - Attach it to the VM

2. IPA will:
   - Boot and run `configure-network.service`
   - Find the config drive
   - Read `network_data.json`
   - Apply the static IP configuration

3. IPA will have network connectivity and can communicate with Ironic

## Troubleshooting

### Cluster Not Accessible

If you see "connection refused" errors:

1. **Start your Kubernetes cluster** (e.g., minikube, kind, or your cloud cluster)
2. **Verify kubectl context:**
   ```bash
   kubectl config current-context
   kubectl cluster-info
   ```

### Secret Already Exists

If the secret already exists and you want to update it:

```bash
kubectl delete secret provisioning-networkdata -n metal3-system
# Then run the setup script again
```

### Wrong Network Configuration

To update the network configuration:

1. Delete the existing secret
2. Run the setup script again with correct values
3. Or manually edit:
   ```bash
   kubectl edit secret provisioning-networkdata -n metal3-system
   ```

## Next Steps

After setting up the network configuration:

1. **Ensure custom IPA ramdisk is built** (if not already done)
2. **Configure Ironic to use custom IPA** (if using custom ramdisk)
3. **Start port forwarding** (if needed for your setup)
4. **Provision your BareMetalHost**

See the main documentation:
- `docs/ipa/HOW_IPA_NETWORK_CONFIG_WORKS.md` - How it works
- `docs/ipa/BUILD_IPA_RAMDISK_MANUAL.md` - Building IPA ramdisk
- `docs/ipa/BUILD_IPA_RAMDISK_QUICK_REF.md` - Quick reference

