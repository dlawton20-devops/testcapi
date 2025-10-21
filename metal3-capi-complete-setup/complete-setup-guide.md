# Complete Metal3 + CAPI Setup Guide

This guide provides start-to-finish instructions for setting up Metal3 + CAPI using OpenStack VMs to simulate bare metal nodes.

## 🎯 Prerequisites

- OpenStack access with admin privileges
- SSH key pair for VM access
- Docker and kind installed
- clusterctl installed
- kubectl installed

## 🚀 Option 1: Kind Cluster Setup (Recommended for Testing)

### Step 1: Create Management Cluster

```bash
# 1. Create kind cluster
kind create cluster --name metal3-management --config kind-config.yaml

# 2. Verify cluster
kubectl cluster-info
kubectl get nodes
```

### Step 2: Install CAPI

```bash
# 3. Install core CAPI
clusterctl init --core cluster-api:v1.6.0

# 4. Install Metal3 provider
clusterctl init --infrastructure metal3:v1.6.0

# 5. Verify CAPI installation
kubectl get pods -n capi-system
kubectl get pods -n capm3-system
```

### Step 3: Install Metal3 Dependencies

```bash
# 6. Install MetalLB
helm install metallb oci://registry.suse.com/edge/charts/metallb \
  --namespace metallb-system \
  --create-namespace

# 7. Configure IP pool for Metal3
export STATIC_IRONIC_IP=10.0.0.100
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

# 8. Create L2Advertisement
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
```

### Step 4: Install Metal3

```bash
# 9. Install Metal3
helm install metal3 oci://registry.suse.com/edge/charts/metal3 \
  --namespace metal3-system \
  --create-namespace \
  --set global.ironicIP="$STATIC_IRONIC_IP"

# 10. Wait for Metal3 to be ready (takes ~2 minutes)
kubectl get pods -n metal3-system
# Wait until all pods are Running
```

### Step 5: Install Rancher Turtles

```bash
# 11. Install Rancher Turtles
cat > values.yaml <<EOF
rancherTurtles:
  features:
    embedded-capi:
      disabled: true
    rancher-webhook:
      cleanup: true
EOF

helm install rancher-turtles oci://registry.suse.com/edge/charts/rancher-turtles \
  --namespace rancher-turtles-system \
  --create-namespace \
  --values values.yaml

# 12. Verify Rancher Turtles
kubectl get pods -n rancher-turtles-system
```

### Step 6: Create OpenStack VMs (Bare Metal Simulation)

```bash
# 13. Create security group
openstack security group create metal3-baremetal \
  --description "Security group for Metal3 bare metal simulation"

# 14. Add security group rules
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

# 15. Create control plane VM
openstack server create \
  --flavor m1.large \
  --image ubuntu-22.04 \
  --key-name your-ssh-key \
  --network private \
  --security-group metal3-baremetal \
  --tag metal3 \
  --tag control-plane \
  --tag baremetal-simulation \
  controlplane-0

# 16. Create worker VMs
openstack server create \
  --flavor m1.medium \
  --image ubuntu-22.04 \
  --key-name your-ssh-key \
  --network private \
  --security-group metal3-baremetal \
  --tag metal3 \
  --tag worker \
  --tag baremetal-simulation \
  worker-0

openstack server create \
  --flavor m1.medium \
  --image ubuntu-22.04 \
  --key-name your-ssh-key \
  --network private \
  --security-group metal3-baremetal \
  --tag metal3 \
  --tag worker \
  --tag baremetal-simulation \
  worker-1
```

### Step 7: Setup OOB Simulation

```bash
# 17. Get VM IPs
CONTROL_PLANE_IP=$(openstack server show controlplane-0 -f value -c addresses | grep -oE '192\.168\.1\.[0-9]+' | head -1)
WORKER_0_IP=$(openstack server show worker-0 -f value -c addresses | grep -oE '192\.168\.1\.[0-9]+' | head -1)
WORKER_1_IP=$(openstack server show worker-1 -f value -c addresses | grep -oE '192\.168\.1\.[0-9]+' | head -1)

echo "Control Plane IP: $CONTROL_PLANE_IP"
echo "Worker 0 IP: $WORKER_0_IP"
echo "Worker 1 IP: $WORKER_1_IP"

# 18. Setup OOB simulation on each VM
for vm_name in "controlplane-0" "worker-0" "worker-1"; do
    vm_ip=$(openstack server show "$vm_name" -f value -c addresses | grep -oE '192\.168\.1\.[0-9]+' | head -1)
    
    echo "Setting up OOB simulation on $vm_name ($vm_ip)"
    
    ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no ubuntu@$vm_ip << 'EOF'
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
done
```

### Step 8: Create BMC Credentials and Network Data

```bash
# 19. Create BMC credentials secret
kubectl create secret generic bmc-credentials \
  --from-literal=username=admin \
  --from-literal=password=password \
  --namespace default

# 20. Create network data secret
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
```

### Step 9: Create BareMetalHost Resources

```bash
# 21. Create control plane BareMetalHost
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
    address: redfish-virtualmedia://${CONTROL_PLANE_IP}:8000/redfish/v1/Systems/1
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

# 22. Create worker BareMetalHosts
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
    address: redfish-virtualmedia://${WORKER_0_IP}:8000/redfish/v1/Systems/1
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
    address: redfish-virtualmedia://${WORKER_1_IP}:8000/redfish/v1/Systems/1
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
```

### Step 10: Monitor BareMetalHost Status

```bash
# 23. Watch BareMetalHost status
kubectl get bmh -w

# 24. Check specific BareMetalHost
kubectl describe bmh controlplane-0
kubectl describe bmh worker-0
kubectl describe bmh worker-1
```

### Step 11: Create RKE2 Cluster with Metal3

```bash
# 25. Create RKE2 cluster using Metal3
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
```

### Step 12: Monitor Cluster Creation

```bash
# 26. Watch cluster creation
kubectl get clusters -w
kubectl get rke2controlplanes -w
kubectl get metal3clusters -w
kubectl get metal3machines -w

# 27. Check cluster status
clusterctl describe cluster sample-cluster
```

### Step 13: Create Worker Nodes

```bash
# 28. Create worker machine deployment
kubectl apply -f - <<EOF
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineDeployment
metadata:
  name: sample-cluster-workers
  namespace: default
spec:
  replicas: 2
  clusterName: sample-cluster
  template:
    spec:
      bootstrap:
        configRef:
          apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
          kind: RKE2ConfigTemplate
          name: sample-cluster-workers
      infrastructureRef:
        apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
        kind: Metal3MachineTemplate
        name: sample-cluster-workers
      version: "v1.28.5+rke2r1"
---
apiVersion: bootstrap.cluster.x-k8s.io/v1beta1
kind: RKE2ConfigTemplate
metadata:
  name: sample-cluster-workers
  namespace: default
spec:
  template:
    spec:
      agentConfig:
        node-name: "worker-\${CLUSTER_NAME}-\${MACHINE_NAME}"
        cluster-cidr: "10.244.0.0/16"
        service-cidr: "10.96.0.0/12"
        kubelet-arg:
          - "cgroup-driver=systemd"
          - "eviction-hard=nodefs.available<0%,nodefs.inodesFree<0%,imagefs.available<0%"
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3MachineTemplate
metadata:
  name: sample-cluster-workers
  namespace: default
spec:
  template:
    spec:
      dataTemplate:
        name: sample-cluster-workers-template
      hostSelector:
        matchLabels:
          cluster-role: worker
      image:
        checksum: http://imagecache.local:8080/SLE-Micro-eib-output.raw.sha256
        checksumType: sha256
        format: raw
        url: http://imagecache.local:8080/SLE-Micro-eib-output.raw
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: Metal3DataTemplate
metadata:
  name: sample-cluster-workers-template
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
```

### Step 14: Final Validation

```bash
# 29. Wait for cluster to be ready
kubectl wait --for=condition=ready cluster/sample-cluster --timeout=30m

# 30. Get cluster kubeconfig
clusterctl get kubeconfig sample-cluster > sample-cluster-kubeconfig

# 31. Verify cluster
kubectl --kubeconfig sample-cluster-kubeconfig get nodes
kubectl --kubeconfig sample-cluster-kubeconfig get pods -A
```

## 🎯 Option 2: Using Rancher Cluster

If you want to use an existing Rancher cluster instead of Kind:

### Step 1: Prepare Rancher Cluster

```bash
# 1. Ensure you have access to your Rancher cluster
kubectl cluster-info

# 2. Install CAPI on Rancher cluster
clusterctl init --core cluster-api:v1.6.0

# 3. Install Metal3 provider
clusterctl init --infrastructure metal3:v1.6.0
```

### Step 2: Continue with Steps 3-14

Follow the same steps 3-14 from the Kind cluster setup above.

## 🔍 Useful Commands

```bash
# Monitor everything
kubectl get clusters -A
kubectl get bmh -A
kubectl get metal3clusters -A
kubectl get metal3machines -A

# Check specific resources
kubectl describe cluster sample-cluster
kubectl describe bmh controlplane-0
clusterctl describe cluster sample-cluster

# Access the created cluster
kubectl --kubeconfig sample-cluster-kubeconfig get nodes

# Clean up
kubectl delete cluster sample-cluster
kubectl delete bmh --all
openstack server delete controlplane-0 worker-0 worker-1
```

## 🎯 What You've Built

You now have:
- ✅ **Management Cluster** with Metal3 + CAPI
- ✅ **Simulated Bare Metal Nodes** (OpenStack VMs with Redfish simulation)
- ✅ **RKE2 Cluster** managed by Metal3
- ✅ **GitOps-ready** infrastructure

This gives you a complete Metal3 + CAPI environment that simulates bare metal management using OpenStack VMs!
