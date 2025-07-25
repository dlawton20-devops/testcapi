# OpenStack Rook Ceph Deployment Guide

This guide walks you through deploying Rook Ceph on OpenStack with dedicated storage volumes.

## 📋 Prerequisites

- OpenStack CLI configured and authenticated
- Kubernetes cluster running on OpenStack instances
- kubectl configured to access your cluster
- 3 platform worker nodes with "platformworker" in their names
- SSH access to your instances

## 🗂️ Step 1: Create OpenStack Volumes

### Create 3 volumes (100GB each) for Ceph storage

```bash
# Create volumes for your 3 platform worker nodes
openstack volume create --size 100 --description "Ceph storage for node1" ceph-storage-node1
openstack volume create --size 100 --description "Ceph storage for node2" ceph-storage-node2  
openstack volume create --size 100 --description "Ceph storage for node3" ceph-storage-node3

# List created volumes to verify
openstack volume list
```

**Expected Output:**
```
+--------------------------------------+-------------------+-----------+------+-------------+
| ID                                   | Name              | Status    | Size | Attached to |
+--------------------------------------+-------------------+-----------+------+-------------+
| xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx | ceph-storage-node1| available |  100 |             |
| xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx | ceph-storage-node2| available |  100 |             |
| xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx | ceph-storage-node3| available |  100 |             |
+--------------------------------------+-----------+-----------+------+-------------+
```

## 🔗 Step 2: Attach Volumes to Instances

### Attach volumes to your platform worker instances

```bash
# Replace <instance-name-1>, <instance-name-2>, <instance-name-3> with your actual instance names
openstack server add volume <instance-name-1> ceph-storage-node1 --device /dev/vdb
openstack server add volume <instance-name-2> ceph-storage-node2 --device /dev/vdb
openstack server add volume <instance-name-3> ceph-storage-node3 --device /dev/vdb

# Verify attachments
openstack server show <instance-name-1> | grep -A 10 "volumes_attached"
```

**Expected Output:**
```
| volumes_attached | [{'id': 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx', 'delete_on_termination': False}] |
```

## 🔧 Step 3: Mount Volumes on Each Instance

SSH into each of your 3 platform worker instances and run these commands:

### Check if volume is detected
```bash
lsblk
```

**Expected Output:**
```
NAME   MAJ:MIN RM SIZE RO TYPE MOUNTPOINT
vda    253:0    0   20G  0 disk 
└─vda1 253:1    0   20G  0 part /
vdb    253:16   0  100G  0 disk  ← This is your new volume
```

### Format and mount the volume
```bash
# Format the volume with XFS filesystem
sudo mkfs.xfs /dev/vdb

# Create mount point for Ceph data
sudo mkdir -p /var/lib/ceph

# Mount the volume
sudo mount /dev/vdb /var/lib/ceph

# Make mount permanent (add to /etc/fstab)
echo "/dev/vdb /var/lib/ceph xfs defaults 0 0" | sudo tee -a /etc/fstab

# Verify mount
df -h /var/lib/ceph
```

**Expected Output:**
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/vdb        100G   33M  100G   1% /var/lib/ceph
```

### Verify mount persistence
```bash
# Test that the mount persists after reboot
sudo umount /var/lib/ceph
sudo mount -a
df -h /var/lib/ceph
```

## 🏷️ Step 4: Label Kubernetes Nodes

### Run the automated labeling script

```bash
# Make sure you're in the cephhelm directory
cd /path/to/cephhelm

# Run the labeling script
./examples/label-nodes.sh
```

**Expected Output:**
```
[INFO] Finding nodes with 'platformworker' in the name...
[INFO] Found 3 platform worker node(s):
  - node1-platformworker
  - node2-platformworker
  - node3-platformworker
[INFO] Starting node labeling process...
[SUCCESS] Applied ceph-storage=true to node1-platformworker
[SUCCESS] Applied node-role.caas.com/platform-worker=true to node1-platformworker
...
```

### Verify node labels
```bash
# Show all nodes with labels
kubectl get nodes --show-labels

# Show only platform worker nodes
kubectl get nodes --show-labels | grep platformworker
```

**Expected Output:**
```
NAME                    STATUS   ROLES    AGE   VERSION   LABELS
node1-platformworker    Ready    worker   1d    v1.24.0   ceph-storage=true,node-role.caas.com/platform-worker=true,...
node2-platformworker    Ready    worker   1d    v1.24.0   ceph-storage=true,node-role.caas.com/platform-worker=true,...
node3-platformworker    Ready    worker   1d    v1.24.0   ceph-storage=true,node-role.caas.com/platform-worker=true,...
```

## 🚀 Step 5: Deploy Rook Ceph

### Option A: Using the deployment script (Recommended)

```bash
# Deploy with the ceph-storage configuration
./deploy.sh -f examples/values-ceph-storage.yaml
```

### Option B: Manual Helm commands

```bash
# Install the chart
helm install rook-ceph . -f examples/values-ceph-storage.yaml

# Or upgrade if already installed
helm upgrade rook-ceph . -f examples/values-ceph-storage.yaml
```

### Option C: Dry run first (Recommended for testing)

```bash
# Test the template without installing
helm template rook-ceph . -f examples/values-ceph-storage.yaml --dry-run

# Or install with dry run
helm install rook-ceph . -f examples/values-ceph-storage.yaml --dry-run
```

## 🔍 Step 6: Verify Deployment

### Check all Rook Ceph resources
```bash
# Check all resources in rook-ceph namespace
kubectl get all -n rook-ceph

# Check Ceph cluster status
kubectl get cephcluster -n rook-ceph

# Check Ceph filesystem
kubectl get cephfilesystem -n rook-ceph

# Check storage classes
kubectl get storageclass
```

**Expected Output:**
```
NAME                    PROVISIONER                     RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
rook-cephfs (default)   rook-ceph.cephfs.csi.ceph.com   Delete          Immediate              true                   2m
```

### Check toolbox and Ceph status
```bash
# Check toolbox pod
kubectl get pods -n rook-ceph -l app=rook-ceph-toolbox

# Access toolbox and check Ceph status
kubectl exec -it -n rook-ceph deploy/rook-ceph-toolbox -- ceph status

# Check Ceph cluster health
kubectl exec -it -n rook-ceph deploy/rook-ceph-toolbox -- ceph health
```

**Expected Output:**
```
  cluster:
    id:     xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    health: HEALTH_OK
 
  services:
    mon: 3 daemons, quorum a,b,c (age 2m)
    mgr: a(active, since 1m)
    mds: myfs:1 {0=myfs.a=up:active} 1 up:standby
    osd: 3 osds: 3 up (since 1m), 3 in (since 1m)
```

### Check test PVC and pod
```bash
# Check test PVC
kubectl get pvc -n rook-ceph

# Check test pod
kubectl get pods -n rook-ceph -l app=test-cephfs

# Check test pod logs
kubectl logs -n rook-ceph test-cephfs-pod
```

**Expected Output:**
```
CephFS test successful!
```

## 🛠️ Troubleshooting

### Common Issues

#### PodSecurityPolicy API Version Error
If you see an error like:
```
resource mapping not found for the name: rook-ceph-system namespace "" from "": no matched for kind "podsecuritypolicy" in version "policy/v1beta1"
```

This is because PodSecurityPolicies were deprecated in Kubernetes 1.21+ and removed in 1.25+. The chart has been updated to remove these deprecated resources. Modern Kubernetes clusters use Pod Security Standards instead.

**Solution:** The chart has been fixed to remove PodSecurityPolicy references. If you're still seeing this error, make sure you're using the latest version of the chart.

### Check Ceph cluster events
```bash
kubectl get events -n rook-ceph --sort-by='.lastTimestamp'
```

### Check operator logs
```bash
kubectl logs -n rook-ceph -l app=rook-ceph-operator
```

### Check OSD pods
```bash
kubectl get pods -n rook-ceph -l app=rook-ceph-osd
kubectl logs -n rook-ceph -l app=rook-ceph-osd
```

### Check monitor pods
```bash
kubectl get pods -n rook-ceph -l app=rook-ceph-mon
kubectl logs -n rook-ceph -l app=rook-ceph-mon
```

## 🧹 Cleanup (if needed)

### Uninstall Rook Ceph
```bash
# Uninstall the Helm chart
helm uninstall rook-ceph

# Delete the namespace
kubectl delete namespace rook-ceph
```

### Detach and delete OpenStack volumes
```bash
# Detach volumes from instances
openstack server remove volume <instance-name-1> ceph-storage-node1
openstack server remove volume <instance-name-2> ceph-storage-node2
openstack server remove volume <instance-name-3> ceph-storage-node3

# Delete volumes
openstack volume delete ceph-storage-node1
openstack volume delete ceph-storage-node2
openstack volume delete ceph-storage-node3
```

## 📝 Notes

- The volumes are mounted at `/var/lib/ceph` on each node
- Ceph data is stored in `/var/lib/ceph` on the attached volumes
- The deployment uses `ceph-storage=true` and `node-role.caas.com/platform-worker=true` labels
- The CephFS storage class is set as default for ReadWriteMany (RWX) access
- Monitor count is set to 3 for high availability
- OSDs are created on the `/dev/vdb` devices

## 🎯 Next Steps

After successful deployment:

1. **Test the storage class** by creating a PVC
2. **Configure your applications** to use the `rook-cephfs` storage class
3. **Monitor Ceph health** regularly using the toolbox
4. **Set up monitoring** with Prometheus/Grafana if needed
5. **Configure backups** for your Ceph cluster 