# Network Architecture: Rancher Cluster → Kind Cluster + Simulators

This document explains how the external Rancher cluster communicates with the Kind cluster and Redfish simulators on the OpenStack VM.

## 🏗️ Network Flow

```
┌─────────────────────────────────────────────────────────┐
│  External Rancher Cluster                               │
│  ├── Rancher UI (manages Kind cluster)                  │
│  ├── Rancher Turtles (CAPI integration)                │
│  └── Metal3/Ironic (provisions bare metal)             │
│      └── Issues Redfish commands to simulators          │
└─────────────────────────────────────────────────────────┘
              ↓ Network Access
              ├─→ Port 6443 (Kubernetes API)
              └─→ Ports 8000-8002 (Redfish APIs)
┌─────────────────────────────────────────────────────────┐
│  OpenStack VM (192.168.1.100)                           │
│  ├── Kind Cluster                                       │
│  │   └── API Server (:6443)                            │
│  └── Redfish Simulators                                 │
│      ├── redfish-sim-controlplane (:8000)              │
│      ├── redfish-sim-worker-0 (:8001)                 │
│      └── redfish-sim-worker-1 (:8002)                 │
└─────────────────────────────────────────────────────────┘
```

## 🔌 Network Connections

### 1. Kubernetes API Access (Port 6443)

**Purpose:** Rancher cluster manages the Kind cluster

**Flow:**
```
Rancher Cluster → VM:6443 → Kind Cluster API Server
```

**Who connects:**
- Rancher cluster agents
- Rancher Turtles controllers
- kubectl commands from Rancher cluster

**What happens:**
- Rancher monitors Kind cluster status
- Rancher Turtles syncs CAPI resources
- Cluster management operations

### 2. Redfish API Access (Ports 8000-8002)

**Purpose:** Metal3/Ironic provisions bare metal nodes via Redfish

**Flow:**
```
Metal3/Ironic (in Rancher cluster) → VM:8000-8002 → Redfish Simulators
```

**Who connects:**
- Metal3 Ironic service (running in Rancher cluster)
- Ironic Inspector (hardware discovery)
- Bare Metal Operator (provisioning operations)

**What happens:**
- Metal3 sends Redfish commands:
  - `GET /redfish/v1/Systems/1` - Check system status
  - `POST /redfish/v1/Systems/1/Actions/ComputerSystem.Reset` - Reboot
  - `POST /redfish/v1/Systems/1/VirtualMedia/1/Actions/VirtualMedia.InsertMedia` - Insert ISO
  - `GET /redfish/v1/Systems/1/VirtualMedia/1` - Check virtual media status

## 📋 Required Network Access

### Security Group Rules

The OpenStack VM security group must allow:

```bash
# Kubernetes API (for Rancher cluster management)
Port 6443/TCP from Rancher cluster network

# Redfish Simulators (for Metal3/Ironic)
Port 8000/TCP from Rancher cluster network (control plane simulator)
Port 8001/TCP from Rancher cluster network (worker-0 simulator)
Port 8002/TCP from Rancher cluster network (worker-1 simulator)
```

### Example: Configure Security Groups

```bash
export RANCHER_NETWORK="10.0.0.0/8"  # Your Rancher cluster network

# Kubernetes API
openstack security group rule create default \
  --protocol tcp --dst-port 6443 \
  --remote-ip "$RANCHER_NETWORK"

# Redfish Simulators
for port in 8000 8001 8002; do
    openstack security group rule create default \
      --protocol tcp --dst-port $port \
      --remote-ip "$RANCHER_NETWORK"
done
```

## 🔄 Complete Workflow

### Step 1: Rancher Manages Kind Cluster

```
1. Rancher cluster connects to Kind cluster API (VM:6443)
2. Rancher imports/manages the Kind cluster
3. Rancher Turtles discovers CAPI resources in Kind cluster
4. Cluster appears in Rancher UI
```

### Step 2: Metal3 Provisions via Redfish

```
1. User creates BareMetalHost resource in Rancher cluster
2. Metal3 Bare Metal Operator sees the resource
3. Metal3 Ironic connects to Redfish simulator (VM:8000-8002)
4. Ironic sends Redfish commands:
   - Check system power state
   - Insert virtual media (ISO image)
   - Reset system to boot from ISO
5. Simulator responds (simulating bare metal behavior)
6. Metal3 provisions the "bare metal" node
```

## 📝 BareMetalHost Configuration

When creating BareMetalHost resources in your Rancher cluster, use the VM's external IP:

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: controlplane-0
  namespace: default
spec:
  bmc:
    # Use VM external IP for Redfish access
    address: redfish-virtualmedia://${VM_IP}:8000/redfish/v1/Systems/1
    credentialsName: bmc-credentials
    disableCertificateVerification: true
  image:
    url: http://imagecache.example.com/ubuntu-20.04.raw
    checksum: http://imagecache.example.com/ubuntu-20.04.raw.sha256
    checksumType: sha256
```

**Important:** Metal3/Ironic (running in Rancher cluster) must be able to reach `${VM_IP}:8000` from the Rancher cluster network.

## 🔍 Verification

### Test from Rancher Cluster

```bash
# From a pod in the Rancher cluster, test connectivity

# Test Kubernetes API access
kubectl run -it --rm test-api \
  --image=curlimages/curl \
  --restart=Never \
  -- curl -k https://${VM_IP}:6443/healthz

# Test Redfish simulator access
kubectl run -it --rm test-redfish \
  --image=curlimages/curl \
  --restart=Never \
  -- curl http://${VM_IP}:8000/redfish/v1/

# Test all simulators
for port in 8000 8001 8002; do
    kubectl run -it --rm test-sim-$port \
      --image=curlimages/curl \
      --restart=Never \
      -- curl http://${VM_IP}:${port}/redfish/v1/
done
```

### Test from Metal3/Ironic Pod

```bash
# Get Metal3 Ironic pod name
IRONIC_POD=$(kubectl get pods -n metal3-system -l app.kubernetes.io/name=metal3-ironic -o name | head -1)

# Test Redfish access from Ironic pod
kubectl exec -n metal3-system $IRONIC_POD -- curl http://${VM_IP}:8000/redfish/v1/Systems/1
```

## 🔒 Security Considerations

### Network Isolation

- **Recommended:** Restrict access to Rancher cluster network only
  ```bash
  --remote-ip <RANCHER_CLUSTER_CIDR>  # e.g., 10.0.0.0/8
  ```

- **Testing:** Allow from all IPs (NOT for production)
  ```bash
  --remote-ip 0.0.0.0/0
  ```

### TLS/HTTPS

- **Kubernetes API:** Uses HTTPS (port 6443) with certificates
- **Redfish Simulators:** Use HTTP (ports 8000-8002) - simulators don't support TLS
- **Production:** Consider VPN or private network for Redfish traffic

## 🎯 Summary

**Network Requirements:**

1. **Rancher → Kind Cluster:**
   - Port 6443 (Kubernetes API)
   - Purpose: Cluster management

2. **Metal3/Ironic → Redfish Simulators:**
   - Ports 8000, 8001, 8002 (Redfish APIs)
   - Purpose: Bare metal provisioning

**Key Points:**

- ✅ Rancher cluster manages Kind cluster via port 6443
- ✅ Metal3/Ironic provisions via Redfish on ports 8000-8002
- ✅ All traffic must be allowed by OpenStack security groups
- ✅ Simulators are accessed using VM's external IP
- ✅ BareMetalHost resources use `redfish-virtualmedia://${VM_IP}:PORT/redfish/v1/Systems/1`

**No Load Balancer needed** - direct VM IP access works perfectly for this use case!

