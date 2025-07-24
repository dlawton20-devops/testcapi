# Rook Ceph Helm Chart

A simplified Helm chart for deploying Rook Ceph storage orchestrator in Kubernetes clusters.

## Overview

This Helm chart deploys the core Rook Ceph components: CRDs, common resources, operator, cluster, and CephFS filesystem. It provides shared filesystem (CephFS) capabilities with ReadWriteMany (RWX) access mode.

## Prerequisites

- Kubernetes cluster (v1.28 - v1.33)
- Helm 3.x
- At least one of these local storage options:
  - Raw devices (no partitions or formatted filesystem)
  - Raw partitions (no formatted filesystem)
  - LVM Logical Volumes (no formatted filesystem)
  - Encrypted devices (no formatted filesystem)
  - Multipath devices (no formatted filesystem)
  - Persistent Volumes available from a storage class in `block` mode

## Installation

The chart automatically handles the correct deployment order using Helm hooks:

1. **CRDs** (Custom Resource Definitions) - Deployed first
2. **Common Resources** (RBAC, Service Accounts) - Deployed second  
3. **Operator** - Deployed third
4. **Cluster** - Deployed fourth (after operator is ready)
5. **Filesystem** - Deployed fifth (after cluster is ready)
6. **Storage Classes** - Deployed sixth
7. **Toolbox** - Deployed seventh (for debugging)
8. **Test PVC & Pod** - Deployed last (to verify functionality)

### 1. Add the Rook Helm repository

```bash
helm repo add rook-release https://charts.rook.io/release
helm repo update
```

### 2. Install the chart

```bash
# Install with default values
helm install rook-ceph ./rook-ceph

# Install with custom values
helm install rook-ceph ./rook-ceph -f custom-values.yaml
```

**Note**: The deployment script (`./deploy.sh`) automatically handles the proper waiting and verification steps.

## Configuration

### Storage Configuration

The most important configuration is the storage section, which allows you to specify how Ceph should use your nodes and devices:

```yaml
cluster:
  spec:
    storage:
      # Use all nodes in the cluster
      useAllNodes: true
      # Use all devices on each node
      useAllDevices: true
      # Device filter (regex pattern)
      # deviceFilter: "^sd."
      
      # Global configuration for all OSDs
      config:
        # crushRoot: "custom-root" # specify a non-default root label for the CRUSH map
        # metadataDevice: "md0" # specify a non-rotational storage so ceph-volume will use it as block db device of bluestore.
        # databaseSizeMB: "1024" # uncomment if the disks are smaller than 100 GB
        # osdsPerDevice: "1" # this value can be overridden at the node or device level
        # encryptedDevice: "false" # the default value for this option is "false"
        # deviceClass: "myclass" # specify a device class for OSDs in the cluster
      
      # Whether to allow changing the device class of an OSD after it is created
      allowDeviceClassUpdate: false
      # Whether to allow resizing the OSD crush weight after osd pvc is increased
      allowOsdCrushWeightUpdate: false
      
      # Individual nodes and their config can be specified as well, but 'useAllNodes' above must be set to false.
      # Then, only the named nodes below will be used as storage resources.
      # Each node's 'name' field should match their 'kubernetes.io/hostname' label.
      nodes:
        # Example node configurations - customize these for your environment
        # - name: "node1.example.com"
        #   devices: # specific devices to use for storage can be specified for each node
        #     - name: "sdb"
        #     - name: "nvme01" # multiple osds can be created on high performance devices
        #       config:
        #         osdsPerDevice: "5"
        #     - name: "/dev/disk/by-id/ata-ST4000DM004-XXXX" # devices can be specified using full udev paths
        #   config: # configuration can be specified at the node level which overrides the cluster level config
        # - name: "node2.example.com"
        #   deviceFilter: "^sd."
```

### Example Custom Values for 3 Nodes

Create a `custom-values.yaml` file with your specific node configuration:

```yaml
cluster:
  spec:
    storage:
      useAllNodes: false  # Set to false when specifying individual nodes
      useAllDevices: false  # Set to false when specifying individual devices
      nodes:
        - name: "node1.example.com"
          devices:
            - name: "sdb"
            - name: "sdc"
        - name: "node2.example.com"
          devices:
            - name: "sdb"
            - name: "sdc"
        - name: "node3.example.com"
          devices:
            - name: "sdb"
            - name: "sdc"
```

### Key Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `operator.enabled` | Enable Rook operator | `true` |
| `operator.namespace` | Namespace for Rook operator | `rook-ceph` |
| `cluster.enabled` | Enable Ceph cluster | `true` |
| `cluster.spec.storage.useAllNodes` | Use all nodes in cluster | `true` |
| `cluster.spec.storage.useAllDevices` | Use all devices on nodes | `true` |
| `cluster.spec.storage.deviceFilter` | Regex pattern for device filtering | `""` |
| `filesystem.enabled` | Enable CephFS filesystem | `true` |
| `storageClasses.cephfs.enabled` | Enable CephFS storage class | `true` |
| `toolbox.enabled` | Enable Ceph toolbox | `true` |
| `testPvc.enabled` | Enable test PVC and pod | `true` |

## Usage

### Verify Installation

1. Check that all pods are running:

```bash
kubectl get pods -n rook-ceph
```

2. Check cluster health:

```bash
kubectl -n rook-ceph get cephcluster -o yaml
```

### Using Storage Classes

Once the cluster is healthy, you can use the CephFS storage class for ReadWriteMany (RWX) access:

#### Shared Filesystem (CephFS)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-shared-pvc
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: rook-cephfs
  resources:
    requests:
      storage: 1Gi
```

### Accessing the Ceph Dashboard

The Ceph dashboard is enabled by default. To access it:

```bash
kubectl -n rook-ceph get service rook-ceph-mgr-dashboard
kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode
```

## Monitoring

The chart includes Prometheus monitoring configuration. To enable monitoring:

```yaml
cluster:
  spec:
    monitoring:
      enabled: true
      rulesNamespace: rook-ceph
```

## Troubleshooting

### Common Issues

1. **OSDs not being created**: Check that devices are available and not formatted
2. **Cluster not healthy**: Use the toolbox to check detailed status
3. **Storage classes not working**: Verify CSI drivers are running

### Using the Toolbox

The toolbox provides access to Ceph commands:

```bash
# Get cluster status
kubectl -n rook-ceph exec -it deploy/rook-ceph-toolbox -- ceph status

# List OSDs
kubectl -n rook-ceph exec -it deploy/rook-ceph-toolbox -- ceph osd tree

# Check pools
kubectl -n rook-ceph exec -it deploy/rook-ceph-toolbox -- ceph osd pool ls

# Check CephFS status
kubectl -n rook-ceph exec -it deploy/rook-ceph-toolbox -- ceph fs status
```

### Testing the Storage Class

A test PVC and pod are automatically created to verify the CephFS storage class:

```bash
# Check test PVC status
kubectl get pvc test-cephfs-pvc -n rook-ceph

# Check test pod logs
kubectl logs test-cephfs-pod -n rook-ceph

# Verify the test file was created
kubectl exec -it test-cephfs-pod -n rook-ceph -- cat /mnt/cephfs/test.txt
```

## Uninstallation

To uninstall the chart:

```bash
helm uninstall rook-ceph
```

**Warning**: This will remove all Ceph data. Make sure to backup any important data before uninstalling.

## Contributing

This chart is based on the official Rook documentation and examples. For more information, visit:

- [Rook Documentation](https://rook.io/docs/rook/latest/)
- [Rook GitHub Repository](https://github.com/rook/rook)

## License

This chart is licensed under the Apache 2.0 License. 