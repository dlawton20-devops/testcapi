# Manual Setup Guide: Kind Cluster + Redfish Simulators

This guide provides step-by-step manual instructions for setting up a Kind cluster with Redfish simulators on an OpenStack VM, **without Rancher integration**.

## 🎯 Overview

This guide will help you:
1. Install all dependencies on the VM manually
2. Create Kind cluster manually
3. Build and run Redfish simulators manually
4. Configure network access for external access
5. Verify everything is working

## 📋 Prerequisites

- OpenStack VM with Ubuntu 22.04+ or Debian 11+
- SSH access to the VM
- OpenStack CLI access (for security groups, optional)
- Local machine with SSH and file transfer capabilities

## 🚀 Step-by-Step Manual Setup

### Step 1: Create and Access OpenStack VM

#### 1.1 Create VM

```bash
# Create VM
openstack server create \
  --flavor m1.large \
  --image ubuntu-22.04 \
  --key-name your-ssh-key \
  --network private \
  --security-group default \
  --tag metal3-kind \
  metal3-vm

# Assign floating IP
FLOATING_IP=$(openstack floating ip create public -f value -c floating_ip_address)
openstack server add floating ip metal3-vm $FLOATING_IP

# Get VM IP
VM_IP=$(openstack server show metal3-vm -f value -c addresses | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
echo "VM IP: $VM_IP"
export VM_IP
```

#### 1.2 SSH to VM

```bash
# Wait for VM to be ready
sleep 30

# SSH to VM
ssh ubuntu@${VM_IP}
```

### Step 2: Install Dependencies on VM

#### 2.1 Update System

```bash
# Update package list
sudo apt-get update

# Upgrade system
sudo apt-get upgrade -y

# Install basic tools
sudo apt-get install -y curl wget git vim
```

#### 2.2 Install Docker

```bash
# Install Docker using official script
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add user to docker group
sudo usermod -aG docker $USER

# Enable and start Docker
sudo systemctl enable docker
sudo systemctl start docker

# Verify Docker
docker --version
docker ps

# Log out and back in for group changes to take effect
exit

# SSH back in
ssh ubuntu@${VM_IP}
docker ps  # Should work without sudo now
```

#### 2.3 Install kubectl

```bash
# Download kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# Install kubectl
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Verify installation
kubectl version --client
```

#### 2.4 Install kind

```bash
# Download kind
KIND_VERSION="v0.20.0"
curl -Lo ./kind https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64

# Make executable
chmod +x ./kind

# Move to PATH
sudo mv ./kind /usr/local/bin/kind

# Verify installation
kind version
```

### Step 3: Create Kind Cluster Configuration

#### 3.1 Create kind-config.yaml

On your local machine, create the configuration file:

```bash
# On your local machine
cat > kind-config.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4

name: metal3-management

networking:
  apiServerAddress: "0.0.0.0"  # Exposed for external access
  apiServerPort: 6443
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
  disableDefaultCNI: false

nodes:
  - role: control-plane
    image: kindest/node:v1.27.3
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
      - |
        kind: ClusterConfiguration
        apiServer:
          extraArgs:
            service-node-port-range: "30000-32767"
        networking:
          podSubnet: "10.244.0.0/16"
          serviceSubnet: "10.96.0.0/12"
    extraPortMappings:
      - containerPort: 80
        hostPort: 8080
        protocol: TCP
      - containerPort: 443
        hostPort: 8443
        protocol: TCP
      - containerPort: 6385
        hostPort: 6385
        protocol: TCP
      - containerPort: 5050
        hostPort: 5050
        protocol: TCP
      - containerPort: 6443
        hostPort: 6443
        protocol: TCP
  - role: worker
    image: kindest/node:v1.27.3
  - role: worker
    image: kindest/node:v1.27.3
EOF
```

#### 3.2 Copy Configuration to VM

```bash
# From your local machine
scp kind-config.yaml ubuntu@${VM_IP}:/tmp/
```

### Step 4: Create Kind Cluster on VM

#### 4.1 Create Cluster

```bash
# SSH to VM
ssh ubuntu@${VM_IP}

# Create Kind cluster
kind create cluster --name metal3-management --config /tmp/kind-config.yaml

# Wait for cluster to be ready
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Verify cluster
kubectl cluster-info
kubectl get nodes
```

#### 4.2 Verify Port Exposures

```bash
# Check that ports are exposed
sudo netstat -tlnp | grep -E '6443|8000|8001|8002'

# Or use ss
sudo ss -tlnp | grep -E '6443|8000|8001|8002'
```

### Step 5: Build Redfish Simulator Docker Image

#### 5.1 Create Dockerfile

On your local machine, create the Dockerfile:

```bash
# On your local machine
cat > Dockerfile.redfish-simulator <<'EOF'
FROM python:3.11-slim

LABEL maintainer="Metal3 Project"
LABEL description="Redfish API Simulator for Metal3 testing"
LABEL version="1.0.0"

WORKDIR /app

COPY redfish-simulator.py /app/redfish-simulator.py

RUN chmod +x /app/redfish-simulator.py

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python3 -c "import urllib.request; urllib.request.urlopen('http://localhost:${PORT:-8000}/redfish/v1/')" || exit 1

CMD ["python3", "/app/redfish-simulator.py"]
EOF
```

#### 5.2 Create Redfish Simulator Script

On your local machine, create the Python simulator:

```bash
# On your local machine
cat > redfish-simulator.py <<'EOF'
#!/usr/bin/env python3
"""
Redfish API Simulator for Metal3 Bare Metal Provisioning
"""
import http.server
import socketserver
import json
import os
import sys

class RedfishSimulator(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass
    
    def _send_json_response(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data, indent=2).encode())
    
    def do_GET(self):
        if self.path == '/redfish/v1/':
            self._send_json_response({
                "@odata.context": "/redfish/v1/$metadata#ServiceRoot.ServiceRoot",
                "@odata.id": "/redfish/v1/",
                "@odata.type": "#ServiceRoot.v1_5_0.ServiceRoot",
                "Id": "RootService",
                "Name": "Root Service",
                "Systems": {"@odata.id": "/redfish/v1/Systems"},
                "Managers": {"@odata.id": "/redfish/v1/Managers"}
            })
        elif self.path == '/redfish/v1/Systems':
            self._send_json_response({
                "@odata.context": "/redfish/v1/$metadata#ComputerSystemCollection.ComputerSystemCollection",
                "@odata.id": "/redfish/v1/Systems",
                "@odata.type": "#ComputerSystemCollection.ComputerSystemCollection",
                "Name": "Computer System Collection",
                "Members@odata.count": 1,
                "Members": [{"@odata.id": "/redfish/v1/Systems/1"}]
            })
        elif self.path == '/redfish/v1/Systems/1':
            cpu_count = int(os.environ.get('CPU_COUNT', 8))
            memory_gb = int(os.environ.get('MEMORY_GB', 64))
            self._send_json_response({
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
                    "Count": cpu_count,
                    "Model": os.environ.get('CPU_MODEL', 'Intel Xeon E5-2680 v4')
                },
                "Memory": {
                    "TotalSystemMemoryGiB": memory_gb
                },
                "Storage": {
                    "Drives": [{
                        "CapacityBytes": int(os.environ.get('STORAGE_BYTES', 1000000000000)),
                        "MediaType": "SSD"
                    }]
                }
            })
        elif self.path == '/redfish/v1/Systems/1/VirtualMedia/1':
            self._send_json_response({
                "@odata.context": "/redfish/v1/$metadata#VirtualMedia.VirtualMedia",
                "@odata.id": "/redfish/v1/Systems/1/VirtualMedia/1",
                "@odata.type": "#VirtualMedia.v1_4_0.VirtualMedia",
                "Id": "1",
                "Name": "Virtual Media",
                "Image": os.environ.get('INSERTED_IMAGE', ''),
                "Inserted": os.environ.get('INSERTED_IMAGE', '') != '',
                "WriteProtected": True
            })
        else:
            self.send_response(404)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Not found", "path": self.path}).encode())
    
    def do_POST(self):
        if self.path == '/redfish/v1/Systems/1/Actions/ComputerSystem.Reset':
            self._send_json_response({
                "Status": "Success",
                "Message": "System reset initiated"
            })
        elif self.path == '/redfish/v1/Systems/1/VirtualMedia/1/Actions/VirtualMedia.InsertMedia':
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = {}
            if content_length > 0:
                post_data = json.loads(self.rfile.read(content_length).decode())
            image_url = post_data.get('Image', '')
            if image_url:
                os.environ['INSERTED_IMAGE'] = image_url
            self._send_json_response({
                "Status": "Success",
                "ImageInserted": True,
                "Image": image_url
            })
        else:
            self.send_response(404)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Not found"}).encode())

if __name__ == "__main__":
    PORT = int(os.environ.get('PORT', 8000))
    HOST = os.environ.get('HOST', '0.0.0.0')
    with socketserver.TCPServer((HOST, PORT), RedfishSimulator) as httpd:
        print(f"Redfish Simulator running on {HOST}:{PORT}", flush=True)
        print(f"CPU Count: {os.environ.get('CPU_COUNT', 8)}", flush=True)
        print(f"Memory: {os.environ.get('MEMORY_GB', 64)} GB", flush=True)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down simulator", flush=True)
            sys.exit(0)
EOF
```

#### 5.3 Copy Files to VM

```bash
# From your local machine
scp Dockerfile.redfish-simulator ubuntu@${VM_IP}:/tmp/
scp redfish-simulator.py ubuntu@${VM_IP}:/tmp/
```

#### 5.4 Build Docker Image on VM

```bash
# SSH to VM
ssh ubuntu@${VM_IP}

# Build image
cd /tmp
docker build -f Dockerfile.redfish-simulator -t redfish-simulator:latest .

# Verify image
docker images | grep redfish-simulator
```

### Step 6: Run Redfish Simulators

#### 6.1 Get Kind Network

```bash
# On VM, get Kind network
KIND_NETWORK=$(docker network ls | grep kind | awk '{print $1}' | head -1)

# If no Kind network found, create one
if [ -z "$KIND_NETWORK" ]; then
    KIND_NETWORK="metal3-simulator-network"
    docker network create $KIND_NETWORK
fi

echo "Using network: $KIND_NETWORK"
```

#### 6.2 Create Control Plane Simulator

```bash
# On VM
docker run -d \
  --name redfish-sim-controlplane \
  --network $KIND_NETWORK \
  --restart unless-stopped \
  -p 8000:8000 \
  -e PORT=8000 \
  -e CPU_COUNT=8 \
  -e MEMORY_GB=64 \
  -e CPU_MODEL="Intel Xeon E5-2680 v4" \
  redfish-simulator:latest

# Verify container is running
docker ps | grep redfish-sim-controlplane

# Check logs
docker logs redfish-sim-controlplane

# Test endpoint
curl http://localhost:8000/redfish/v1/
```

#### 6.3 Create Worker-0 Simulator

```bash
# On VM
docker run -d \
  --name redfish-sim-worker-0 \
  --network $KIND_NETWORK \
  --restart unless-stopped \
  -p 8001:8000 \
  -e PORT=8000 \
  -e CPU_COUNT=4 \
  -e MEMORY_GB=32 \
  -e CPU_MODEL="Intel Xeon E5-2650 v4" \
  redfish-simulator:latest

# Verify
docker ps | grep redfish-sim-worker-0
docker logs redfish-sim-worker-0
curl http://localhost:8001/redfish/v1/
```

#### 6.4 Create Worker-1 Simulator

```bash
# On VM
docker run -d \
  --name redfish-sim-worker-1 \
  --network $KIND_NETWORK \
  --restart unless-stopped \
  -p 8002:8000 \
  -e PORT=8000 \
  -e CPU_COUNT=4 \
  -e MEMORY_GB=32 \
  -e CPU_MODEL="Intel Xeon E5-2650 v4" \
  redfish-simulator:latest

# Verify
docker ps | grep redfish-sim-worker-1
docker logs redfish-sim-worker-1
curl http://localhost:8002/redfish/v1/
```

#### 6.5 Get Container Information

```bash
# On VM, get container IPs
CONTROL_PLANE_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' redfish-sim-controlplane)
WORKER_0_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' redfish-sim-worker-0)
WORKER_1_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' redfish-sim-worker-1)

echo "Control Plane Simulator IP: $CONTROL_PLANE_IP"
echo "Worker 0 Simulator IP: $WORKER_0_IP"
echo "Worker 1 Simulator IP: $WORKER_1_IP"

# Get VM external IP (from your local machine)
echo "VM External IP: ${VM_IP}"
```

### Step 7: Configure Security Groups (Optional)

If you need external access to the simulators or Kubernetes API:

```bash
# From your local machine (with OpenStack CLI)
export VM_IP="192.168.1.100"  # Your VM IP
export ALLOWED_NETWORK="10.0.0.0/8"  # Network that needs access

# Allow Kubernetes API (port 6443)
openstack security group rule create default \
  --protocol tcp \
  --dst-port 6443 \
  --remote-ip "$ALLOWED_NETWORK" \
  --description "Kubernetes API"

# Allow Redfish Simulators (ports 8000-8002)
for port in 8000 8001 8002; do
    openstack security group rule create default \
      --protocol tcp \
      --dst-port $port \
      --remote-ip "$ALLOWED_NETWORK" \
      --description "Redfish simulator port $port"
done

# Verify rules
openstack security group rule list default -f table
```

### Step 8: Get Kubeconfig

#### 8.1 Get Kubeconfig from VM

```bash
# From your local machine
ssh ubuntu@${VM_IP} "kind get kubeconfig --name metal3-management" > /tmp/kind-metal3-management-kubeconfig.yaml
```

#### 8.2 Update Kubeconfig Server URL (if needed)

```bash
# On your local machine
# Update server URL to use VM external IP (if accessing from outside)
sed -i.bak "s|server: https://.*:6443|server: https://${VM_IP}:6443|" /tmp/kind-metal3-management-kubeconfig.yaml

# Verify the change
grep "server:" /tmp/kind-metal3-management-kubeconfig.yaml
```

#### 8.3 Use Kubeconfig

```bash
# On your local machine
export KUBECONFIG=/tmp/kind-metal3-management-kubeconfig.yaml

# Test access
kubectl get nodes
kubectl cluster-info
```

## 🔍 Verification

### Verify Kind Cluster

```bash
# On VM
kubectl get nodes
kubectl get pods -A
kubectl cluster-info

# Check API server is accessible
curl -k https://localhost:6443/healthz
```

### Verify Simulators

```bash
# On VM
docker ps | grep redfish-sim

# Test all endpoints
curl http://localhost:8000/redfish/v1/
curl http://localhost:8001/redfish/v1/
curl http://localhost:8002/redfish/v1/

# Check logs
docker logs redfish-sim-controlplane
docker logs redfish-sim-worker-0
docker logs redfish-sim-worker-1
```

### Verify External Access (if configured)

```bash
# From your local machine or another host
export VM_IP="192.168.1.100"

# Test Kubernetes API
curl -k https://${VM_IP}:6443/healthz

# Test Redfish simulators
curl http://${VM_IP}:8000/redfish/v1/
curl http://${VM_IP}:8001/redfish/v1/
curl http://${VM_IP}:8002/redfish/v1/
```

### Test from Kind Cluster Pods

```bash
# On VM, test simulators from a pod in the Kind cluster
kubectl run -it --rm test-redfish \
  --image=curlimages/curl \
  --restart=Never \
  -- curl http://localhost:8000/redfish/v1/

# Or use container IPs
CONTROL_PLANE_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' redfish-sim-controlplane)
kubectl run -it --rm test-redfish-ip \
  --image=curlimages/curl \
  --restart=Never \
  -- curl http://${CONTROL_PLANE_IP}:8000/redfish/v1/
```

## 📝 Summary Information

After completing this setup, you have:

### Kind Cluster
- **Name**: `metal3-management`
- **Nodes**: 1 control plane + 2 workers
- **Kubernetes Version**: v1.27.3
- **API Server**: `https://${VM_IP}:6443` (or localhost:6443 from VM)

### Redfish Simulators
- **Control Plane**: `http://${VM_IP}:8000/redfish/v1/` (or localhost:8000 from VM)
- **Worker 0**: `http://${VM_IP}:8001/redfish/v1/` (or localhost:8001 from VM)
- **Worker 1**: `http://${VM_IP}:8002/redfish/v1/` (or localhost:8002 from VM)

### BMC Addresses for BareMetalHost

When creating BareMetalHost resources (in your Rancher cluster or elsewhere), use:

```yaml
# Control Plane
bmc:
  address: redfish-virtualmedia://${VM_IP}:8000/redfish/v1/Systems/1

# Worker 0
bmc:
  address: redfish-virtualmedia://${VM_IP}:8001/redfish/v1/Systems/1

# Worker 1
bmc:
  address: redfish-virtualmedia://${VM_IP}:8002/redfish/v1/Systems/1
```

## 🛠️ Management Commands

### View Everything

```bash
# On VM
echo "=== Kind Cluster ==="
kubectl get nodes
kubectl get pods -A

echo ""
echo "=== Redfish Simulators ==="
docker ps | grep redfish-sim

echo ""
echo "=== Network ==="
docker network ls | grep -E "kind|bridge"
sudo netstat -tlnp | grep -E '6443|8000|8001|8002'
```

### Restart Components

```bash
# Restart Kind cluster
kind delete cluster --name metal3-management
kind create cluster --name metal3-management --config /tmp/kind-config.yaml

# Restart simulators
docker restart redfish-sim-controlplane redfish-sim-worker-0 redfish-sim-worker-1
```

### View Logs

```bash
# Kind cluster logs
kubectl logs -n kube-system <pod-name>

# Simulator logs
docker logs redfish-sim-controlplane
docker logs redfish-sim-worker-0
docker logs redfish-sim-worker-1
```

### Clean Up

```bash
# Delete Kind cluster
kind delete cluster --name metal3-management

# Stop and remove simulators
docker stop redfish-sim-controlplane redfish-sim-worker-0 redfish-sim-worker-1
docker rm redfish-sim-controlplane redfish-sim-worker-0 redfish-sim-worker-1

# Remove image (optional)
docker rmi redfish-simulator:latest
```

## 🔧 Troubleshooting

### Kind Cluster Not Starting

```bash
# Check Docker is running
docker info

# Check kind logs
kind get clusters
kind get kubeconfig --name metal3-management

# Check node containers
docker ps | grep kind
```

### Simulators Not Responding

```bash
# Check containers are running
docker ps | grep redfish-sim

# Check logs
docker logs redfish-sim-controlplane

# Check ports are bound
sudo netstat -tlnp | grep -E '8000|8001|8002'

# Test from VM
curl http://localhost:8000/redfish/v1/
```

### Network Connectivity Issues

```bash
# Check firewall
sudo ufw status

# Check security groups (if using OpenStack)
openstack security group rule list default

# Test connectivity
curl -v http://${VM_IP}:8000/redfish/v1/
```

## 📊 Resource Usage

Typical resource usage on VM:

- **Kind Cluster**: ~2GB RAM, ~10GB disk
- **Simulators**: ~50MB RAM each, minimal disk
- **Total**: ~3GB RAM, ~15GB disk

## 🎉 Next Steps

After setup is complete:

1. **Use the Kind cluster** for your workloads
2. **Use Redfish simulators** for Metal3 testing
3. **Create BareMetalHost resources** using the BMC addresses provided
4. **Integrate with your existing Rancher cluster** (if needed) - see `docs/RANCHER-INTEGRATION.md`

## 📚 Additional Resources

- **Network Architecture**: See `docs/NETWORK-ARCHITECTURE.md` for network flow
- **Cluster Access**: See `docs/CLUSTER-ACCESS.md` for access methods
- **Rancher Integration**: See `docs/RANCHER-INTEGRATION.md` (if you need to integrate with Rancher)

