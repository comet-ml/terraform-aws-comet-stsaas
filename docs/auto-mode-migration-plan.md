# Plan: EKS Auto Mode + private-cluster data-plane split

## Context

Two coupled decisions drive this:

1. **Move to EKS Auto Mode** instead of Karpenter for node provisioning.
2. The clusters run a **private API endpoint** not yet reachable from the
   Terraform runner (no TGW/VPN path). **The TF runner has no data-plane access.**

Consequence of (2): Terraform **cannot create any in-cluster object** for these
clusters — `kubernetes_*`, `kubectl_manifest`, and `helm_release` all open a
connection to the API server and will fail at apply, not just plan. So the
module must be split cleanly into:

- **AWS control-plane resources** (EKS, IAM, SQS, VPC, tags) — reachable via the
  AWS API from anywhere. **Stay in Terraform.**
- **In-cluster / data-plane objects** (manifests, charts, RBAC, storage classes)
  — require API access. **Move to ArgoCD** (`comet-ml/comet-gitops`), which has a
  network path to the private cluster.

This also matches the stated GitOps direction (helm releases → ArgoCD).

## Part A — EKS Auto Mode (control-plane only, no cluster access needed)

Auto Mode's built-in nodepools are provisioned by the **EKS control plane** when
`compute_config.node_pools` is set — a pure EKS API call, no data-plane access.

In `modules/comet_eks/main.tf`, the `module "eks"` block (v21 already supports it):
```hcl
  compute_config = {
    enabled    = var.eks_enable_auto_mode
    node_pools = var.eks_auto_mode_node_pools   # e.g. ["system", "general-purpose"]
  }
```
New root vars (default off, so existing consumers are unaffected):
- `eks_enable_auto_mode` (bool, default false)
- `eks_auto_mode_node_pools` (list(string), default `["system", "general-purpose"]`)

**VERIFIED against v21.23.0 source** (`.terraform/modules/comet_eks.eks`):

- `compute_config` schema is exactly `{ enabled, node_pools, node_role_arn }`.
- The module **auto-creates the Auto Mode node IAM role** when
  `compute_config.enabled = true` (`create_auto_mode_iam_resources`) and wires it
  itself: `node_role_arn = node_pools != null ? aws_iam_role.eks_auto[0].arn : ...`.
  **So do NOT pass `node_role_arn`** when using built-in node_pools — omit it.
- Auto Mode role gets these managed policies: `AmazonEKSComputePolicy`,
  `AmazonEKSBlockStoragePolicy`, `AmazonEKSLoadBalancingPolicy`,
  `AmazonEKSNetworkingPolicy` → i.e. **compute, block storage, load balancing,
  and networking are all NATIVE under Auto Mode.**

**Custom NodePools/NodeClasses** (taints, limits, instance shaping — the
`auto_mode_nodepools` map dev/CI uses) are **CRDs → they go to ArgoCD**, NOT
Terraform, because of the private-endpoint constraint. dev/CI creates them with
`kubernetes_manifest`; we cannot (no API path). comet-gitops owns them.

## Part B — Karpenter: gate off, keep code, document teardown

Karpenter stays in the module but gated by `enable_karpenter` (already the case,
default false). Do **not** delete — mixed/unknown fleet state and this is a
reusable module. Auto Mode and Karpenter are mutually exclusive per cluster.

- Confirm `enable_karpenter` default is `false` and Auto Mode/Karpenter can't
  both be on (add a validation or precondition).
- The 23 Karpenter resources (SQS, EventBridge ×8, node IAM role + 5 policy
  attachments, instance profile, access entry, controller IRSA + policy,
  `helm_release.karpenter_stsaas`, ec2 discovery tags) remain, inert when off.
- Teardown for a live-Karpenter env: enable Auto Mode → migrate/drain workloads
  onto Auto Mode nodes → set `enable_karpenter = false` → apply (destroys the
  Karpenter AWS infra). The `helm_release` is already handled by the ArgoCD
  runbook (see docs/argocd-helm-migration.md).

## Part C — Move ALL data-plane resources out of Terraform

Every in-cluster resource must leave TF for private clusters. Gate each behind
its existing/new toggle so consumers WITH API access can still use them, but the
private-cluster path sets them off and ArgoCD owns them.

**11 data-plane resources in `modules/comet_eks/main.tf`:**

| Resource | Line | Existing toggle | Destination |
|----------|------|-----------------|-------------|
| `helm_release.external_secrets_crds` | 606 | `external_secrets_via_helm_release` | ArgoCD (Tier A runbook) |
| `helm_release.external_secrets` | 647 | `external_secrets_via_helm_release` | ArgoCD |
| `kubectl_manifest.cluster_secret_store` | 730 | `external_secrets_via_helm_release` | ArgoCD |
| `helm_release.karpenter_stsaas` | 1327 | `karpenter_via_helm_release` | removed (Auto Mode) / ArgoCD if kept |
| `kubernetes_storage_class.gp3` | 465 | **none — add one** | ArgoCD or keep if API reachable |
| `kubernetes_storage_class.comet_generic` | 493 | `create_comet_generic_storage_class` | ArgoCD |
| `kubernetes_namespace.monitoring` | 898 | `enable_monitoring_setup` | ArgoCD |
| `kubernetes_secret.monitoring` | 912 | `enable_monitoring_setup` | ArgoCD (or ESO-sourced) |
| `kubernetes_annotations.app_ns_node_selector` | 1446 | `enable_namespace_nodegroup_pinning` | N/A under Auto Mode* |
| `kubernetes_annotations.admin_ns_node_selector` | 1462 | `enable_namespace_nodegroup_pinning` | N/A under Auto Mode* |
| `kubernetes_namespace.redis_insights` | 1484 | `enable_redis_insights_ns` | ArgoCD |

\* Namespace nodegroup-pinning targets named managed node groups
(`nodegroup_name=comet/admin`). Under Auto Mode there are no such node groups —
this pinning is Karpenter/MNG-specific and becomes obsolete; scheduling moves to
NodePool selectors/taints (ArgoCD-owned). Retire these under Auto Mode.

**Gap:** `kubernetes_storage_class.gp3` has **no toggle** — it's always created.
Add `create_gp3_storage_class` (default true) so private-cluster deployments can
turn it off and let ArgoCD own the default StorageClass.

### VERIFIED — what Auto Mode makes redundant (native capabilities)

From v21.23.0 the Auto Mode node role gets `AmazonEKSComputePolicy`,
`AmazonEKSBlockStoragePolicy`, `AmazonEKSLoadBalancingPolicy`,
`AmazonEKSNetworkingPolicy`. dev/CI's real config corroborates the practical
fallout:

- **Block storage (EBS CSI) is native.** So `module.irsa-ebs-csi` + the
  `aws-ebs-csi-driver` entry in the `eks_addons` map become **redundant** under
  Auto Mode. ⚠️ **Migration hazard (from dev/CI comment):** don't just drop them —
  the existing default StorageClass points at `ebs.csi.aws.com`; it must be
  **re-pointed to the Auto Mode storage class first** (e.g. `gp3-auto-delete`) or
  PVC provisioning breaks. dev/CI kept `aws-ebs-csi-driver` until that re-point
  was done as a separate change.
- **Load balancing is native.** The **ALB controller** in `eks_blueprints_addons`
  becomes redundant → drop `enable_aws_load_balancer_controller` under Auto Mode
  (Tier B).
- **vpc-cni / kube-proxy are native.** dev/CI sets these to `null` in the addons
  map ("DaemonSets are 0/0 on Auto Mode nodes") — drop them from `eks_addons`
  when Auto Mode is on.
- **gp3 StorageClass**: Auto Mode ships its own EBS-backed storage class, so the
  module's `gp3` SC is redundant/conflicting under Auto Mode — retire it (same
  re-point ordering caveat as EBS CSI above).

### The provider wiring problem
Even gated off, the `kubernetes`/`helm`/`kubectl` **provider blocks** in
providers.tf still try to init an exec-auth connection. With `enable_eks` false
they resolve to null host (already handled). Confirm that a private-cluster
consumer with all data-plane toggles off produces a clean plan/apply with **no
API calls**. If any remain, that resource wasn't gated.

## What stays in Terraform (control-plane, always safe)

`module.eks`, all IRSA role modules (external_secrets, karpenter, loki,
cloudwatch_exporter, cluster_autoscaler, irsa-ebs-csi), `module.eks_blueprints_addons`†,
Karpenter AWS prereqs (when enabled), SG rules, access entries, EC2 tags, KMS.

† Caveat: `eks_blueprints_addons` installs helm charts (ALB controller,
cert-manager, external-dns) — those ARE data-plane and would fail on a private
cluster. Under Auto Mode + private endpoint, these likely also move to ArgoCD
(and some, e.g. ALB controller, may be native to Auto Mode). Tracked separately
(Tier B) — out of scope here but flagged.

## Rollout

1. Add Auto Mode vars + `compute_config` wiring (default off). No behavior change.
2. Add missing toggles (`create_gp3_storage_class`, Auto/Karpenter mutual-excl).
3. Stand up ArgoCD apps in comet-gitops for the data-plane objects + custom
   NodePools/NodeClasses.
4. Per env: enable Auto Mode, adopt data-plane objects into ArgoCD, flip all
   data-plane toggles off, gate Karpenter off, apply. Verify plan shows **no
   K8s/helm API operations**.
5. **StorageClass re-point (ordering-critical):** before dropping `irsa-ebs-csi` /
   the ebs-csi addon / gp3 SC, re-point the default StorageClass to the Auto Mode
   class. Skipping this breaks PVC provisioning. Do it as its own step, verified,
   before the EBS teardown.
6. dev/CI → staging → prod.

## Open items — status

- ✅ **RESOLVED** v21 `compute_config` schema = `{enabled, node_pools,
  node_role_arn}`; module auto-creates + wires the Auto Mode node role — don't
  pass `node_role_arn`.
- ✅ **RESOLVED** Auto Mode makes `irsa-ebs-csi` + ebs-csi addon redundant (native
  block storage) — but requires the StorageClass re-point first (see Rollout #5).
- ✅ **RESOLVED** gp3 StorageClass redundant under Auto Mode (native EBS SC);
  retire with the same re-point ordering.
- ⬜ **STILL TO CONFIRM at implementation** all provider blocks stay inert (no API
  calls) when every data-plane toggle is off — validate via a plan with Auto Mode
  on + all data-plane toggles false.
- ⬜ **STILL TO CONFIRM** Auto Mode built-in node_pools naming for this account
  (`["system", "general-purpose"]`) vs dev/CI which uses only `["system"]` +
  custom NodePools. Decide default.
