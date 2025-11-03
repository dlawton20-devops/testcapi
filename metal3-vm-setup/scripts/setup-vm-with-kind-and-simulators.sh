#!/bin/bash

# Complete Setup: Kind Cluster + Redfish Simulators on OpenStack VM
# This script sets up everything on a single OpenStack VM:
# - Docker installation
# - Kind cluster (management cluster)
# - Redfish simulators (bare metal node simulation)
# - Network configuration for access from outside

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[SETUP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SETUP]${NC} $1"
}

print_error() {
    echo -e "${RED}[SETUP]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[SETUP]${NC} $1"
}

# Configuration
VM_IP="${VM_IP:-}"
VM_USER="${VM_USER:-ubuntu}"
SSH_KEY="${SSH_KEY:-~/.ssh/id_rsa}"
CLUSTER_NAME="${CLUSTER_NAME:-metal3-management}"
KIND_VERSION="${KIND_VERSION:-v0.20.0}"
KUBERNETES_VERSION="${KUBERNETES_VERSION:-v1.27.3}"

# Ports
CONTROL_PLANE_PORT=8000
WORKER_0_PORT=8001
WORKER_1_PORT=8002

# Check if VM_IP is set
if [ -z "$VM_IP" ]; then
    print_error "VM_IP not set. Please set it to your OpenStack VM's external IP:"
    print_error "  export VM_IP=192.168.1.100"
    exit 1
fi

print_status "═══════════════════════════════════════════════════"
print_status "Complete VM Setup: Kind + Redfish Simulators"
print_status "═══════════════════════════════════════════════════"
print_status "VM IP: $VM_IP"
print_status "User: $VM_USER"
print_status "Cluster: $CLUSTER_NAME"
print_status ""

# Check SSH connectivity
print_status "Checking SSH connectivity..."
if ! ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" "echo 'Connected'" &>/dev/null; then
    print_error "Cannot connect to VM at $VM_IP"
    exit 1
fi
print_success "SSH connection successful"

# Setup function - runs on VM
setup_vm() {
    print_status "Setting up VM (this may take several minutes)..."
    
    ssh -i "$SSH_KEY" "$VM_USER@$VM_IP" << 'ENDSSH'
set -e

# Update system
sudo apt-get update
sudo apt-get install -y curl wget git

# Install Docker
if ! command -v docker &>/dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    sudo systemctl enable docker
    sudo systemctl start docker
    rm get-docker.sh
fi

# Install kubectl
if ! command -v kubectl &>/dev/null; then
    echo "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
fi

# Install kind
if ! command -v kind &>/dev/null; then
    echo "Installing kind..."
    KIND_VERSION="v0.20.0"
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
fi

# Install helm
if ! command -v helm &>/dev/null; then
    echo "Installing helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo "Dependencies installed successfully"
ENDSSH

    print_success "VM dependencies installed"
}

# Copy files to VM
copy_files() {
    print_status "Copying setup files to VM..."
    
    # Create temporary directory structure on VM
    ssh -i "$SSH_KEY" "$VM_USER@$VM_IP" "mkdir -p /tmp/metal3-setup/scripts"
    
    # Get script directory (parent of scripts/)
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
    
    # Copy kind config
    scp -i "$SSH_KEY" "$BASE_DIR/kind-config.yaml" "$VM_USER@$VM_IP:/tmp/metal3-setup/"
    
    # Copy Dockerfile and simulator script
    scp -i "$SSH_KEY" "$SCRIPT_DIR/Dockerfile.redfish-simulator" "$VM_USER@$VM_IP:/tmp/metal3-setup/scripts/"
    scp -i "$SSH_KEY" "$SCRIPT_DIR/redfish-simulator.py" "$VM_USER@$VM_IP:/tmp/metal3-setup/scripts/"
    
    print_success "Files copied"
}

# Setup kind cluster
setup_kind_cluster() {
    print_status "Setting up Kind cluster on VM..."
    
    ssh -i "$SSH_KEY" "$VM_USER@$VM_IP" << ENDSSH
set -e

CLUSTER_NAME="${CLUSTER_NAME}"
KUBERNETES_VERSION="${KUBERNETES_VERSION}"

# Delete existing cluster if it exists
kind delete cluster --name "$CLUSTER_NAME" 2>/dev/null || true

# Create kind cluster
echo "Creating kind cluster..."
kind create cluster --name "$CLUSTER_NAME" --config /tmp/metal3-setup/kind-config.yaml

# Wait for cluster to be ready
echo "Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Get kubeconfig
echo "Getting cluster info..."
kubectl cluster-info
kubectl get nodes

echo "Kind cluster is ready!"
ENDSSH

    print_success "Kind cluster created"
}

# Build and run Redfish simulators
setup_simulators() {
    print_status "Setting up Redfish simulators on VM..."
    
    ssh -i "$SSH_KEY" "$VM_USER@$VM_IP" << ENDSSH
set -e

cd /tmp/metal3-setup/scripts

# Build simulator image
echo "Building Redfish simulator image..."
docker build -f Dockerfile.redfish-simulator -t redfish-simulator:latest .

# Stop existing simulators
docker stop redfish-sim-controlplane redfish-sim-worker-0 redfish-sim-worker-1 2>/dev/null || true
docker rm redfish-sim-controlplane redfish-sim-worker-0 redfish-sim-worker-1 2>/dev/null || true

# Get kind network name
KIND_NETWORK=\$(docker network ls | grep kind | awk '{print \$1}' | head -1)
if [ -z "\$KIND_NETWORK" ]; then
    # If kind network not found, create bridge network
    KIND_NETWORK="metal3-simulator-network"
    docker network create \$KIND_NETWORK 2>/dev/null || true
fi

echo "Using network: \$KIND_NETWORK"

# Create control plane simulator
echo "Creating control plane simulator..."
docker run -d \
  --name redfish-sim-controlplane \
  --network \$KIND_NETWORK \
  --restart unless-stopped \
  -p ${CONTROL_PLANE_PORT}:8000 \
  -e PORT=8000 \
  -e CPU_COUNT=8 \
  -e MEMORY_GB=64 \
  redfish-simulator:latest

# Create worker-0 simulator
echo "Creating worker-0 simulator..."
docker run -d \
  --name redfish-sim-worker-0 \
  --network \$KIND_NETWORK \
  --restart unless-stopped \
  -p ${WORKER_0_PORT}:8000 \
  -e PORT=8000 \
  -e CPU_COUNT=4 \
  -e MEMORY_GB=32 \
  redfish-simulator:latest

# Create worker-1 simulator
echo "Creating worker-1 simulator..."
docker run -d \
  --name redfish-sim-worker-1 \
  --network \$KIND_NETWORK \
  --restart unless-stopped \
  -p ${WORKER_1_PORT}:8000 \
  -e PORT=8000 \
  -e CPU_COUNT=4 \
  -e MEMORY_GB=32 \
  redfish-simulator:latest

# Wait for containers to start
sleep 3

# Get container IPs
echo "Getting simulator IPs..."
CONTROL_PLANE_IP=\$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' redfish-sim-controlplane)
WORKER_0_IP=\$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' redfish-sim-worker-0)
WORKER_1_IP=\$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' redfish-sim-worker-1)

echo "Simulator IPs:"
echo "CONTROL_PLANE_IP=\$CONTROL_PLANE_IP"
echo "WORKER_0_IP=\$WORKER_0_IP"
echo "WORKER_1_IP=\$WORKER_1_IP"

# Test simulators
echo "Testing simulators..."
for port in ${CONTROL_PLANE_PORT} ${WORKER_0_PORT} ${WORKER_1_PORT}; do
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:\$port/redfish/v1/ | grep -q "200"; then
        echo "✓ Simulator on port \$port is responding"
    else
        echo "✗ Simulator on port \$port is not responding"
    fi
done

echo "Simulators are ready!"
ENDSSH

    print_success "Redfish simulators created"
}

# Get cluster kubeconfig
get_kubeconfig() {
    print_status "Retrieving kubeconfig..."
    
    ssh -i "$SSH_KEY" "$VM_USER@$VM_IP" "kind get kubeconfig --name $CLUSTER_NAME" > "/tmp/${CLUSTER_NAME}-kubeconfig.yaml"
    
    # Check if API server is bound to 0.0.0.0 or 127.0.0.1
    API_ADDRESS=$(grep "apiServerAddress" "$(dirname "$0")/../kind-config.yaml" | grep -oE '"[^"]+"' | tr -d '"' || echo "127.0.0.1")
    
    if [ "$API_ADDRESS" = "0.0.0.0" ]; then
        # Update kubeconfig to use VM IP
        sed -i.bak "s|server: https://.*:6443|server: https://${VM_IP}:6443|" "/tmp/${CLUSTER_NAME}-kubeconfig.yaml"
        print_success "Kubeconfig saved and configured for direct access: /tmp/${CLUSTER_NAME}-kubeconfig.yaml"
        print_status "Access directly:"
        print_status "  export KUBECONFIG=/tmp/${CLUSTER_NAME}-kubeconfig.yaml"
        print_status "  kubectl get nodes"
    else
        print_success "Kubeconfig saved to: /tmp/${CLUSTER_NAME}-kubeconfig.yaml"
        print_status "To access cluster, use SSH port forwarding:"
        print_status "  Terminal 1: ssh -L 6443:localhost:6443 $VM_USER@$VM_IP"
        print_status "  Terminal 2: export KUBECONFIG=/tmp/${CLUSTER_NAME}-kubeconfig.yaml"
        print_status "  Terminal 2: kubectl --server=https://localhost:6443 get nodes"
        print_status ""
        print_status "Or use the helper script:"
        print_status "  ./scripts/ssh-tunnel.sh"
    fi
}

# Get simulator information
get_simulator_info() {
    print_status "Getting simulator information..."
    
    SIM_INFO=$(ssh -i "$SSH_KEY" "$VM_USER@$VM_IP" << 'ENDSSH'
# Get container IPs
CONTROL_PLANE_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' redfish-sim-controlplane 2>/dev/null || echo "N/A")
WORKER_0_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' redfish-sim-worker-0 2>/dev/null || echo "N/A")
WORKER_1_IP=$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}}{{end}}' redfish-sim-worker-1 2>/dev/null || echo "N/A")

cat << EOF
CONTROL_PLANE_IP=$CONTROL_PLANE_IP
WORKER_0_IP=$WORKER_0_IP
WORKER_1_IP=$WORKER_1_IP
EOF
ENDSSH
)
    
    echo "$SIM_INFO"
}

# Main execution
main() {
    setup_vm
    copy_files
    setup_kind_cluster
    setup_simulators
    get_kubeconfig
    get_simulator_info
    
    print_success "═══════════════════════════════════════════════════"
    print_success "Setup Complete!"
    print_success "═══════════════════════════════════════════════════"
    print_status ""
    print_status "VM Information:"
    print_status "  IP: $VM_IP"
    print_status "  Cluster: $CLUSTER_NAME"
    print_status ""
    print_status "Kubeconfig:"
    print_status "  Location: /tmp/${CLUSTER_NAME}-kubeconfig.yaml"
    print_status "  Usage: export KUBECONFIG=/tmp/${CLUSTER_NAME}-kubeconfig.yaml"
    print_status ""
    print_status "Redfish Simulators (accessible from VM IP):"
    print_status "  Control Plane: http://${VM_IP}:${CONTROL_PLANE_PORT}/redfish/v1/"
    print_status "  Worker 0:      http://${VM_IP}:${WORKER_0_PORT}/redfish/v1/"
    print_status "  Worker 1:      http://${VM_IP}:${WORKER_1_PORT}/redfish/v1/"
    print_status ""
    print_status "BMC Addresses for BareMetalHost:"
    print_status "  Control Plane: redfish-virtualmedia://${VM_IP}:${CONTROL_PLANE_PORT}/redfish/v1/Systems/1"
    print_status "  Worker 0:      redfish-virtualmedia://${VM_IP}:${WORKER_0_PORT}/redfish/v1/Systems/1"
    print_status "  Worker 1:      redfish-virtualmedia://${VM_IP}:${WORKER_1_PORT}/redfish/v1/Systems/1"
    print_status ""
    print_warning "IMPORTANT: Ensure security groups allow:"
    print_warning "  - SSH (port 22) from your management machine"
    print_warning "  - HTTP (ports 8000-8002) from networks that need access"
    print_status ""
    print_status "Next steps:"
    print_status "  1. Export kubeconfig: export KUBECONFIG=/tmp/${CLUSTER_NAME}-kubeconfig.yaml"
    print_status "  2. Verify cluster: kubectl get nodes"
    print_status "  3. Continue with Metal3 setup in rancher-metal3-simulator-guide.md"
}

main "$@"

