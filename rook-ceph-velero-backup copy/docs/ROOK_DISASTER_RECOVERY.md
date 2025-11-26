# Rook Ceph Disaster Recovery Guide

This guide covers Rook Ceph disaster recovery scenarios as documented in the [official Rook documentation](https://www.rook.io/docs/rook/latest-release/Troubleshooting/disaster-recovery/), integrated with Velero backup/restore procedures.

## Disaster Recovery Scenarios

1. **Restoring Mon Quorum** - Recover from mon quorum loss
2. **Restoring CRDs After Deletion** - Recover when Rook CRDs are deleted
3. **Adopting Existing Cluster** - Move Rook cluster to new Kubernetes cluster
4. **PVC-Based Cluster Recovery** - Restore cluster using PVC backups
5. **Namespace Deletion Recovery** - Restore after Rook namespace deletion

## Scenario 1: Restoring Mon Quorum

When mons lose quorum, use Rook's automated restore-quorum command.

### Using Rook kubectl Plugin

```bash
# If the name of the healthy mon is 'c'
kubectl rook-ceph mons restore-quorum c
```

The plugin will walk you through the automated restoration process.

### Manual Procedure

If the plugin is not available, follow these steps:

1. **Identify healthy mon**:
   ```bash
   kubectl get pods -n rook-ceph -l app=rook-ceph-mon
   ```

2. **Remove unhealthy mons from quorum** (requires access to mon pod):
   ```bash
   # Exec into healthy mon pod
   kubectl exec -it -n rook-ceph <healthy-mon-pod> -- bash
   
   # Remove unhealthy mons
   ceph mon remove <unhealthy-mon-id>
   ```

3. **Grow quorum back**:
   ```bash
   # Rook operator will automatically add mons back
   kubectl get pods -n rook-ceph -l app=rook-ceph-mon
   ```

## Scenario 2: Restoring CRDs After Deletion

When Rook CRDs are deleted, they get stuck in `Deleting` state. This procedure restores them.

### Prerequisites

- Access to the cluster
- Backup of CRDs (via Velero or manual)
- Original CephCluster configuration

### Procedure

1. **Scale down operator**:
   ```bash
   kubectl -n rook-ceph scale --replicas=0 deploy/rook-ceph-operator
   ```

2. **Backup all Rook CRs and critical metadata**:
   ```bash
   # Store CephCluster CR settings
   kubectl -n rook-ceph get cephcluster rook-ceph -o yaml > cluster.yaml
   
   # Backup other Rook CRs in terminating state
   kubectl -n rook-ceph get cephblockpool -o yaml > blockpools.yaml
   kubectl -n rook-ceph get cephfilesystem -o yaml > filesystems.yaml
   kubectl -n rook-ceph get cephobjectstore -o yaml > objectstores.yaml
   
   # Backup critical secrets and configmaps
   kubectl -n rook-ceph get secret -o yaml > secrets.yaml
   kubectl -n rook-ceph get configmap -o yaml > configmaps.yaml
   ```

3. **Remove finalizers from CRDs**:
   ```bash
   # Remove finalizer from CephCluster
   kubectl -n rook-ceph patch cephcluster rook-ceph --type json -p '[{"op":"remove","path":"/metadata/finalizers"}]'
   
   # Remove finalizers from other CRs
   kubectl -n rook-ceph patch cephblockpool <pool-name> --type json -p '[{"op":"remove","path":"/metadata/finalizers"}]'
   ```

4. **Delete CRDs**:
   ```bash
   kubectl delete crd cephclusters.ceph.rook.io
   kubectl delete crd cephblockpools.ceph.rook.io
   kubectl delete crd cephfilesystems.ceph.rook.io
   kubectl delete crd cephobjectstores.ceph.rook.io
   ```

5. **Reinstall Rook CRDs**:
   ```bash
   kubectl create -f crds.yaml -f common.yaml -f operator.yaml
   ```

6. **Restore CRs from backup**:
   ```bash
   kubectl apply -f cluster.yaml
   kubectl apply -f blockpools.yaml
   kubectl apply -f filesystems.yaml
   kubectl apply -f objectstores.yaml
   ```

7. **Scale operator back up**:
   ```bash
   kubectl -n rook-ceph scale --replicas=1 deploy/rook-ceph-operator
   ```

### Using Velero for CRD Recovery

If you have a Velero backup, restore the CRDs:

```bash
# Create restore manifest for CRDs only
cat > restore-crds.yaml <<EOF
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: restore-rook-crds
  namespace: velero
spec:
  backupName: <backup-name>
  includedNamespaces:
    - rook-ceph
  includeClusterResources: true
  includedResources:
    - cephclusters.ceph.rook.io
    - cephblockpools.ceph.rook.io
    - cephfilesystems.ceph.rook.io
    - cephobjectstores.ceph.rook.io
  restorePVs: false
EOF

kubectl apply -f restore-crds.yaml
```

## Scenario 3: Adopting Existing Cluster into New Kubernetes Cluster

Move an existing Rook Ceph cluster to a new Kubernetes cluster.

### Prerequisites

- Access to original cluster's `dataDirHostPath`
- Original cluster configuration
- New Kubernetes cluster ready

### Procedure

1. **Backup original cluster configuration**:
   ```bash
   # Backup CephCluster CR
   kubectl -n rook-ceph get cephcluster rook-ceph -o yaml > cluster.yaml
   
   # Backup other CRs
   kubectl -n rook-ceph get cephblockpool -o yaml > blockpools.yaml
   kubectl -n rook-ceph get cephfilesystem -o yaml > filesystems.yaml
   
   # Backup secrets and configmaps
   kubectl -n rook-ceph get secret -o yaml > secrets.yaml
   kubectl -n rook-ceph get configmap -o yaml > configmaps.yaml
   ```

2. **Extract critical information from dataDirHostPath**:
   ```bash
   # On original cluster nodes, find dataDirHostPath
   # Default: /var/lib/rook
   
   # Extract from rook-ceph.config
   cat /var/lib/rook/rook-ceph/rook-ceph.config
   
   # Extract from client.admin.keyring
   cat /var/lib/rook/rook-ceph/client.admin.keyring
   ```

3. **Create rook-ceph-mon secret**:
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: rook-ceph-mon
     namespace: rook-ceph
     finalizers:
       - ceph.rook.io/disaster-protection
   type: kubernetes.io/rook
   data:
     ceph-secret: <base64-encoded-keyring>
     ceph-username: Y2xpZW50LmFkbWlu  # client.admin
     mon-secret: <base64-encoded-keyring>
     fsid: <base64-encoded-fsid>
   ```

   Encode values:
   ```bash
   echo -n "client.admin keyring content" | base64
   echo -n "cluster-fsid" | base64
   ```

4. **Create rook-ceph-mon-endpoints configmap**:
   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: rook-ceph-mon-endpoints
     namespace: rook-ceph
     finalizers:
       - ceph.rook.io/disaster-protection
   data:
     csi-cluster-config-json: '[{"clusterID":"rook-ceph","monitors":["<mon1-ip>:6789","<mon2-ip>:6789","<mon3-ip>:6789"],"namespace":""}]'
     data: k=<mon1-ip>:6789,m=<mon2-ip>:6789,o=<mon3-ip>:6789
     mapping: '{"node":{"k":{"Name":"<node1>","Hostname":"<node1>","Address":"<node1-ip>"},"m":{"Name":"<node2>","Hostname":"<node2>","Address":"<node2-ip>"},"o":{"Name":"<node3>","Hostname":"<node3>","Address":"<node3-ip>"}}}'
     maxMonId: "15"
   ```

5. **On new cluster, deploy Rook**:
   ```bash
   kubectl create -f crds.yaml -f common.yaml -f operator.yaml
   ```

6. **Create secret and configmap**:
   ```bash
   kubectl create -f rook-ceph-mon.yaml -f rook-ceph-mon-endpoints.yaml
   ```

7. **Create CephCluster CR**:
   ```bash
   kubectl create -f cluster.yaml
   ```

8. **Restore other CRs**:
   ```bash
   kubectl apply -f blockpools.yaml
   kubectl apply -f filesystems.yaml
   ```

### Using Velero for Cluster Adoption

```bash
# On original cluster, create backup
kubectl apply -f configs/backup-full.yaml

# On new cluster, restore
kubectl apply -f configs/restore-full.yaml

# Then follow steps 3-8 above to adopt the cluster
```

## Scenario 4: Backing Up and Restoring PVC-Based Cluster

Restore a Rook cluster based on PVCs into a new Kubernetes cluster.

### Backup Procedure

1. **Backup all PVCs using Velero**:
   ```bash
   # Create backup manifest
   cat > backup-pvc-cluster.yaml <<EOF
   apiVersion: velero.io/v1
   kind: Backup
   metadata:
     name: rook-pvc-cluster-backup
     namespace: velero
   spec:
     includedNamespaces:
       - rook-ceph
       - <application-namespaces>
     includeClusterResources: true
     defaultVolumesToFsBackup: true
     storageLocation: default
   EOF
   
   kubectl apply -f backup-pvc-cluster.yaml
   ```

2. **Backup Rook CRs separately**:
   ```bash
   kubectl -n rook-ceph get cephcluster -o yaml > cluster.yaml
   kubectl -n rook-ceph get cephblockpool -o yaml > blockpools.yaml
   kubectl -n rook-ceph get cephfilesystem -o yaml > filesystems.yaml
   ```

### Restore Procedure

1. **Install Rook on new cluster**:
   ```bash
   kubectl create -f crds.yaml -f common.yaml -f operator.yaml
   ```

2. **Restore from Velero backup**:
   ```bash
   # Create restore manifest
   cat > restore-pvc-cluster.yaml <<EOF
   apiVersion: velero.io/v1
   kind: Restore
   metadata:
     name: restore-pvc-cluster
     namespace: velero
   spec:
     backupName: rook-pvc-cluster-backup
     includedNamespaces:
       - rook-ceph
       - <application-namespaces>
     includeClusterResources: true
     restorePVs: true
   EOF
   
   kubectl apply -f restore-pvc-cluster.yaml
   ```

3. **Restore Rook CRs**:
   ```bash
   kubectl apply -f cluster.yaml
   kubectl apply -f blockpools.yaml
   kubectl apply -f filesystems.yaml
   ```

4. **Verify cluster**:
   ```bash
   kubectl get cephcluster -n rook-ceph
   kubectl get pods -n rook-ceph
   kubectl get pvc -A
   ```

## Scenario 5: Restoring After Namespace Deletion

Recover Rook cluster after the `rook-ceph` namespace is deleted.

### Procedure

1. **Recreate namespace**:
   ```bash
   kubectl create namespace rook-ceph
   ```

2. **Restore from Velero backup**:
   ```bash
   # If you have a Velero backup
   cat > restore-namespace.yaml <<EOF
   apiVersion: velero.io/v1
   kind: Restore
   metadata:
     name: restore-rook-namespace
     namespace: velero
   spec:
     backupName: <backup-name>
     includedNamespaces:
       - rook-ceph
     includeClusterResources: true
     restorePVs: true
   EOF
   
   kubectl apply -f restore-namespace.yaml
   ```

3. **If no Velero backup, manual restore**:
   ```bash
   # Reinstall Rook
   kubectl create -f crds.yaml -f common.yaml -f operator.yaml
   
   # Recreate CephCluster CR (if you have backup)
   kubectl apply -f cluster.yaml
   
   # Recreate secrets and configmaps (if you have backup)
   kubectl apply -f secrets.yaml
   kubectl apply -f configmaps.yaml
   ```

4. **Verify cluster recovery**:
   ```bash
   kubectl get pods -n rook-ceph
   kubectl get cephcluster -n rook-ceph
   ```

## Best Practices

1. **Regular Velero Backups**:
   - Schedule daily backups of Rook namespace
   - Include all Rook CRs in backups
   - Backup application namespaces separately

2. **Document Configuration**:
   - Keep copies of CephCluster CRs
   - Document dataDirHostPath locations
   - Record mon IPs and node mappings

3. **Test Recovery Procedures**:
   - Test restore procedures in non-production
   - Verify mon quorum recovery
   - Test CRD restoration

4. **Monitor Cluster Health**:
   - Set up alerts for mon quorum loss
   - Monitor CRD deletion events
   - Track namespace deletion events

## Velero Backup Strategy for Disaster Recovery

Create comprehensive backups:

```bash
# 1. Full Rook operator backup
kubectl apply -f configs/backup-rook-operator.yaml

# 2. Application namespaces backup
kubectl apply -f configs/backup-app-only.yaml

# 3. Scheduled backups
kubectl apply -f configs/backup-schedule.yaml
```

## References

- [Official Rook Disaster Recovery Documentation](https://www.rook.io/docs/rook/latest-release/Troubleshooting/disaster-recovery/)
- [Rook kubectl Plugin](https://rook.io/docs/rook/latest-release/Troubleshooting/kubectl-plugin/)
- [Velero Backup Documentation](docs/BACKUP_GUIDE.md)
- [Velero Restore Documentation](docs/RESTORE_GUIDE.md)

