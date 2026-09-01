# Brownfield state migration (v1.x/v2.x → v6.x) — DND-1573 / DND-1257.
#
# ⚠️ THIS FILE MAKES THIS A TEMPORARY "MIGRATION" MODULE VERSION. It is meant to be
#    consumed for exactly ONE apply per brownfield cluster, then the wrapper bumps to
#    the permanent v6.0.0 tag WITHOUT this file. See MIGRATION.md at the repo root.
#
# Supersedes v5.6.2-migration, which cannot be used by the remaining brownfield envs:
# it predates DND-875, so it lacks rds_auto_minor_version_upgrade (which porsche, si,
# waystar and zoox all pass) plus rds_parameter_group_family, rds_use_proxy_endpoint
# and rds_proxy_ack_no_iam_auth. Those envs would fail on an unsupported argument
# before the removed{} blocks below ever ran.
#
# Cut from v6.0.0 rather than v5.7.0 so Stage 1 lands directly on the v6 surface —
# Stage 2 is then only "drop the providers map", with no second behaviour change.
#
# The v5 "Infra-Only + ArgoCD" refactor DELETED these in-cluster / eks-blueprints-addons
# resources from the module (they are now owned by GitOps / native EKS add-ons). Clusters
# upgrading from a v1/v2 module version still carry them in state, and because the module
# root's kubernetes/helm/aws provider *config blocks* were also removed (child-module
# design), `terraform plan` fails with "Provider configuration not present" for all of
# them until the objects leave state.
#
# HOW THIS WORKS (proven against bayer, DND-1573 / #2205):
#   - These `removed` blocks drop the objects from state WITHOUT destroying the live
#     resources (`lifecycle { destroy = false }`) — the live workloads are adopted by
#     comet-infra (ArgoCD) / native EKS add-ons as part of the coordinated cutover.
#   - The orphans bind in state to `module.comet.provider["...{aws,kubernetes,helm}"]`.
#     To satisfy that binding the module declares the kubernetes+helm *requirements*
#     (versions.tf) — but declares NO provider config blocks. Instead the WRAPPER passes
#     its fully-configured providers in:
#         module "comet" {
#           providers = { aws = aws, kubernetes = kubernetes, helm = helm }
#         }
#     This populates module.comet.provider[...] with the wrapper's real assume_role/region
#     (an empty `provider "aws" {}` here would instead HIJACK credentials → AccessDenied).
#   - Greenfield v6 clusters never had these resources, so the blocks are a harmless no-op.
#
# NOT COVERED HERE — root-level orphans. porsche and si additionally carry
# kubernetes_cluster_role.agentro_extras, kubernetes_cluster_role_binding.agentro_extras,
# kubernetes_cluster_role_binding.agentro_view, kubernetes_role.agentro_portforward and
# kubernetes_role_binding.agentro_portforward at the STATE ROOT, not under module.comet.
# They are not module-addressed, so they must be removed{} in the WRAPPER, not here.
#
# NOTE: do NOT `removed` the whole `module.eks_blueprints_addons` — its `aws_eks_addon.this[*]`
# children (coredns/kube-proxy/vpc-cni/metrics-server/ebs-csi) are relocated via the `moved`
# blocks in main.tf. Only the Helm-based sub-modules below were deleted.

# --- eks-blueprints-addons Helm sub-modules ---
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

# zoox only — enabled there via eks_aws_cloudwatch_metrics, which v6 removed. Harmless
# no-op on every other cluster.
removed {
  from = module.eks_blueprints_addons.module.aws_cloudwatch_metrics
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

# --- v1.20.x-only in-cluster resources (Group C) ---
# Present on circuit, circuit-dev, eonnext, fetch, mercedesamgf1 and netflix; a no-op on
# the v2.1.x envs. Karpenter-via-Helm is superseded by EKS Auto Mode, external-secrets and
# the comet-generic StorageClass by comet-infra GitOps.
removed {
  from = helm_release.karpenter_stsaas
  lifecycle {
    destroy = false
  }
}

removed {
  from = helm_release.external_secrets
  lifecycle {
    destroy = false
  }
}

removed {
  from = helm_release.external_secrets_crds
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_storage_class.comet_generic
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_annotations.admin_ns_node_selector
  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_annotations.app_ns_node_selector
  lifecycle {
    destroy = false
  }
}
