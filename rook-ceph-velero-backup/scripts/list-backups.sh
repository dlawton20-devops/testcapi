#!/bin/bash
set -e

# List Velero Backups Script
# This script lists all available Velero backups with details

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
DETAILED=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --detailed|-d)
      DETAILED=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --detailed, -d    Show detailed information for each backup"
      echo "  -h, --help        Show this help message"
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      exit 1
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

# Check if Velero is installed
if ! kubectl get namespace velero &> /dev/null; then
  echo -e "${RED}Error: Velero not installed${NC}"
  exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Velero Backups${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# List backups
velero backup get

if [ "$DETAILED" = true ]; then
  echo ""
  echo -e "${YELLOW}Detailed Backup Information:${NC}"
  echo ""
  
  # Get list of backups
  BACKUPS=$(velero backup get -o json | jq -r '.items[] | .metadata.name' 2>/dev/null || velero backup get | tail -n +2 | awk '{print $1}' | grep -v "^$")
  
  if [ -z "$BACKUPS" ]; then
    echo "No backups found."
    exit 0
  fi
  
  for backup in $BACKUPS; do
    echo -e "${GREEN}----------------------------------------${NC}"
    echo -e "${GREEN}Backup: $backup${NC}"
    echo -e "${GREEN}----------------------------------------${NC}"
    velero backup describe $backup
    echo ""
  done
fi

# Show backup storage location status
echo -e "${YELLOW}Backup Storage Location:${NC}"
velero backup-location get
echo ""

