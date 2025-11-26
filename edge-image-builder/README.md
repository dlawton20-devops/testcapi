# Edge Image Builder Documentation

This folder contains all documentation related to building OS images with SUSE Edge Image Builder for Metal3.

## Files in This Folder

### 1. EDGE_IMAGE_BUILDER_INSTALL.md
**Prerequisites and Installation Guide**
- Prerequisites for installing Edge Image Builder via Helm
- Proxy configuration (for environments behind corporate proxy)
- Storage configuration
- Complete installation steps
- Troubleshooting installation issues

### 2. BUILD_IMAGE_WITH_NMSTATE.md
**Building Images with nmstate Support**
- How to build images that include nmstate package
- Including configure-network.sh script in image
- Complete build configuration examples
- Verification steps

### 3. EDGE_IMAGE_BUILDER_STATIC_IP.md
**Static IP Configuration Implementation**
- configure-network.sh script details
- nmstate format NetworkData secrets
- BareMetalHost configuration
- Complete workflow from build to provisioning

### 4. EDGE_IMAGE_BUILDER_GUIDE.md
**General Edge Image Builder Usage**
- Overview of Edge Image Builder
- Building images in separate environments
- Image serving and caching
- Integration with Metal3

### 5. MANUAL_PODMAN_SETUP.md
**Manual Setup with Podman (Local)**
- Running Edge Image Builder locally without Helm/Kubernetes
- Directory structure setup (base-images, network, custom/scripts)
- Creating downstream-cluster-config.yaml
- Preparing base images (xz decompression)
- Required 01-fix-growfs.sh script
- Complete step-by-step manual workflow

## Quick Start

### For Local Podman Setup (No Kubernetes Required)
1. **Manual Setup**: See `MANUAL_PODMAN_SETUP.md` - Complete guide for running Edge Image Builder locally with Podman

### For Kubernetes/Helm Setup
1. **Install Edge Image Builder**: See `EDGE_IMAGE_BUILDER_INSTALL.md`
2. **Build Image with nmstate**: See `BUILD_IMAGE_WITH_NMSTATE.md`
3. **Configure Static IPs**: See `EDGE_IMAGE_BUILDER_STATIC_IP.md`
4. **Use with Metal3**: See `EDGE_IMAGE_BUILDER_GUIDE.md`

## Reference

- [SUSE Edge Metal3 Quickstart](https://documentation.suse.com/suse-edge/3.3/html/edge/quickstart-metal3.html)
- [SUSE Edge Image Builder Documentation](https://documentation.suse.com/suse-edge/3.3/html/edge/edge-image-builder.html)

