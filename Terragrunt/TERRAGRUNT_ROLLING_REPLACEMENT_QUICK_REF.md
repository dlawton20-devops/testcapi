# Terragrunt Rolling Replacement - Quick Reference

## The Problem

When changing flavors in a 3-AZ Rancher2/OpenStack setup, Terragrunt replaces all nodes at once, causing service disruption.

## The Solution: Use `-target` Flag

Target individual nodes to replace them one at a time.

## Two Approaches

### 1. Create-Before-Destroy (When Capacity is Constrained) ⭐ RECOMMENDED

**Use when**: You don't have enough space on remaining nodes to handle drained workloads.

**Process**:
1. Create new node (with new flavor) using `-target`
2. Wait for new node to join cluster and be Ready
3. Drain old node (workloads migrate to new node)
4. Old node is automatically destroyed by Terraform

**Command**:
```bash
# Using the script
./scripts/utilities/rolling-node-replace.sh \
  --create-before-destroy \
  --resource-name "openstack_compute_instance_v2.rancher_node" \
  --node-count 3

# Or manually
terragrunt apply -target='openstack_compute_instance_v2.rancher_node[0]'
kubectl wait --for=condition=Ready node/rancher-node-0 --timeout=600s
kubectl drain rancher-node-0 --ignore-daemonsets --delete-emptydir-data
# Repeat for nodes 1 and 2
```

### 2. Drain-Before-Replace (When You Have Capacity)

**Use when**: You have enough capacity on remaining nodes.

**Process**:
1. Drain old node (workloads move to other nodes)
2. Cordon old node
3. Create new node (with new flavor) using `-target`
4. Wait for new node to join cluster

**Command**:
```bash
# Using the script
./scripts/utilities/rolling-node-replace.sh \
  --resource-name "openstack_compute_instance_v2.rancher_node" \
  --node-count 3

# Or manually
kubectl drain rancher-node-0 --ignore-daemonsets --delete-emptydir-data
kubectl cordon rancher-node-0
terragrunt apply -target='openstack_compute_instance_v2.rancher_node[0]'
kubectl wait --for=condition=Ready node/rancher-node-0 --timeout=600s
# Repeat for nodes 1 and 2
```

## Required Terraform Configuration

Ensure your resources have `create_before_destroy`:

```hcl
resource "openstack_compute_instance_v2" "rancher_node" {
  count = 3
  name  = "rancher-node-${count.index}"
  flavor_name = var.instance_flavor
  
  lifecycle {
    create_before_destroy = true
  }
}
```

## Quick Decision Tree

```
Do you have enough capacity on remaining nodes?
│
├─ YES → Use Drain-Before-Replace
│        (Drain → Cordon → Replace → Wait)
│
└─ NO  → Use Create-Before-Destroy ⭐
         (Replace → Wait → Drain → Auto-destroy)
```

## Key Points

- ✅ Always use `-target` to replace one node at a time
- ✅ Use `create_before_destroy = true` in Terraform
- ✅ Wait for nodes to be Ready before proceeding
- ✅ Use `kubectl wait` instead of just sleeping
- ✅ Test with `--dry-run` first

## See Also

- Full guide: `docs/TERRAGRUNT_ROLLING_REPLACEMENT_GUIDE.md`
- Script: `scripts/utilities/rolling-node-replace.sh`




