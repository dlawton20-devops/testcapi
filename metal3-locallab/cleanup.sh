#!/bin/bash
set -e

echo "🧹 Cleaning up old clusters and containers..."

# Clean up kind clusters
if command -v kind &> /dev/null; then
    echo "Checking for kind clusters..."
    CLUSTERS=$(kind get clusters 2>/dev/null || echo "")
    if [ -n "$CLUSTERS" ]; then
        echo "Found kind clusters: $CLUSTERS"
        for cluster in $CLUSTERS; do
            echo "Deleting kind cluster: $cluster"
            kind delete cluster --name "$cluster" 2>/dev/null || true
        done
    else
        echo "No kind clusters found"
    fi
fi

# Clean up minikube
if command -v minikube &> /dev/null; then
    echo "Checking minikube status..."
    if minikube status &>/dev/null; then
        echo "Stopping and deleting minikube cluster..."
        minikube stop 2>/dev/null || true
        minikube delete 2>/dev/null || true
    else
        echo "No active minikube cluster"
    fi
fi

# Clean up Docker containers and images
if docker ps &>/dev/null; then
    echo "Cleaning up Docker resources..."
    
    # Stop all running containers
    echo "Stopping all running containers..."
    docker stop $(docker ps -q) 2>/dev/null || true
    
    # Remove all stopped containers
    echo "Removing stopped containers..."
    docker container prune -f 2>/dev/null || true
    
    # Remove unused images
    echo "Removing unused Docker images..."
    docker image prune -a -f 2>/dev/null || true
    
    # Remove unused volumes
    echo "Removing unused volumes..."
    docker volume prune -f 2>/dev/null || true
    
    # Remove unused networks
    echo "Removing unused networks..."
    docker network prune -f 2>/dev/null || true
    
    # System prune for everything
    echo "Performing Docker system prune..."
    docker system prune -a -f --volumes 2>/dev/null || true
else
    echo "⚠️  Docker is not running. Start Docker Desktop or Rancher Desktop first."
    echo "   Then run this script again to clean up Docker resources."
fi

# Clean up libvirt VMs
echo "Checking for libvirt VMs..."
if virsh list --all 2>/dev/null | grep -q "running\|shut off"; then
    echo "Found libvirt VMs. Listing:"
    virsh list --all
    echo ""
    echo "⚠️  To delete libvirt VMs, run: virsh destroy <vm-name> && virsh undefine <vm-name>"
else
    echo "No libvirt VMs found"
fi

# Clean up old kubectl contexts (optional - commented out to preserve other clusters)
# echo "Cleaning up old kubectl contexts..."
# if [ -f ~/.kube/config ]; then
#     OLD_CONTEXTS=$(kubectl config get-contexts -o name 2>/dev/null | grep -E "(kind-metal3|minikube)" || true)
#     if [ -n "$OLD_CONTEXTS" ]; then
#         echo "Found old contexts: $OLD_CONTEXTS"
#         for ctx in $OLD_CONTEXTS; do
#             echo "Removing context: $ctx"
#             kubectl config delete-context "$ctx" 2>/dev/null || true
#         done
#     fi
# fi

# Clean up Metal3 specific resources
echo "Cleaning up Metal3-specific resources..."
if kind get clusters 2>/dev/null | grep -q "metal3-management"; then
    echo "Deleting Metal3 kind cluster..."
    kind delete cluster --name metal3-management 2>/dev/null || true
fi

# Clean up libvirt VMs created for Metal3
echo "Checking for Metal3 libvirt VMs..."
METAL3_VMS=$(virsh list --all --name 2>/dev/null | grep -E "metal3-node|metal3-" || true)
if [ -n "$METAL3_VMS" ]; then
    echo "Found Metal3 VMs: $METAL3_VMS"
    for vm in $METAL3_VMS; do
        echo "Destroying and removing VM: $vm"
        virsh destroy "$vm" 2>/dev/null || true
        virsh undefine "$vm" 2>/dev/null || true
    done
fi

# Clean up Metal3 images directory
if [ -d "$HOME/metal3-images" ]; then
    echo "Metal3 images directory found at $HOME/metal3-images"
    echo "⚠️  To remove images and free space, run: rm -rf $HOME/metal3-images"
fi

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "Disk space summary:"
df -h . | tail -1

