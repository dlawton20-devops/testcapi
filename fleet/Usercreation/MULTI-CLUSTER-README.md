# Multi-Cluster Rancher User Setup

Automate adding cluster and project role permissions to a local user across **ALL clusters** in Rancher (both upstream and downstream).

## 🎯 What This Does

- **Discovers all clusters** in your Rancher instance (local + downstream)
- **Adds cluster permissions** (`cluster-member` + `cluster-view`) to ALL clusters
- **Adds project permissions** (`project-member` + `project-view`) to ALL projects
- **Works with both upstream and downstream clusters**
- **Supports dry-run mode** for testing

## 🚀 Quick Start

### Option 1: Shell Script (Recommended)
```bash
# Dry run first (see what would be created)
./multi-cluster-setup.sh lma-user true

# Apply for real
./multi-cluster-setup.sh lma-user false
```

### Option 2: Terraform
```bash
cd terraform-multi-cluster/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init && terraform apply
```

## 📁 Multi-Cluster Files

```
rancher-user-setup/
├── multi-cluster-setup.sh          # Main multi-cluster script
├── cleanup-multi-cluster.sh        # Cleanup script
├── terraform-multi-cluster/        # Terraform multi-cluster setup
│   ├── main.tf
│   └── variables.tf
└── multi-cluster-manifests/        # Generated manifests (auto-created)
```

## 🔧 How It Works

### 1. **Cluster Discovery**
- Uses `kubectl get clusters.management.cattle.io` to find ALL clusters
- Works with both local and downstream clusters
- No need to specify cluster IDs manually

### 2. **Permission Creation**
For each cluster, creates:
- `ClusterRoleTemplateBinding` with `cluster-member` role
- `ClusterRoleTemplateBinding` with `cluster-view` role

For each project, creates:
- `ProjectRoleTemplateBinding` with `project-member` role
- `ProjectRoleTemplateBinding` with `project-view` role

### 3. **Manifest Generation**
- Creates individual YAML files for each cluster/project
- Stores them in `multi-cluster-manifests/` directory
- Easy to review and modify before applying

## 📋 Usage Examples

### Basic Setup
```bash
# Set up user across all clusters
./multi-cluster-setup.sh lma-user

# Dry run to see what would be created
./multi-cluster-setup.sh lma-user true
```

### Cleanup
```bash
# Remove all permissions for user
./cleanup-multi-cluster.sh lma-user

# Skip confirmation prompt
./cleanup-multi-cluster.sh lma-user true
```

### Terraform Setup
```bash
cd terraform-multi-cluster/
terraform init
terraform plan  # See what will be created
terraform apply
```

## 🔍 What Gets Created

### For Each Cluster:
```yaml
# Cluster Member Role
apiVersion: management.cattle.io/v3
kind: ClusterRoleTemplateBinding
metadata:
  name: lma-user-cluster-member-c-xxxxx
  namespace: "cattle-global-data"
clusterRoleTemplateId: "cluster-member"
userId: "user-xxxxx"
clusterId: "c-xxxxx"

# Cluster Viewer Role
apiVersion: management.cattle.io/v3
kind: ClusterRoleTemplateBinding
metadata:
  name: lma-user-cluster-viewer-c-xxxxx
  namespace: "cattle-global-data"
clusterRoleTemplateId: "cluster-view"
userId: "user-xxxxx"
clusterId: "c-xxxxx"
```

### For Each Project:
```yaml
# Project Member Role
apiVersion: management.cattle.io/v3
kind: ProjectRoleTemplateBinding
metadata:
  name: lma-user-project-member-p-xxxxx
  namespace: "cattle-global-data"
projectId: "c-xxxxx:p-xxxxx"
roleTemplateId: "project-member"
userId: "user-xxxxx"

# Project Viewer Role
apiVersion: management.cattle.io/v3
kind: ProjectRoleTemplateBinding
metadata:
  name: lma-user-project-viewer-p-xxxxx
  namespace: "cattle-global-data"
projectId: "c-xxxxx:p-xxxxx"
roleTemplateId: "project-view"
userId: "user-xxxxx"
```

## 🛠️ Prerequisites

### For Shell Script
- `kubectl` configured and connected to Rancher cluster
- User must already exist in Rancher
- Admin access to Rancher

### For Terraform
- Terraform installed
- Rancher API token with admin privileges
- User will be created if it doesn't exist

## 🔍 Verification

After setup, verify permissions:

```bash
# Check cluster permissions
kubectl get clusterroletemplatebindings.management.cattle.io | grep lma-user

# Check project permissions
kubectl get projectroletemplatebindings.management.cattle.io | grep lma-user

# Count total permissions
kubectl get clusterroletemplatebindings.management.cattle.io | grep lma-user | wc -l
kubectl get projectroletemplatebindings.management.cattle.io | grep lma-user | wc -l
```

## 🐛 Troubleshooting

### Common Issues

1. **User Not Found**
   ```bash
   # Check if user exists
   kubectl get users.management.cattle.io | grep lma-user
   
   # Create user first
   ./auto-setup.sh lma-user
   ```

2. **Permission Denied**
   - Ensure you're logged in as admin
   - Check Rancher API token permissions

3. **Clusters Not Found**
   ```bash
   # Check cluster discovery
   kubectl get clusters.management.cattle.io
   ```

4. **Projects Not Found**
   ```bash
   # Check project discovery
   kubectl get projects.management.cattle.io
   ```

### Debug Commands

```bash
# Check what clusters will be processed
kubectl get clusters.management.cattle.io -o custom-columns="ID:.metadata.name,NAME:.spec.displayName,STATE:.status.state"

# Check what projects will be processed
kubectl get projects.management.cattle.io -o custom-columns="ID:.metadata.name,NAME:.spec.displayName,CLUSTER:.spec.clusterName"

# Check existing permissions
kubectl get clusterroletemplatebindings.management.cattle.io -o wide | grep lma-user
kubectl get projectroletemplatebindings.management.cattle.io -o wide | grep lma-user
```

## 📊 Monitoring

### Check Permission Counts
```bash
# Count cluster permissions
kubectl get clusterroletemplatebindings.management.cattle.io | grep lma-user | wc -l

# Count project permissions
kubectl get projectroletemplatebindings.management.cattle.io | grep lma-user | wc -l

# Count total clusters
kubectl get clusters.management.cattle.io | wc -l

# Count total projects
kubectl get projects.management.cattle.io | wc -l
```

### Check User Access
```bash
# Test user access to a specific cluster
kubectl auth can-i get pods --as=user-xxxxx

# Test user access to a specific project
kubectl auth can-i get pods --as=user-xxxxx -n project-namespace
```

## 🔐 Security Notes

- **Global Access**: User gets access to ALL clusters and projects
- **Built-in Roles**: Uses only Rancher's built-in role templates
- **Audit Trail**: All permissions are visible in Rancher UI
- **Easy Cleanup**: Use cleanup script to remove all permissions

## 🚨 Important Considerations

1. **Scale**: This gives the user access to EVERYTHING in Rancher
2. **Security**: Consider if global access is really needed
3. **Maintenance**: New clusters/projects will need manual permission addition
4. **Cleanup**: Use the cleanup script to remove permissions when needed

## 📈 Advanced Usage

### Exclude Specific Clusters (Terraform)
```hcl
# In terraform.tfvars
exclude_clusters = ["c-exclude1", "c-exclude2"]
exclude_projects = ["c-cluster1:p-exclude1"]
```

### Custom Role Templates
Modify the script to use custom role templates instead of built-in ones.

### Scheduled Updates
Set up a cron job to run the script periodically for new clusters/projects.

---

**⚠️ Warning**: This gives the user access to ALL clusters and projects in your Rancher instance. Use with caution and ensure proper security controls are in place.