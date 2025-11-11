# IPMI vs Redfish for BareMetalHost

This document explains the difference between IPMI and Redfish, and how to use each in BareMetalHost resources.

## 🔄 IPMI vs Redfish

### IPMI (Intelligent Platform Management Interface)

- **Protocol**: Traditional BMC protocol
- **Address Format**: `ipmi://<host>:<port>`
- **Port**: Typically 623 (or 6230-6232 in our setup)
- **Simulator**: virtualbmc
- **Pros**: Simple, widely supported
- **Cons**: Older protocol, less features

### Redfish

- **Protocol**: Modern REST-based API (DMTF standard)
- **Address Format**: `redfish+http://<host>:<port>/redfish/v1/Systems/<system-id>` or `redfish+https://...`
- **Port**: Typically 8000 (or 8000-8002 in our setup)
- **Simulator**: sushy-tools (sushy emulator)
- **Pros**: Modern, REST API, more features, better for automation
- **Cons**: Requires system ID lookup

## 📋 Current Setup: IPMI (Default)

The current documentation uses **IPMI** with virtualbmc:

```yaml
bmc:
  address: ipmi://192.168.1.100:6230
  credentialsName: bmc-credentials
```

**Setup:**
- virtualbmc running on ports 6230, 6231, 6232
- One virtual BMC per libvirt VM

## 📋 Alternative: Redfish Setup

To use **Redfish** instead of IPMI:

### Step 1: Setup Redfish Simulator

```bash
# On OpenStack VM
# Install sushy-tools
sudo pip3 install sushy-tools

# Create systemd service
sudo tee /etc/systemd/system/sushy-emulator.service <<'EOF'
[Unit]
Description=Sushy Redfish Emulator
After=network.target libvirtd.service

[Service]
Type=simple
User=ubuntu
Environment="SUSHY_EMULATOR_LISTEN_IP=0.0.0.0"
Environment="SUSHY_EMULATOR_LISTEN_PORT=8000"
Environment="SUSHY_EMULATOR_OS_CLOUD=metal3"
Environment="SUSHY_EMULATOR_LIBVIRT_URI=qemu:///system"
ExecStart=/usr/local/bin/sushy-emulator
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Start service
sudo systemctl daemon-reload
sudo systemctl enable sushy-emulator
sudo systemctl start sushy-emulator

# Verify
curl http://localhost:8000/redfish/v1/
```

### Step 2: Get System IDs

There are several ways to get the Redfish system ID for each libvirt VM:

#### Method 1: From Redfish API (Recommended)

```bash
# On OpenStack VM, query Redfish endpoint
curl http://localhost:8000/redfish/v1/Systems

# Output example:
# {
#   "Members": [
#     {
#       "@odata.id": "/redfish/v1/Systems/492fcbab-4a79-40d7-8fea-a7835a05ef4a"
#     },
#     {
#       "@odata.id": "/redfish/v1/Systems/882533c5-2f14-49f6-aa44-517e1e404fd8"
#     }
#   ]
# }

# Extract system IDs (if you have jq installed)
curl -s http://localhost:8000/redfish/v1/Systems | jq -r '.Members[].@odata.id' | sed 's|/redfish/v1/Systems/||'

# Or manually extract from the output
# System ID is the UUID after "/redfish/v1/Systems/"
```

#### Method 2: From libvirt VM UUID (Easier)

Sushy emulator uses libvirt VM UUIDs as system IDs:

```bash
# On OpenStack VM, get UUID for each VM
sudo virsh dominfo node-0 | grep UUID
# Output: UUID:           492fcbab-4a79-40d7-8fea-a7835a05ef4a

sudo virsh dominfo node-1 | grep UUID
# Output: UUID:           882533c5-2f14-49f6-aa44-517e1e404fd8

sudo virsh dominfo node-2 | grep UUID
# Output: UUID:           a1b2c3d4-e5f6-7890-abcd-ef1234567890

# Extract just the UUID
NODE_0_UUID=$(sudo virsh dominfo node-0 | grep UUID | awk '{print $2}')
NODE_1_UUID=$(sudo virsh dominfo node-1 | grep UUID | awk '{print $2}')
NODE_2_UUID=$(sudo virsh dominfo node-2 | grep UUID | awk '{print $2}')

echo "Node-0 System ID: $NODE_0_UUID"
echo "Node-1 System ID: $NODE_1_UUID"
echo "Node-2 System ID: $NODE_2_UUID"
```

#### Method 3: Match by VM Name

If you need to match system IDs to VM names:

```bash
# Get all system IDs and their corresponding VM info
for vm in node-0 node-1 node-2; do
    UUID=$(sudo virsh dominfo $vm | grep UUID | awk '{print $2}')
    echo "$vm UUID: $UUID"
    
    # Verify it exists in Redfish
    curl -s http://localhost:8000/redfish/v1/Systems/$UUID | jq -r '.Name // .Id' || echo "Not found in Redfish"
done
```

#### Method 4: One-liner to Get All System IDs

```bash
# On OpenStack VM, get all system IDs at once
for vm in node-0 node-1 node-2; do
    UUID=$(sudo virsh dominfo $vm | grep UUID | awk '{print $2}')
    echo "export ${vm^^}_SYSTEM_ID=\"$UUID\""
done

# Output:
# export NODE-0_SYSTEM_ID="492fcbab-4a79-40d7-8fea-a7835a05ef4a"
# export NODE-1_SYSTEM_ID="882533c5-2f14-49f6-aa44-517e1e404fd8"
# export NODE-2_SYSTEM_ID="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
```

### Step 3: Create BareMetalHost with Redfish

```bash
# From Rancher cluster
export VM_IP="192.168.1.100"  # Your OpenStack VM IP
export NODE_0_SYSTEM_ID="492fcbab-4a79-40d7-8fea-a7835a05ef4a"  # From Step 2

kubectl apply -f - <<EOF
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-0
  namespace: default
spec:
  online: true
  bootMACAddress: $(ssh ubuntu@${VM_IP} "sudo virsh domiflist node-0 | grep metal3 | awk '{print \$5}'")
  bmc:
    address: redfish+http://${VM_IP}:8000/redfish/v1/Systems/${NODE_0_SYSTEM_ID}
    credentialsName: bmc-credentials
    disableCertificateVerification: true
  bootMode: legacy
  automatedCleaningMode: metadata
  image:
    url: http://imagecache.example.com/ubuntu-22.04.raw
    checksum: http://imagecache.example.com/ubuntu-22.04.raw.sha256
    checksumType: sha256
    format: raw
EOF
```

## 🔍 Key Differences in BareMetalHost

### IPMI Configuration

```yaml
bmc:
  address: ipmi://192.168.1.100:6230
  credentialsName: bmc-credentials
  disableCertificateVerification: true  # Not needed for IPMI, but doesn't hurt
```

**Characteristics:**
- One port per VM (6230, 6231, 6232)
- Simple address format
- No system ID needed

### Redfish Configuration

```yaml
bmc:
  address: redfish+http://192.168.1.100:8000/redfish/v1/Systems/492fcbab-4a79-40d7-8fea-a7835a05ef4a
  credentialsName: bmc-credentials
  disableCertificateVerification: true  # Important for HTTP (not HTTPS)
```

**Characteristics:**
- One endpoint for all VMs (port 8000)
- Requires system ID in path
- Can use HTTP or HTTPS
- More RESTful API

## 📊 Comparison Table

| Feature | IPMI | Redfish |
|---------|------|---------|
| **Protocol** | IPMI | REST API |
| **Address Format** | `ipmi://host:port` | `redfish+http://host:port/redfish/v1/Systems/<id>` |
| **Ports** | 6230, 6231, 6232 (one per VM) | 8000 (shared endpoint) |
| **Simulator** | virtualbmc | sushy-tools |
| **System ID** | Not needed | Required |
| **Complexity** | Simple | More complex |
| **Features** | Basic | Advanced |
| **Standards** | IPMI 2.0 | DMTF Redfish |

## 🎯 Which Should You Use?

### Use IPMI When:
- ✅ You want simplicity
- ✅ You don't need advanced features
- ✅ You're just getting started
- ✅ You want one port per VM

### Use Redfish When:
- ✅ You need modern REST API
- ✅ You want more features
- ✅ You prefer standards-based approach
- ✅ You want a single endpoint for all VMs

## 📝 Example: Both IPMI and Redfish

You can use both simultaneously:

```bash
# IPMI for node-0
kubectl apply -f - <<EOF
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-0-ipmi
spec:
  bmc:
    address: ipmi://192.168.1.100:6230
EOF

# Redfish for node-1
kubectl apply -f - <<EOF
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-1-redfish
spec:
  bmc:
    address: redfish+http://192.168.1.100:8000/redfish/v1/Systems/<system-id>
EOF
```

## 🔧 Troubleshooting

### IPMI Issues

```bash
# Test IPMI
ipmitool -I lanplus -U admin -P password -H 192.168.1.100 -p 6230 power status

# Check virtual BMC
vbmc list
vbmc show node-0
```

### Redfish Issues

```bash
# Test Redfish endpoint
curl http://192.168.1.100:8000/redfish/v1/

# List systems
curl http://192.168.1.100:8000/redfish/v1/Systems

# Check sushy service
sudo systemctl status sushy-emulator
```

## 📚 Summary

**Current Documentation Uses:**
- ✅ **IPMI** (default) - `ipmi://host:port`
- ✅ Simple setup with virtualbmc
- ✅ One port per VM

**Redfish Alternative:**
- ✅ **Redfish** - `redfish+http://host:port/redfish/v1/Systems/<id>`
- ✅ More complex but more features
- ✅ Single endpoint for all VMs

Both work with Metal3! Choose based on your needs.

