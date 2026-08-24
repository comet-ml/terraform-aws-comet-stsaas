# Brownfield state migration (v1.x/v2.x → v5.x) — DND-1573 / DND-1257.
#
# ⚠️ THIS FILE MAKES THIS A TEMPORARY "MIGRATION" MODULE VERSION. It is meant to be
#    consumed for exactly ONE apply per brownfield cluster, then the wrapper bumps to a
#    permanent v5.x tag WITHOUT this file. See MIGRATION.md at the repo root.
#
# The v5 "Infra-Only + ArgoCD" refactor DELETED these in-cluster / eks-blueprints-addons
# resources from the module (they are now owned by GitOps / native EKS add-ons). Clusters
# upgrading from a v1/v2 module version still carry them in state, and because the module
# root's kubernetes/helm/aws provider *config blocks* were also removed (child-module
# design), `terraform plan` fails with "Provider configuration not present" for all of
# them until the objects leave state.
#
# HOW THIS WORKS (proven against bayer, DND-1573):
#   - These `removed` blocks drop the objects from state WITHOUT destroying the live
#     resources (`lifecycle { destroy = false }`) — the live workloads are adopted by
#     comet-infra (ArgoCD) / native EKS add-ons as part of the coordinated cutover.
#   - The 6 kubernetes/helm orphans AND the ~9 aws (IAM) orphans below all bind in state
#     to `module.comet.provider["...{aws,kubernetes,helm}"]`. To satisfy that binding the
#     module declares the kubernetes+helm *requirements* (versions.tf) — but declares NO
#     provider config blocks. Instead the WRAPPER passes its fully-configured providers in:
#         module "comet" {
#           providers = { aws = aws, kubernetes = kubernetes, helm = helm }
#         }
#     This populates module.comet.provider[...] with the wrapper's real assume_role/region
#     (an empty `provider "aws" {}` here would instead HIJACK credentials → AccessDenied).
#   - Greenfield v5 clusters never had these resources, so the blocks are a harmless no-op.
#
# NOTE: do NOT `removed` the whole `module.eks_blueprints_addons` — its `aws_eks_addon.this[*]`
# children (coredns/kube-proxy/vpc-cni/metrics-server/ebs-csi) are relocated via the `moved`
# blocks in main.tf. Only the Helm-based sub-modules below were deleted.
#
# NOTE: `module.irsa-ebs-csi.aws_iam_role_policy_attachment.custom[0]` is deliberately NOT
# listed here. The irsa-ebs-csi submodule still EXISTS (source swapped v4.7.0 → v5.39); the
# old attachment re-addresses and v5.39 recreates the equivalent one. That is a benign
# in-place destroy+create of an IAM attachment (the role is kept by name), not an orphan.

# --- eks-blueprints-addons Helm sub-modules (ALB controller, cert-manager, external-dns) ---
# Removing the sub-module call drops all of its resources (aws_iam_policy/role/attachment +
# helm_release). ALB controller → comet-infra (ArgoCD); cert-manager + external-dns → native
# EKS managed add-ons (see main.tf module.eks.addons).
removed {
  from = module.eks_blueprints_addons.module.aws_load_balancer_controller
  lifecycle {
    destroy = false
  }
}

removed {
  from = module.eks_blueprints_addons.module.cert_manager
  lifecycle {
    destroy = false
  }
}

removed {
  from = module.eks_blueprints_addons.module.external_dns
  lifecycle {
    destroy = false
  }
}

# --- In-cluster resources now owned by comet-infra (ArgoCD) ---
# gp3 StorageClass + monitoring namespace/secret moved to the comet-infra Helm chart.
removed {
  from = kubernetes_storage_class.gp3
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_namespace.monitoring
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_secret.monitoring
  lifecycle {
    destroy = false
  }
}
