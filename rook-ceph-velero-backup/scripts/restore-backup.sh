#!/bin/bash
set -e

# Rook Ceph Restore Script
# This script restores a Rook Ceph cluster from a Velero backup

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
BACKUP_NAME=""
RESTORE_NAME=""
NAMESPACES=""
NAMESPACE_MAPPINGS=""
INCLUDE_CLUSTER_RESOURCES=true

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --backup)
      BACKUP_NAME="$2"
      shift 2
      ;;
    --name)
      RESTORE_NAME="$2"
      shift 2
      ;;
    --namespaces)
      NAMESPACES="$2"
      shift 2
      ;;
    --namespace-mappings)
      NAMESPACE_MAPPINGS="$2"
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
      echo "  --backup NAME              Backup name to restore from (required)"
      echo "  --name NAME                Custom restore name (auto-generated if not provided)"
      echo "  --namespaces NAMESPACES    Comma-separated list of namespaces to restore"
      echo "  --namespace-mappings MAP   Namespace mappings (e.g., old:new,prod:prod-new)"
      echo "  --no-cluster-resources     Exclude cluster-scoped resources"
      echo "  -h, --help                Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0 --backup rook-ceph-backup-20240115-020000"
      echo "  $0 --backup app-backup-20240115 --namespaces production"
      echo "  $0 --backup backup-name --namespace-mappings production:production-new"
      exit 0
      ;;
    *)
      if [ -z "$BACKUP_NAME" ]; then
        BACKUP_NAME="$1"
      else
        echo -e "${RED}Unknown option: $1${NC}"
        exit 1
      fi
      shift
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

# Require backup name
if [ -z "$BACKUP_NAME" ]; then
  echo -e "${RED}Error: Backup name is required${NC}"
  echo ""
  echo "Available backups:"
  velero backup get
  echo ""
  echo "Usage: $0 --backup <backup-name>"
  exit 1
fi

# Verify backup exists
echo -e "${YELLOW}Verifying backup exists...${NC}"
if ! velero backup describe $BACKUP_NAME &>/dev/null; then
  echo -e "${RED}Error: Backup '$BACKUP_NAME' not found${NC}"
  echo ""
  echo "Available backups:"
  velero backup get
  exit 1
fi

# Check backup status
BACKUP_PHASE=$(velero backup describe $BACKUP_NAME --details | grep -i "Phase:" | awk '{print $2}')
if [ "$BACKUP_PHASE" != "Completed" ]; then
  echo -e "${YELLOW}Warning: Backup is not in 'Completed' state (current: $BACKUP_PHASE)${NC}"
  read -p "Continue anyway? (y/N): " CONTINUE
  if [[ ! $CONTINUE =~ ^[Yy]$ ]]; then
    exit 0
  fi
fi

echo -e "${GREEN}✓ Prerequisites check passed${NC}"

# Generate restore name if not provided
if [ -z "$RESTORE_NAME" ]; then
  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
  RESTORE_NAME="restore-${BACKUP_NAME}-${TIMESTAMP}"
fi

echo -e "${YELLOW}Creating restore: $RESTORE_NAME${NC}"
echo -e "${YELLOW}From backup: $BACKUP_NAME${NC}"

# Build restore command
RESTORE_CMD="velero restore create $RESTORE_NAME --from-backup $BACKUP_NAME --wait"

# Add namespace filter if provided
if [ -n "$NAMESPACES" ]; then
  RESTORE_CMD="$RESTORE_CMD --include-namespaces=$NAMESPACES"
fi

# Add namespace mappings if provided
if [ -n "$NAMESPACE_MAPPINGS" ]; then
  RESTORE_CMD="$RESTORE_CMD --namespace-mappings=$NAMESPACE_MAPPINGS"
fi

# Add cluster resources option
if [ "$INCLUDE_CLUSTER_RESOURCES" = true ]; then
  RESTORE_CMD="$RESTORE_CMD --include-cluster-resources=true"
else
  RESTORE_CMD="$RESTORE_CMD --include-cluster-resources=false"
fi

# Execute restore
echo "Running: $RESTORE_CMD"
eval $RESTORE_CMD

# Check restore status
echo ""
echo -e "${YELLOW}Checking restore status...${NC}"
sleep 5

RESTORE_STATUS=$(velero restore describe $RESTORE_NAME --details | grep -i "Phase:" | awk '{print $2}')

if [ "$RESTORE_STATUS" == "Completed" ]; then
  echo -e "${GREEN}✓ Restore completed successfully${NC}"
elif [ "$RESTORE_STATUS" == "PartiallyFailed" ]; then
  echo -e "${YELLOW}⚠ Restore completed with some failures${NC}"
elif [ "$RESTORE_STATUS" == "Failed" ]; then
  echo -e "${RED}✗ Restore failed${NC}"
  echo "Check logs: velero restore logs $RESTORE_NAME"
  exit 1
else
  echo -e "${YELLOW}Restore status: $RESTORE_STATUS${NC}"
fi

# Display restore information
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Restore Information${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
velero restore describe $RESTORE_NAME
echo ""

# Show restore summary
echo -e "${YELLOW}Restore Summary:${NC}"
velero restore get $RESTORE_NAME
echo ""

# Post-restore verification suggestions
echo -e "${GREEN}Restore created: $RESTORE_NAME${NC}"
echo ""
echo "Next steps:"
echo "  1. Verify restore: velero restore describe $RESTORE_NAME"
echo "  2. View restore logs: velero restore logs $RESTORE_NAME"
echo "  3. Check restored resources:"
if [ -n "$NAMESPACES" ]; then
  for ns in $(echo $NAMESPACES | tr ',' ' '); do
    echo "     kubectl get all -n $ns"
  done
else
  echo "     kubectl get all -A"
fi
echo "  4. Verify Ceph cluster: kubectl get cephcluster -n rook-ceph"
echo "  5. Check PVCs: kubectl get pvc -A"
echo ""

