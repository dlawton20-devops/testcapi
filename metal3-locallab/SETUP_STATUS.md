# Metal3 Setup Status

## ✅ Completed

1. **Kubernetes Cluster**: kind cluster `metal3-management` created
2. **MetalLB**: Installed from SUSE Edge registry (OCI format)
   - IP Pool: 172.18.255.200-172.18.255.250
   - Status: Running
3. **cert-manager**: Installed (required for Metal3)
4. **Metal3**: Installed from SUSE Edge registry
   - Ironic VIP: 172.18.255.200
   - Status: Pods running
5. **sushy-tools**: Installed and configured
   - Location: ~/metal3-sushy/
   - LaunchAgent: ~/Library/LaunchAgents/com.metal3.sushy-emulator.plist
   - To start: `launchctl load ~/Library/LaunchAgents/com.metal3.sushy-emulator.plist`
6. **Ubuntu Focal Image**: Downloaded (~618MB)

## ⚠️ Pending

1. **Libvirt Bridge Network**: Created but needs sudo to start
   - Network name: `metal3-net`
   - To start: `sudo virsh net-start metal3-net`
   - Alternative: Use default network (needs to be created)

2. **VM Creation**: VM definition created but needs network to start
   - VM name: `metal3-node-0`
   - Image: Ubuntu Focal (20.04)
   - Disk: ~/metal3-images/metal3-node-0.qcow2

3. **BareMetalHost**: Will be created after VM is running

## Next Steps

### 1. Start the libvirt network (requires sudo):

```bash
sudo virsh net-start metal3-net
sudo virsh net-autostart metal3-net
```

Or create and start the default network:

```bash
# Create default network XML
cat > /tmp/default-net.xml <<EOF
<network>
  <name>default</name>
  <uuid>$(uuidgen)</uuid>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='virbr0' stp='on' delay='0'/>
  <mac address='52:54:00:00:00:01'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
EOF

sudo virsh net-define /tmp/default-net.xml
sudo virsh net-autostart default
sudo virsh net-start default
```

### 2. Start sushy-tools:

```bash
launchctl load ~/Library/LaunchAgents/com.metal3.sushy-emulator.plist
```

Or run manually:
```bash
~/metal3-sushy/start-sushy.sh
```

### 3. Create the VM and BareMetalHost:

```bash
./create-baremetal-host.sh
```

## Verification

Check Metal3 status:
```bash
kubectl get pods -n metal3-system
kubectl get svc -n metal3-system
kubectl get bmh -n metal3-system
```

Check sushy-tools:
```bash
curl -u admin:admin http://localhost:8000/redfish/v1/Systems
```

Check libvirt:
```bash
virsh list --all
virsh net-list --all
```

## Troubleshooting

See `./troubleshoot.sh` for a comprehensive health check.

For detailed troubleshooting, see:
https://documentation.suse.com/suse-edge/3.3/html/edge/troubleshooting-directed-network-provisioning.html

