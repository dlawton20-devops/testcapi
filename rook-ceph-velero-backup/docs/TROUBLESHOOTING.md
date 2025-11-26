# Velero Rook Ceph Backup/Restore Troubleshooting

Common issues and solutions when backing up and restoring Rook Ceph clusters with Velero.

## Backup Issues

### Issue: Backup Stuck in "InProgress" State

**Symptoms:**
- Backup remains in "InProgress" phase for extended period
- No progress in backup logs

**Diagnosis:**
```bash
# Check backup status
velero backup describe <backup-name>

# Check Velero pod logs
kubectl logs -n velero -l app.kubernetes.io/name=velero --tail=100

# Check node-agent logs
kubectl logs -n velero -l component=node-agent --tail=100
```

**Solutions:**
1. Check if PVCs are mounted and accessible
2. Verify node-agent pods are running on all nodes
3. Check for disk space issues
4. Verify S3 connectivity

```bash
# Restart Velero pod
kubectl delete pod -n velero -l app.kubernetes.io/name=velero

# Check node-agent pods
kubectl get pods -n velero -l component=node-agent
```

### Issue: Backup Fails with "Volume Backup Failed"

**Symptoms:**
- Backup shows "PartiallyFailed" or "Failed" status
- Errors related to volume backups

**Diagnosis:**
```bash
# Check backup logs for specific errors
velero backup logs <backup-name> | grep -i error

# Check PVC status
kubectl get pvc -A

# Check if pods using PVCs are running
kubectl get pods -A -o wide | grep -E "Pending|Error|CrashLoop"
```

**Solutions:**
1. Ensure pods using PVCs are running
2. Check PVC mount status
3. Verify storage class exists
4. Check for permission issues

```bash
# Restart pods using problematic PVCs
kubectl delete pod -n <namespace> <pod-name>

# Verify PVC is bound
kubectl get pvc -n <namespace> <pvc-name>
```

### Issue: Cannot Connect to S3 Storage

**Symptoms:**
- Backup fails immediately
- Errors about S3 connectivity
- "BackupStorageLocation not available"

**Diagnosis:**
```bash
# Check backup storage location
velero backup-location get

# Test S3 connectivity from cluster
kubectl run -it --rm debug --image=amazon/aws-cli --restart=Never -- \
  aws s3 ls s3://velero-backups --endpoint-url=https://minio.velero.svc.cluster.local:9000

# Check Velero credentials
kubectl get secret cloud-credentials -n velero -o yaml
```

**Solutions:**
1. Verify S3 endpoint is correct
2. Check credentials are valid
3. Verify network connectivity
4. Check S3 bucket exists and is accessible

```bash
# Update backup storage location
kubectl edit backupstoragelocation default -n velero

# Recreate credentials secret
kubectl create secret generic cloud-credentials \
  --from-file cloud=./credentials-velero \
  -n velero
```

### Issue: Backup Size Too Large

**Symptoms:**
- Backup takes very long
- S3 storage fills up quickly
- Backup fails due to storage limits

**Diagnosis:**
```bash
# Check backup size
velero backup describe <backup-name> | grep -i size

# Check PVC sizes
kubectl get pvc -A -o json | jq '.items[] | {name: .metadata.name, namespace: .metadata.namespace, size: .spec.resources.requests.storage}'

# Check S3 storage usage
aws s3 ls s3://velero-backups/ --recursive --summarize --endpoint-url=https://minio.velero.svc.cluster.local:9000
```

**Solutions:**
1. Exclude large, non-critical namespaces
2. Use selective resource backup
3. Increase S3 storage capacity
4. Implement backup retention policies

```bash
# Create selective backup excluding large namespaces
velero backup create selective-backup \
  --include-namespaces=production \
  --exclude-namespaces=logs,metrics,monitoring
```

## Restore Issues

### Issue: Restore Stuck in "InProgress" State

**Symptoms:**
- Restore remains in progress indefinitely
- No resources being restored

**Diagnosis:**
```bash
# Check restore status
velero restore describe <restore-name>

# Check Velero logs
kubectl logs -n velero -l app.kubernetes.io/name=velero --tail=100

# Check for conflicting resources
kubectl get all -A | grep <resource-name>
```

**Solutions:**
1. Check for resource conflicts
2. Verify target namespace exists
3. Check storage class availability
4. Verify Rook Ceph operator is running

```bash
# Delete conflicting resources if needed
kubectl delete <resource-type> <resource-name> -n <namespace>

# Retry restore
velero restore create <new-restore-name> --from-backup <backup-name>
```

### Issue: PVCs Not Restoring

**Symptoms:**
- Restore completes but PVCs are missing
- PVCs show "Pending" status
- Storage class not found errors

**Diagnosis:**
```bash
# Check PVC status
kubectl get pvc -A

# Check storage classes
kubectl get storageclass

# Check restore logs
velero restore logs <restore-name> | grep -i pvc
```

**Solutions:**
1. Ensure storage classes exist in target cluster
2. Create missing storage classes
3. Update PVC storage class if needed
4. Verify Rook Ceph is providing storage classes

```bash
# Create storage class if missing
kubectl apply -f <storage-class-yaml>

# Update PVC storage class
kubectl patch pvc <pvc-name> -n <namespace> -p '{"spec":{"storageClassName":"<storage-class>"}}'
```

### Issue: Ceph Cluster Not Healthy After Restore

**Symptoms:**
- CephCluster shows "NotReady" status
- Ceph pods in CrashLoopBackOff
- OSDs not coming up

**Diagnosis:**
```bash
# Check CephCluster status
kubectl get cephcluster -n rook-ceph -o yaml

# Check Ceph pods
kubectl get pods -n rook-ceph

# Check Ceph operator logs
kubectl logs -n rook-ceph -l app=rook-ceph-operator --tail=100
```

**Solutions:**
1. Verify node labels match original cluster
2. Check disk availability
3. Verify network configuration
4. Review CephCluster resource configuration

```bash
# Check node labels
kubectl get nodes --show-labels

# Restart Ceph operator
kubectl delete pod -n rook-ceph -l app=rook-ceph-operator

# Check CephCluster events
kubectl describe cephcluster -n rook-ceph
```

### Issue: Application Pods Not Starting After Restore

**Symptoms:**
- Pods remain in "Pending" state
- PVCs not binding
- Image pull errors

**Diagnosis:**
```bash
# Check pod status
kubectl get pods -n <namespace>

# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check PVC status
kubectl get pvc -n <namespace>
```

**Solutions:**
1. Verify PVCs are bound
2. Check storage class availability
3. Verify image pull secrets
4. Check resource quotas

```bash
# Check PVC binding
kubectl get pvc -n <namespace>

# Check resource quotas
kubectl get resourcequota -n <namespace>

# Check image pull secrets
kubectl get secrets -n <namespace> | grep docker
```

## General Issues

### Issue: Velero Pod CrashLoopBackOff

**Symptoms:**
- Velero pod keeps restarting
- Backup/restore operations fail

**Diagnosis:**
```bash
# Check Velero pod status
kubectl get pods -n velero

# Check Velero pod logs
kubectl logs -n velero -l app.kubernetes.io/name=velero --tail=100

# Check pod events
kubectl describe pod -n velero -l app.kubernetes.io/name=velero
```

**Solutions:**
1. Check credentials secret
2. Verify S3 connectivity
3. Check resource limits
4. Review Velero configuration

```bash
# Check credentials
kubectl get secret cloud-credentials -n velero

# Recreate Velero deployment
kubectl delete deployment velero -n velero
# Then reinstall Velero
```

### Issue: Node-Agent Pods Not Running

**Symptoms:**
- Node-agent pods not scheduled
- Volume backups failing

**Diagnosis:**
```bash
# Check node-agent pods
kubectl get pods -n velero -l component=node-agent

# Check daemonset
kubectl get daemonset -n velero

# Check node labels
kubectl get nodes --show-labels
```

**Solutions:**
1. Verify node-agent daemonset exists
2. Check node taints/tolerations
3. Verify node resources
4. Check pod security policies

```bash
# Check daemonset
kubectl get daemonset -n velero

# Restart daemonset
kubectl rollout restart daemonset node-agent -n velero
```

### Issue: Backup Storage Location Not Available

**Symptoms:**
- Cannot create backups
- "BackupStorageLocation not available" errors

**Diagnosis:**
```bash
# Check backup storage location
velero backup-location get

# Check BSL status
kubectl get backupstoragelocation -n velero -o yaml

# Test S3 connectivity
kubectl run -it --rm debug --image=amazon/aws-cli --restart=Never -- \
  aws s3 ls s3://velero-backups --endpoint-url=https://minio.velero.svc.cluster.local:9000
```

**Solutions:**
1. Verify S3 endpoint is accessible
2. Check credentials
3. Verify bucket exists
4. Check network connectivity

```bash
# Update BSL configuration
kubectl edit backupstoragelocation default -n velero

# Verify BSL after update
velero backup-location get
```

## Performance Issues

### Issue: Backups Taking Too Long

**Symptoms:**
- Backups take hours to complete
- High CPU/memory usage during backups

**Solutions:**
1. Exclude non-critical resources
2. Use selective namespace backup
3. Increase node resources
4. Optimize S3 upload settings

```bash
# Create faster backup with exclusions
velero backup create fast-backup \
  --include-namespaces=production \
  --exclude-resources=events,secrets
```

### Issue: Restores Taking Too Long

**Symptoms:**
- Restores take hours to complete
- Resources restored slowly

**Solutions:**
1. Restore in phases (operator first, then apps)
2. Use selective resource restore
3. Increase cluster resources
4. Optimize restore parallelism

## Getting Help

### Collecting Debug Information

```bash
# Collect Velero logs
kubectl logs -n velero -l app.kubernetes.io/name=velero > velero-logs.txt

# Collect node-agent logs
kubectl logs -n velero -l component=node-agent > node-agent-logs.txt

# Collect backup/restore information
velero backup describe <backup-name> > backup-info.txt
velero restore describe <restore-name> > restore-info.txt

# Collect cluster information
kubectl get all -A > cluster-state.txt
```

### Useful Commands

```bash
# Check Velero version
velero version

# List all backups
velero backup get

# List all restores
velero restore get

# Check backup storage location
velero backup-location get

# Check volume snapshot locations
velero snapshot-location get
```

## Prevention

1. **Regular Testing**: Test backup/restore procedures regularly
2. **Monitoring**: Set up alerts for backup failures
3. **Documentation**: Document procedures and known issues
4. **Resource Planning**: Ensure sufficient storage and resources
5. **Validation**: Verify backups after creation
6. **Retention Policies**: Implement proper backup retention

