# Manual Setup Guide: Kind Cluster + Redfish Simulators on OpenStack VM

This guide provides step-by-step manual instructions for setting up a Kind cluster with Redfish simulators on an OpenStack VM, without using automated scripts.

## 🎯 Overview

This guide will help you:
1. Install all dependencies on the VM manually
2. Create Kind cluster manually
3. Build and run Redfish simulators manually
4. Configure network access manually
5. Prepare for Rancher integration manually

## 📋 Prerequisites

- OpenStack VM with Ubuntu 22.04+ or Debian 11+
- SSH access to the VM
- OpenStack CLI access (for security groups)
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

#### 2.5 Install helm (Optional, for future use)

```bash
# Install helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installation
helm version
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
  apiServerAddress: "0.0.0.0"  # Exposed for external Rancher access
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
```

#### 6.5 Test Simulators

```bash
# On VM, test all simulators
curl http://localhost:8000/redfish/v1/
curl http://localhost:8001/redfish/v1/
curl http://localhost:8002/redfish/v1/

# Get container IPs (for reference)
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' redfish-sim-controlplane
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' redfish-sim-worker-0
docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' redfish-sim-worker-1
```

### Step 7: Configure Security Groups

#### 7.1 Configure for Rancher Cluster Access

From your local machine (with OpenStack CLI):

```bash
# Set Rancher cluster network
export RANCHER_NETWORK="10.0.0.0/8"  # Replace with your Rancher cluster network CIDR

# Allow Kubernetes API (port 6443)
openstack security group rule create default \
  --protocol tcp \
  --dst-port 6443 \
  --remote-ip "$RANCHER_NETWORK" \
  --description "Kubernetes API for Rancher cluster management"

# Allow Redfish Simulators (ports 8000-8002)
for port in 8000 8001 8002; do
    openstack security group rule create default \
      --protocol tcp \
      --dst-port $port \
      --remote-ip "$RANCHER_NETWORK" \
      --description "Redfish simulator port $port for Metal3/Ironic"
done

# Verify rules
openstack security group rule list default -f table
```

#### 7.2 Verify Security Group Rules

```bash
# List all rules
openstack security group rule list default

# Check specific ports
openstack security group rule list default | grep -E '6443|8000|8001|8002'
```

### Step 8: Get and Configure Kubeconfig

#### 8.1 Get Kubeconfig from VM

```bash
# From your local machine
ssh ubuntu@${VM_IP} "kind get kubeconfig --name metal3-management" > /tmp/kind-metal3-management-kubeconfig.yaml
```

#### 8.2 Update Kubeconfig Server URL

```bash
# On your local machine
# Update server URL to use VM external IP
sed -i.bak "s|server: https://.*:6443|server: https://${VM_IP}:6443|" /tmp/kind-metal3-management-kubeconfig.yaml

# Verify the change
grep "server:" /tmp/kind-metal3-management-kubeconfig.yaml
```

#### 8.3 Test Kubeconfig

```bash
# On your local machine
kubectl --kubeconfig=/tmp/kind-metal3-management-kubeconfig.yaml get nodes

# Should output:
# NAME                              STATUS   ROLES           AGE   VERSION
# metal3-management-control-plane   Ready    control-plane   ...   v1.27.3
# metal3-management-worker          Ready    <none>          ...   v1.27.3
# metal3-management-worker2         Ready    <none>          ...   v1.27.3
```

### Step 9: Test Network Connectivity from Rancher Cluster

#### 9.1 Test from Rancher Cluster Pod

From your Rancher cluster, test connectivity:

```bash
# Test Kubernetes API access
kubectl run -it --rm test-api \
  --image=curlimages/curl \
  --restart=Never \
  -- curl -k https://${VM_IP}:6443/healthz

# Expected output: ok

# Test Redfish simulators
for port in 8000 8001 8002; do
    kubectl run -it --rm test-redfish-$port \
      --image=curlimages/curl \
      --restart=Never \
      -- curl http://${VM_IP}:${port}/redfish/v1/
done
```

### Step 10: Import Cluster into Rancher

#### 10.1 Via Rancher UI (Recommended)

1. **Access Rancher UI**: Navigate to your Rancher cluster URL
2. **Go to Clusters**: Click "Clusters" in the left menu
3. **Import Existing**: Click "Import Existing" or "Add Cluster"
4. **Get Import Command**: Rancher will provide a kubectl command
5. **Run Import Command**: Execute the command with the Kind cluster kubeconfig:

```bash
# Example (your actual command will be different)
kubectl --kubeconfig=/tmp/kind-metal3-management-kubeconfig.yaml apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: cattle-system
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cattle-import
  namespace: cattle-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cattle-import
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: cattle-import
  namespace: cattle-system
---
# ... rest of import manifest from Rancher UI
EOF
```

6. **Wait for Import**: Cluster should appear in Rancher UI within 1-2 minutes

#### 10.2 Via Rancher API (Alternative)

```bash
# Set variables
export RANCHER_URL="https://rancher.example.com"
export RANCHER_TOKEN="your-api-token-here"

# Base64 encode kubeconfig
KUBECONFIG_B64=$(base64 -w 0 /tmp/kind-metal3-management-kubeconfig.yaml)

# Create cluster via API
curl -X POST \
  -H "Authorization: Bearer $RANCHER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"cluster\",
    \"name\": \"kind-metal3-management\",
    \"kubeconfig\": \"$KUBECONFIG_B64\"
  }" \
  "$RANCHER_URL/v3/clusters"
```

### Step 11: Create BareMetalHost Resources in Rancher

#### 11.1 Create BMC Credentials Secret

In your Rancher cluster, create the BMC credentials:

```bash
# From Rancher cluster
kubectl create secret generic bmc-credentials \
  --from-literal=username=admin \
  --from-literal=password=password \
  --namespace default
```

#### 11.2 Create BareMetalHost Resources

```bash
# From Rancher cluster
# Set VM IP
export VM_IP="192.168.1.100"  # Your VM's external IP

# Create control plane BareMetalHost
kubectl apply -f - <<EOF
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: controlplane-0
  namespace: default
spec:
  online: true
  bootMACAddress: 00:00:00:00:00:00
  bmc:
    address: redfish-virtualmedia://${VM_IP}:8000/redfish/v1/Systems/1
    credentialsName: bmc-credentials
    disableCertificateVerification: true
  bootMode: UEFI
  image:
    url: http://imagecache.example.com/ubuntu-20.04.raw
    checksum: http://imagecache.example.com/ubuntu-20.04.raw.sha256
    checksumType: sha256
    format: raw
EOF

# Create worker BareMetalHosts
kubectl apply -f - <<EOF
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: worker-0
  namespace: default
spec:
  online: true
  bootMACAddress: 00:00:00:00:00:01
  bmc:
    address: redfish-virtualmedia://${VM_IP}:8001/redfish/v1/Systems/1
    credentialsName: bmc-credentials
    disableCertificateVerification: true
  bootMode: UEFI
  image:
    url: http://imagecache.example.com/ubuntu-20.04.raw
    checksum: http://imagecache.example.com/ubuntu-20.04.raw.sha256
    checksumType: sha256
    format: raw
---
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: worker-1
  namespace: default
spec:
  online: true
  bootMACAddress: 00:00:00:00:00:02
  bmc:
    address: redfish-virtualmedia://${VM_IP}:8002/redfish/v1/Systems/1
    credentialsName: bmc-credentials
    disableCertificateVerification: true
  bootMode: UEFI
  image:
    url: http://imagecache.example.com/ubuntu-20.04.raw
    checksum: http://imagecache.example.com/ubuntu-20.04.raw.sha256
    checksumType: sha256
    format: raw
EOF
```

#### 11.3 Monitor BareMetalHosts

```bash
# From Rancher cluster
kubectl get bmh -w

# Check status
kubectl describe bmh controlplane-0
```

## 🔍 Verification Steps

### Verify Kind Cluster

```bash
# On VM
kubectl get nodes
kubectl get pods -A
kubectl cluster-info
```

### Verify Simulators

```bash
# On VM
docker ps | grep redfish-sim

# Test endpoints
curl http://localhost:8000/redfish/v1/
curl http://localhost:8001/redfish/v1/
curl http://localhost:8002/redfish/v1/

# Check logs
docker logs redfish-sim-controlplane
```

### Verify Network Access

```bash
# From Rancher cluster, test connectivity
# Test Kubernetes API
curl -k https://${VM_IP}:6443/healthz

# Test Redfish simulators
curl http://${VM_IP}:8000/redfish/v1/
curl http://${VM_IP}:8001/redfish/v1/
curl http://${VM_IP}:8002/redfish/v1/
```

### Verify Rancher Integration

```bash
# In Rancher UI, check:
# 1. Cluster appears in Clusters list
# 2. Cluster status is "Active"
# 3. Nodes are visible

# Via kubectl on Rancher cluster
kubectl get clusters -A
kubectl get cluster kind-metal3-management -o yaml
```

## 🛠️ Troubleshooting

### Kind Cluster Not Accessible

```bash
# Check if API server is listening
ssh ubuntu@${VM_IP} "sudo netstat -tlnp | grep 6443"

# Check kind cluster status
ssh ubuntu@${VM_IP} "kubectl get nodes"

# Check security group rules
openstack security group rule list default | grep 6443
```

### Simulators Not Accessible

```bash
# Check containers are running
ssh ubuntu@${VM_IP} "docker ps | grep redfish-sim"

# Check ports are exposed
ssh ubuntu@${VM_IP} "sudo netstat -tlnp | grep -E '8000|8001|8002'"

# Check security group rules
openstack security group rule list default | grep -E '8000|8001|8002'

# Test from VM itself
ssh ubuntu@${VM_IP} "curl http://localhost:8000/redfish/v1/"
```

### Rancher Cannot Connect

```bash
# Test from Rancher cluster pod
kubectl run -it --rm test \
  --image=nicolaka/netshoot \
  --restart=Never \
  -- nc -zv ${VM_IP} 6443

# Check firewall on VM
ssh ubuntu@${VM_IP} "sudo ufw status"
```

## 📊 Summary

After completing this manual setup, you have:

1. ✅ **Kind cluster** running on OpenStack VM
   - API server exposed on port 6443
   - 1 control plane + 2 worker nodes
   - Accessible from Rancher cluster

2. ✅ **Redfish simulators** running as Docker containers
   - Control plane simulator on port 8000
   - Worker-0 simulator on port 8001
   - Worker-1 simulator on port 8002
   - Accessible from Rancher cluster Metal3/Ironic

3. ✅ **Network access** configured
   - Security groups allow Rancher cluster → VM ports
   - Kubernetes API accessible
   - Redfish APIs accessible

4. ✅ **Rancher integration** ready
   - Kubeconfig prepared
   - Cluster can be imported
   - BareMetalHost resources ready

## 🎯 Next Steps

1. **Import cluster into Rancher** (Step 10)
2. **Create BareMetalHost resources** (Step 11)
3. **Use Metal3 to provision workloads** via Rancher UI
4. **Monitor cluster operations** in Rancher UI

## 📚 Additional Resources

- **Network Architecture**: See `docs/NETWORK-ARCHITECTURE.md`
- **Rancher Integration**: See `docs/RANCHER-INTEGRATION.md`
- **Cluster Access**: See `docs/CLUSTER-ACCESS.md`

