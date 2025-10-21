#!/bin/bash

# Complete Metal3 + CAPI Auto Setup Script
# This script sets up everything from start to finish

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[AUTO-SETUP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[AUTO-SETUP]${NC} $1"
}

print_error() {
    echo -e "${RED}[AUTO-SETUP]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[AUTO-SETUP]${NC} $1"
}

# Configuration
CLUSTER_TYPE=${1:-"kind"}  # "kind" or "rancher"
CLUSTER_NAME="metal3-management"
STATIC_IRONIC_IP="10.0.0.100"
SSH_KEY="~/.ssh/id_rsa"
SSH_USER="ubuntu"

print_status "Starting complete Metal3 + CAPI setup..."
print_status "Cluster type: $CLUSTER_TYPE"
print_status "Cluster name: $CLUSTER_NAME"

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if required tools are installed
    local tools=("kubectl" "clusterctl" "helm" "openstack")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            print_error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    # Check if we can connect to OpenStack
    if ! openstack server list &> /dev/null; then
        print_error "Cannot connect to OpenStack. Please check your credentials."
        exit 1
    fi
    
    print_success "Prerequisites check completed"
}

# Create management cluster
create_management_cluster() {
    if [ "$CLUSTER_TYPE" = "kind" ]; then
        print_status "Creating Kind management cluster..."
        
        # Check if kind is installed
        if ! command -v kind &> /dev/null; then
            print_error "kind is not installed. Please install it first."
            exit 1
        fi
        
        # Create kind cluster
        kind create cluster --name "$CLUSTER_NAME" --config kind-config.yaml
        
        # Verify cluster
        kubectl cluster-info
        kubectl get nodes
        
        print_success "Kind management cluster created"
    else
        print_status "Using existing Rancher cluster..."
        
        # Verify cluster access
        kubectl cluster-info
        kubectl get nodes
        
        print_success "Rancher cluster access verified"
    fi
}

# Install CAPI
install_capi() {
    print_status "Installing CAPI..."
    
    # Install core CAPI
    clusterctl init --core cluster-api:v1.6.0
    
    # Install Metal3 provider
    clusterctl init --infrastructure metal3:v1.6.0
    
    # Wait for CAPI to be ready
    kubectl wait --for=condition=ready pod -l control-plane=controller-manager -n capi-system --timeout=300s
    kubectl wait --for=condition=ready pod -l control-plane=controller-manager -n capm3-system --timeout=300s
    
    print_success "CAPI installation completed"
}

# Install Metal3 dependencies
install_metal3_dependencies() {
    print_status "Installing Metal3 dependencies..."
    
    # Install MetalLB
    helm install metallb oci://registry.suse.com/edge/charts/metallb \
        --namespace metallb-system \
        --create-namespace
    
    # Configure IP pool for Metal3
    kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: ironic-ip-pool
  namespace: metallb-system
spec:
  addresses:
  - ${STATIC_IRONIC_IP}/32
  serviceAllocation:
    priority: 100
    serviceSelectors:
    - matchExpressions:
      - {key: app.kubernetes.io/name, operator: In, values: [metal3-ironic]}
EOF
    
    # Create L2Advertisement
    kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: ironic-ip-pool-l2-adv
  namespace: metallb-system
spec:
  ipAddressPools:
  - ironic-ip-pool
EOF
    
    print_success "Metal3 dependencies installed"
}

# Install Metal3
install_metal3() {
    print_status "Installing Metal3..."
    
    # Install Metal3
    helm install metal3 oci://registry.suse.com/edge/charts/metal3 \
        --namespace metal3-system \
        --create-namespace \
        --set global.ironicIP="$STATIC_IRONIC_IP"
    
    # Wait for Metal3 to be ready
    print_status "Waiting for Metal3 to be ready (this may take a few minutes)..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=baremetal-operator -n metal3-system --timeout=600s
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=metal3-ironic -n metal3-system --timeout=600s
    
    print_success "Metal3 installation completed"
}

# Install Rancher Turtles
install_rancher_turtles() {
    print_status "Installing Rancher Turtles..."
    
    # Create values file
    cat > values.yaml <<EOF
rancherTurtles:
  features:
    embedded-capi:
      disabled: true
    rancher-webhook:
      cleanup: true
EOF
    
    # Install Rancher Turtles
    helm install rancher-turtles oci://registry.suse.com/edge/charts/rancher-turtles \
        --namespace rancher-turtles-system \
        --create-namespace \
        --values values.yaml
    
    # Wait for Rancher Turtles to be ready
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=rancher-turtles -n rancher-turtles-system --timeout=300s
    
    print_success "Rancher Turtles installation completed"
}

# Create OpenStack VMs
create_openstack_vms() {
    print_status "Creating OpenStack VMs for bare metal simulation..."
    
    # Create security group
    if ! openstack security group show metal3-baremetal &> /dev/null; then
        openstack security group create metal3-baremetal \
            --description "Security group for Metal3 bare metal simulation"
        
        # Add security group rules
        openstack security group rule create metal3-baremetal \
            --protocol tcp --dst-port 22 --remote-ip 0.0.0.0/0
        openstack security group rule create metal3-baremetal \
            --protocol tcp --dst-port 80 --remote-ip 0.0.0.0/0
        openstack security group rule create metal3-baremetal \
            --protocol tcp --dst-port 443 --remote-ip 0.0.0.0/0
        openstack security group rule create metal3-baremetal \
            --protocol tcp --dst-port 6385 --remote-ip 0.0.0.0/0
        openstack security group rule create metal3-baremetal \
            --protocol tcp --dst-port 5050 --remote-ip 0.0.0.0/0
        openstack security group rule create metal3-baremetal \
            --protocol tcp --dst-port 6443 --remote-ip 0.0.0.0/0
        openstack security group rule create metal3-baremetal \
            --protocol tcp --dst-port 30000:32767 --remote-ip 0.0.0.0/0
        
        print_success "Security group created"
    else
        print_status "Security group already exists"
    fi
    
    # Create VMs
    local vm_names=("controlplane-0" "worker-0" "worker-1")
    local vm_flavors=("m1.large" "m1.medium" "m1.medium")
    
    for i in "${!vm_names[@]}"; do
        local vm_name="${vm_names[$i]}"
        local vm_flavor="${vm_flavors[$i]}"
        
        if openstack server show "$vm_name" &> /dev/null; then
            print_status "VM '$vm_name' already exists, skipping..."
            continue
        fi
        
        print_status "Creating VM: $vm_name"
        
        openstack server create \
            --flavor "$vm_flavor" \
            --image ubuntu-22.04 \
            --key-name your-ssh-key \
            --network private \
            --security-group metal3-baremetal \
            --tag metal3 \
            --tag baremetal-simulation \
            "$vm_name"
        
        print_success "VM '$vm_name' created"
    done
    
    print_success "OpenStack VMs created"
}

# Setup OOB simulation
setup_oob_simulation() {
    print_status "Setting up OOB simulation on VMs..."
    
    local vm_names=("controlplane-0" "worker-0" "worker-1")
    
    for vm_name in "${vm_names[@]}"; do
        print_status "Setting up OOB simulation on $vm_name..."
        
        # Get VM IP
        local vm_ip=$(openstack server show "$vm_name" -f value -c addresses | grep -oE '192\.168\.1\.[0-9]+' | head -1)
        
        if [ -z "$vm_ip" ]; then
            print_error "Could not get IP for VM '$vm_name'"
            continue
        fi
        
        print_status "VM $vm_name IP: $vm_ip"
        
        # Wait for VM to be ready
        print_status "Waiting for VM $vm_name to be ready..."
        local max_attempts=30
        local attempt=0
        
        while [ $attempt -lt $max_attempts ]; do
            if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$SSH_USER@$vm_ip" "echo 'VM ready'" &> /dev/null; then
                break
            fi
            print_status "Waiting for VM $vm_name to be ready... (attempt $((attempt+1))/$max_attempts)"
            sleep 10
            ((attempt++))
        done
        
        if [ $attempt -eq $max_attempts ]; then
            print_error "VM $vm_name is not ready after $max_attempts attempts"
            continue
        fi
        
        # Setup OOB simulation
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$vm_ip" << 'EOF'
            # Update system
            sudo apt update
            sudo apt upgrade -y
            
            # Install Python dependencies
            sudo apt install -y python3 python3-pip
            
            # Create redfish simulator directory
            sudo mkdir -p /opt/redfish-simulator
            cd /opt/redfish-simulator
            
            # Create redfish simulator script
            sudo tee redfish-simulator.py << 'PYTHON_EOF'
#!/usr/bin/env python3
import http.server
import socketserver
import json
import os
import subprocess
from urllib.parse import urlparse, parse_qs

class RedfishSimulator(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/redfish/v1/':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = {
                "@odata.context": "/redfish/v1/$metadata#ServiceRoot.ServiceRoot",
                "@odata.id": "/redfish/v1/",
                "@odata.type": "#ServiceRoot.v1_5_0.ServiceRoot",
                "Id": "RootService",
                "Name": "Root Service",
                "Systems": {"@odata.id": "/redfish/v1/Systems"},
                "Managers": {"@odata.id": "/redfish/v1/Managers"}
            }
            self.wfile.write(json.dumps(response).encode())
        
        elif self.path == '/redfish/v1/Systems/1':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = {
                "@odata.context": "/redfish/v1/$metadata#ComputerSystem.ComputerSystem",
                "@odata.id": "/redfish/v1/Systems/1",
                "@odata.type": "#ComputerSystem.v1_15_0.ComputerSystem",
                "Id": "1",
                "Name": "System",
                "PowerState": "On",
                "Boot": {
                    "BootSourceOverrideEnabled": "Once",
                    "BootSourceOverrideTarget": "Cd",
                    "BootSourceOverrideMode": "UEFI"
                },
                "Processors": {
                    "Count": 8,
                    "Model": "Intel Xeon E5-2680 v4"
                },
                "Memory": {
                    "TotalSystemMemoryGiB": 64
                },
                "Storage": {
                    "Drives": [
                        {
                            "CapacityBytes": 1000000000000,
                            "MediaType": "SSD"
                        }
                    ]
                }
            }
            self.wfile.write(json.dumps(response).encode())
        
        elif self.path == '/redfish/v1/Systems/1/VirtualMedia/1':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = {
                "@odata.context": "/redfish/v1/$metadata#VirtualMedia.VirtualMedia",
                "@odata.id": "/redfish/v1/Systems/1/VirtualMedia/1",
                "@odata.type": "#VirtualMedia.v1_4_0.VirtualMedia",
                "Id": "1",
                "Name": "Virtual Media",
                "Image": "",
                "Inserted": False,
                "WriteProtected": True
            }
            self.wfile.write(json.dumps(response).encode())
        
        else:
            self.send_response(404)
            self.end_headers()
    
    def do_POST(self):
        if self.path == '/redfish/v1/Systems/1/Actions/ComputerSystem.Reset':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = {"Status": "Success"}
            self.wfile.write(json.dumps(response).encode())
        
        elif self.path == '/redfish/v1/Systems/1/VirtualMedia/1/Actions/VirtualMedia.InsertMedia':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            response = {"Status": "Success"}
            self.wfile.write(json.dumps(response).encode())
        
        else:
            self.send_response(404)
            self.end_headers()

if __name__ == "__main__":
    PORT = 8000
    with socketserver.TCPServer(("", PORT), RedfishSimulator) as httpd:
        print(f"Redfish Simulator running on port {PORT}")
        httpd.serve_forever()
PYTHON_EOF
            
            # Make script executable
            sudo chmod +x redfish-simulator.py
            
            # Create systemd service
            sudo tee /etc/systemd/system/redfish-simulator.service << 'SERVICE_EOF'
[Unit]
Description=Redfish Simulator
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /opt/redfish-simulator/redfish-simulator.py
Restart=always
RestartSec=5
WorkingDirectory=/opt/redfish-simulator

[Install]
WantedBy=multi-user.target
SERVICE_EOF
            
            # Enable and start service
            sudo systemctl daemon-reload
            sudo systemctl enable redfish-simulator
            sudo systemctl start redfish-simulator
            
            # Wait for service to start
            sleep 5
            
            # Verify service is running
            if sudo systemctl is-active --quiet redfish-simulator; then
                echo "Redfish simulator is running"
            else
                echo "Failed to start redfish simulator"
                sudo systemctl status redfish-simulator
                exit 1
            fi
            
            # Test redfish endpoint
            if curl -s http://localhost:8000/redfish/v1/ | grep -q "RootService"; then
                echo "Redfish endpoint is responding"
            else
                echo "Redfish endpoint is not responding"
                exit 1
            fi
            
            echo "OOB simulation setup complete on $(hostname)"
EOF
        
        if [ $? -eq 0 ]; then
            print_success "OOB simulation setup complete on $vm_name"
        else
            print_error "Failed to setup OOB simulation on $vm_name"
        fi
    done
    
    print_success "OOB simulation setup completed"
}

# Create BMC credentials and network data
create_credentials() {
    print_status "Creating BMC credentials and network data..."
    
    # Create BMC credentials secret
    kubectl create secret generic bmc-credentials \
        --from-literal=username=admin \
        --from-literal=password=password \
        --namespace default \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Create network data secret
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: network-data
  namespace: default
type: Opaque
stringData:
  networkData: |
    version: 1
    config:
      - type: physical
        name: eth0
        subnets:
          - type: dhcp
      - type: physical
        name: eth1
        subnets:
          - type: static
            address: 192.168.1.10/24
            gateway: 192.168.1.1
            dns_nameservers:
              - 8.8.8.8
              - 8.8.4.4
EOF
    
    print_success "Credentials and network data created"
}

# Create BareMetalHost resources
create_baremetal_hosts() {
    print_status "Creating BareMetalHost resources..."
    
    # Get VM IPs
    local control_plane_ip=$(openstack server show controlplane-0 -f value -c addresses | grep -oE '192\.168\.1\.[0-9]+' | head -1)
    local worker_0_ip=$(openstack server show worker-0 -f value -c addresses | grep -oE '192\.168\.1\.[0-9]+' | head -1)
    local worker_1_ip=$(openstack server show worker-1 -f value -c addresses | grep -oE '192\.168\.1\.[0-9]+' | head -1)
    
    print_status "Control Plane IP: $control_plane_ip"
    print_status "Worker 0 IP: $worker_0_ip"
    print_status "Worker 1 IP: $worker_1_ip"
    
    # Create control plane BareMetalHost
    kubectl apply -f - <<EOF
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: controlplane-0
  namespace: default
  labels:
    cluster-role: control-plane
spec:
  online: true
  bootMACAddress: 00:00:00:00:00:00
  bmc:
    address: redfish-virtualmedia://${control_plane_ip}:8000/redfish/v1/Systems/1
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
    
    # Create worker BareMetalHosts
    kubectl apply -f - <<EOF
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: worker-0
  namespace: default
  labels:
    cluster-role: worker
spec:
  online: true
  bootMACAddress: 00:00:00:00:00:01
  bmc:
    address: redfish-virtualmedia://${worker_0_ip}:8000/redfish/v1/Systems/1
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
---
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: worker-1
  namespace: default
  labels:
    cluster-role: worker
spec:
  online: true
  bootMACAddress: 00:00:00:00:00:02
  bmc:
    address: redfish-virtualmedia://${worker_1_ip}:8000/redfish/v1/Systems/1
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
    
    print_success "BareMetalHost resources created"
}

# Create RKE2 cluster
create_rke2_cluster() {
    print_status "Creating RKE2 cluster with Metal3..."
    
    kubectl apply -f - <<EOF
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: sample-cluster
  namespace: default
spec:
  clusterNetwork:
    pods:
      cidrBlocks: ["10.244.0.0/16"]
    services:
      cidrBlocks: ["10.96.0.0/12"]
    serviceDomain: "cluster.local"
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: RKE2ControlPlane
    name: sample-cluster-control-plane
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: Metal3Cluster
    name: sample-cluster
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3Cluster
metadata:
  name: sample-cluster
  namespace: default
spec: {}
---
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: RKE2ControlPlane
metadata:
  name: sample-cluster-control-plane
  namespace: default
spec:
  replicas: 1
  version: "v1.28.5+rke2r1"
  serverConfig:
    tls-san:
      - "sample-cluster.example.com"
    cluster-cidr: "10.244.0.0/16"
    service-cidr: "10.96.0.0/12"
  machineTemplate:
    infrastructureRef:
      apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
      kind: Metal3MachineTemplate
      name: sample-cluster-control-plane
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3MachineTemplate
metadata:
  name: sample-cluster-control-plane
  namespace: default
spec:
  template:
    spec:
      dataTemplate:
        name: sample-cluster-control-plane-template
      hostSelector:
        matchLabels:
          cluster-role: control-plane
      image:
        checksum: http://imagecache.local:8080/SLE-Micro-eib-output.raw.sha256
        checksumType: sha256
        format: raw
        url: http://imagecache.local:8080/SLE-Micro-eib-output.raw
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3DataTemplate
metadata:
  name: sample-cluster-control-plane-template
  namespace: default
spec:
  clusterName: sample-cluster
  metaData:
    objectNames:
      - key: name
        object: machine
      - key: local-hostname
        object: machine
      - key: local_hostname
        object: machine
  networkData:
    objectNames:
      - key: name
        object: machine
      - key: local-hostname
        object: machine
      - key: local_hostname
        object: machine
EOF
    
    print_success "RKE2 cluster created"
}

# Main execution
main() {
    print_status "Starting complete Metal3 + CAPI setup..."
    
    check_prerequisites
    create_management_cluster
    install_capi
    install_metal3_dependencies
    install_metal3
    install_rancher_turtles
    create_openstack_vms
    setup_oob_simulation
    create_credentials
    create_baremetal_hosts
    create_rke2_cluster
    
    print_success "Complete Metal3 + CAPI setup finished!"
    print_status ""
    print_status "🎉 Setup completed successfully!"
    print_status ""
    print_status "Next steps:"
    print_status "1. Monitor cluster creation: kubectl get clusters -w"
    print_status "2. Check BareMetalHost status: kubectl get bmh -w"
    print_status "3. Monitor cluster status: clusterctl describe cluster sample-cluster"
    print_status ""
    print_status "Useful commands:"
    print_status "  kubectl get clusters -A                    # View all clusters"
    print_status "  kubectl get bmh -A                         # View BareMetalHosts"
    print_status "  kubectl get metal3clusters -A              # View Metal3 clusters"
    print_status "  kubectl get metal3machines -A              # View Metal3 machines"
    print_status "  clusterctl describe cluster sample-cluster # Describe cluster"
    print_status ""
    print_status "Access the created cluster:"
    print_status "  clusterctl get kubeconfig sample-cluster > sample-cluster-kubeconfig"
    print_status "  kubectl --kubeconfig sample-cluster-kubeconfig get nodes"
}

# Run main function
main "$@"
