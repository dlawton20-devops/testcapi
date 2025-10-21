#!/bin/bash

# Create OpenStack VMs to simulate bare metal nodes for Metal3 testing
# Based on SUSE Edge Metal3 documentation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[METAL3]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[METAL3]${NC} $1"
}

print_error() {
    echo -e "${RED}[METAL3]${NC} $1"
}

# Configuration
CONTROL_PLANE_COUNT=1
WORKER_COUNT=2
FLAVOR="m1.large"
IMAGE="ubuntu-22.04"
SSH_KEY="metal3-key"
NETWORK="private"
SECURITY_GROUP="metal3-baremetal"

print_status "Creating OpenStack VMs to simulate bare metal nodes..."

# Check if OpenStack CLI is available
if ! command -v openstack &> /dev/null; then
    print_error "OpenStack CLI is not installed. Please install it first."
    exit 1
fi

# Check if we can connect to OpenStack
if ! openstack server list &> /dev/null; then
    print_error "Cannot connect to OpenStack. Please check your credentials."
    exit 1
fi

# Create security group for bare metal simulation
print_status "Creating security group for bare metal simulation..."
if ! openstack security group show "$SECURITY_GROUP" &> /dev/null; then
    openstack security group create "$SECURITY_GROUP" \
        --description "Security group for Metal3 bare metal simulation"
    
    # Allow SSH
    openstack security group rule create "$SECURITY_GROUP" \
        --protocol tcp --dst-port 22 --remote-ip 0.0.0.0/0
    
    # Allow HTTP/HTTPS for image serving
    openstack security group rule create "$SECURITY_GROUP" \
        --protocol tcp --dst-port 80 --remote-ip 0.0.0.0/0
    openstack security group rule create "$SECURITY_GROUP" \
        --protocol tcp --dst-port 443 --remote-ip 0.0.0.0/0
    
    # Allow Metal3 Ironic ports
    openstack security group rule create "$SECURITY_GROUP" \
        --protocol tcp --dst-port 6385 --remote-ip 0.0.0.0/0
    openstack security group rule create "$SECURITY_GROUP" \
        --protocol tcp --dst-port 5050 --remote-ip 0.0.0.0/0
    
    # Allow Kubernetes API server
    openstack security group rule create "$SECURITY_GROUP" \
        --protocol tcp --dst-port 6443 --remote-ip 0.0.0.0/0
    
    # Allow NodePort range
    openstack security group rule create "$SECURITY_GROUP" \
        --protocol tcp --dst-port 30000:32767 --remote-ip 0.0.0.0/0
    
    print_success "Security group '$SECURITY_GROUP' created"
else
    print_status "Security group '$SECURITY_GROUP' already exists"
fi

# Create control plane VMs
print_status "Creating control plane VMs..."
for i in $(seq 0 $((CONTROL_PLANE_COUNT-1))); do
    VM_NAME="controlplane-${i}"
    
    if openstack server show "$VM_NAME" &> /dev/null; then
        print_status "VM '$VM_NAME' already exists, skipping..."
        continue
    fi
    
    print_status "Creating VM: $VM_NAME"
    
    # Create user data for bare metal simulation
    cat > "/tmp/${VM_NAME}-userdata.yaml" << EOF
#cloud-config
package_update: true
package_upgrade: true

packages:
  - qemu-kvm
  - libvirt-daemon-system
  - libvirt-clients
  - bridge-utils
  - virt-manager
  - ipxe
  - tftpd-hpa
  - dnsmasq
  - apache2

write_files:
  - path: /etc/netplan/50-cloud-init.yaml
    content: |
      network:
        version: 2
        ethernets:
          eth0:
            dhcp4: true
            dhcp6: false
          eth1:
            dhcp4: false
            dhcp6: false
            addresses:
              - 192.168.1.10${i}/24
        bridges:
          br0:
            interfaces: [eth1]
            dhcp4: false
            dhcp6: false
            addresses:
              - 192.168.1.10${i}/24
            gateway4: 192.168.1.1
            nameservers:
              addresses: [8.8.8.8, 8.8.4.4]

runcmd:
  - systemctl enable libvirtd
  - systemctl start libvirtd
  - systemctl enable apache2
  - systemctl start apache2
  - mkdir -p /var/www/html/images
  - chown -R www-data:www-data /var/www/html/images
  - echo "Bare metal simulation VM ready" > /var/www/html/status

final_message: "Bare metal simulation VM is ready"
EOF
    
    # Create the VM
    openstack server create \
        --flavor "$FLAVOR" \
        --image "$IMAGE" \
        --key-name "$SSH_KEY" \
        --network "$NETWORK" \
        --security-group "$SECURITY_GROUP" \
        --user-data "/tmp/${VM_NAME}-userdata.yaml" \
        --tag "metal3" \
        --tag "control-plane" \
        --tag "baremetal-simulation" \
        "$VM_NAME"
    
    print_success "VM '$VM_NAME' created"
done

# Create worker VMs
print_status "Creating worker VMs..."
for i in $(seq 0 $((WORKER_COUNT-1))); do
    VM_NAME="worker-${i}"
    
    if openstack server show "$VM_NAME" &> /dev/null; then
        print_status "VM '$VM_NAME' already exists, skipping..."
        continue
    fi
    
    print_status "Creating VM: $VM_NAME"
    
    # Create user data for bare metal simulation
    cat > "/tmp/${VM_NAME}-userdata.yaml" << EOF
#cloud-config
package_update: true
package_upgrade: true

packages:
  - qemu-kvm
  - libvirt-daemon-system
  - libvirt-clients
  - bridge-utils
  - virt-manager
  - ipxe
  - tftpd-hpa
  - dnsmasq
  - apache2

write_files:
  - path: /etc/netplan/50-cloud-init.yaml
    content: |
      network:
        version: 2
        ethernets:
          eth0:
            dhcp4: true
            dhcp6: false
          eth1:
            dhcp4: false
            dhcp6: false
            addresses:
              - 192.168.1.20${i}/24
        bridges:
          br0:
            interfaces: [eth1]
            dhcp4: false
            dhcp6: false
            addresses:
              - 192.168.1.20${i}/24
            gateway4: 192.168.1.1
            nameservers:
              addresses: [8.8.8.8, 8.8.4.4]

runcmd:
  - systemctl enable libvirtd
  - systemctl start libvirtd
  - systemctl enable apache2
  - systemctl start apache2
  - mkdir -p /var/www/html/images
  - chown -R www-data:www-data /var/www/html/images
  - echo "Bare metal simulation VM ready" > /var/www/html/status

final_message: "Bare metal simulation VM is ready"
EOF
    
    # Create the VM
    openstack server create \
        --flavor "$FLAVOR" \
        --image "$IMAGE" \
        --key-name "$SSH_KEY" \
        --network "$NETWORK" \
        --security-group "$SECURITY_GROUP" \
        --user-data "/tmp/${VM_NAME}-userdata.yaml" \
        --tag "metal3" \
        --tag "worker" \
        --tag "baremetal-simulation" \
        "$VM_NAME"
    
    print_success "VM '$VM_NAME' created"
done

# Wait for VMs to be ready
print_status "Waiting for VMs to be ready..."
sleep 30

# Get VM IPs and create BareMetalHost resources
print_status "Creating BareMetalHost resources..."

# Create control plane BareMetalHost resources
for i in $(seq 0 $((CONTROL_PLANE_COUNT-1))); do
    VM_NAME="controlplane-${i}"
    VM_IP=$(openstack server show "$VM_NAME" -f value -c addresses | grep -oE '192\.168\.1\.10[0-9]' | head -1)
    
    if [ -z "$VM_IP" ]; then
        print_error "Could not get IP for VM '$VM_NAME'"
        continue
    fi
    
    print_status "Creating BareMetalHost for $VM_NAME (IP: $VM_IP)"
    
    cat > "../baremetal-hosts/${VM_NAME}.yaml" << EOF
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: ${VM_NAME}
  namespace: default
  labels:
    cluster-role: control-plane
    metal3.io/baremetal-host: ${VM_NAME}
spec:
  online: true
  bootMACAddress: 00:00:00:00:00:0${i}
  bmc:
    address: redfish-virtualmedia://${VM_IP}:8000/redfish/v1/Systems/1
    credentialsName: bmc-credentials
    disableCertificateVerification: true
  bootMode: UEFI
  automatedCleaningMode: metadata
  preprovisioningNetworkDataName: network-data
  networkData:
    name: network-data
  image:
    url: http://imagecache.local:8080/SLE-Micro-eib-output.raw
    checksum: http://imagecache.local:8080/SLE-Micro-eib-output.raw.sha256
    checksumType: sha256
    format: raw
  hardwareProfile: unknown
EOF
    
    print_success "BareMetalHost resource created for $VM_NAME"
done

# Create worker BareMetalHost resources
for i in $(seq 0 $((WORKER_COUNT-1))); do
    VM_NAME="worker-${i}"
    VM_IP=$(openstack server show "$VM_NAME" -f value -c addresses | grep -oE '192\.168\.1\.20[0-9]' | head -1)
    
    if [ -z "$VM_IP" ]; then
        print_error "Could not get IP for VM '$VM_NAME'"
        continue
    fi
    
    print_status "Creating BareMetalHost for $VM_NAME (IP: $VM_IP)"
    
    cat > "../baremetal-hosts/${VM_NAME}.yaml" << EOF
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: ${VM_NAME}
  namespace: default
  labels:
    cluster-role: worker
    metal3.io/baremetal-host: ${VM_NAME}
spec:
  online: true
  bootMACAddress: 00:00:00:00:00:1${i}
  bmc:
    address: redfish-virtualmedia://${VM_IP}:8000/redfish/v1/Systems/1
    credentialsName: bmc-credentials
    disableCertificateVerification: true
  bootMode: UEFI
  automatedCleaningMode: metadata
  preprovisioningNetworkDataName: network-data
  networkData:
    name: network-data
  image:
    url: http://imagecache.local:8080/SLE-Micro-eib-output.raw
    checksum: http://imagecache.local:8080/SLE-Micro-eib-output.raw.sha256
    checksumType: sha256
    format: raw
  hardwareProfile: unknown
EOF
    
    print_success "BareMetalHost resource created for $VM_NAME"
done

# Clean up temporary files
rm -f /tmp/*-userdata.yaml

print_success "Bare metal simulation VMs created successfully!"
print_status ""
print_status "Next steps:"
print_status "1. Apply BareMetalHost resources: kubectl apply -f ../baremetal-hosts/"
print_status "2. Create BMC credentials: kubectl apply -f ../secrets/bmc-credentials.yaml"
print_status "3. Create network data: kubectl apply -f ../secrets/network-data.yaml"
print_status "4. Create RKE2 cluster: kubectl apply -f ../clusters/rke2-metal3-cluster.yaml"
print_status ""
print_status "Useful commands:"
print_status "  kubectl get bmh -w                    # Watch BareMetalHost status"
print_status "  kubectl describe bmh controlplane-0   # Describe BareMetalHost"
print_status "  openstack server list                 # List OpenStack VMs"
