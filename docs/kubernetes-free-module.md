# Plan: a Kubernetes-API-free Terraform module (Tier B)

Goal: make `terraform-aws-comet-stsaas` provision **only AWS/IAM** — zero
Kubernetes-API dependency — so the first `terraform apply` succeeds on a
**private-endpoint cluster that the runner cannot yet reach**. Everything that
lives *inside* the cluster moves to ArgoCD (`comet-ml/comet-gitops`), assembled
as an **infra umbrella chart**.

This completes the split described in
[`auto-mode-migration-plan.md`](./auto-mode-migration-plan.md) and picks up where
[`argocd-helm-migration.md`](./argocd-helm-migration.md) (Tier A) stopped:

- **Tier A (done, v4.0.0):** in-module `helm_release` (external-secrets,
  karpenter) + `kubectl_manifest.cluster_secret_store` → ArgoCD. Left the
  `kubernetes_*` resources in Terraform.
- **Tier B (this doc):** relocate the remaining `kubernetes_*` resources too,
  then delete the `helm`, `kubernetes`, and `gavinbunney/kubectl` providers from
  the module. Supersedes the "the gp3 StorageClass and other `kubernetes_*`
  resources stay in Terraform" note in `argocd-helm-migration.md`.

## Why (the bootstrap ordering)

A new STSaaS customer is created in three steps:

1. **AWS infra (this module).** VPC, subnets, EKS cluster (private API),
   node groups, IAM/IRSA, security groups (incl. the Auto-Mode↔node-SG
   coexistence rules), **EKS native add-ons**, ACM, RDS, ElastiCache, S3.
2. **Interconnect (separate Terraform).** TGW, cross-region attachments, routes.
   *Only after this is the private EKS API reachable from the internal network / VPN.*
3. **Workloads (ArgoCD).** `cometml` app + the **infra umbrella chart**.

The problem: any `kubernetes_*` / `helm_release` / `kubectl_manifest` resource
opens a connection to the API server **at apply time**. On the **first** run of
step 1, step 2 hasn't happened yet, so the API is unreachable and those resources
**fail the apply** (not just plan). Native EKS add-ons are exempt — they are
installed through the **EKS control-plane API** (AWS-side), not the cluster API,
so they stay in step 1 safely.

Conclusion: step 1 must contain **no cluster-API resource at all**.

## What still uses a cluster-API provider in v4.0.0

| Resource | Provider | Gate | Active on stsaasuat? |
|---|---|---|---|
| `kubernetes_storage_class.gp3` | kubernetes | *unconditional* | yes |
| `kubernetes_storage_class.comet_generic` | kubernetes | `create_comet_generic_storage_class` (default true) | yes |
| `kubernetes_namespace.monitoring` | kubernetes | `enable_monitoring_setup` | yes |
| `kubernetes_namespace.redis_insights` | kubernetes | `enable_redis_insights_ns` | yes (agentro) |
| `kubernetes_annotations.app_ns_node_selector` | kubernetes | `enable_namespace_nodegroup_pinning` | yes |
| `kubernetes_annotations.admin_ns_node_selector` | kubernetes | `enable_namespace_nodegroup_pinning` | yes |
| `kubernetes_secret.monitoring` | kubernetes | `enable_monitoring_setup && manage_monitoring_secret` | no — ceded to ESO |
| `helm_release.external_secrets_crds` / `.external_secrets` | helm | `install_external_secrets_via_helm` (default off) | no |
| `helm_release.karpenter_stsaas` | helm | `install_karpenter_via_helm` (default off) | no |
| `kubectl_manifest.cluster_secret_store` | kubectl | `install_external_secrets_via_helm` (default off) | no |

A provider cannot be dropped from `required_providers` while **any** resource
block referencing it exists — even a `count = 0` block. So the `helm`/`kubectl`
blocks (all off everywhere — verified across all 10 wrappers) and the
`kubernetes_*` blocks must be **deleted**, not just disabled.

## Relocation map (Terraform → ArgoCD)

| Leaving Terraform | Lands in | ArgoCD sync-wave |
|---|---|---|
| `gp3` (default) + `comet-generic` StorageClasses | umbrella chart | **`-2`** (before anything needing a PVC) |
| `ClusterSecretStore` (`cluster-secret-store`) | external-secrets app / umbrella | **`-1`** (before any `ExternalSecret`) |
| `monitoring`, `redis-insights` namespaces | umbrella chart (or app `CreateNamespace=true`) | **`-1`** |
| namespace node-selector annotations (`scheduler.alpha.kubernetes.io/node-selector`) | umbrella chart namespace templates (same object as the namespace) | with the namespace |
| external-secrets / karpenter Helm releases | already ArgoCD (Tier A) | — |
| `monitoring` Secret | already ESO (`manage_monitoring_secret=false`) | — |

Everything else the module manages (EKS, IAM/IRSA, SQS, VPC, SGs, native EKS
add-ons, RDS/ElastiCache/S3) is AWS-API and **stays**.

## The infra umbrella chart (comet-gitops)

One ArgoCD Application → one Helm chart holding all cluster-bootstrap infra, so a
new cluster gets it in a single sync. Suggested contents + waves:

```
infra-umbrella/
  templates/
    storageclass-gp3.yaml            # wave -2, is-default-class=true
    storageclass-comet-generic.yaml  # wave -2
    clustersecretstore.yaml          # wave -1  (SecretsManager, region, SA jwt ref)
    namespace-monitoring.yaml        # wave -1  (+ node-selector annotation)
    namespace-redis-insights.yaml    # wave -1
    # nodepools / nodeclasses (Auto Mode CRDs) — wave -1
  values.yaml   # per-cluster: clusterName, region, node-selector targets, zone ids
```

Per-cluster values live in `dply-managed-clients/.../helm/infra/values.yaml`
(same convention as the other STSaaS controllers), referenced from the
comet-gitops `infra/*.yaml` ApplicationSet. Standalone controllers that already
have their own ApplicationSet (alb-operator, cluster-autoscaler, external-secrets,
monitoring, reloader, redis-insights) can stay as-is or fold into the umbrella —
the umbrella's minimum job is the **bootstrap primitives** (storage classes,
namespaces, ClusterSecretStore, nodepools).

## Bootstrap ordering caveats

- **StorageClass first (wave -2).** With Auto Mode, EBS CSI is native, but the
  *default* `gp3` StorageClass object must still exist before any stateful app or
  `cometml` PVC. Keep `storageclass.kubernetes.io/is-default-class: "true"`.
- **ClusterSecretStore before ExternalSecrets (wave -1).** Any `ExternalSecret`
  fails to resolve until the store exists.
- **Namespace + its node-selector annotation are one object.** The
  `scheduler.alpha.kubernetes.io/node-selector` annotation must be present when
  the namespace is created; put both in the same template.
- **Node-selector target under coexistence.** The cluster runs managed node
  groups *and* Auto Mode pools. Decide per namespace whether pinning targets a
  managed-nodegroup label or `karpenter.sh/nodepool` (e.g. `system`), and express
  it in the umbrella values — mirrors the ALB→system-pool pinning already done.
- **`cometml` depends only on** the default StorageClass and the ESO-provided
  secrets, both of which land in earlier waves — so no new ordering coupling.

## Migration hazard: do NOT let Terraform destroy live namespaces

For `stsaasuat` (and any live cluster), the `kubernetes_*` resources above are
**currently in state** (`count > 0`). Deleting the blocks would make the next
apply **destroy** them — and destroying `kubernetes_namespace.monitoring` /
`redis_insights` would **delete everything in those namespaces**. Adopt into
ArgoCD first, exactly like Tier A:

1. Build + sync the umbrella chart (ArgoCD adopts the existing StorageClasses /
   namespaces / annotations — use ArgoCD's resource-tracking label/annotation so
   the adoption is non-destructive).
2. `terraform state rm` each `kubernetes_*` resource so Terraform forgets the live
   object without deleting it:
   ```bash
   terraform state rm 'module.comet.module.comet_eks[0].kubernetes_storage_class.gp3'
   terraform state rm 'module.comet.module.comet_eks[0].kubernetes_storage_class.comet_generic[0]'
   terraform state rm 'module.comet.module.comet_eks[0].kubernetes_namespace.monitoring[0]'
   terraform state rm 'module.comet.module.comet_eks[0].kubernetes_annotations.app_ns_node_selector[0]'
   # admin_ns_node_selector is for_each — rm each key
   terraform state rm 'module.agentro_k8s_rbac.kubernetes_namespace.redis_insights[0]'
   ```
3. Remove the resource blocks + the three providers from module code and apply
   (now a no-op for those — they're neither in state nor in config).

New clusters skip the adoption dance entirely: nothing is in TF state, so the
umbrella chart is the sole creator from day one.

## Module changes (the actual removal)

- Delete: `kubernetes_storage_class.gp3` / `.comet_generic`,
  `kubernetes_namespace.monitoring`, `kubernetes_secret.monitoring`,
  `kubernetes_annotations.app_ns_node_selector` / `.admin_ns_node_selector`,
  `kubernetes_namespace.redis_insights`, `helm_release.external_secrets_crds` /
  `.external_secrets` / `.karpenter_stsaas`, `kubectl_manifest.cluster_secret_store`,
  and the `install_external_secrets_via_helm` / `install_karpenter_via_helm` locals.
- Delete the now-unused variables: `create_comet_generic_storage_class`,
  `enable_monitoring_setup`, `manage_monitoring_secret`, `monitoring_namespace`,
  `enable_namespace_nodegroup_pinning`, `admin_pinned_namespaces`,
  `enable_redis_insights_ns`, `external_secrets_via_helm_release`,
  `karpenter_via_helm_release`, ESO/karpenter chart-version + helm-cred vars.
- Remove `helm`, `kubernetes`, and `kubectl` from `required_providers` in both
  `versions.tf` and `modules/comet_eks/versions.tf`, and delete any `provider`
  blocks / `time_sleep.wait_for_cluster_access` that only existed to gate them.
- Keep: all AWS/IAM, native EKS add-ons (`aws_eks_addon`, `module.eks.addons`),
  IRSA roles, SQS/EventBridge, VPC, SGs.

**Wrapper impact (10 consumers):** each wrapper that passes the now-deleted vars
(e.g. `eks_external_secrets_via_helm_release`, `manage_monitoring_secret`,
`enable_monitoring_setup`, `monitoring_namespace`, …) must drop those lines, or
`terraform` errors on an undefined argument. Coordinate module + wrappers in the
same rollout.

## Versioning & rollout

- Cut the module change as a **new major version** (v5.0.0) — it removes public
  variables and providers (breaking for consumers).
- Rollout per environment, **dev/CI → staging → prod**, following the adoption
  hazard above. `stsaasuat` first (its Helm/ESO paths are already off; only the
  `kubernetes_*` adoption remains).
- Definition of done: `terraform providers` for a wrapper lists **no**
  `helm`/`kubernetes`/`kubectl`; a from-scratch step-1 apply against a brand-new
  private cluster succeeds with **no** API-server connection attempt.

## End state

- **Module:** AWS/IAM + native EKS add-ons only. First-run safe on a private
  cluster; faster `init`; no third-party `gavinbunney/kubectl` dependency.
- **ArgoCD:** single source of truth for all in-cluster state — `cometml` +
  infra umbrella chart (+ the standalone controller ApplicationSets).
