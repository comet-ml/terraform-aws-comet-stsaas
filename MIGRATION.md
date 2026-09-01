# Brownfield migration to v6.0.0 (DND-1573 / DND-1257)

For clusters still on a v1.20.x or v2.1.x module version. Greenfield clusters and
anything already on v5.x/v6.x do not need this — bump straight to `v6.0.0`.

## Why a temporary tag

The v5 "Infra-Only + ArgoCD" refactor deleted the module's in-cluster and
eks-blueprints-addons resources; GitOps and native EKS add-ons own them now.
A cluster upgrading from v1/v2 still carries those objects in state, and because
the module also dropped its kubernetes/helm provider *config blocks*, `plan` fails
with `Provider configuration not present` for every one of them.

`v6.0.1-migration` is `v6.0.0` plus:

- `modules/comet_eks/removed.tf` — 13 `removed{}` blocks, all `destroy = false`
- `kubernetes` + `helm` back in both `versions.tf` files (requirements only, no
  provider config blocks)

It is consumed for exactly ONE apply per cluster, then the wrapper moves to the
permanent `v6.0.0`.

Do not use `v5.6.2-migration` for this. It predates DND-875 and lacks
`rds_auto_minor_version_upgrade`, `rds_parameter_group_family`,
`rds_use_proxy_endpoint` and `rds_proxy_ack_no_iam_auth` — envs that pass any of
them fail on an unsupported argument before the removed blocks run.

## Stage 1 — drop the orphans

Wrapper:

```hcl
module "comet" {
  source = "github.com/comet-ml/terraform-aws-comet-stsaas?ref=v6.0.1-migration"

  providers = {
    aws        = aws
    kubernetes = kubernetes
    helm       = helm
  }
  ...
}
```

The `providers` map is required: the orphans bind to
`module.comet.provider["...{aws,kubernetes,helm}"]`, and this populates that with
the wrapper's real assume_role/region. An empty `provider "aws" {}` inside the
module would hijack credentials instead (AccessDenied).

Also in the same PR:

- **Root-level orphans** — porsche and si carry `kubernetes_cluster_role.agentro_extras`,
  `kubernetes_cluster_role_binding.{agentro_extras,agentro_view}` and
  `kubernetes_role{,_binding}.agentro_portforward` at the STATE ROOT. They are not
  module-addressed, so add `removed{}` blocks for them in the WRAPPER.
- **`mysql_vpn` import** — v6/DND-1522 creates the VPN→MySQL rule unconditionally,
  but every env already has it out of state from the DND-752 era. Without an
  `import{}` the apply fails `InvalidPermission.Duplicate`. See the rule-id table in
  the rollout plan.
- **Drop deleted vars** — `enable_argocd_management_eks_access`,
  `enable_vpn_eks_api_access`, `enable_ci_runners_eks_api_access`,
  `enable_vpn_redis_access`, `enable_monitoring_setup`, `monitoring_namespace`,
  `eks_create_comet_generic_storage_class`, `enable_redis_insights_ns`.

Apply. The objects leave state; live infrastructure is untouched.

## Stage 1.5 — GitOps adoption

comet-infra (ArgoCD) / native EKS add-ons must own the ALB controller, cert-manager,
external-dns, the gp3 StorageClass and the monitoring namespace/secret. Coordinate
this with Stage 1 — it is the real risk in the sequence, not the terraform.

## Stage 2 — land on the permanent tag

```hcl
source = "github.com/comet-ml/terraform-aws-comet-stsaas?ref=v6.0.0"
```

Drop the `providers` map and `helm` from the wrapper's `required_providers`. **Keep
`kubernetes`** if the wrapper's own modules use it — `agentro_k8s_rbac` and
`automation_smoke_rbac` own kubernetes resources outside `module.comet`, and dropping
the provider strands them.

Delete the wrapper's one-shot `imports.tf` and any Stage 1 `removed{}` blocks once
applied.

Expected plan: no infrastructure change. Stage 1 already landed on the v6 surface.

## Order

Canary **waystar** — its orphan set is exactly the six blocks proven against bayer,
with no root-level extras and no `aws_cloudwatch_metrics`. Then zoox, si, porsche.
Group C (v1.20.x: circuit, circuit-dev, eonnext, fetch, mercedesamgf1, netflix)
after Group B is complete; those additionally hit the Karpenter-Helm → EKS Auto Mode
migration, which is its own piece of work.
