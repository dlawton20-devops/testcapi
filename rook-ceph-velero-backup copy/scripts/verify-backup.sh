#!/bin/bash
set -e

# Backup Verification Script
# This script verifies the integrity of a Velero backup

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
BACKUP_NAME=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --backup)
      BACKUP_NAME="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --backup NAME     Backup name to verify (required)"
      echo "  -h, --help       Show this help message"
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
if ! command -v velero &> /dev/null; then
  echo -e "${RED}Error: Velero CLI not found${NC}"
  exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
  echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
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
echo -e "${YELLOW}Verifying backup: $BACKUP_NAME${NC}"
if ! velero backup describe $BACKUP_NAME &>/dev/null; then
  echo -e "${RED}Error: Backup '$BACKUP_NAME' not found${NC}"
  exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Backup Verification${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check backup phase
echo -e "${YELLOW}1. Checking backup status...${NC}"
BACKUP_PHASE=$(velero backup describe $BACKUP_NAME --details | grep -i "Phase:" | awk '{print $2}')
echo "Phase: $BACKUP_PHASE"

if [ "$BACKUP_PHASE" == "Completed" ]; then
  echo -e "${GREEN}✓ Backup is in Completed state${NC}"
elif [ "$BACKUP_PHASE" == "PartiallyFailed" ]; then
  echo -e "${YELLOW}⚠ Backup has some failures${NC}"
else
  echo -e "${RED}✗ Backup is not in Completed state${NC}"
fi

# Get backup details
echo ""
echo -e "${YELLOW}2. Backup Details:${NC}"
velero backup describe $BACKUP_NAME

# Check for errors
echo ""
echo -e "${YELLOW}3. Checking for errors...${NC}"
BACKUP_LOGS=$(velero backup logs $BACKUP_NAME 2>&1)
ERROR_COUNT=$(echo "$BACKUP_LOGS" | grep -i "error" | wc -l | tr -d ' ')

if [ "$ERROR_COUNT" -eq 0 ]; then
  echo -e "${GREEN}✓ No errors found in backup logs${NC}"
else
  echo -e "${YELLOW}⚠ Found $ERROR_COUNT error(s) in backup logs${NC}"
  echo "$BACKUP_LOGS" | grep -i "error" | head -10
fi

# Check backup storage location
echo ""
echo -e "${YELLOW}4. Checking backup storage location...${NC}"
BACKUP_LOCATION=$(velero backup describe $BACKUP_NAME --details | grep -i "Storage Location:" | awk '{print $3}')
if [ -n "$BACKUP_LOCATION" ]; then
  echo "Storage Location: $BACKUP_LOCATION"
  LOCATION_STATUS=$(velero backup-location get $BACKUP_LOCATION -o json 2>/dev/null | jq -r '.status.phase' 2>/dev/null || echo "Unknown")
  if [ "$LOCATION_STATUS" == "Available" ]; then
    echo -e "${GREEN}✓ Backup storage location is available${NC}"
  else
    echo -e "${YELLOW}⚠ Backup storage location status: $LOCATION_STATUS${NC}"
  fi
fi

# Summary
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Verification Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

if [ "$BACKUP_PHASE" == "Completed" ] && [ "$ERROR_COUNT" -eq 0 ]; then
  echo -e "${GREEN}✓ Backup verification passed${NC}"
  echo "Backup '$BACKUP_NAME' is ready for restore."
  exit 0
else
  echo -e "${YELLOW}⚠ Backup verification completed with warnings${NC}"
  echo "Review the details above before restoring."
  exit 1
fi

