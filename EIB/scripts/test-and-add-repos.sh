#!/bin/bash
# Script to test and add correct repositories for SL-Micro 6.2

echo "=========================================="
echo "Testing and Adding Repositories for SL-Micro 6.2"
echo "=========================================="
echo ""
echo "Run these commands INSIDE your SL-Micro VM:"
echo ""

echo "# Step 1: Check what's already available"
echo "sudo zypper repos"
echo "sudo zypper search podman"
echo "sudo zypper search jq"
echo ""

echo "# Step 2: Test repository URLs before adding"
echo "# Test utilities repository:"
echo "curl -I https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/utilities.repo"
echo ""

echo "# Step 3: Try adding utilities repository (for jq)"
echo "# If the URL above returns 200 OK, run:"
echo "sudo zypper addrepo -f \\"
echo "  https://download.opensuse.org/repositories/utilities/openSUSE_Leap_15.4/utilities.repo \\"
echo "  utilities-leap"
echo ""

echo "# Step 4: Try containers repository"
echo "# Test first:"
echo "curl -I https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/openSUSE_Leap_15.4/"
echo ""
echo "# If available, try adding:"
echo "sudo zypper addrepo -f \\"
echo "  https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/openSUSE_Leap_15.4/devel:kubic:libcontainers:stable.repo \\"
echo "  containers-stable"
echo ""

echo "# Step 5: Alternative - Use SUSEConnect (if you have credentials)"
echo "export http_proxy=http://your-proxy:8080"
echo "export https_proxy=http://your-proxy:8080"
echo "sudo -E SUSEConnect --url https://scc.suse.com"
echo ""

echo "# Step 6: Refresh and verify"
echo "sudo zypper refresh"
echo "sudo zypper repos"
echo "sudo zypper search podman jq"
echo ""

echo "=========================================="
echo "If repositories don't work, try:"
echo "=========================================="
echo ""
echo "# Check what repositories are in your system"
echo "ls /etc/zypp/repos.d/"
echo ""
echo "# Check if packages are in default repos"
echo "sudo zypper search -t package podman"
echo "sudo zypper search -t package jq"
echo ""


