#!/bin/bash
# Add SUSE repositories for SL-Micro 6.2

echo "=========================================="
echo "Adding SUSE Repositories for SL-Micro 6.2"
echo "=========================================="
echo ""
echo "Run these commands INSIDE your SL-Micro VM:"
echo ""

echo "# 1. Check current repositories"
echo "sudo zypper repos"
echo ""

echo "# 2. Add Package Hub (contains many additional packages)"
echo "sudo zypper addrepo -f \\"
echo "  https://download.opensuse.org/repositories/utilities/SLE_15_SP4/utilities.repo"
echo ""

echo "# 3. Add containers/podman repository (if available)"
echo "# Note: Repository names must be valid identifiers (no spaces, special chars)"
echo "sudo zypper addrepo -f \\"
echo "  https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/SLE_15_SP4/ \\"
echo "  containers-stable"
echo ""

echo "# 4. Alternative: Try SLE Micro specific repository"
echo "sudo zypper addrepo -f \\"
echo "  https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/SLE_Micro_6.2/ \\"
echo "  containers-slemicro"
echo ""

echo "# 5. Refresh repositories"
echo "sudo zypper refresh"
echo ""

echo "# 6. List available packages"
echo "sudo zypper search podman"
echo "sudo zypper search jq"
echo ""

echo "=========================================="
echo "If repositories fail, try:"
echo "=========================================="
echo ""
echo "# Use SUSEConnect to register (if you have credentials)"
echo "sudo SUSEConnect --url https://scc.suse.com"
echo ""
echo "# Or use public OBS repositories"
echo "sudo zypper addrepo -f \\"
echo "  https://download.opensuse.org/repositories/utilities/SLE_15_SP4/utilities.repo"
echo ""


