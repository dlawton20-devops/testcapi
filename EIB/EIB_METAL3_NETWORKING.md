# EIB Image Configuration for Metal3 with Static Networking

## Overview

When building a downstream cluster image for Metal3, you need to configure:
1. **Network configuration** - So the BareMetalHost can communicate with Metal3
2. **RKE2/Kubernetes setup** - For the cluster itself
3. **Image cache access** - To download the image during provisioning

## Network Requirements

### What the Image Needs

The image needs network configuration so that:
- ✅ **BareMetalHost can reach Metal3 management cluster** (for provisioning)
- ✅ **Nodes can communicate with each other** (cluster networking)
- ✅ **Nodes can reach image cache server** (to download the image)
- ✅ **Nodes can reach container registries** (for Kubernetes images)

### Static vs Dynamic Networking

**Static Networking** (what you're using):
- IP addresses are pre-configured in the image
- No DHCP required
- More predictable, better for automation
- Requires network configuration in EIB definition

**Dynamic Networking** (DHCP):
- IPs assigned at boot time
- Easier setup but less predictable
- May need additional configuration

## EIB Definition File for Metal3

Here's what your `eib/downstream-cluster-config.yaml` should include:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: eib-metal3-downstream
data:
  # Base image
  base_image: "slemicro.iso"
  
  # RKE2 configuration
  rke2_version: "v1.31.0+rke2r1"  # Adjust to your needs
  
  # Network configuration - CRITICAL for Metal3
  network_config: |
    # Static network configuration
    # This allows the BareMetalHost to communicate with Metal3
    version: 2
    ethernets:
      enp0s2:  # Adjust interface name as needed
        addresses:
          - 192.168.1.100/24  # Static IP for this node
        gateway4: 192.168.1.1
        nameservers:
          addresses:
            - 8.8.8.8
            - 8.8.4.4
        # Routes to Metal3 management cluster
        routes:
          - to: 10.0.0.0/8      # Management cluster network
            via: 192.168.1.1
          - to: 172.16.0.0/12    # Kubernetes pod network
            via: 192.168.1.1
  
  # Operating system packages
  operatingSystem:
    packages:
      additionalRepos:
        - url: https://download.opensuse.org/repositories/utilities/15.6/
      # Side-loaded RPMs (if using)
      # RPMs will be in eib/rpms/
  
  # RKE2 server configuration (for control plane nodes)
  rke2_config: |
    # Network configuration for RKE2
    cni: "canal"  # or "calico", "flannel", etc.
    node-ip: "192.168.1.100"  # Static IP
    node-external-ip: "192.168.1.100"
    
    # Cluster configuration
    cluster-cidr: "10.42.0.0/16"
    service-cidr: "10.43.0.0/16"
    
    # Allow Metal3 to reach the API
    tls-san:
      - "192.168.1.100"
      - "kubernetes.default.svc.cluster.local"
  
  # RKE2 agent configuration (for worker nodes)
  rke2_agent_config: |
    server: "https://192.168.1.100:9345"  # Control plane endpoint
    node-ip: "192.168.1.101"  # Worker node IP
    token: "your-token-here"  # Will be set by Metal3
```

## Key Network Configuration Points

### 1. Static IP Configuration

The image needs a static IP so:
- Metal3 can reach it for provisioning
- Other nodes can find it
- It's predictable and doesn't change

```yaml
network_config: |
  version: 2
  ethernets:
    enp0s2:
      addresses:
        - 192.168.1.100/24  # Static IP
      gateway4: 192.168.1.1
```

### 2. Routes to Metal3 Management Cluster

Ensure the node can reach the Metal3 management cluster:

```yaml
routes:
  - to: 10.0.0.0/8      # Management cluster network
    via: 192.168.1.1    # Gateway
```

### 3. DNS Configuration

For resolving Metal3 services and container registries:

```yaml
nameservers:
  addresses:
    - 8.8.8.8
    - 8.8.4.4
    # Or your internal DNS
```

### 4. RKE2 Network Configuration

RKE2 needs to know the node's IP:

```yaml
rke2_config: |
  node-ip: "192.168.1.100"  # Must match network_config IP
  tls-san:
    - "192.168.1.100"       # For API access
```

## Metal3 BareMetalHost Configuration

When you create the BareMetalHost in Metal3, it will reference your image:

```yaml
apiVersion: metal3.io/v1alpha1
kind: BareMetalHost
metadata:
  name: worker-0
spec:
  image:
    url: http://imagecache.local:8080/SLE-Micro-eib-output.raw
    checksum: http://imagecache.local:8080/SLE-Micro-eib-output.raw.sha256
  online: true
  bootMACAddress: "00:11:22:33:44:55"
```

The image needs to:
1. **Boot with the static network config** you defined
2. **Be able to reach Metal3** (via routes/gateway)
3. **Download and install RKE2** (if not pre-installed)
4. **Join the cluster** (using the token provided by Metal3)

## Complete Example for Metal3

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: eib-metal3-worker
data:
  base_image: "slemicro.iso"
  
  # Network - allows communication with Metal3
  network_config: |
    version: 2
    ethernets:
      enp0s2:
        addresses:
          - 192.168.1.100/24
        gateway4: 192.168.1.1
        nameservers:
          addresses: [8.8.8.8, 8.8.4.4]
        routes:
          - to: 10.0.0.0/8
            via: 192.168.1.1
  
  # RKE2 agent (for worker nodes)
  rke2_agent_config: |
    server: "https://control-plane-ip:9345"
    node-ip: "192.168.1.100"
    # Token will be provided by Metal3 via cloud-init
  
  operatingSystem:
    packages:
      additionalRepos:
        - url: https://download.opensuse.org/repositories/utilities/15.6/
```

## What Metal3 Provides

Metal3 will inject via cloud-init/metadata:
- **RKE2 token** - For joining the cluster
- **Control plane endpoint** - Where to connect
- **Node-specific configuration** - Via Metal3DataTemplate

## Network Interface Names

**Important**: Network interface names may differ between:
- **Ironic Python Agent (IPA)** - Used during provisioning
- **SL-Micro** - The actual OS

You may need to configure both:

```yaml
# For IPA (during provisioning)
preprovisioningNetworkDataName: "ipa-network-config"

# For SL-Micro (after boot)
networkData:
  name: "slemicro-network-config"
```

## Testing Network Configuration

After building the image, you can test:

1. **Boot the image** in a VM
2. **Verify static IP** is configured:
   ```bash
   ip addr show
   ```
3. **Test connectivity to Metal3**:
   ```bash
   ping <metal3-management-cluster-ip>
   curl -k https://<metal3-api>:6443
   ```
4. **Verify DNS**:
   ```bash
   nslookup kubernetes.default.svc.cluster.local
   ```

## Common Issues

### "Node can't reach Metal3"

**Solution**: Add route to management cluster network:
```yaml
routes:
  - to: <management-cluster-network>
    via: <gateway>
```

### "Interface name mismatch"

**Solution**: Configure both IPA and SL-Micro network configs (see above)

### "RKE2 can't join cluster"

**Solution**: Ensure:
- `node-ip` matches static IP in network_config
- Routes to control plane are configured
- DNS can resolve cluster services

## Summary

For Metal3 with static networking, your EIB image needs:

1. ✅ **Static IP configuration** - So it's predictable
2. ✅ **Routes to Metal3** - So it can communicate back
3. ✅ **RKE2 configuration** - With correct node-ip
4. ✅ **DNS configuration** - For cluster services
5. ✅ **Image cache access** - To download the image itself

The key is: **The image must be able to reach Metal3's management cluster** so it can:
- Receive provisioning instructions
- Download additional resources if needed
- Report status back to Metal3
- Join the Kubernetes cluster


