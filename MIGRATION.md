# Brownfield migration: stsaas module v1.x/v2.x → v5.x (DND-1257 / DND-1573)

The v5 "Infra-Only + ArgoCD" refactor made the module **Kubernetes-API-free** and dropped
its own `provider "aws"/"kubernetes"/"helm"` config blocks (the caller now owns providers).
That is correct for **greenfield** clusters. But a cluster upgrading from a v1/v2 module tag
still carries ~15 resources in state that v5 deleted (gp3 StorageClass, monitoring
namespace/secret, and the `eks_blueprints_addons` ALB-controller / cert-manager / external-dns
IAM + Helm releases). Because their provider config is gone, a plain `?ref` bump fails with:

```
Error: Provider configuration not present
To work with module.comet.module.comet_eks[0]...helm_release.this[0] (orphan) its original
provider configuration at module.comet.provider["registry.terraform.io/hashicorp/helm"] is
required, but it has been removed.
```

## The two-stage migration

Do the upgrade in **two `?ref` bumps**, so the module never permanently carries a provider
block (which would reintroduce the child-module anti-pattern and leak the provider onto
greenfield consumers).

### Stage 1 — the migration tag (this branch/tag)

A throwaway module version = the current permanent v5 module **plus**:
- `modules/comet_eks/removed.tf` — `removed { ... lifecycle { destroy = false } }` for the
  6 kubernetes/helm orphans (drops from state, keeps live infra).
- `kubernetes` + `helm` entries in `required_providers` (root + `modules/comet_eks`
  `versions.tf`) — the *requirement* only; **no provider config blocks**.

The wrapper (per customer, e.g. `comet-devops/terraform/stsaas/<customer>/main.tf`) must, for
this one apply, pass its already-configured providers into the module:

```hcl
module "comet" {
  source = "github.com/comet-ml/terraform-aws-comet-stsaas?ref=<MIGRATION_TAG>"

  # STAGE-1 ONLY: hand the module the wrapper's fully-configured providers so the
  # removed{} blocks can bind the state orphans (which reference module.comet.provider[...])
  # with the REAL assume_role/region. Remove this map again in Stage 2.
  providers = {
    aws        = aws
    kubernetes = kubernetes
    helm       = helm
  }

  # ... existing inputs, incl. eks_enable_auto_mode = true ...
}
```

> ⚠️ Do **not** instead add an empty `provider "aws" {}` to the module — it overrides the
> wrapper's `assume_role`, so the apply runs as the base identity and fails with
> `AccessDenied` / "Unexpected Identity Change". The `providers = {}` map is the correct
> mechanism (it passes the wrapper's configured provider through unchanged).

**Apply once.** Expected plan: the ~12 orphans show *"will no longer be managed by Terraform,
but will not be destroyed"*; a small number of benign destroys (`time_sleep.*` timing helpers;
`irsa-ebs-csi.aws_iam_role_policy_attachment.custom` re-creates under the v5.39 submodule).
**No live StorageClass / namespace / IAM role / Helm release is destroyed.** If the plan wants
to DESTROY any of those, STOP — an address is missing from `removed.tf`.

### Stage 2 — the permanent tag

Bump the wrapper to the permanent v5 tag (no `removed.tf`) and **delete the `providers = {}`
map** (the module is provider-less again; the wrapper's default providers inherit for any
`aws` resources, which is all v5 creates). State is already clean, so the plan is additive.

## Prerequisites (do BEFORE Stage 1)

The Stage-1 apply *stops Terraform managing* the ALB controller / cert-manager / external-dns
and the gp3 StorageClass + monitoring namespace. Something else must already own them or be
ready to adopt them, or you get an outage:
- **comet-infra** ArgoCD app for the cluster is Synced/Healthy and owns `gp3-auto`, the
  ALB controller, and the nodepools.
- monitoring namespace/secret already GitOps/ESO-owned.
- cert-manager + external-dns transition to native EKS managed add-ons (module-owned via
  `module.eks.addons`).

See the Notion runbook "Migrate an STSaaS customer to the new module + EKS Auto Mode" and
`comet-devops/terraform/stsaas/stsaasuat/CUTOVER-v5.0.0.md` (the pilot, which used
`terraform state rm` for the same orphans — the migration tag makes it declarative instead).

## Rollback

`removed { destroy = false }` only forgets from state; the live objects are untouched. To put
one back under Terraform management, `terraform import` it (or revert the wrapper `?ref` to the
old tag before applying Stage 1).
