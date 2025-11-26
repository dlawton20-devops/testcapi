#!/bin/bash
set -e

# Rook Ceph Backup Creation Script
# This script creates a backup of Rook Ceph cluster and applications

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
BACKUP_TYPE="full"
NAMESPACES=""
BACKUP_NAME=""
TTL=""
INCLUDE_CLUSTER_RESOURCES=true

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --type)
      BACKUP_TYPE="$2"
      shift 2
      ;;
    --namespaces)
      NAMESPACES="$2"
      shift 2
      ;;
    --name)
      BACKUP_NAME="$2"
      shift 2
      ;;
    --ttl)
      TTL="$2"
      shift 2
      ;;
    --no-cluster-resources)
      INCLUDE_CLUSTER_RESOURCES=false
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --type TYPE                Backup type: full, rook-only, app-only [default: full]"
      echo "  --namespaces NAMESPACES    Comma-separated list of namespaces"
      echo "  --name NAME                Custom backup name (auto-generated if not provided)"
      echo "  --ttl DURATION             Backup TTL (e.g., 720h for 30 days)"
      echo "  --no-cluster-resources     Exclude cluster-scoped resources"
      echo "  -h, --help                Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0 --type full"
      echo "  $0 --type app-only --namespaces production,staging"
      echo "  $0 --type rook-only --name rook-backup-$(date +%Y%m%d)"
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
  echo -e "${RED}Error: Velero CLI not found${NC}"
  exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
  echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
  exit 1
fi

# Check if Velero is installed
if ! kubectl get namespace velero &> /dev/null; then
  echo -e "${RED}Error: Velero not installed. Run install-velero.sh first${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Prerequisites check passed${NC}"

# Generate backup name if not provided
if [ -z "$BACKUP_NAME" ]; then
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  BACKUP_NAME="rook-ceph-${BACKUP_TYPE}-backup-${TIMESTAMP}"
fi

echo -e "${YELLOW}Creating backup: $BACKUP_NAME${NC}"

# Build backup command based on type
BACKUP_CMD="velero backup create $BACKUP_NAME"

case $BACKUP_TYPE in
  full)
    echo -e "${YELLOW}Creating full cluster backup...${NC}"
    if [ -n "$NAMESPACES" ]; then
      BACKUP_CMD="$BACKUP_CMD --include-namespaces=$NAMESPACES"
    else
      BACKUP_CMD="$BACKUP_CMD --include-namespaces=rook-ceph,default"
    fi
    if [ "$INCLUDE_CLUSTER_RESOURCES" = true ]; then
      BACKUP_CMD="$BACKUP_CMD --include-cluster-resources=true"
    fi
    ;;
  rook-only)
    echo -e "${YELLOW}Creating Rook Ceph operator backup...${NC}"
    BACKUP_CMD="$BACKUP_CMD --include-namespaces=rook-ceph"
    BACKUP_CMD="$BACKUP_CMD --include-resources=cephclusters.ceph.rook.io,cephblockpools.ceph.rook.io,cephfilesystems.ceph.rook.io,cephobjectstores.ceph.rook.io,deployments,statefulsets,configmaps,secrets"
    ;;
  app-only)
    if [ -z "$NAMESPACES" ]; then
      echo -e "${RED}Error: --namespaces required for app-only backup${NC}"
      exit 1
    fi
    echo -e "${YELLOW}Creating application backup for namespaces: $NAMESPACES${NC}"
    BACKUP_CMD="$BACKUP_CMD --include-namespaces=$NAMESPACES"
    ;;
  *)
    echo -e "${RED}Error: Unknown backup type: $BACKUP_TYPE${NC}"
    exit 1
    ;;
esac

# Add common options
BACKUP_CMD="$BACKUP_CMD --default-volumes-to-fs-backup --wait"

# Add TTL if provided
if [ -n "$TTL" ]; then
  BACKUP_CMD="$BACKUP_CMD --ttl=$TTL"
fi

# Execute backup
echo "Running: $BACKUP_CMD"
eval $BACKUP_CMD

# Check backup status
echo ""
echo -e "${YELLOW}Checking backup status...${NC}"
sleep 5

BACKUP_STATUS=$(velero backup describe $BACKUP_NAME --details | grep -i "Phase:" | awk '{print $2}')

if [ "$BACKUP_STATUS" == "Completed" ]; then
  echo -e "${GREEN}✓ Backup completed successfully${NC}"
elif [ "$BACKUP_STATUS" == "PartiallyFailed" ]; then
  echo -e "${YELLOW}⚠ Backup completed with some failures${NC}"
elif [ "$BACKUP_STATUS" == "Failed" ]; then
  echo -e "${RED}✗ Backup failed${NC}"
  echo "Check logs: velero backup logs $BACKUP_NAME"
  exit 1
else
  echo -e "${YELLOW}Backup status: $BACKUP_STATUS${NC}"
fi

# Display backup information
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Backup Information${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
velero backup describe $BACKUP_NAME
echo ""

# Show backup summary
echo -e "${YELLOW}Backup Summary:${NC}"
velero backup get $BACKUP_NAME
echo ""

echo -e "${GREEN}Backup created: $BACKUP_NAME${NC}"
echo ""
echo "Next steps:"
echo "  1. Verify backup: velero backup describe $BACKUP_NAME"
echo "  2. View backup logs: velero backup logs $BACKUP_NAME"
echo "  3. List backups: velero backup get"
echo ""

