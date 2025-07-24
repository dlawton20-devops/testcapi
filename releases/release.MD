
# 📄 Tenant Upgrade & Rancher Release Policy

## Overview
This document defines the strategy, frequency, and guardrails for upgrading Rancher and tenant Kubernetes clusters in our platform. It balances operational workload, stability, and compatibility across our 18 tenant environments.

---

## 🎯 Goals
- Stay within supported Rancher and Kubernetes versions
- Reduce upgrade bottlenecks
- Maintain stability and quality during rollouts
- Enable predictable release planning and testing

---

## 🧭 Rancher Version Upgrade Policy

### Frequency
- **Twice per year** (every 6 months)
  - Example: February & August upgrade windows

### Criteria for New Rancher Version Adoption
- Must be **2 minor versions from latest**, e.g., adopt `v2.8.x` if `v2.9.x` is latest
- Must be **at least 2 months old** to allow early bugs to surface
- Must be **tested internally** in a staging Rancher cluster
- Must be **compatible with tenant workloads**, logging, and monitoring

### Triggers for Out-of-Cycle Upgrade
- Security CVEs or critical bugs
- Upstream support EOL for current Rancher version
- Required feature or Kubernetes version compatibility

---

## 🔁 Tenant Upgrade Strategy

### Upgrade Process
1. **Plan upgrades** at the start of upgrade sprints
2. **Upgrade staging/canary tenants first** (1–2 low-risk clusters)
3. Monitor for **2–3 days** post-upgrade
4. Roll out to **remaining tenants in batches** across sprints
5. Perform **health checks** and document version updates

### Frequency
- **Every 6 months**, aligned with Rancher upgrade schedule
- Each upgrade window is executed over **2–3 sprints**

### Scope
- Upgrade Rancher agents on tenant clusters
- Upgrade Helm charts (logging, monitoring, etc.)
- Upgrade downstream Kubernetes versions if needed

### Tools
- Use `rancher-backup` Helm chart for Rancher snapshots
- Track upgrade status in Google Sheet or versioned YAML doc

### Example Rollout Plan
| Sprint | Action                             |
|--------|------------------------------------|
| Sprint 1 | Stage Rancher upgrade, validate RC |
| Sprint 2 | Upgrade Rancher in prod           |
| Sprint 3 | Upgrade 6 tenants                 |
| Sprint 4 | Upgrade remaining tenants         |

---

## ✅ Guardrails

### Merge Guardrails
- All changes must go through MRs/PRs
- Minimum 1 peer review required
- CI checks: `terraform validate`, `ansible-lint`, etc.
- Changes must be tested in staging and labeled `tested ✅`

### Release Guardrails
- Only tested RCs can be promoted to `vX.Y.Z`
- Release promotion must be signed off
- Releases must come from `main` or `release` branches

### Tenant Upgrade Guardrails
- Always back up before upgrades
- Perform health checks after each upgrade
- Use feature flags or config gating for risky changes

---

## 🧪 Testing Strategy

### Per Sprint
- Only test releases that introduce impactful changes
- Light validation for internal RCs: control plane, cluster sync, logging
- Full validation for Rancher upgrades or K8s bumps

### Validation Checklist
- Rancher UI and login
- Downstream clusters synced and healthy
- Logging and monitoring Helm apps functional
- Workloads running post-upgrade

---

## 📌 Summary
| Area                  | Frequency / Rule                          |
|-----------------------|-------------------------------------------|
| Rancher upgrade       | Every 6 months, 2 months post-release     |
| Tenant upgrade        | Every 6 months, phased over 2–3 sprints   |
| Security/CVE upgrade  | As needed                                 |
| Merge process         | Peer-reviewed, CI-validated MRs only      |
| Release tags          | Only from tested and approved RCs         |

---

## 📂 Appendix
- [ ] Add upgrade tracking template (Google Sheet or YAML)
- [ ] Define rollback steps in playbooks
- [ ] Add links to Rancher support matrix and changelog
