#!/bin/bash

# Setup OOB (Out-of-Band) simulation for Metal3 bare metal testing
# This script configures OpenStack VMs to simulate BMC/Redfish interfaces

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[OOB]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OOB]${NC} $1"
}

print_error() {
    echo -e "${RED}[OOB]${NC} $1"
}

# Configuration
VM_NAMES=("controlplane-0" "worker-0" "worker-1")
SSH_USER="ubuntu"
SSH_KEY="~/.ssh/id_rsa"

print_status "Setting up OOB simulation for Metal3 bare metal testing..."

# Function to setup OOB on a single VM
setup_oob_on_vm() {
    local vm_name=$1
    local vm_ip=$2
    
    print_status "Setting up OOB simulation on $vm_name ($vm_ip)"
    
    # SSH into VM and setup OOB simulation
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$vm_ip" << 'EOF'
        # Update system
        sudo apt update
        sudo apt upgrade -y
        
        # Install Docker
        sudo apt install -y docker.io
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo usermod -aG docker ubuntu
        
        # Install Python dependencies
        sudo apt install -y python3 python3-pip python3-venv
        
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
        
        # Create image serving directory
        sudo mkdir -p /var/www/html/images
        sudo chown -R www-data:www-data /var/www/html/images
        
        # Install Apache for image serving
        sudo apt install -y apache2
        sudo systemctl enable apache2
        sudo systemctl start apache2
        
        # Create status page
        echo "OOB simulation ready" | sudo tee /var/www/html/status
        
        echo "OOB simulation setup complete on $(hostname)"
EOF
    
    if [ $? -eq 0 ]; then
        print_success "OOB simulation setup complete on $vm_name"
    else
        print_error "Failed to setup OOB simulation on $vm_name"
        return 1
    fi
}

# Get VM IPs and setup OOB simulation
for vm_name in "${VM_NAMES[@]}"; do
    print_status "Getting IP for $vm_name..."
    
    # Get VM IP
    vm_ip=$(openstack server show "$vm_name" -f value -c addresses | grep -oE '192\.168\.1\.[0-9]+' | head -1)
    
    if [ -z "$vm_ip" ]; then
        print_error "Could not get IP for VM '$vm_name'"
        continue
    fi
    
    print_status "VM $vm_name IP: $vm_ip"
    
    # Wait for VM to be ready
    print_status "Waiting for VM $vm_name to be ready..."
    while ! ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$SSH_USER@$vm_ip" "echo 'VM ready'" &> /dev/null; do
        print_status "Waiting for VM $vm_name to be ready..."
        sleep 10
    done
    
    # Setup OOB simulation
    setup_oob_on_vm "$vm_name" "$vm_ip"
done

print_success "OOB simulation setup complete for all VMs!"
print_status ""
print_status "Next steps:"
print_status "1. Create BMC credentials: kubectl create secret generic bmc-credentials --from-literal=username=admin --from-literal=password=password"
print_status "2. Create BareMetalHost resources with redfish-virtualmedia://<VM_IP>:8000/redfish/v1/Systems/1"
print_status "3. Test OOB connectivity: curl http://<VM_IP>:8000/redfish/v1/"
print_status ""
print_status "Useful commands:"
print_status "  curl http://<VM_IP>:8000/redfish/v1/                    # Test Redfish endpoint"
print_status "  ssh ubuntu@<VM_IP> 'sudo systemctl status redfish-simulator'  # Check service status"
print_status "  kubectl get bmh -w                                     # Watch BareMetalHost status"
