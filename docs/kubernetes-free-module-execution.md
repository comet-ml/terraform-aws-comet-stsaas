# Execution plan: strip the kubernetes/helm/kubectl providers from the module (v5.0.0)

Concrete, resource-by-resource plan to make `terraform-aws-comet-stsaas`
AWS/IAM-only, per [`kubernetes-free-module.md`](./kubernetes-free-module.md).
Grounded in the current `main` (v4.0.0 base): the module has **17** cluster-API
resources across three providers, plus `time_sleep.wait_for_cluster_access`
(exists only to gate them). Everything below is **versioned** — nothing affects a
cluster until it bumps `?ref` to v5.0.0, so the module change is safe to build
ahead of the per-cluster rollout.

## Full inventory → destination

### `helm` provider (all gated OFF in every wrapper — verified)
| Resource | Destination |
|---|---|
| `helm_release.external_secrets_crds` | GitOps — `comet-external-secrets` chart (already deployed) |
| `helm_release.external_secrets` | same |
| `helm_release.karpenter_stsaas` | dropped — superseded by Auto Mode |

### `kubectl` provider (gated OFF)
| `kubectl_manifest.cluster_secret_store` | GitOps — `comet-external-secrets` chart ships the `ClusterSecretStore` |

### `kubernetes` provider
| Resource | Destination |
|---|---|
| `kubernetes_storage_class.gp3` / `.comet_generic` | **comet-infra** (`storageClasses`) — stsaasuat done; other clusters on onboarding |
| `kubernetes_namespace.monitoring` | **comet-infra** (`namespaces`) |
| `kubernetes_secret.monitoring` | already ESO (`manage_monitoring_secret=false`); just delete the resource |
| `kubernetes_annotations.app_ns_node_selector` (app→`comet`) | **NS-pinning fold — decision below** |
| `kubernetes_annotations.admin_ns_node_selector` (cert-manager/external-dns/external-secrets→`admin`) | **NS-pinning fold — decision below** |
| `kubernetes_namespace.redis_insights` | **`agentro_k8s_rbac` local module** (comet-devops) — already moved there for stsaasuat via wrapper `moved` blocks |
| `kubernetes_cluster_role_binding.agentro_view` | `agentro_k8s_rbac` local module (already moved for stsaasuat) |
| `kubernetes_cluster_role.agentro_extras` + `kubernetes_cluster_role_binding.agentro_extras` | `agentro_k8s_rbac` (or drop — superseded by the agentro ClusterRole for stsaasuat) |
| `kubernetes_role.agentro_portforward` + `kubernetes_role_binding.agentro_portforward` | `agentro_k8s_rbac` (or drop — superseded) |

### `time_sleep.wait_for_cluster_access`
Delete — it only sequences the k8s-API resources above. (Verify no AWS resource
genuinely needs it; a couple of `aws_eks_access_entry`/agentro depends_on lines
reference it and must be cleaned or repointed.)

## The two open decisions

**1. NS-pinning fold (blocks dropping the annotations).** Today the module pins
the app namespace → `comet` and cert-manager/external-dns/external-secrets → `admin`
via `scheduler.alpha.kubernetes.io/node-selector`. Options:
- **(a) Preserve, relocate to GitOps** — app-ns annotation into the cometml chart's
  namespace; external-secrets into the `comet-external-secrets` chart; cert-manager
  & external-dns are *native EKS add-ons* → set pod `nodeSelector` via the add-on's
  `configuration_values` (AWS API, stays in the module, no k8s provider). Preserves
  current behavior.
- **(b) Drop it** — under Auto Mode, schedulable add-ons already pin to the `system`
  pool (`auto_mode_addon_values`); let Auto Mode / pod-level selectors handle the
  rest. Simplest, but a scheduling behavior change (pods leave the `comet`/`admin`
  managed nodegroups). **Needs ops sign-off.**
- Recommendation: (a) for parity, per the earlier "fold into owning charts" choice.

**2. agentro RBAC home.** The 5 agentro RBAC resources + `redis_insights` ns must
leave the module. `comet-devops/terraform/local-modules/agentro-role/rbac` already
owns the moved-out pieces for stsaasuat. Plan: move **all** agentro RBAC to that
local module (for every cluster), so the module carries none. Confirm the local
module is the intended permanent home (vs GitOps).

## Removal sequencing (chunks by risk)

- **Chunk A — helm + kubectl (safe now).** Delete `external_secrets_*`,
  `karpenter_stsaas` helm_releases + `cluster_secret_store` + the
  `install_external_secrets_via_helm`/`install_karpenter_via_helm` locals; remove
  `helm` and `gavinbunney/kubectl` from `required_providers` (root + comet_eks).
  No cluster uses these paths. Drops the third-party provider.
- **Chunk B — agentro RBAC.** Move the 5 agentro RBAC resources + `redis_insights`
  ns to `agentro_k8s_rbac`; add `moved`/import handling per cluster.
- **Chunk C — storage/namespaces.** Delete `kubernetes_storage_class.*`,
  `kubernetes_namespace.monitoring`, `kubernetes_secret.monitoring` + the SC tag
  locals (`gp3_tag_params`, `comet_generic_tag_params`, `common_tags_list`, …).
  Each cluster's set must already be on comet-infra.
- **Chunk D — NS pinning.** Apply decision (1); delete both `kubernetes_annotations`.
- **Chunk E — drop `kubernetes` provider + `time_sleep`** (only after A–D) and the
  now-unused variables (see below).
- **Chunk F — consumers + release.** Strip removed-var pass-throughs from the 10
  wrappers (`comet-devops/terraform/stsaas/*`), tag **v5.0.0**, roll per cluster.

## Variables to remove (comet_eks + root + wrapper pass-throughs)
`external_secrets_via_helm_release`, `external_secrets_chart_version`,
`karpenter_via_helm_release`, `karpenter_chart_version` (+ karpenter helm creds),
`enable_monitoring_setup`, `monitoring_namespace`, `manage_monitoring_secret`,
`storage_class_reclaim_policy`, `create_comet_generic_storage_class`,
`enable_namespace_nodegroup_pinning`, `app_namespace`, `admin_pinned_namespaces`,
`enable_redis_insights_ns` (+ any agentro enable var). Each has a root `eks_*`
alias and a pass-through in the 10 wrappers — remove all three layers together.

## Per-cluster rollout (gated)

The module is versioned, so a cluster only goes k8s-free when it bumps to v5.0.0.
**Prerequisites per cluster before cutover:** (1) onboarded to comet-infra
(StorageClasses/namespaces adopted); (2) agentro RBAC on `agentro_k8s_rbac`;
(3) NS pinning relocated per decision (1); (4) ESO already GitOps (true today).

- **stsaasuat first** — already on comet-infra + agentro moved; only pinning + the
  `state rm` remain.
- **Other 9 clusters** — must onboard comet-infra first (they still rely on the
  module for StorageClasses/namespaces). Order dev/CI → staging → prod.

**Cutover per cluster (coordinated, non-destructive):**
1. `terraform state rm` the adopted `kubernetes_*` (StorageClasses, monitoring ns,
   redis_insights, annotations) so v5.0.0 doesn't try to destroy the live objects.
2. Bump the wrapper `?ref` → v5.0.0 + drop removed-var pass-throughs.
3. `terraform plan` — expect **no** destroys of live k8s objects (they're gone from
   both config and state; owned by ArgoCD / agentro module).
4. `terraform apply`. Then `terraform providers` shows no helm/kubernetes/kubectl.

## Verification
- Module: `terraform validate` after each chunk (catches dangling refs to removed
  resources/locals/providers). `terraform providers` on a v5.0.0 wrapper lists only
  aws/random/tls/cloudinit/time-as-needed — **no** helm/kubernetes/kubectl.
- Cluster: from-scratch step-1 apply on a brand-new private cluster completes with
  **zero** API-server connection attempts; comet-infra + agentro + ESO healthy in
  ArgoCD; StorageClasses/namespaces untouched (adoption no-op).
