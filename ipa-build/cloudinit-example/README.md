# OpenStack Provider Alias Configuration

This configuration demonstrates how to use multiple OpenStack provider aliases to access different projects within the same Terraform/Terragrunt setup.

## Problem
Previously, only one OpenStack provider was configured, which limited access to a single project. This meant you could only query tenant worker networks, but not control plane or platform worker networks that exist in a different project.

## Solution
Two provider aliases are now configured:

1. **`openstack.tenant`** - For accessing tenant worker networks (tenantworker0, tenantworker1)
2. **`openstack.control_platform`** - For accessing control plane and platform worker networks

## Configuration Details

### Provider Configuration (`providers.tf`)
- Two provider blocks with different aliases
- Each provider points to a different project via `project_name`
- Both use the same authentication credentials but different project contexts

### Data Sources (`main.tf`)
- Network and subnet data sources now use conditional provider selection
- Control plane and platform worker networks use `openstack.control_platform`
- Tenant worker networks use `openstack.tenant`

### Terragrunt Configuration (`terragrunt.hcl`)
- The `inputs` block passes both project names to Terraform
- Update `control_platform_project_name` to point to your actual control/platform project

## Usage

1. Update `terragrunt.hcl` with your actual project names:
   - `tenant_project_name` - Your tenant project name
   - `control_platform_project_name` - Your control plane/platform worker project name

2. Ensure your environment variables are set (especially `CAAS_TENANT_PASSWORD`)

3. Run Terragrunt as usual:
   ```bash
   terragrunt plan
   terragrunt apply
   ```

## Key Changes

- Added provider aliases in `providers.tf`
- Updated data sources to conditionally select the appropriate provider based on network type
- Modified Terragrunt inputs to pass both project names



