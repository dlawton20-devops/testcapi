# Scripts Documentation

This directory contains scripts for managing the OpenStack + Rancher + CAPI environment.

## Scripts Overview

### 1. `install-turtles.sh`
**Purpose**: Installs and configures Turtles, CAPO, and CAPI components
**What it does**:
- Creates necessary namespaces
- Installs Turtles (Rancher's CAPI integration)
- Installs CAPO (Cluster API Provider for OpenStack)
- Installs core CAPI components
- Creates OpenStack credentials secret
- Sets up Turtles configuration
**Usage**:
```bash
./install-turtles.sh
```

### 2. `create-cluster.sh`
**Purpose**: Creates a new cluster using the cluster template
**What it does**:
- Validates environment variables
- Generates cluster configuration from template
- Creates cluster using Rancher API
- Monitors cluster creation status
**Usage**:
```bash
export RANCHER_URL="https://your-rancher-server"
export RANCHER_TOKEN="your-api-token"
export CLUSTER_NAME="your-cluster-name"
./create-cluster.sh
```

### 3. `setup-env.sh`
**Purpose**: Sets up the environment variables and configurations
**What it does**:
- Creates .env file from template
- Sets up OpenStack credentials
- Configures cluster settings
**Usage**:
```bash
./setup-env.sh
```

## Required Environment Variables

### For Turtles/CAPI:
```bash
OS_AUTH_URL
OS_USERNAME
OS_PASSWORD
OS_PROJECT_NAME
OS_PROJECT_DOMAIN_NAME
OS_USER_DOMAIN_NAME
OS_REGION_NAME
OS_NETWORK_ID
OS_SUBNET_ID
OS_FLOATING_IP_NETWORK
OS_EXTERNAL_NETWORK_ID
OS_IMAGE_NAME
OS_FLAVOR_NAME
```

### For Rancher:
```bash
RANCHER_URL
RANCHER_TOKEN
CLUSTER_NAME
```

## Script Dependencies

- `kubectl`: Required for all scripts
- `jq`: Required for JSON parsing in create-cluster.sh
- `envsubst`: Required for template processing
- OpenStack CLI tools (optional)

## Script Execution Order

1. First run `setup-env.sh` to configure environment
2. Then run `install-turtles.sh` to install components
3. Finally run `create-cluster.sh` to create clusters

## Error Handling

Each script includes basic error handling:
- Checks for required tools
- Validates environment variables
- Monitors deployment status
- Provides error messages and exit codes 