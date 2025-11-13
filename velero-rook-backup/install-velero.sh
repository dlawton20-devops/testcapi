#!/bin/bash
# Velero Installation Script for Rook Ceph Backup
# This script installs Velero and configures it for backing up Rook Ceph

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
VELERO_VERSION="v1.12.0"
NAMESPACE="velero"
BACKUP_LOCATION="default"

# Functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed"
        exit 1
    fi
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        print_warn "Helm is not installed. Installing via script..."
        install_helm
    fi
    
    # Check cluster access
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot access Kubernetes cluster"
        exit 1
    fi
    
    print_info "Prerequisites check passed"
}

install_helm() {
    print_info "Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
}

setup_object_storage() {
    print_info "Setting up object storage backend..."
    
    echo "Select your object storage provider:"
    echo "1) AWS S3"
    echo "2) MinIO (for testing)"
    echo "3) Azure Blob Storage"
    echo "4) Google Cloud Storage"
    read -p "Enter choice [1-4]: " choice
    
    case $choice in
        1)
            setup_aws_s3
            ;;
        2)
            setup_minio
            ;;
        3)
            setup_azure
            ;;
        4)
            setup_gcs
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
}

setup_aws_s3() {
    print_info "Configuring AWS S3..."
    
    read -p "Enter S3 bucket name: " BUCKET_NAME
    read -p "Enter AWS region: " AWS_REGION
    read -p "Enter AWS access key ID: " AWS_ACCESS_KEY
    read -s -p "Enter AWS secret access key: " AWS_SECRET_KEY
    echo
    
    # Create credentials file
    cat > /tmp/credentials-velero <<EOF
[default]
aws_access_key_id=${AWS_ACCESS_KEY}
aws_secret_access_key=${AWS_SECRET_KEY}
EOF
    
    PROVIDER="aws"
    CONFIG_REGION="region=${AWS_REGION}"
}

setup_minio() {
    print_info "Configuring MinIO..."
    
    # Install MinIO if not exists
    if ! kubectl get namespace minio &> /dev/null; then
        kubectl create namespace minio
        helm repo add minio https://charts.min.io/
        helm repo update
        helm install minio minio/minio \
            --namespace minio \
            --set accessKey=minioadmin \
            --set secretKey=minioadmin \
            --set buckets[0].name=velero \
            --set buckets[0].policy=public
    fi
    
    read -p "Enter MinIO endpoint (e.g., http://minio.minio.svc.cluster.local:9000): " MINIO_ENDPOINT
    read -p "Enter MinIO access key: " MINIO_ACCESS_KEY
    read -s -p "Enter MinIO secret key: " MINIO_SECRET_KEY
    echo
    
    # Create credentials file
    cat > /tmp/credentials-velero <<EOF
[default]
aws_access_key_id=${MINIO_ACCESS_KEY}
aws_secret_access_key=${MINIO_SECRET_KEY}
EOF
    
    PROVIDER="aws"
    BUCKET_NAME="velero"
    CONFIG_REGION="s3ForcePathStyle=true,region=minio"
}

setup_azure() {
    print_info "Configuring Azure Blob Storage..."
    print_warn "Azure setup requires additional configuration"
    PROVIDER="azure"
    # Add Azure-specific setup here
}

setup_gcs() {
    print_info "Configuring Google Cloud Storage..."
    print_warn "GCS setup requires additional configuration"
    PROVIDER="gcp"
    # Add GCS-specific setup here
}

install_velero_helm() {
    print_info "Installing Velero using Helm..."
    
    # Create namespace
    kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Add Helm repository
    helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
    helm repo update
    
    # Create secret from credentials
    kubectl create secret generic cloud-credentials \
        --from-file cloud=/tmp/credentials-velero \
        -n ${NAMESPACE} \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Install Velero
    helm upgrade --install velero vmware-tanzu/velero \
        --namespace ${NAMESPACE} \
        --set-file credentials.secretContents.cloud=/tmp/credentials-velero \
        --set configuration.provider=${PROVIDER} \
        --set configuration.backupStorageLocation.bucket=${BUCKET_NAME} \
        --set configuration.backupStorageLocation.config.region=${AWS_REGION:-us-west-2} \
        --set configuration.volumeSnapshotLocation.config.region=${AWS_REGION:-us-west-2} \
        --set initContainers[0].name=velero-plugin-for-aws \
        --set initContainers[0].image=velero/velero-plugin-for-aws:v1.8.0 \
        --set initContainers[0].volumeMounts[0].mountPath=/target \
        --set initContainers[0].volumeMounts[0].name=plugins \
        --set configuration.restic.enabled=true \
        --wait
    
    print_info "Velero installed successfully"
}

install_velero_cli() {
    print_info "Installing Velero CLI tool..."
    
    # Download Velero CLI
    if [ "$(uname)" == "Darwin" ]; then
        VELERO_CLI_URL="https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-darwin-amd64.tar.gz"
    else
        VELERO_CLI_URL="https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz"
    fi
    
    print_info "Downloading Velero CLI..."
    curl -fsSL ${VELERO_CLI_URL} -o /tmp/velero.tar.gz
    tar -xzf /tmp/velero.tar.gz -C /tmp
    sudo mv /tmp/velero-${VELERO_VERSION}-*/velero /usr/local/bin/
    rm -rf /tmp/velero-*
    
    print_info "Velero CLI installed to /usr/local/bin/velero"
}

install_velero_cli_method() {
    print_info "Installing Velero server using CLI..."
    
    # Create namespace
    kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Install Velero using CLI
    velero install \
        --provider ${PROVIDER} \
        --plugins velero/velero-plugin-for-aws:v1.8.0 \
        --bucket ${BUCKET_NAME} \
        --secret-file /tmp/credentials-velero \
        --use-volume-snapshots=false \
        --use-restic \
        --backup-location-config ${CONFIG_REGION}
    
    print_info "Velero installed using CLI"
}

verify_installation() {
    print_info "Verifying Velero installation..."
    
    # Wait for pods to be ready
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=velero -n ${NAMESPACE} --timeout=300s
    
    # Check Velero server
    if kubectl get deployment velero -n ${NAMESPACE} &> /dev/null; then
        print_info "Velero server is running"
    else
        print_error "Velero server is not running"
        exit 1
    fi
    
    # Check Restic daemonset
    if kubectl get daemonset restic -n ${NAMESPACE} &> /dev/null; then
        print_info "Restic daemonset is running"
    else
        print_warn "Restic daemonset is not found (may not be enabled)"
    fi
    
    # Check backup storage location
    if kubectl get backupstoragelocation default -n ${NAMESPACE} &> /dev/null; then
        print_info "Backup storage location configured"
    else
        print_warn "Backup storage location not found"
    fi
    
    print_info "Installation verification complete"
}

create_backup_storage_location() {
    print_info "Creating backup storage location..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: velero.io/v1
kind: BackupStorageLocation
metadata:
  name: default
  namespace: ${NAMESPACE}
spec:
  provider: ${PROVIDER}
  objectStorage:
    bucket: ${BUCKET_NAME}
  config:
    ${CONFIG_REGION}
EOF
    
    print_info "Backup storage location created"
}

main() {
    print_info "Starting Velero installation for Rook Ceph backup..."
    
    check_prerequisites
    setup_object_storage
    
    echo ""
    echo "Select installation method:"
    echo "1) Helm (Recommended)"
    echo "2) Velero CLI"
    read -p "Enter choice [1-2]: " install_method
    
    case $install_method in
        1)
            install_velero_helm
            verify_installation
            ;;
        2)
            install_velero_cli
            install_velero_cli_method
            verify_installation
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac
    
    print_info "Installation complete!"
    print_info "Next steps:"
    print_info "1. Review backup configurations in backup-pvcs.yaml and backup-cephfs.yaml"
    print_info "2. Create a test backup: kubectl apply -f backup-pvcs.yaml"
    print_info "3. Check backup status: velero backup describe <backup-name>"
    
    # Cleanup
    rm -f /tmp/credentials-velero
}

# Run main function
main

