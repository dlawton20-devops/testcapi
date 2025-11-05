# Integrating with Existing Rancher Cluster

This guide explains how to integrate the Metal3 dev environment (OpenStack VM with libvirt VMs) with your existing 3-node RKE2 Rancher cluster that already has Metal3 and Turtles installed.

## 🎯 Overview

Your existing setup:
- ✅ 3-node RKE2 Rancher cluster
- ✅ Metal3 installed
- ✅ Rancher Turtles installed

What we're adding:
- ✅ OpenStack VM with libvirt VMs (simulated bare metal hosts)
- ✅ BMC access from Rancher cluster
- ✅ BareMetalHost resources in Rancher

## 📋 Prerequisites

1. **Rancher cluster** is running and accessible
2. **Metal3** is installed and working
3. **Network connectivity** between Rancher cluster and OpenStack VM
4. **OpenStack VM** is set up with libvirt VMs (see COMPLETE-SETUP-GUIDE.md)

## 🔧 Integration Steps

### Step 1: Verify Metal3 in Rancher Cluster

```bash
# From your Rancher cluster
kubectl get pods -n metal3-system
kubectl get bmh -A

# Check Metal3/Ironic is running
kubectl get svc -n metal3-system | grep ironic
```

### Step 2: Get BMC Information from OpenStack VM

```bash
# Set VM IP
export VM_IP="192.168.1.100"

# Get BMC addresses and MAC addresses
cd metal3-openstack-dev-env
./scripts/get-bmh-config.sh
```

This will output:
- MAC addresses for each libvirt VM
- BMC addresses (IPMI or Redfish)
- Sample BareMetalHost YAML

### Step 3: Create BMC Credentials in Rancher

```bash
# From your Rancher cluster
kubectl create secret generic bmc-credentials \
  --from-literal=username=admin \
  --from-literal=password=password \
  --namespace default

# Verify
kubectl get secret bmc-credentials -n default
```

### Step 4: Create BareMetalHost Resources

```bash
# From your Rancher cluster
# Use the output from get-bmh-config.sh

export VM_IP="192.168.1.100"  # Your OpenStack VM IP

# Get MAC addresses (adjust as needed)
NODE_0_MAC="00:ee:d0:b8:47:7d"  # From get-bmh-config.sh output
NODE_1_MAC="00:ee:d0:b8:47:7e"  # From get-bmh-config.sh output
NODE_2_MAC="00:ee:d0:b8:47:7f"  # From get-bmh-config.sh output

# Create BareMetalHost for node-0
kubectl apply -f - <<EOF
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-0
  namespace: default
spec:
  online: true
  bootMACAddress: ${NODE_0_MAC}
  bmc:
    address: ipmi://${VM_IP}:6230
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

# Create BareMetalHost for node-1
kubectl apply -f - <<EOF
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-1
  namespace: default
spec:
  online: true
  bootMACAddress: ${NODE_1_MAC}
  bmc:
    address: ipmi://${VM_IP}:6231
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

# Create BareMetalHost for node-2
kubectl apply -f - <<EOF
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: node-2
  namespace: default
spec:
  online: true
  bootMACAddress: ${NODE_2_MAC}
  bmc:
    address: ipmi://${VM_IP}:6232
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

### Step 5: Monitor BareMetalHost Status

```bash
# From Rancher cluster
kubectl get bmh -w

# Check detailed status
kubectl describe bmh node-0

# Check in Rancher UI
# Navigate to: Cluster → Resources → BareMetalHosts
```

### Step 6: Verify Metal3 Can Access BMCs

```bash
# From Rancher cluster, test BMC access
# Test IPMI from a pod
kubectl run -it --rm test-ipmi \
  --image=quay.io/metalkube/vbmc:latest \
  --restart=Never \
  -- ipmitool -I lanplus -U admin -P password -H ${VM_IP} -p 6230 power status

# Check Metal3/Ironic logs
kubectl logs -n metal3-system -l app.kubernetes.io/name=metal3-ironic | tail -50
```

## 🔍 Troubleshooting

### BareMetalHost Stuck in Registering

```bash
# Check BMC connectivity
kubectl describe bmh node-0 | grep -A 10 "Error\|Status"

# Check Metal3 operator logs
kubectl logs -n metal3-system -l app.kubernetes.io/name=metal3-baremetal-operator | grep node-0

# Test BMC from Rancher cluster
kubectl run -it --rm test-bmc \
  --image=nicolaka/netshoot \
  --restart=Never \
  -- nc -zv ${VM_IP} 6230
```

### Metal3 Cannot Access BMC

```bash
# Verify security groups
openstack security group rule list default | grep -E '6230|6231|6232'

# Check firewall on VM
ssh ubuntu@${VM_IP} "sudo ufw status"

# Check virtual BMC is running
ssh ubuntu@${VM_IP} "vbmc list"
```

### Network Connectivity Issues

See `docs/NETWORK-CONFIGURATION.md` for detailed network troubleshooting.

## 📝 Summary

After integration:

1. ✅ **BareMetalHost resources** created in Rancher cluster
2. ✅ **Metal3** can access BMCs on OpenStack VM
3. ✅ **libvirt VMs** are managed as bare metal hosts
4. ✅ **Provisioning** works via Metal3/Ironic

Your Rancher cluster can now provision and manage the simulated bare metal hosts!

