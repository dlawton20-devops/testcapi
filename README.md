# Work Environment (OpenStack + Rancher + CAPI)

This environment simulates the production setup using OpenStack, Rancher, and Cluster API (CAPI).

## Directory Structure

- `capi/`: Cluster API configurations
  - `cluster-templates/`: Templates for different cluster types
  - `providers/`: CAPI provider configurations
  - `values/`: Environment-specific values

- `openstack/`: OpenStack configurations
  - `credentials/`: OpenStack credentials (templates)
  - `templates/`: OpenStack resource templates

- `rancher/`: Rancher configurations
  - `bootstrap/`: Rancher bootstrap configurations
  - `cluster-configs/`: Rancher cluster configurations

## Setup Instructions

1. Configure OpenStack credentials
2. Install and configure CAPI providers
3. Set up Rancher management cluster
4. Create workload clusters using CAPI

## Usage

This environment is designed to mirror the production setup and should be used for:
- Testing CAPI configurations
- Validating OpenStack integrations
- Testing Rancher cluster management
- Developing and testing cluster templates 

rancher-capo-turtles-setup/ 