# Port Forwarding & Network Configuration - Detailed Explanation

## Overview

The VM (metal3-node-0) runs in user-mode networking, which isolates it from the Kubernetes cluster network. To allow IPA to reach Ironic, we set up a two-stage port forwarding chain and configured static IP routing.

---

## Network Topology

```
┌─────────────────────────────────────────────────────────┐
│  Kubernetes Kind Cluster (172.18.0.0/16)                 │
│                                                           │
│  ┌──────────────────────────────────────────────┐        │
│  │  Ironic Service (metal3-metal3-ironic)        │        │
│  │  - Cluster IP: 10.108.146.230                │        │
│  │  - NodePort: 31385 (external access)          │        │
│  │  - Port: 6185 (HTTPS)                         │        │
│  └──────────────────────────────────────────────┘        │
└─────────────────────────────────────────────────────────┘
                          ▲
                          │ kubectl port-forward
                          │ localhost:6385 → svc:6185
                          │
┌─────────────────────────────────────────────────────────┐
│  macOS Host (192.168.1.242)                            │
│                                                          │
│  ┌──────────────────────────────────────────────┐     │
│  │  localhost:6385                               │     │
│  │  (kubectl port-forward listens here)         │     │
│  └──────────────────────────────────────────────┘     │
│                          ▲                              │
│                          │ socat                        │
│                          │ 192.168.1.242:6385 →        │
│                          │ localhost:6385               │
│                          │                              │
│  ┌──────────────────────────────────────────────┐     │
│  │  VM Network (user-mode)                       │     │
│  │  - Network: 10.0.2.0/24                      │     │
│  │  - VM IP: 10.0.2.100/24                       │     │
│  │  - Gateway: 10.0.2.2 (host)                  │     │
│  └──────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────┘
```

---

## Port Forwarding Setup

### Problem

- Ironic service runs inside Kubernetes cluster (172.18.0.0/16)
- VM runs in user-mode network (10.0.2.0/24)
- VM cannot directly reach Kubernetes cluster network
- Need to expose Ironic to VM via host's external IP

### Solution: Two-Stage Port Forwarding

#### Stage 1: kubectl port-forward

**Command:**
```bash
kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6385:6185
```

**What it does:**
- Listens on: `localhost:6385` (on macOS host)
- Forwards to: Ironic service port `6185` (inside Kubernetes)
- Protocol: TCP (HTTPS)
- Result: Ironic is accessible at `localhost:6385` on the host

**Why localhost only?**
- `kubectl port-forward` by default only binds to localhost
- This is a security feature - not accessible from other machines
- We need another layer to expose it externally

#### Stage 2: socat forwarder

**Command:**
```bash
socat TCP-LISTEN:6385,fork,reuseaddr TCP:localhost:6385
```

**What it does:**
- Listens on: `192.168.1.242:6385` (host's external IP)
- Forwards to: `localhost:6385` (where kubectl port-forward listens)
- Options:
  - `fork`: Handle multiple connections
  - `reuseaddr`: Allow port reuse
- Result: Ironic is accessible at `192.168.1.242:6385` from outside

**Why two stages?**
1. `kubectl port-forward` only binds to localhost (security)
2. `socat` makes it accessible on host's external IP
3. VM can now reach `192.168.1.242:6385` via its gateway

### Connection Flow

When IPA tries to connect to Ironic:

```
IPA (10.0.2.100)
    │
    │ HTTPS request to 192.168.1.242:6385
    ▼
Gateway (10.0.2.2 = macOS host)
    │
    │ Routes to 192.168.1.242:6385
    ▼
socat (listening on 192.168.1.242:6385)
    │
    │ Forwards to localhost:6385
    ▼
kubectl port-forward (listening on localhost:6385)
    │
    │ Forwards to Kubernetes service
    ▼
Ironic Service (port 6185)
    │
    │ HTTPS response
    ▼
(Response flows back through the same chain)
```

---

## Network Configuration (Static IP Routing)

### Problem

- VM uses user-mode networking (isolated network: 10.0.2.0/24)
- Kubernetes cluster is on different network (172.18.0.0/16)
- VM cannot directly reach cluster network
- Need static IP configuration to route through host gateway

### Solution: Static IP Configuration

#### 1. Base OS (Ubuntu) - via cloud-init

**Location:** `create-baremetal-host.sh` (cloud-init user-data)

**Configuration:**
```yaml
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: false
      addresses:
        - 10.0.2.100/24
      gateway4: 10.0.2.2
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
```

**What this does:**
- Sets static IP: `10.0.2.100/24` (within user-mode network)
- Gateway: `10.0.2.2` (macOS host)
- Disables DHCP (matches lab setup requirement)
- Applied when VM boots Ubuntu OS

#### 2. IPA (Ironic Python Agent) - via NetworkData Secret

**Location:** Kubernetes Secret `provisioning-networkdata` in `metal3-system` namespace

**Configuration:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: provisioning-networkdata
  namespace: metal3-system
type: Opaque
stringData:
  networkData: |
    version: 2
    ethernets:
      eth0:
        dhcp4: false
        addresses:
          - 10.0.2.100/24
        gateway4: 10.0.2.2
        nameservers:
          addresses:
            - 8.8.8.8
            - 8.8.4.4
```

**What this does:**
- Same static IP configuration as base OS
- Applied when IPA boots from virtual media ISO
- Injected into IPA ramdisk by Metal3
- Allows IPA to have network connectivity immediately

**How it's applied:**
- Referenced in BareMetalHost via `preprovisioningNetworkDataName: "provisioning-networkdata"`
- Metal3 injects this into the boot ISO
- IPA applies it when it boots

### Routing Flow

**User-mode network routing:**
```
VM (10.0.2.100)
    │
    │ Wants to reach 192.168.1.242:6385
    │ (not in local network 10.0.2.0/24)
    ▼
Gateway (10.0.2.2 = macOS host)
    │
    │ Routes to host's external IP
    ▼
macOS Host (192.168.1.242)
    │
    │ Port forwarding chain
    ▼
Ironic Service
```

**Why static IP?**
1. **Consistency**: Matches lab setup (no DHCP)
2. **Predictability**: Same IP every boot
3. **Routing**: Gateway (10.0.2.2) is always the host
4. **Port forwarding**: Host can forward to Ironic

---

## Verification

### Check Port Forwarding

```bash
# Check if kubectl port-forward is running
ps aux | grep "kubectl port-forward.*ironic"

# Check if socat is running
ps aux | grep "socat.*6385"

# Test connection from host
curl -k https://localhost:6385/
curl -k https://192.168.1.242:6385/
```

### Check Network Configuration

```bash
# Check VM IP
virsh domifaddr metal3-node-0

# Check NetworkData secret
kubectl get secret provisioning-networkdata -n metal3-system -o jsonpath='{.data.networkData}' | base64 -d

# Check BareMetalHost references NetworkData
kubectl get baremetalhost metal3-node-0 -n metal3-system -o yaml | grep preprovisioningNetworkDataName
```

### Test from VM (when IPA boots)

```bash
# SSH into IPA
ssh -i ~/.ssh/id_rsa_ipa root@10.0.2.100

# Test Ironic connection
curl -k https://192.168.1.242:6385/

# Check network config
ip addr show
ip route show
```

---

## Summary

**Port Forwarding:**
- Two-stage forwarding: `kubectl port-forward` → `socat`
- Exposes Ironic from Kubernetes cluster to host's external IP
- Allows VM to reach Ironic via `192.168.1.242:6385`

**Network Configuration:**
- Static IP `10.0.2.100/24` for both base OS and IPA
- Gateway `10.0.2.2` (host) routes traffic
- Matches lab setup (no DHCP)
- Applied via cloud-init (base OS) and NetworkData (IPA)

**Result:**
- VM can reach Ironic at `192.168.1.242:6385`
- Traffic flows: VM → Gateway → socat → kubectl port-forward → Ironic
- Both base OS and IPA use same static IP configuration

