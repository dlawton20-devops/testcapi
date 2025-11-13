#!/bin/bash
# Script to create Velero backups for Rook Ceph
# Usage: ./create-backup.sh [backup-type] [backup-name]

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

VELERO_NAMESPACE="velero"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_velero() {
    if ! kubectl get namespace ${VELERO_NAMESPACE} &> /dev/null; then
        print_error "Velero namespace not found. Please install Velero first."
        exit 1
    fi
    
    if ! kubectl get deployment velero -n ${VELERO_NAMESPACE} &> /dev/null; then
        print_error "Velero is not installed. Please run install-velero.sh first."
        exit 1
    fi
    
    print_info "Velero is installed and ready"
}

create_pvc_backup() {
    local backup_name=${1:-"rook-ceph-pvcs-backup-$(date +%Y%m%d-%H%M%S)"}
    
    print_info "Creating PVC backup: ${backup_name}"
    
    # Create backup from template
    cat <<EOF | kubectl apply -f -
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: ${backup_name}
  namespace: ${VELERO_NAMESPACE}
  labels:
    app: rook-ceph
    backup-type: pvc
    created: "$(date +%Y-%m-%d)"
spec:
  includedNamespaces:
    - rook-ceph
    - default
  includedResources:
    - persistentvolumeclaims
    - persistentvolumes
    - pods
  defaultVolumesToRestic: true
  snapshotVolumes: false
  includeClusterResources: false
  storageLocation: default
  ttl: 720h
EOF
    
    print_info "Backup created: ${backup_name}"
    print_info "Monitor progress with: velero backup describe ${backup_name}"
}

create_cephfs_backup() {
    local backup_name=${1:-"rook-ceph-cephfs-backup-$(date +%Y%m%d-%H%M%S)"}
    
    print_info "Creating CephFS backup: ${backup_name}"
    
    cat <<EOF | kubectl apply -f -
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: ${backup_name}
  namespace: ${VELERO_NAMESPACE}
  labels:
    app: rook-ceph
    backup-type: cephfs
    created: "$(date +%Y-%m-%d)"
spec:
  includedNamespaces:
    - rook-ceph
    - default
  includedResources:
    - persistentvolumeclaims
    - persistentvolumes
    - pods
    - cephfilesystems.ceph.rook.io
    - cephfilesystemsubpools.ceph.rook.io
  labelSelector:
    matchExpressions:
      - key: volume.beta.kubernetes.io/storage-class
        operator: In
        values:
          - rook-cephfs
          - cephfs
  defaultVolumesToRestic: true
  includeClusterResources: true
  storageLocation: default
  ttl: 720h
EOF
    
    print_info "CephFS backup created: ${backup_name}"
    print_info "Monitor progress with: velero backup describe ${backup_name}"
}

create_full_backup() {
    local backup_name=${1:-"rook-ceph-full-backup-$(date +%Y%m%d-%H%M%S)"}
    
    print_info "Creating full Rook Ceph backup: ${backup_name}"
    
    cat <<EOF | kubectl apply -f -
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: ${backup_name}
  namespace: ${VELERO_NAMESPACE}
  labels:
    app: rook-ceph
    backup-type: full
    created: "$(date +%Y-%m-%d)"
spec:
  includedNamespaces:
    - rook-ceph
    - default
  includedResources:
    - '*'
  includeClusterResources: true
  defaultVolumesToRestic: true
  storageLocation: default
  ttl: 168h
EOF
    
    print_info "Full backup created: ${backup_name}"
    print_info "Monitor progress with: velero backup describe ${backup_name}"
}

list_backups() {
    print_info "Listing all backups:"
    kubectl get backups -n ${VELERO_NAMESPACE}
}

describe_backup() {
    local backup_name=$1
    
    if [ -z "$backup_name" ]; then
        print_error "Backup name required"
        exit 1
    fi
    
    print_info "Backup details for: ${backup_name}"
    kubectl describe backup ${backup_name} -n ${VELERO_NAMESPACE}
}

show_backup_logs() {
    local backup_name=$1
    
    if [ -z "$backup_name" ]; then
        print_error "Backup name required"
        exit 1
    fi
    
    print_info "Backup logs for: ${backup_name}"
    if command -v velero &> /dev/null; then
        velero backup logs ${backup_name}
    else
        print_warn "Velero CLI not found. Install it or use kubectl logs"
        kubectl logs -n ${VELERO_NAMESPACE} -l component=velero --tail=100
    fi
}

show_usage() {
    cat <<EOF
Usage: $0 [command] [options]

Commands:
  pvc [name]              Create PVC backup (default name: rook-ceph-pvcs-backup-TIMESTAMP)
  cephfs [name]           Create CephFS backup (default name: rook-ceph-cephfs-backup-TIMESTAMP)
  full [name]             Create full Rook Ceph backup (default name: rook-ceph-full-backup-TIMESTAMP)
  list                    List all backups
  describe <name>         Describe a specific backup
  logs <name>             Show logs for a backup
  help                    Show this help message

Examples:
  $0 pvc
  $0 pvc my-pvc-backup
  $0 cephfs my-cephfs-backup
  $0 full
  $0 list
  $0 describe rook-ceph-pvcs-backup-20240101-120000
  $0 logs rook-ceph-pvcs-backup-20240101-120000

EOF
}

main() {
    check_velero
    
    local command=${1:-help}
    
    case $command in
        pvc)
            create_pvc_backup "$2"
            ;;
        cephfs)
            create_cephfs_backup "$2"
            ;;
        full)
            create_full_backup "$2"
            ;;
        list)
            list_backups
            ;;
        describe)
            describe_backup "$2"
            ;;
        logs)
            show_backup_logs "$2"
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            print_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"

