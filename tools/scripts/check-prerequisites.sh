#!/bin/bash

# Function to check if a command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo "Error: $1 is required but not installed"
        return 1
    fi
    return 0
}

# Function to check environment variables
check_env_var() {
    if [ -z "${!1}" ]; then
        echo "Error: $1 is not set"
        return 1
    fi
    return 0
}

# Check required commands
echo "Checking required commands..."
commands=("kubectl" "jq" "envsubst")
for cmd in "${commands[@]}"; do
    check_command $cmd || exit 1
done

# Check OpenStack environment variables
echo "Checking OpenStack environment variables..."
openstack_vars=(
    "OS_AUTH_URL"
    "OS_USERNAME"
    "OS_PASSWORD"
    "OS_PROJECT_NAME"
    "OS_PROJECT_DOMAIN_NAME"
    "OS_USER_DOMAIN_NAME"
    "OS_REGION_NAME"
    "OS_NETWORK_ID"
    "OS_SUBNET_ID"
    "OS_FLOATING_IP_NETWORK"
    "OS_EXTERNAL_NETWORK_ID"
    "OS_IMAGE_NAME"
    "OS_FLAVOR_NAME"
)

for var in "${openstack_vars[@]}"; do
    check_env_var $var || exit 1
done

# Check Rancher environment variables
echo "Checking Rancher environment variables..."
rancher_vars=(
    "RANCHER_URL"
    "RANCHER_TOKEN"
    "CLUSTER_NAME"
)

for var in "${rancher_vars[@]}"; do
    check_env_var $var || exit 1
done

# Check Kubernetes connection
echo "Checking Kubernetes connection..."
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "All prerequisites met!"
exit 0 