#!/bin/bash
set -e

# Velero Installation Script for Rook Ceph Backup
# This script installs Velero on a Kubernetes cluster

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
PROVIDER="aws"
BUCKET_NAME="velero-backups"
REGION="minio"
S3_ENDPOINT=""
CREDENTIALS_FILE=""
TARGET_CLUSTER=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --provider)
      PROVIDER="$2"
      shift 2
      ;;
    --bucket)
      BUCKET_NAME="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --s3-endpoint)
      S3_ENDPOINT="$2"
      shift 2
      ;;
    --credentials)
      CREDENTIALS_FILE="$2"
      shift 2
      ;;
    --target-cluster)
      TARGET_CLUSTER=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --provider PROVIDER       Storage provider (aws, azure, gcp) [default: aws]"
      echo "  --bucket BUCKET_NAME       S3 bucket name [default: velero-backups]"
      echo "  --region REGION            S3 region [default: minio]"
      echo "  --s3-endpoint ENDPOINT     S3 endpoint URL (required for MinIO)"
      echo "  --credentials FILE         Path to credentials file"
      echo "  --target-cluster           Install on target cluster (for restore)"
      echo "  -h, --help                Show this help message"
      echo ""
      echo "Example:"
      echo "  $0 --s3-endpoint https://minio.velero.svc.cluster.local:9000 --credentials ./credentials-velero"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      exit 1
      ;;
  esac
done

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v velero &> /dev/null; then
  echo -e "${RED}Error: Velero CLI not found. Please install it first.${NC}"
  echo "Installation: https://velero.io/docs/main/basic-install/"
  exit 1
fi

if ! command -v kubectl &> /dev/null; then
  echo -e "${RED}Error: kubectl not found. Please install it first.${NC}"
  exit 1
fi

# Check kubectl connectivity
if ! kubectl cluster-info &> /dev/null; then
  echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Prerequisites check passed${NC}"

# Check for credentials file
if [ -z "$CREDENTIALS_FILE" ]; then
  echo -e "${YELLOW}Credentials file not specified.${NC}"
  read -p "Enter path to credentials file: " CREDENTIALS_FILE
fi

if [ ! -f "$CREDENTIALS_FILE" ]; then
  echo -e "${RED}Error: Credentials file not found: $CREDENTIALS_FILE${NC}"
  echo "Create a credentials file with S3 access keys"
  exit 1
fi

# For MinIO, require S3 endpoint
if [ "$REGION" == "minio" ] && [ -z "$S3_ENDPOINT" ]; then
  echo -e "${YELLOW}S3 endpoint not specified for MinIO.${NC}"
  read -p "Enter S3 endpoint URL (e.g., https://minio.velero.svc.cluster.local:9000): " S3_ENDPOINT
fi

# Check if Velero is already installed
if kubectl get namespace velero &> /dev/null; then
  echo -e "${YELLOW}Velero namespace already exists.${NC}"
  read -p "Do you want to reinstall? (y/N): " REINSTALL
  if [[ ! $REINSTALL =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
  fi
  echo -e "${YELLOW}Uninstalling existing Velero...${NC}"
  velero uninstall --force
fi

# Install Velero
echo -e "${YELLOW}Installing Velero...${NC}"

INSTALL_CMD="velero install \
  --provider $PROVIDER \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket $BUCKET_NAME \
  --secret-file $CREDENTIALS_FILE \
  --use-volume-snapshots=false \
  --use-node-agent \
  --default-volumes-to-fs-backup"

# Add S3 endpoint if provided
if [ -n "$S3_ENDPOINT" ]; then
  INSTALL_CMD="$INSTALL_CMD \
  --backup-location-config region=$REGION,s3ForcePathStyle=\"true\",s3Url=$S3_ENDPOINT"
else
  INSTALL_CMD="$INSTALL_CMD \
  --backup-location-config region=$REGION"
fi

echo "Running: $INSTALL_CMD"
eval $INSTALL_CMD

# Wait for Velero to be ready
echo -e "${YELLOW}Waiting for Velero to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=velero -n velero --timeout=300s

# Verify installation
echo -e "${YELLOW}Verifying installation...${NC}"

if kubectl get pods -n velero | grep -q "Running"; then
  echo -e "${GREEN}✓ Velero pods are running${NC}"
else
  echo -e "${RED}✗ Velero pods are not running${NC}"
  kubectl get pods -n velero
  exit 1
fi

# Check backup storage location
echo -e "${YELLOW}Checking backup storage location...${NC}"
sleep 5
velero backup-location get

# Display status
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Velero installation completed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Verify backup storage location: velero backup-location get"
echo "  2. Create a test backup: velero backup create test-backup --include-namespaces default"
echo "  3. Check backup status: velero backup describe test-backup"
echo ""

if [ "$TARGET_CLUSTER" = true ]; then
  echo -e "${YELLOW}Note: This is a target cluster for restore operations.${NC}"
  echo "Ensure backup storage is accessible from this cluster."
fi

