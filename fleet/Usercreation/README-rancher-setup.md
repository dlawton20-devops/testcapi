# Rancher Local User Setup Guide

This guide shows you how to set up a local user with read-only permissions and create an LMA (Logging, Monitoring, Alerting) project in Rancher using Kubernetes manifests.

## Prerequisites

- Access to a Rancher cluster with admin privileges
- `kubectl` configured to access your Rancher cluster
- `rancher` CLI (optional but helpful)

## Step-by-Step Instructions

### 1. Get Required IDs

Before applying the manifests, you need to gather some IDs:

#### Get Your User ID
```bash
# Method 1: Using kubectl
kubectl get users.management.cattle.io -o wide

# Method 2: Using rancher CLI
rancher users ls

# Method 3: From Rancher UI
# Go to Users & Authentication > Users, click on your user, copy ID from URL
```

#### Get Cluster ID
```bash
kubectl get clusters.management.cattle.io -o wide
```

### 2. Update the Manifest File

Edit `rancher-user-setup.yaml` and replace the following placeholders:

- `your-local-user-id` → Your actual Rancher user ID
- `c-xxxxx:p-xxxxx` → Your actual cluster:project IDs
- `your-cluster-name` → Your actual cluster name

### 3. Apply the Manifests

```bash
# Apply all manifests
kubectl apply -f rancher-user-setup.yaml
```

**Note:** You may need to apply them in order if you encounter dependency issues:

```bash
# 1. Create the project first
kubectl apply -f - <<EOF
apiVersion: management.cattle.io/v3
kind: Project
metadata:
  name: lma
  namespace: "cattle-global-data"
  labels:
    field.cattle.io/projectId: "YOUR_CLUSTER_ID:YOUR_PROJECT_ID"
spec:
  displayName: "LMA (Logging, Monitoring, Alerting)"
  description: "Project for Logging, Monitoring, and Alerting components"
  clusterName: "YOUR_CLUSTER_NAME"
EOF

# 2. Then apply the rest
kubectl apply -f rancher-user-setup.yaml
```

## What the Manifests Do

### 1. Cluster Read-Only Access
- Binds your user to the built-in `view` ClusterRole
- Gives read-only access to cluster resources

### 2. Cluster Viewer Role (Rancher-specific)
- Uses Rancher's `ClusterRoleTemplateBinding`
- Provides cluster viewer permissions through Rancher's RBAC system

### 3. LMA Project Creation
- Creates a project named "LMA"
- Includes both `cattle-monitoring-system` and `cattle-logging-system` namespaces
- Namespaces are labeled to belong to the project

### 4. Project-Level Permissions
- Grants read-only access to the LMA project
- Uses Rancher's `ProjectRoleTemplateBinding`

### 5. Namespace-Level RBAC
- Additional RoleBindings for each namespace
- Ensures read-only access to monitoring and logging resources

## Verification

After applying the manifests, verify the setup:

```bash
# Check if the project was created
kubectl get projects.management.cattle.io

# Check if namespaces are properly labeled
kubectl get namespaces --show-labels | grep lma

# Check role bindings
kubectl get clusterrolebindings | grep local-user
kubectl get rolebindings -A | grep local-user
```

## Troubleshooting

### Common Issues

1. **Permission Denied**: Ensure you're logged in as an admin user
2. **Project ID Not Found**: Create the project first, then get its ID
3. **User ID Not Found**: Verify the user exists in Rancher

### Getting Help

- Check Rancher logs: `kubectl logs -n cattle-system -l app=rancher`
- Verify RBAC: `kubectl auth can-i get pods --as=your-user-id`
- Check project membership: `kubectl get projectroletemplatebindings.management.cattle.io`

## Security Notes

- The manifests use read-only permissions by default
- User IDs are sensitive - don't commit them to version control
- Consider using Rancher's built-in role templates for consistency
- Regularly audit user permissions and project access