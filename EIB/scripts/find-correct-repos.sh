#!/bin/bash
# Script to find and test correct repository URLs for SL-Micro 6.2

echo "=========================================="
echo "Finding Correct Repositories for SL-Micro 6.2"
echo "=========================================="
echo ""

echo "Testing repository URLs..."
echo ""

# Test various repository paths
REPOS=(
    "https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/SLE_Micro_6.2/"
    "https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/SLE_15_SP4/"
    "https://download.opensuse.org/repositories/devel:/kubic:/containers/SLE_15_SP4/"
    "https://download.opensuse.org/repositories/utilities/SLE_15_SP4/"
    "https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/"
)

echo "Testing repository availability:"
echo ""

for repo in "${REPOS[@]}"; do
    echo -n "Testing: $repo ... "
    if curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$repo" | grep -q "200\|301\|302"; then
        echo "✓ Available"
    else
        echo "✗ Not found"
    fi
done

echo ""
echo "=========================================="
echo "Recommended Commands for SL-Micro 6.2:"
echo "=========================================="
echo ""
echo "Run these INSIDE your SL-Micro VM:"
echo ""
echo "# 1. Check what repositories are already available"
echo "sudo zypper repos"
echo ""
echo "# 2. Try utilities repository (for jq)"
echo "sudo zypper addrepo -f \\"
echo "  https://download.opensuse.org/repositories/utilities/SLE_15_SP4/utilities.repo"
echo ""
echo "# 3. Try containers repository - Option A (SLE Micro specific)"
echo "sudo zypper addrepo -f \\"
echo "  https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/SLE_Micro_6.2/ \\"
echo "  containers-slemicro"
echo ""
echo "# 4. Try containers repository - Option B (SLE 15 SP4 - SL-Micro is based on this)"
echo "sudo zypper addrepo -f \\"
echo "  https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/SLE_15_SP4/ \\"
echo "  containers-stable"
echo ""
echo "# 5. Refresh and verify"
echo "sudo zypper refresh"
echo "sudo zypper repos"
echo ""


