# Sonobuoy Handover Guide

This guide explains **what to run** with Sonobuoy on your telco Rancher downstream cluster, **how** to run it, and **what to hand over**.

---

## 1. What you are testing

You want to prove that the cluster:
- Is **Kubernetes-conformant** (API + behavior)
- Has **working networking and storage** (incl. Cinder)
- Is **clean** after tests finish

Assumption: the cluster is *empty* apart from infrastructure components (Metal3, Cinder, etc.) and **no production workloads**.

---

## 2. Which Sonobuoy mode to use

### Recommended (your case: no workloads)

Run **certified-conformance**:

- **What it is**: Official CNCF Kubernetes conformance suite
- **Why**: Gives you the strongest proof for customer handover
- **Disruptive tests?** Yes, but they only touch **test resources** Sonobuoy creates
- **Safe here?** Yes, because you have no production workloads

Command:

```bash
sonobuoy run --mode=certified-conformance --wait --delete
```

### Optional extras

- **Quick smoke test** (fast, not required):
  ```bash
  sonobuoy run --mode=quick --wait --delete
  ```
- **Non-disruptive** (if workloads ever exist later):
  ```bash
  sonobuoy run --mode=non-disruptive --wait --delete
  ```

---

## 3. Install Sonobuoy

### macOS
```bash
brew install sonobuoy
```

### Linux (generic)
```bash
VERSION=$(curl -s https://api.github.com/repos/vmware-tanzu/sonobuoy/releases/latest | jq -r '.tag_name')
curl -L "https://github.com/vmware-tanzu/sonobuoy/releases/download/${VERSION}/sonobuoy_${VERSION#v}_linux_amd64.tar.gz" | tar -xz
sudo mv sonobuoy /usr/local/bin/

sonobuoy version
```

---

## 4. Run, retrieve, clean up

### 4.1 Run certified conformance

```bash
# Run full certified conformance (recommended)
sonobuoy run --mode=certified-conformance --wait --delete
```

Key flags:
- `--wait`: block until tests finish
- `--delete`: clean up Sonobuoy + test resources afterwards

### 4.2 Retrieve results

```bash
# Save results tarball
RESULTS_TGZ="certified-conformance-$(date +%Y%m%d-%H%M%S).tar.gz"
sonobuoy retrieve "$RESULTS_TGZ"

# Quick summary
sonobuoy results "$RESULTS_TGZ"

# Detailed report for handover
sonobuoy results "$RESULTS_TGZ" > handover-test-report.txt
```

### 4.3 Verify cleanup

```bash
# Sonobuoy namespace should be gone or empty
kubectl get ns sonobuoy || echo "sonobuoy namespace removed"

# Check nothing obvious left over
kubectl get pods --all-namespaces | grep -Ei 'sonobuoy|e2e|conformance' || echo "no test pods found"
```

If you ever run without `--delete`, you can clean up with:

```bash
sonobuoy delete
```

---

## 5. What Sonobuoy actually tests (high level)

The **certified-conformance** run covers Kubernetes E2E tests for:
- **API**: CRUD behavior for core resources
- **Networking**: pod-to-pod, services, DNS
- **Storage**: PV/PVC, StorageClass, attach/mount (exercises your Cinder class)
- **Scheduling**: node selection, taints/tolerations, resource requests/limits
- **Workloads**: Deployments, StatefulSets, DaemonSets, Jobs
- **Security/RBAC**: service accounts, basic RBAC scenarios

All of this is done using **temporary test resources** that are removed at the end (plus your `--delete`).

---

## 6. Handover artifacts to give the customer

Run something like this at the end:

```bash
RESULTS_TGZ="certified-conformance-$(date +%Y%m%d-%H%M%S).tar.gz"

# After tests complete
sonobuoy retrieve "$RESULTS_TGZ"
sonobuoy results "$RESULTS_TGZ" > handover-test-report.txt
```

Then hand over:

1. **Results tarball**: `certified-conformance-YYYYMMDD-HHMMSS.tar.gz`
2. **Summary report**: `handover-test-report.txt`
3. (Optional) A short note in your main project docs: 
   - "Cluster validated with Sonobuoy certified-conformance on <date>. All tests passed; see attached report and results tarball."

---

## 7. Useful commands (quick reference)

```bash
# Run certified conformance (full proof)
sonobuoy run --mode=certified-conformance --wait --delete

# Check progress
sonobuoy status
sonobuoy logs --follow

# Retrieve results
sonobuoy retrieve
sonobuoy results <tarball>

# Cleanup if needed
sonobuoy delete
```