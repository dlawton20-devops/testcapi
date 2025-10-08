# Rancher Local User Setup

Complete automation for creating Rancher local users with proper RBAC permissions and LMA project setup.

## 📁 Files Overview

```
rancher-user-setup/
├── rancher-user-setup.yaml    # Main Kubernetes manifest
├── auto-setup.sh              # Fully automated setup script
├── find-ids.sh                # Simple ID finder script
├── setup-rancher-user.sh      # Helper script with commands
├── multi-cluster-setup.sh     # Multi-cluster automation
├── cleanup-multi-cluster.sh   # Multi-cluster cleanup
├── terraform/                 # Terraform automation
│   ├── main.tf
│   ├── variables.tf
│   └── terraform.tfvars.example
├── terraform-multi-cluster/   # Multi-cluster Terraform
│   ├── main.tf
│   └── variables.tf
├── gitlab-user-setup/         # GitLab automation
│   ├── gitlab-automation.sh
│   ├── setup-gitlab.sh
│   ├── config.yaml
│   └── README.md
└── README.md                  # This file
```

## 🚀 Quick Start Options

### Option 1: Fully Automated (Recommended)
```bash
# Run the auto-setup script
./auto-setup.sh [username]

# Example:
./auto-setup.sh lma-user
```

### Option 2: Multi-Cluster Setup
```bash
# Set up user across all clusters
./multi-cluster-setup.sh lma-user

# Dry run first
./multi-cluster-setup.sh lma-user true
```

### Option 3: GitLab User Automation
```bash
cd gitlab-user-setup/
./setup-gitlab.sh
```

### Option 4: Find IDs First, Then Apply
```bash
# Find all required IDs
./find-ids.sh [username]

# Edit the manifest with found IDs
nano rancher-user-setup.yaml

# Apply manually
kubectl apply -f rancher-user-setup.yaml
```

### Option 5: Terraform (Infrastructure as Code)
```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan
terraform apply
```

## 🔧 Manual Setup

### Step 1: Get Required IDs

#### Using the find-ids script:
```bash
./find-ids.sh your-username
```

#### Using kubectl commands:
```bash
# Get cluster ID
kubectl get clusters.management.cattle.io -o wide

# Get user ID
kubectl get users.management.cattle.io -o wide

# Get project ID (after creating project)
kubectl get projects.management.cattle.io -o wide
```

### Step 2: Update Manifest
Edit `rancher-user-setup.yaml` and replace:
- `your-local-user-id` → Your actual Rancher user ID
- `c-xxxxx:p-xxxxx` → Your actual cluster:project IDs
- `your-cluster-name` → Your actual cluster name

### Step 3: Apply Manifests
```bash
kubectl apply -f rancher-user-setup.yaml
```

## 🏗️ What Gets Created

### User Permissions (Built-in Rancher Roles)
- **Global**: `user` (basic Rancher access)
- **Cluster**: `cluster-member` + `cluster-view` (full cluster access)
- **Project**: `project-member` + `project-view` (full project access)

### LMA Project
- **Project**: "LMA (Logging, Monitoring, Alerting)"
- **Namespaces**: 
  - `cattle-monitoring-system`
  - `cattle-logging-system`

### RBAC Bindings
- Global role binding for user permissions
- Cluster role bindings for cluster access
- Project role bindings for LMA project access

## 🛠️ Prerequisites

### For Auto-Setup Script
- `kubectl` configured and connected to Rancher cluster
- `rancher` CLI (optional, for user creation)

### For Terraform
- Terraform installed
- Rancher API token with admin privileges
- Target cluster ID

### For Manual Setup
- `kubectl` configured and connected to Rancher cluster
- Admin access to Rancher

## 📋 Terraform Variables

Create `terraform/terraform.tfvars`:

```hcl
rancher_api_url = "https://rancher.your-domain.com"
rancher_token   = "token-xxxxx:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
cluster_id      = "c-xxxxx"
username        = "lma-user"
password        = "your-secure-password"
display_name    = "LMA User"
email          = "lma-user@example.com"
```

## 🔍 Verification

After setup, verify the configuration:

```bash
# Check user permissions
kubectl auth can-i get pods --as=your-user-id

# Check project exists
kubectl get projects.management.cattle.io | grep -i lma

# Check namespaces
kubectl get namespaces | grep -E "(cattle-monitoring|cattle-logging)"

# Check role bindings
kubectl get clusterrolebindings | grep local-user
kubectl get rolebindings -A | grep local-user
```

## 🐛 Troubleshooting

### Common Issues

1. **Permission Denied**
   - Ensure you're logged in as an admin user
   - Check Rancher API token permissions

2. **User Not Found**
   - Create user manually in Rancher UI first
   - Or use the auto-setup script with Rancher CLI

3. **Cluster ID Not Found**
   - Verify kubectl is connected to the right cluster
   - Check cluster exists: `kubectl get clusters.management.cattle.io`

4. **Project Creation Fails**
   - Ensure cluster ID is correct
   - Check if project already exists

### Debug Commands

```bash
# Check Rancher logs
kubectl logs -n cattle-system -l app=rancher

# Verify RBAC
kubectl auth can-i get pods --as=your-user-id

# Check project membership
kubectl get projectroletemplatebindings.management.cattle.io
```

## 🔐 Security Notes

- All manifests use Rancher's built-in roles for consistency
- User IDs are sensitive - don't commit them to version control
- Consider using Rancher's built-in role templates for consistency
- Regularly audit user permissions and project access

## 🎯 GitLab Integration

The project also includes GitLab automation for creating users and repository access:

### **GitLab User Automation**
- **Creates 6 users** with specified usernames, emails, and passwords
- **Invites all users** to 10 repositories with appropriate access levels
- **Handles existing users** gracefully (won't create duplicates)
- **Supports dry-run mode** for testing

### **Quick Start for GitLab**
```bash
cd gitlab-user-setup/
./setup-gitlab.sh
```

### **GitLab Features**
- Interactive setup helper
- Comprehensive error handling
- Rate limit management
- Detailed logging
- Configurable access levels

## 📚 Additional Resources

- [Rancher RBAC Documentation](https://rancher.com/docs/rancher/v2.8/en/admin-settings/rbac/)
- [Rancher CLI Documentation](https://rancher.com/docs/rancher/v2.8/en/cli/)
- [Terraform Rancher2 Provider](https://registry.terraform.io/providers/rancher/rancher2/latest/docs)
- [GitLab API Documentation](https://docs.gitlab.com/ee/api/)