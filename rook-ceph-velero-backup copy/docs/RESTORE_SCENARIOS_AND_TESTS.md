# Restore Scenarios and How to Test Them

This doc gives **concrete, testable restore scenarios** for Rook Ceph + Velero:

- Simple app/namespace restore on the same cluster  
- Rook namespace deletion recovery  
- OpenStack platform workers (Cinder volumes, CephFS)  
- Bare-metal cluster (local disks, CephFS + RWO)

All flows use **Velero CRDs and manifests** (no `velero restore` CLI flags) and map to the
[Rook disaster recovery guide](https://www.rook.io/docs/rook/latest-release/Troubleshooting/disaster-recovery/).

---

## Scenario 1 – Simple App/Namespace Restore (Same Cluster)

**Goal:** Restore a broken app namespace (PVCs + pods) on the same cluster.

### 1.1 Break it

```bash
# Inspect current state
kubectl get pods -n production
kubectl get pvc -n production

# Break the app namespace
kubectl delete ns production
kubectl get ns production  # should be gone
```

### 1.2 Restore it

1. Make sure you have (or create) an app backup (see `configs/backup-app-only.yaml`):

   ```bash
   kubectl apply -f configs/backup-app-only.yaml
   kubectl get backup -n velero
   ```

2. Create a `Restore` object:

   ```yaml
   apiVersion: velero.io/v1
   kind: Restore
   metadata:
     name: app-restore-test
     namespace: velero
   spec:
     backupName: app-production-backup   # set this to your backup name
     includedNamespaces:
       - production
     includeClusterResources: false
     restorePVs: true
   ```

3. Apply and verify:

   ```bash
   kubectl apply -f app-restore-test.yaml
   kubectl get restore app-restore-test -n velero -o jsonpath='{.status.phase}'; echo

   kubectl get ns production
   kubectl get pods -n production
   kubectl get pvc -n production
   ```

You now have a reproducible test for “single namespace restore with PVCs”.

---

## Scenario 2 – Rook Namespace Deletion (Namespace DR)

**Goal:** Delete `rook-ceph` and bring it back via Velero, matching “Restoring the Rook cluster after the Rook namespace is deleted” in the
[Rook DR docs](https://www.rook.io/docs/rook/latest-release/Troubleshooting/disaster-recovery/).

### 2.1 Prerequisites

- `rook-ceph` healthy.  
- `rook-disaster-recovery-backup` exists (`configs/backup-disaster-recovery.yaml`):

  ```bash
  kubectl apply -f configs/backup-disaster-recovery.yaml
  kubectl get backup rook-disaster-recovery-backup -n velero -w
  ```

### 2.2 Break it

```bash
kubectl delete ns rook-ceph
kubectl get ns rook-ceph  # should be gone
```

### 2.3 Restore it

Use the **namespace-only** restore in `configs/restore-disaster-recovery.yaml` (`restore-rook-namespace`):

```bash
sed -n '66,80p' configs/restore-disaster-recovery.yaml   # inspect object

kubectl apply -f configs/restore-disaster-recovery.yaml
kubectl get restore restore-rook-namespace -n velero -o jsonpath='{.status.phase}'; echo

kubectl get ns rook-ceph
kubectl get pods -n rook-ceph
kubectl get cephcluster -n rook-ceph
```

If some CRs/secrets are missing, follow Scenario 5 in `ROOK_DISASTER_RECOVERY.md`.

---

## Scenario 3 – OpenStack Platform Workers (Cinder Volumes, CephFS)

**Goal:** Treat the OpenStack cluster as lost, keep Cinder OSD volumes, rebuild
Kubernetes + Rook, and restore all state with Velero.

This matches “Backing up and restoring a cluster based on PVCs into a new Kubernetes cluster” in the
[Rook DR docs](https://www.rook.io/docs/rook/latest-release/Troubleshooting/disaster-recovery/).

### 3.1 On the source OpenStack cluster

```bash
kubectl apply -f configs/backup-disaster-recovery.yaml
kubectl get backup rook-disaster-recovery-backup -n velero -w
```

### 3.2 Break it (simulated)

1. Create a **new** OpenStack Kubernetes cluster (new control plane + platform workers).  
2. Attach the **same Cinder OSD volumes** that were used by the old platform workers.  
3. Stop using the old kubeconfig; treat the old cluster as gone.

### 3.3 Restore on the new OpenStack cluster

```bash
# 1. Install Velero (same bucket/credentials)
velero install ...
kubectl get backup rook-disaster-recovery-backup -n velero

# 2. Install Rook CRDs + operator (same version)
# kubectl apply -f crds.yaml -f common.yaml -f operator.yaml

# 3. Apply DR restore CRD
sed -n '1,40p' configs/restore-disaster-recovery.yaml   # check backupName
kubectl apply -f configs/restore-disaster-recovery.yaml

kubectl get restore rook-disaster-recovery-restore -n velero -o jsonpath='{.status.phase}'; echo

# 4. Verify Ceph and apps
kubectl get cephcluster -n rook-ceph
kubectl get pods -n rook-ceph
kubectl exec -it -n rook-ceph deploy/rook-ceph-tools -- ceph status

kubectl get pvc -A
kubectl get pods -A
```

If Ceph is healthy and apps are running, your **Cinder-backed CephFS DR test** passed.

---

## Scenario 4 – Bare-Metal Cluster (Local Disks, CephFS + RWO)

**Goal:** Reinstall Kubernetes on the same bare-metal hosts, keeping local disks
and `/var/lib/rook`, then adopt the existing Ceph cluster with Rook + Velero.

This maps to “Adopt an existing Rook Ceph cluster into a new Kubernetes cluster” in the
[Rook DR docs](https://www.rook.io/docs/rook/latest-release/Troubleshooting/disaster-recovery/).

### 4.1 On the original bare-metal cluster

```bash
kubectl apply -f configs/backup-disaster-recovery.yaml
kubectl get backup rook-disaster-recovery-backup -n velero -w
```

### 4.2 Break it (simulated)

- Reinstall Kubernetes on the **same physical nodes**, but:
  - Do **not** wipe the OSD disks.  
  - Do **not** wipe `/var/lib/rook/rook-ceph` (or your `dataDirHostPath`).

### 4.3 Restore + adopt on the reinstalled cluster

```bash
# 1. Install Velero (same bucket)
velero install ...

# 2. Install Rook CRDs + operator
# kubectl apply -f crds.yaml -f common.yaml -f operator.yaml

# 3. Apply DR restore CRD
kubectl apply -f configs/restore-disaster-recovery.yaml
kubectl get restore rook-disaster-recovery-restore -n velero -o jsonpath='{.status.phase}'; echo
```

If Ceph doesn’t immediately come up healthy, follow Scenario 3 in
`ROOK_DISASTER_RECOVERY.md` to rebuild:

- `rook-ceph-mon` **Secret**  
- `rook-ceph-mon-endpoints` **ConfigMap**

using `rook-ceph.config` and `client.admin.keyring` from `dataDirHostPath`.

Then verify:

```bash
# CephFS
kubectl get cephfilesystem -n rook-ceph
kubectl get pods -n rook-ceph | grep mds

# RWO (RBD)
kubectl get cephblockpool -n rook-ceph
kubectl get storageclass | grep rook-ceph
kubectl get pvc -A
```

---

## Scenario 5 – End-to-End DR Drill (Per Environment)

### 5.1 OpenStack Drill (Platform Workers)

1. On source cluster: `kubectl apply -f configs/backup-disaster-recovery.yaml`.  
2. Create new OpenStack K8s cluster, attach OSD Cinder volumes.  
3. Install Velero + Rook.  
4. `kubectl apply -f configs/restore-disaster-recovery.yaml`.  
5. Verify Ceph and apps.

### 5.2 Bare-Metal Drill

1. On original cluster: `kubectl apply -f configs/backup-disaster-recovery.yaml`.  
2. Reinstall K8s on same hosts, keep disks + `/var/lib/rook`.  
3. Install Velero + Rook.  
4. `kubectl apply -f configs/restore-disaster-recovery.yaml`.  
5. Complete adoption steps from `ROOK_DISASTER_RECOVERY.md` Scenario 3 if needed.  
6. Verify CephFS, RWO, and apps.

---

## Where to Look in This Repo

- **This file:** `docs/RESTORE_SCENARIOS_AND_TESTS.md`  
- **Generic restore options:** `docs/RESTORE_GUIDE.md`  
- **Rook DR details (mon configs, secrets, configmaps):** `docs/ROOK_DISASTER_RECOVERY.md`  
- **Velero DR CRDs:** `configs/backup-disaster-recovery.yaml`, `configs/restore-disaster-recovery.yaml`


