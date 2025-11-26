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

## Quick Start

1. **Install Edge Image Builder**: See `EDGE_IMAGE_BUILDER_INSTALL.md`
2. **Build Image with nmstate**: See `BUILD_IMAGE_WITH_NMSTATE.md`
3. **Configure Static IPs**: See `EDGE_IMAGE_BUILDER_STATIC_IP.md`
4. **Use with Metal3**: See `EDGE_IMAGE_BUILDER_GUIDE.md`

## Reference

- [SUSE Edge Metal3 Quickstart](https://documentation.suse.com/suse-edge/3.3/html/edge/quickstart-metal3.html)
- [SUSE Edge Image Builder Documentation](https://documentation.suse.com/suse-edge/3.3/html/edge/edge-image-builder.html)

