# Terragrunt Rolling Node Replacement Guide

## Problem Statement

When changing the flavor (instance type) in a 3-AZ Rancher2/OpenStack setup, Terraform/Terragrunt replaces all nodes simultaneously instead of performing a graceful rolling replacement. This can cause service disruption.

## Solution: Using `-target` Flag for Rolling Replacements

The `-target` flag allows you to apply changes to specific resources one at a time, enabling a controlled rolling replacement.

## Method 1: Manual Rolling Replacement with `-target`

### Step-by-Step Process

1. **Identify your node resources** in your Terraform configuration. They might look like:
   ```hcl
   resource "openstack_compute_instance_v2" "rancher_node" {
     count = 3
     name  = "rancher-node-${count.index}"
     # ... other configuration
   }
   ```

2. **Apply changes to one node at a time**:
   ```bash
   # Replace node 0 first
   terragrunt apply -target='openstack_compute_instance_v2.rancher_node[0]'
   
   # Wait for node 0 to be healthy in Rancher
   # Then replace node 1
   terragrunt apply -target='openstack_compute_instance_v2.rancher_node[1]'
   
   # Wait for node 1 to be healthy
   # Finally replace node 2
   terragrunt apply -target='openstack_compute_instance_v2.rancher_node[2]'
   ```

### Example with Multiple Resources

If your nodes are defined across multiple resources (e.g., separate resources for each AZ):

```bash
# AZ 1
terragrunt apply -target='openstack_compute_instance_v2.rancher_node_az1'

# Wait, then AZ 2
terragrunt apply -target='openstack_compute_instance_v2.rancher_node_az2'

# Wait, then AZ 3
terragrunt apply -target='openstack_compute_instance_v2.rancher_node_az3'
```

## Method 2: Using Lifecycle Rules

Add `create_before_destroy` to your node resources to ensure new nodes are created before old ones are destroyed:

```hcl
resource "openstack_compute_instance_v2" "rancher_node" {
  count = 3
  name  = "rancher-node-${count.index}"
  flavor_name = var.instance_flavor
  
  # ... other configuration ...
  
  lifecycle {
    create_before_destroy = true
  }
}
```

**Note**: This alone won't prevent all nodes from being replaced at once, but it ensures the new node is created before the old one is destroyed.

## Method 3: Create-Before-Destroy with Capacity Constraints

**This is the recommended method when you don't have enough capacity on remaining nodes.**

When changing flavors, you need to:
1. **Create the new node first** (with new flavor)
2. **Wait for it to join the cluster**
3. **Drain the old node** (workloads migrate to the new node)
4. **Remove the old node**

### Terraform Configuration

Ensure your resources use `create_before_destroy`:

```hcl
resource "openstack_compute_instance_v2" "rancher_node" {
  count = 3
  name  = "rancher-node-${count.index}"
  flavor_name = var.instance_flavor
  
  # ... other configuration ...
  
  lifecycle {
    create_before_destroy = true
  }
}
```

### Manual Process

```bash
# Step 1: Create new node (Terraform will create before destroying)
terragrunt apply -target='openstack_compute_instance_v2.rancher_node[0]'

# Step 2: Wait for new node to join cluster and be Ready
kubectl wait --for=condition=Ready node/rancher-node-0 --timeout=300s

# Step 3: Drain the old node (workloads move to new node)
kubectl drain rancher-node-0 --ignore-daemonsets --delete-emptydir-data

# Step 4: Cordon the old node
kubectl cordon rancher-node-0

# Step 5: Remove old node from Terraform state (if it still exists)
# Terraform should have already destroyed it, but verify:
terragrunt state list | grep rancher_node

# Repeat for other nodes...
```

### Using Temporary Node Approach

If `create_before_destroy` doesn't work as expected, you can temporarily add a new node:

```hcl
# Temporarily increase count to 4
resource "openstack_compute_instance_v2" "rancher_node" {
  count = 4  # Temporarily 4 nodes
  name  = "rancher-node-${count.index}"
  flavor_name = var.instance_flavor
  # ... configuration ...
}
```

Then:
1. Apply to create node-3
2. Wait for it to join
3. Drain node-0
4. Remove node-0 from state: `terragrunt state rm 'openstack_compute_instance_v2.rancher_node[0]'`
5. Adjust count back to 3 and reorder indices

## Method 4: Combining `-target` with Lifecycle Rules (Simple Case)

For cases where you have enough capacity:

```hcl
resource "openstack_compute_instance_v2" "rancher_node" {
  count = 3
  name  = "rancher-node-${count.index}"
  flavor_name = var.instance_flavor
  
  # ... other configuration ...
  
  lifecycle {
    create_before_destroy = true
  }
}
```

Then use `-target` to replace one at a time:

```bash
terragrunt apply -target='openstack_compute_instance_v2.rancher_node[0]'
# Wait for health check
terragrunt apply -target='openstack_compute_instance_v2.rancher_node[1]'
# Wait for health check
terragrunt apply -target='openstack_compute_instance_v2.rancher_node[2]'
```

## Method 5: Scripted Rolling Replacement

Create a script to automate the rolling replacement:

```bash
#!/bin/bash
# rolling-replace.sh

set -e

NODE_COUNT=3
RESOURCE_NAME="openstack_compute_instance_v2.rancher_node"

for i in $(seq 0 $((NODE_COUNT - 1))); do
  echo "Replacing node $i..."
  terragrunt apply -target="${RESOURCE_NAME}[${i}]" -auto-approve
  
  echo "Waiting for node $i to be healthy..."
  # Add your health check logic here
  # For example, wait for node to be ready in Rancher
  sleep 60  # Adjust based on your needs
  
  echo "Node $i replacement complete."
done

echo "All nodes replaced successfully."
```

## Method 6: Using `replace_triggered_by` for Controlled Replacements

If you want to control when replacements happen, you can use `replace_triggered_by`:

```hcl
variable "flavor_version" {
  description = "Version identifier for flavor changes"
  type        = string
  default     = "v1"
}

resource "openstack_compute_instance_v2" "rancher_node" {
  count = 3
  name  = "rancher-node-${count.index}"
  flavor_name = var.instance_flavor
  
  lifecycle {
    replace_triggered_by = [
      var.flavor_version
    ]
  }
}
```

Then increment `flavor_version` when you want to trigger replacements, and use `-target` to replace one at a time.

## Choosing the Right Method

### When to Use Create-Before-Destroy Mode

Use `--create-before-destroy` (or Method 3) when:
- **You don't have enough capacity** on remaining nodes to handle workloads from a drained node
- **You're running at high resource utilization** (CPU, memory, or pod density)
- **You want zero downtime** during the replacement
- **Your workloads cannot tolerate temporary unavailability**

**Workflow**: Create new node → Wait for it to join → Drain old node → Remove old node

### When to Use Drain-Before-Replace Mode

Use the standard drain-first approach when:
- **You have sufficient capacity** on remaining nodes
- **You're running at low-to-moderate resource utilization**
- **You can tolerate brief periods of reduced capacity**
- **You want to ensure workloads are moved before creating new resources**

**Workflow**: Drain old node → Cordon old node → Create new node → Wait for it to join

## Best Practices

1. **Always use `-target` for rolling replacements** when changing flavors
2. **Add health checks** between replacements to ensure the cluster remains healthy
3. **Use `create_before_destroy = true` in Terraform** to ensure proper ordering
4. **Monitor cluster capacity** before starting replacements
5. **Test in a non-production environment first**
6. **Use create-before-destroy mode** when capacity is constrained
7. **Verify node readiness** using `kubectl wait` instead of just sleeping

## Rancher-Specific Considerations

1. **Node Drain**: Before replacing a node, drain it in Rancher:
   ```bash
   kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
   ```

2. **Node Removal**: After draining, cordon the node:
   ```bash
   kubectl cordon <node-name>
   ```

3. **Health Verification**: After replacement, verify the node is healthy:
   ```bash
   kubectl get nodes
   kubectl describe node <new-node-name>
   ```

## Complete Workflow Examples

### Workflow 1: With Capacity Constraints (Create-Before-Destroy)

```bash
#!/bin/bash
# complete-rolling-replace-cbd.sh
# Use this when you don't have enough capacity on remaining nodes

set -e

NODE_COUNT=3
RESOURCE_PREFIX="openstack_compute_instance_v2.rancher_node"

for i in $(seq 0 $((NODE_COUNT - 1))); do
  NODE_NAME="rancher-node-${i}"
  
  echo "=== Step 1: Creating new node $i (with new flavor) ==="
  # Terraform with create_before_destroy will create new node first
  terragrunt apply -target="${RESOURCE_PREFIX}[${i}]" -auto-approve
  
  echo "=== Step 2: Waiting for new node to join cluster ==="
  # Wait for the new node to be Ready
  kubectl wait --for=condition=Ready node/"$NODE_NAME" --timeout=600s || {
    echo "Warning: New node may not be ready yet, but continuing..."
  }
  
  echo "=== Step 3: Draining old node $i ==="
  # Drain the old node - workloads will move to the new node
  kubectl drain "$NODE_NAME" \
    --ignore-daemonsets \
    --delete-emptydir-data \
    --timeout=300s \
    --grace-period=60 || {
    echo "Warning: Drain may have failed, but continuing..."
  }
  
  echo "=== Step 4: Cordoning old node $i ==="
  kubectl cordon "$NODE_NAME" || true
  
  echo "=== Step 5: Verifying new node health ==="
  kubectl get nodes "$NODE_NAME" -o wide
  
  echo "=== Node $i replacement complete ===\n"
done

echo "=== All nodes replaced successfully ==="
```

### Workflow 2: With Sufficient Capacity (Drain-Before-Replace)

```bash
#!/bin/bash
# complete-rolling-replace-drain-first.sh
# Use this when you have enough capacity on remaining nodes

set -e

NODE_COUNT=3
RESOURCE_PREFIX="openstack_compute_instance_v2.rancher_node"

for i in $(seq 0 $((NODE_COUNT - 1))); do
  NODE_NAME="rancher-node-${i}"
  
  echo "=== Step 1: Draining node $i ==="
  kubectl drain "$NODE_NAME" --ignore-daemonsets --delete-emptydir-data --timeout=300s || true
  
  echo "=== Step 2: Cordon node $i ==="
  kubectl cordon "$NODE_NAME" || true
  
  echo "=== Step 3: Replacing node $i with Terragrunt ==="
  terragrunt apply -target="${RESOURCE_PREFIX}[${i}]" -auto-approve
  
  echo "=== Step 4: Waiting for new node to be ready ==="
  kubectl wait --for=condition=Ready node/"$NODE_NAME" --timeout=600s
  
  echo "=== Step 5: Verifying node health ==="
  kubectl get nodes "$NODE_NAME" -o wide
  
  echo "=== Node $i replacement complete ===\n"
done

echo "=== All nodes replaced successfully ==="
```

## Using the Rolling Replacement Script

The provided script (`scripts/utilities/rolling-node-replace.sh`) supports both modes:

### Create-Before-Destroy Mode (Recommended for Capacity Constraints)

```bash
./scripts/utilities/rolling-node-replace.sh \
  --resource-name "openstack_compute_instance_v2.rancher_node" \
  --node-count 3 \
  --create-before-destroy \
  --wait-time 180
```

### Drain-Before-Replace Mode (When You Have Capacity)

```bash
./scripts/utilities/rolling-node-replace.sh \
  --resource-name "openstack_compute_instance_v2.rancher_node" \
  --node-count 3 \
  --wait-time 120
```

### Dry Run (Test First)

```bash
./scripts/utilities/rolling-node-replace.sh \
  --resource-name "openstack_compute_instance_v2.rancher_node" \
  --node-count 3 \
  --create-before-destroy \
  --dry-run
```

## Troubleshooting

### Issue: `-target` doesn't work as expected

**Solution**: Ensure you're using the correct resource address. Use `terragrunt plan -target='resource.address'` first to verify.

### Issue: Dependencies prevent targeting

**Solution**: You may need to target dependent resources as well:
```bash
terragrunt apply -target='resource1' -target='resource2'
```

### Issue: Nodes still replace all at once

**Solution**: 
1. Check if you're using `for_each` instead of `count` - adjust the target syntax accordingly
2. Verify there are no dependencies forcing simultaneous replacement
3. Use `terraform state list` to see exact resource addresses
4. Ensure `create_before_destroy = true` is set in your resource lifecycle block

### Issue: New node created but old node not destroyed

**Solution**: This is expected behavior with `create_before_destroy`. The old node will be destroyed after the new one is created and verified. You may need to manually verify the new node is healthy before Terraform proceeds.

### Issue: Workloads fail to migrate during drain

**Solution**: 
1. Check if you have enough capacity on remaining nodes
2. Use create-before-destroy mode instead
3. Verify pod disruption budgets aren't preventing migration
4. Check for node affinity/anti-affinity rules that might prevent scheduling

## Additional Resources

- [Terraform Target Documentation](https://www.terraform.io/docs/cli/commands/plan.html#target-address)
- [Terragrunt Target Usage](https://terragrunt.gruntwork.io/docs/reference/cli-options/#apply)
- [Terraform Lifecycle Rules](https://www.terraform.io/docs/language/meta-arguments/lifecycle.html)

