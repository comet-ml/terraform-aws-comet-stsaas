locals {
  volume_type                  = "gp3"
  volume_encrypted             = false
  volume_delete_on_termination = true

  # Gates for in-module helm_release installs. Dedup'd so the 4 external-secrets
  # resources and the karpenter helm_release all share a single source of truth.
  install_external_secrets_via_helm = var.enable_external_secrets && var.external_secrets_via_helm_release
  install_karpenter_via_helm        = var.enable_karpenter && var.karpenter_via_helm_release

  # Check if additional S3 bucket ARNs are provided
  has_additional_s3_buckets = var.additional_s3_bucket_arns != null && length(var.additional_s3_bucket_arns) > 0

  # Build the IAM policies map for node groups
  # Combines the comet S3 policy (if enabled) with additional S3 policy (if buckets provided)
  node_group_iam_policies = merge(
    var.s3_enabled ? { comet_s3_access = var.comet_ec2_s3_iam_policy } : {},
    local.has_additional_s3_buckets ? { additional_s3_access = aws_iam_policy.additional_s3_bucket_policy[0].arn } : {}
  )

  # Auto-generate security group rules for private access CIDRs
  private_access_sg_rules = var.eks_cluster_endpoint_private_access && length(var.eks_private_access_cidrs) > 0 ? {
    for idx, cidr in var.eks_private_access_cidrs : "private_access_${idx}" => {
      description = "Allow private access from ${cidr}"
      protocol    = "-1" # All protocols
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      cidr_blocks = [cidr]
    }
  } : {}

  # Merge auto-generated rules with any additional custom rules
  cluster_security_group_rules = merge(
    local.private_access_sg_rules,
    var.eks_cluster_security_group_additional_rules
  )

  # Tags the Cluster Autoscaler uses for auto-discovery of ASGs. Merged into
  # local.eks_managed_node_group_defaults.tags so every managed nodegroup
  # inherits them automatically. When CA is disabled this is empty and the
  # tags are not applied.
  cluster_autoscaler_asg_tags = var.eks_enable_cluster_autoscaler ? {
    "k8s.io/cluster-autoscaler/enabled"                 = "true"
    "k8s.io/cluster-autoscaler/${var.eks_cluster_name}" = "owned"
  } : {}

  # Defaults applied to every entry in eks_managed_node_groups. v21 of the
  # upstream module dropped the top-level eks_managed_node_group_defaults
  # variable, so we merge these into each entry below.
  eks_managed_node_group_defaults = merge(
    {
      ami_type                   = var.eks_mng_ami_type
      enable_bootstrap_user_data = true
      enable_monitoring          = true
      force_update_version       = var.eks_mng_force_update_version
      # When false, the node group keeps its current AMI release (release_version
      # is left AWS-managed) instead of bumping to the latest on every apply —
      # lets AMI rolls be scheduled separately from other terraform changes.
      use_latest_ami_release_version = var.eks_mng_use_latest_ami_release_version
      # When pinned, don't auto-promote new launch-template versions to default,
      # so the node groups (which then track "$Default") don't roll on benign LT
      # changes (e.g. tag-only version bumps). Deliberate rolls bump the default.
      update_launch_template_default_version = !var.eks_mng_pin_launch_template_version
      # Set platform based on AMI type - AL2023 uses nodeadm, AL2 uses bootstrap.sh
      platform = startswith(var.eks_mng_ami_type, "AL2023") ? "al2023" : "linux"
      # Preserve v20 IMDS hop limit of 2. v21 default is 1 — flipping it would
      # break any sidecar/proxy pattern that reaches IMDS through an extra hop.
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
        instance_metadata_tags      = "disabled"
      }
      # common_tags on the nodegroup propagate to instances; CA discovery
      # tags must be on the ASG so the autoscaler can match them.
      tags = merge(var.common_tags, local.cluster_autoscaler_asg_tags)
    },
    var.eks_mng_ami_id != null ? {
      ami_id = var.eks_mng_ami_id
    } : {}
  )

  # Build access entries for admin roles
  admin_access_entries = {
    for arn in var.eks_admin_role_arns : arn => {
      principal_arn = arn
      type          = "STANDARD"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }
}

# IAM policy for additional S3 bucket access (only created if additional_s3_bucket_arns is provided)
resource "aws_iam_policy" "additional_s3_bucket_policy" {
  count = local.has_additional_s3_buckets ? 1 : 0

  name        = "additional-s3-access-policy-${var.eks_cluster_name}"
  description = "Policy for access to additional S3 buckets from EKS cluster ${var.eks_cluster_name}"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:ListBucket*",
          "s3:PutBucket*",
          "s3:GetBucket*",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts",
          "s3:ListBucketMultipartUploads"
        ],
        Resource = flatten([
          for arn in var.additional_s3_bucket_arns : [
            arn,
            "${arn}/*"
          ]
        ])
      }
    ]
  })

  tags = merge(
    var.common_tags,
    {
      Name = "additional-s3-access-policy-${var.eks_cluster_name}"
    }
  )
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.23.0"

  name                    = var.eks_cluster_name
  kubernetes_version      = var.eks_cluster_version
  endpoint_public_access  = var.eks_cluster_endpoint_public_access
  endpoint_private_access = var.eks_cluster_endpoint_private_access
  deletion_protection     = var.eks_cluster_deletion_protection

  security_group_additional_rules = local.cluster_security_group_rules

  authentication_mode                      = var.eks_authentication_mode
  enable_cluster_creator_admin_permissions = var.eks_enable_cluster_creator_admin_permissions

  access_entries = local.admin_access_entries

  # KMS key access control for cluster encryption
  kms_key_administrators = var.kms_key_administrators
  kms_key_users          = var.kms_key_users

  vpc_id     = var.vpc_id
  subnet_ids = var.eks_private_subnets

  # Bake the Karpenter discovery tag directly into the node SG so it is never
  # dropped when Terraform modifies the security group during subsequent applies.
  node_security_group_tags = var.enable_karpenter ? {
    "karpenter.sh/discovery" = var.eks_cluster_name
  } : {}

  eks_managed_node_groups = merge(
    # Karpenter Node Group — created when Karpenter is enabled.
    # Dedicated to the Karpenter controller only; tainted so no other pods schedule here.
    # All other node groups are suppressed when Karpenter is enabled (Karpenter provisions them).
    var.enable_karpenter ? {
      karpenter = merge(local.eks_managed_node_group_defaults, {
        name           = "karpenter"
        instance_types = var.eks_karpenter_node_instance_types
        min_size       = var.eks_karpenter_node_min_size
        max_size       = var.eks_karpenter_node_max_size
        desired_size   = var.eks_karpenter_node_desired_size
        block_device_mappings = {
          xvda = {
            device_name = "/dev/xvda"
            ebs = {
              volume_size           = var.eks_karpenter_node_disk_size
              volume_type           = local.volume_type
              encrypted             = local.volume_encrypted
              delete_on_termination = local.volume_delete_on_termination
            }
          }
        }
        labels = {
          nodegroup_name = "karpenter"
        }
        taints = {
          dedicated = {
            key    = "dedicated"
            value  = "karpenter"
            effect = "NO_SCHEDULE"
          }
        }
        tags_propagate_at_launch     = true
        launch_template_version      = var.eks_mng_pin_launch_template_version ? "$Default" : "$Latest"
        iam_role_additional_policies = local.node_group_iam_policies
      })
    } : {},
    # Admin Node Group — always created when enabled. Required for system workloads (cert-manager, LBC,
    # external-secrets, etc.) before Karpenter bootstraps, and for infra isolation in production.
    # When Karpenter is enabled, uses smaller instance types since these nodes only run system pods.
    var.enable_admin_node_group ? {
      admin = merge(local.eks_managed_node_group_defaults, {
        name           = var.eks_admin_name
        instance_types = var.enable_karpenter ? var.eks_admin_karpenter_instance_types : var.eks_admin_instance_types
        capacity_type  = var.eks_admin_capacity_type
        min_size       = var.eks_admin_min_size
        max_size       = var.eks_admin_max_size
        desired_size   = var.eks_admin_desired_size
        block_device_mappings = {
          xvda = {
            device_name = "/dev/xvda"
            ebs = {
              volume_size           = var.eks_mng_disk_size
              volume_type           = local.volume_type
              encrypted             = local.volume_encrypted
              delete_on_termination = local.volume_delete_on_termination
            }
          }
        }
        labels = {
          nodegroup_name = "admin"
        }
        tags_propagate_at_launch     = true
        launch_template_version      = var.eks_mng_pin_launch_template_version ? "$Default" : "$Latest"
        iam_role_additional_policies = local.node_group_iam_policies
        },
        var.eks_admin_ami_type != null ? { ami_type = var.eks_admin_ami_type } : {},
      var.eks_admin_subnet_ids != null ? { subnet_ids = var.eks_admin_subnet_ids } : {})
    } : {},
    # Comet Node Group — disabled when Karpenter is enabled (Karpenter provisions comet nodes)
    (var.enable_comet_node_group && !var.enable_karpenter) ? {
      comet = merge(local.eks_managed_node_group_defaults, {
        name            = var.eks_comet_name
        use_name_prefix = var.eks_comet_use_name_prefix
        iam_role_name   = var.eks_comet_iam_role_name
        instance_types  = var.eks_comet_instance_types
        capacity_type   = var.eks_comet_capacity_type
        min_size        = var.eks_comet_min_size
        max_size        = var.eks_comet_max_size
        desired_size    = var.eks_comet_desired_size
        block_device_mappings = {
          xvda = {
            device_name = "/dev/xvda"
            ebs = {
              volume_size           = var.eks_mng_disk_size
              volume_type           = local.volume_type
              encrypted             = local.volume_encrypted
              delete_on_termination = local.volume_delete_on_termination
            }
          }
        }
        labels = {
          nodegroup_name = "comet"
        }
        tags_propagate_at_launch     = true
        launch_template_version      = var.eks_mng_pin_launch_template_version ? "$Default" : "$Latest"
        iam_role_additional_policies = local.node_group_iam_policies
        },
        var.eks_comet_ami_type != null ? { ami_type = var.eks_comet_ami_type } : {},
      var.eks_comet_subnet_ids != null ? { subnet_ids = var.eks_comet_subnet_ids } : {})
    } : {},
    # Druid Node Group — disabled when Karpenter is enabled
    (var.enable_druid_node_group && var.enable_mpm_infra && !var.enable_karpenter) ? {
      druid = merge(local.eks_managed_node_group_defaults, {
        name           = var.eks_druid_name
        instance_types = var.eks_druid_instance_types
        min_size       = var.eks_druid_min_size
        max_size       = var.eks_druid_max_size
        desired_size   = var.eks_druid_desired_size
        block_device_mappings = {
          xvda = {
            device_name = "/dev/xvda"
            ebs = {
              volume_size           = var.eks_mng_disk_size
              volume_type           = local.volume_type
              encrypted             = local.volume_encrypted
              delete_on_termination = local.volume_delete_on_termination
            }
          }
        }
        labels = {
          nodegroup_name = "druid"
        }
        tags_propagate_at_launch     = true
        launch_template_version      = var.eks_mng_pin_launch_template_version ? "$Default" : "$Latest"
        iam_role_additional_policies = local.node_group_iam_policies
        },
      var.eks_druid_subnet_ids != null ? { subnet_ids = var.eks_druid_subnet_ids } : {})
    } : {},
    # Airflow Node Group — disabled when Karpenter is enabled
    (var.enable_airflow_node_group && var.enable_mpm_infra && !var.enable_karpenter) ? {
      airflow = merge(local.eks_managed_node_group_defaults, {
        name           = var.eks_airflow_name
        instance_types = var.eks_airflow_instance_types
        min_size       = var.eks_airflow_min_size
        max_size       = var.eks_airflow_max_size
        desired_size   = var.eks_airflow_desired_size
        block_device_mappings = {
          xvda = {
            device_name = "/dev/xvda"
            ebs = {
              volume_size           = var.eks_mng_disk_size
              volume_type           = local.volume_type
              encrypted             = local.volume_encrypted
              delete_on_termination = local.volume_delete_on_termination
            }
          }
        }
        labels = {
          nodegroup_name = "airflow"
        }
        tags_propagate_at_launch     = true
        launch_template_version      = var.eks_mng_pin_launch_template_version ? "$Default" : "$Latest"
        iam_role_additional_policies = local.node_group_iam_policies
        },
      var.eks_airflow_subnet_ids != null ? { subnet_ids = var.eks_airflow_subnet_ids } : {})
    } : {},
    # ClickHouse Node Group — requires explicit opt-in AND Karpenter must be disabled
    (var.enable_clickhouse_node_group && !var.enable_karpenter) ? {
      clickhouse = merge(local.eks_managed_node_group_defaults, {
        name            = var.eks_clickhouse_name
        use_name_prefix = var.eks_clickhouse_use_name_prefix
        iam_role_name   = var.eks_clickhouse_iam_role_name
        instance_types  = var.eks_clickhouse_instance_types
        capacity_type   = var.eks_clickhouse_capacity_type
        min_size        = var.eks_clickhouse_min_size
        max_size        = var.eks_clickhouse_max_size
        desired_size    = var.eks_clickhouse_desired_size
        block_device_mappings = {
          xvda = {
            device_name = "/dev/xvda"
            ebs = {
              volume_size           = var.eks_clickhouse_volume_size
              volume_type           = var.eks_clickhouse_volume_type
              encrypted             = var.eks_clickhouse_volume_encrypted
              delete_on_termination = var.eks_clickhouse_delete_on_termination
            }
          }
        }
        labels = {
          nodegroup_name = "clickhouse"
        }
        taints                       = var.eks_clickhouse_taints
        tags_propagate_at_launch     = true
        launch_template_version      = var.eks_mng_pin_launch_template_version ? "$Default" : "$Latest"
        iam_role_additional_policies = local.node_group_iam_policies
        },
        var.eks_clickhouse_ami_type != null ? { ami_type = var.eks_clickhouse_ami_type } : {},
      var.eks_clickhouse_subnet_ids != null ? { subnet_ids = var.eks_clickhouse_subnet_ids } : {})
    } : {},
    # Additional custom node groups
    {
      for k, v in var.additional_node_groups : k => merge(
        local.eks_managed_node_group_defaults,
        v,
        {
          tags             = merge(local.eks_managed_node_group_defaults.tags, lookup(v, "tags", {}))
          metadata_options = merge(local.eks_managed_node_group_defaults.metadata_options, lookup(v, "metadata_options", {}))
        }
      )
    }
  )
}


module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name             = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

resource "time_sleep" "wait_for_cluster_access" {
  count = var.eks_enable_cluster_creator_admin_permissions ? 1 : 0

  depends_on      = [module.eks]
  create_duration = "60s"
}

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.24"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  oidc_provider_arn = module.eks.oidc_provider_arn
  cluster_version   = module.eks.cluster_version

  eks_addons = merge(
    {
      coredns            = {}
      vpc-cni            = {}
      kube-proxy         = {}
      aws-ebs-csi-driver = { service_account_role_arn = module.irsa-ebs-csi.iam_role_arn }
    },
    # metrics-server is required for HPA and `kubectl top`. It runs in
    # kube-system and listens on port 10251; node SG rule above lets the
    # kube-apiserver reach it.
    var.eks_enable_metrics_server ? {
      metrics-server = merge(
        {},
        var.eks_metrics_server_addon_version != null ? {
          addon_version = var.eks_metrics_server_addon_version
        } : {}
      )
    } : {}
  )

  enable_aws_load_balancer_controller = var.eks_aws_load_balancer_controller
  enable_cert_manager                 = var.eks_cert_manager
  enable_aws_cloudwatch_metrics       = var.eks_aws_cloudwatch_metrics
  enable_external_dns                 = var.eks_external_dns
  external_dns_route53_zone_arns      = var.eks_external_dns_r53_zones

  depends_on = [time_sleep.wait_for_cluster_access]
}

# Wait for AWS Load Balancer Controller webhook to be ready before creating Services
# This prevents race conditions where cert-manager or other addons try to create Services
# before the ALB mutating webhook has registered its endpoints
resource "time_sleep" "wait_for_alb_webhook" {
  count = var.eks_aws_load_balancer_controller ? 1 : 0

  depends_on      = [module.eks_blueprints_addons]
  create_duration = "60s"
}

locals {
  # Build tag specifications for EBS CSI driver
  # Each tag needs to be a separate tagSpecification_N parameter with format "key=value"
  # Note: common_tags passed from root module already includes Terraform=true and Environment tags
  common_tags_list = [for k, v in var.common_tags : "${k}=${v}"]

  # Base tags for gp3 storage class (only StorageClass identifier, other tags come from common_tags)
  gp3_base_tags  = ["StorageClass=gp3"]
  gp3_all_tags   = concat(local.gp3_base_tags, local.common_tags_list)
  gp3_tag_params = { for idx, tag in local.gp3_all_tags : "tagSpecification_${idx + 1}" => tag }

  # Base tags for comet-generic storage class (only StorageClass identifier, other tags come from common_tags)
  comet_generic_base_tags  = ["StorageClass=comet-generic"]
  comet_generic_all_tags   = concat(local.comet_generic_base_tags, local.common_tags_list)
  comet_generic_tag_params = { for idx, tag in local.comet_generic_all_tags : "tagSpecification_${idx + 1}" => tag }
}

resource "kubernetes_storage_class" "gp3" {
  depends_on = [time_sleep.wait_for_cluster_access]

  metadata {
    name   = "gp3"
    labels = var.common_tags
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner = "ebs.csi.aws.com"

  parameters = merge(
    {
      type = "gp3"
      # Optionally, set iops and throughput:
      # iops       = "3000"
      # throughput = "125"
    },
    local.gp3_tag_params
  )

  reclaim_policy         = var.storage_class_reclaim_policy
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
}

resource "kubernetes_storage_class" "comet_generic" {
  # Some deployments have comet-generic created by the comet-ml Helm chart
  # (Helm/ArgoCD-owned). Set create_comet_generic_storage_class=false there so
  # this module does not fight the chart over ownership of the same SC.
  count = var.create_comet_generic_storage_class ? 1 : 0

  depends_on = [time_sleep.wait_for_cluster_access]

  metadata {
    name   = "comet-generic"
    labels = var.common_tags
  }

  storage_provisioner = "ebs.csi.aws.com"

  parameters = merge(
    { type = "gp3" },
    local.comet_generic_tag_params
  )

  reclaim_policy         = var.storage_class_reclaim_policy
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
}

#########################################
#### Cluster Autoscaler IRSA Role ####
#########################################
# Allows the cluster-autoscaler service account (deployed out-of-band by
# ArgoCD) to describe and modify EKS-managed ASGs. ASG auto-discovery is
# driven by the `k8s.io/cluster-autoscaler/*` tags applied via
# `eks_managed_node_group_defaults.tags` above.
module "cluster_autoscaler_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  count = var.eks_enable_cluster_autoscaler ? 1 : 0

  role_name                        = "${var.environment}-cluster-autoscaler"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_names = [var.eks_cluster_name]

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-cluster-autoscaler"
      Description = "IRSA role for Cluster Autoscaler to manage EKS-managed ASGs"
    }
  )
}

#########################################
#### External Secrets IRSA Role ####
#########################################
# This role allows the external-secrets service account to access AWS Secrets Manager
module "external_secrets_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  count = var.enable_external_secrets ? 1 : 0

  # Role name defaults to {environment}-external-secrets; override to adopt an
  # existing differently-named role (e.g. legacy hand-rolled "zoox-external-secrets")
  # without recreating it (which would break the SA's IRSA annotation).
  role_name = coalesce(var.external_secrets_iam_role_name_override, "${var.environment}-external-secrets")

  # Attach the external secrets policy that allows Secrets Manager access
  attach_external_secrets_policy = true

  # Limit access to secrets matching the environment's path pattern
  # Uses coalesce() to match how secrets are created in the comet_secretsmanager module:
  # - If secretsmanager_environment is set, use it (e.g., "mercedesamgf1")
  # - Otherwise, fall back to environment (e.g., "mercedesamgf1-euw2")
  external_secrets_secrets_manager_arns = [
    "arn:aws:secretsmanager:*:*:secret:cometml/${coalesce(var.secretsmanager_environment, var.environment)}/*"
  ]

  # Configure OIDC provider for IRSA
  # This allows the Kubernetes service account to assume this IAM role
  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-external-secrets"
      Description = "IRSA role for External Secrets Operator to access AWS Secrets Manager"
    }
  )
}

# Deploy External Secrets - Two-phase installation
# This replicates the comet-ml/comet-devops/charts/external-secrets umbrella chart behavior
# with the CRD installation workaround from the README:
#
# Phase 1: Install CRDs first (workaround for CRD installation bug in umbrella chart)
# Phase 2: Install the full external-secrets operator
# Phase 3: Create ClusterSecretStore after webhook is ready

# Phase 1: Install external-secrets CRDs first
# This follows the workaround from comet-devops README:
# "helm install external-secrets external-secrets/external-secrets --set installCRDs=true"
resource "helm_release" "external_secrets_crds" {
  count = local.install_external_secrets_via_helm ? 1 : 0

  name             = "external-secrets-crds"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version
  namespace        = "external-secrets"
  create_namespace = true

  # Only install CRDs, disable everything else
  set = [
    {
      name  = "installCRDs"
      value = "true"
    },
    {
      name  = "webhook.create"
      value = "false"
    },
    {
      name  = "certController.create"
      value = "false"
    },
    {
      name  = "createOperator"
      value = "false"
    },
  ]

  wait    = true
  timeout = 300

  depends_on = [
    module.eks,
    module.eks_blueprints_addons,
    time_sleep.wait_for_alb_webhook
  ]
}

# Phase 2: Install the full external-secrets operator
resource "helm_release" "external_secrets" {
  count = local.install_external_secrets_via_helm ? 1 : 0

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version
  namespace        = "external-secrets"
  create_namespace = false # Already created by CRDs release

  # Wait for the release to be fully deployed before marking as complete
  wait          = true
  wait_for_jobs = true
  timeout       = 600 # 10 minutes to allow webhook to become ready

  # CRDs already installed, skip to avoid conflicts
  set = [
    {
      name  = "installCRDs"
      value = "false"
    },
    # Match values from comet-devops values.yaml
    {
      name  = "replicaCount"
      value = "1"
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.automount"
      value = "true"
    },
    # IRSA annotation from values-dply.yaml pattern
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = module.external_secrets_irsa_role[0].iam_role_arn
    },
    # Webhook configuration from values.yaml
    {
      name  = "webhook.create"
      value = "true"
    },
    {
      name  = "webhook.replicaCount"
      value = "1"
    },
    # CertController configuration from values.yaml
    {
      name  = "certController.create"
      value = "true"
    },
    {
      name  = "certController.replicaCount"
      value = "1"
    },
  ]

  depends_on = [
    module.eks,
    module.eks_blueprints_addons,
    module.external_secrets_irsa_role,
    helm_release.external_secrets_crds,
    time_sleep.wait_for_alb_webhook
  ]
}

# Phase 3: ClusterSecretStore for AWS Secrets Manager
# This matches the template from comet-devops/charts/external-secrets/templates/cluster-secret-store.yml
# Using a time_sleep to ensure the webhook is ready before creating the ClusterSecretStore
resource "time_sleep" "wait_for_external_secrets_webhook" {
  count = local.install_external_secrets_via_helm ? 1 : 0

  depends_on = [helm_release.external_secrets]

  # Wait for webhook endpoints to be fully registered
  # The comet-devops README notes timing issues with the webhook on first install
  create_duration = "60s"
}

# Using kubectl_manifest instead of kubernetes_manifest to avoid the chicken-and-egg problem
# where kubernetes_manifest tries to connect to the cluster during plan before it exists
resource "kubectl_manifest" "cluster_secret_store" {
  count = local.install_external_secrets_via_helm ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "cluster-secret-store"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  })

  depends_on = [
    helm_release.external_secrets,
    time_sleep.wait_for_external_secrets_webhook
  ]
}

#########################################
#### Loki IRSA Role and IAM Policy ####
#########################################
data "aws_iam_policy_document" "loki" {
  count = var.enable_loki ? 1 : 0

  statement {
    actions = [
      "s3:ListBucket",
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
    ]
    resources = [
      var.loki_s3_bucket_arn,
      "${var.loki_s3_bucket_arn}/*"
    ]
  }
}

resource "aws_iam_policy" "loki" {
  count = var.enable_loki ? 1 : 0

  name_prefix = "${var.environment}-loki-"
  description = "Provides permissions for Loki on ${var.environment} cluster"
  policy      = data.aws_iam_policy_document.loki[0].json

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-loki"
    }
  )
}

module "loki_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  count = var.enable_loki ? 1 : 0

  role_name = coalesce(var.loki_iam_role_name_override, "${var.environment}-loki")

  role_policy_arns = {
    loki = aws_iam_policy.loki[0].arn
  }

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["monitoring:monitoring-loki"]
    }
  }

  depends_on = [
    module.eks,
    aws_iam_policy.loki
  ]

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-loki"
      Description = "IRSA role for Loki to access S3 bucket for log storage"
    }
  )
}

##################################################
#### CloudWatch Exporter IRSA Role and Policy ####
##################################################
data "aws_iam_policy_document" "cloudwatch_exporter" {
  count = var.enable_cloudwatch_exporter ? 1 : 0

  statement {
    actions = [
      "cloudwatch:Describe*",
      "cloudwatch:Get*",
      "cloudwatch:List*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "cloudwatch_exporter" {
  count = var.enable_cloudwatch_exporter ? 1 : 0

  name_prefix = "${var.environment}-cloudwatch-exporter-"
  description = "Provides CloudWatch read access for prometheus-cloudwatch-exporter on ${var.environment} cluster"
  policy      = data.aws_iam_policy_document.cloudwatch_exporter[0].json

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}-cloudwatch-exporter"
    }
  )
}

module "cloudwatch_exporter_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  count = var.enable_cloudwatch_exporter ? 1 : 0

  role_name = coalesce(var.cloudwatch_exporter_iam_role_name_override, "${var.environment}-cloudwatch-exporter")

  role_policy_arns = {
    cloudwatch_exporter = aws_iam_policy.cloudwatch_exporter[0].arn
  }

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["monitoring:monitoring-prometheus-cloudwatch-exporter"]
    }
  }

  depends_on = [
    module.eks,
    aws_iam_policy.cloudwatch_exporter
  ]

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-cloudwatch-exporter"
      Description = "IRSA role for prometheus-cloudwatch-exporter to scrape CloudWatch metrics"
    }
  )
}

#########################################
#### Monitoring Namespace and Secrets ####
#########################################
resource "kubernetes_namespace" "monitoring" {
  count = var.enable_monitoring_setup ? 1 : 0

  metadata {
    name = var.monitoring_namespace
  }

  depends_on = [
    module.eks,
    module.eks_blueprints_addons,
    time_sleep.wait_for_alb_webhook
  ]
}

resource "kubernetes_secret" "monitoring" {
  count = var.enable_monitoring_setup ? 1 : 0

  metadata {
    name      = "monitoring"
    namespace = kubernetes_namespace.monitoring[0].metadata[0].name
  }

  data = {
    grafana-admin-user     = var.grafana_admin_user
    grafana-admin-password = var.grafana_admin_password
  }

  type      = "Opaque"
  immutable = false

  depends_on = [kubernetes_namespace.monitoring]
}

#########################################
#### Karpenter Prerequisites ####
#########################################

data "aws_caller_identity" "current" {}

# Tag private subnets for Karpenter node discovery
resource "aws_ec2_tag" "karpenter_subnet" {
  for_each    = var.enable_karpenter ? toset(var.eks_private_subnets) : toset([])
  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = var.eks_cluster_name
}

# Tag the node shared security group for Karpenter discovery
resource "aws_ec2_tag" "karpenter_sg" {
  count       = var.enable_karpenter ? 1 : 0
  resource_id = module.eks.node_security_group_id
  key         = "karpenter.sh/discovery"
  value       = var.eks_cluster_name

  depends_on = [module.eks]
}

# SQS queue for spot interruption / rebalance event handling
resource "aws_sqs_queue" "karpenter_interruption" {
  count                     = var.enable_karpenter ? 1 : 0
  name                      = "karpenter-${var.eks_cluster_name}"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = merge(
    var.common_tags,
    { Name = "karpenter-${var.eks_cluster_name}" }
  )
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  count     = var.enable_karpenter ? 1 : 0
  queue_url = aws_sqs_queue.karpenter_interruption[0].url

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = ["events.amazonaws.com", "sqs.amazonaws.com"] }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.karpenter_interruption[0].arn
    }]
  })
}

# EventBridge rules — forward interruption events to the SQS queue
resource "aws_cloudwatch_event_rule" "karpenter_spot_interruption" {
  count       = var.enable_karpenter ? 1 : 0
  name        = "karpenter-spot-interruption-${var.eks_cluster_name}"
  description = "Karpenter spot interruption warning for ${var.eks_cluster_name}"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })
  tags = merge(var.common_tags, { Name = "karpenter-spot-interruption-${var.eks_cluster_name}" })
}

resource "aws_cloudwatch_event_target" "karpenter_spot_interruption" {
  count = var.enable_karpenter ? 1 : 0
  rule  = aws_cloudwatch_event_rule.karpenter_spot_interruption[0].name
  arn   = aws_sqs_queue.karpenter_interruption[0].arn
}

resource "aws_cloudwatch_event_rule" "karpenter_rebalance" {
  count       = var.enable_karpenter ? 1 : 0
  name        = "karpenter-rebalance-${var.eks_cluster_name}"
  description = "Karpenter rebalance recommendation for ${var.eks_cluster_name}"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })
  tags = merge(var.common_tags, { Name = "karpenter-rebalance-${var.eks_cluster_name}" })
}

resource "aws_cloudwatch_event_target" "karpenter_rebalance" {
  count = var.enable_karpenter ? 1 : 0
  rule  = aws_cloudwatch_event_rule.karpenter_rebalance[0].name
  arn   = aws_sqs_queue.karpenter_interruption[0].arn
}

resource "aws_cloudwatch_event_rule" "karpenter_instance_state" {
  count       = var.enable_karpenter ? 1 : 0
  name        = "karpenter-instance-state-${var.eks_cluster_name}"
  description = "Karpenter instance state-change notification for ${var.eks_cluster_name}"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })
  tags = merge(var.common_tags, { Name = "karpenter-instance-state-${var.eks_cluster_name}" })
}

resource "aws_cloudwatch_event_target" "karpenter_instance_state" {
  count = var.enable_karpenter ? 1 : 0
  rule  = aws_cloudwatch_event_rule.karpenter_instance_state[0].name
  arn   = aws_sqs_queue.karpenter_interruption[0].arn
}

resource "aws_cloudwatch_event_rule" "karpenter_health_event" {
  count       = var.enable_karpenter ? 1 : 0
  name        = "karpenter-health-${var.eks_cluster_name}"
  description = "Karpenter AWS health event for ${var.eks_cluster_name}"
  event_pattern = jsonencode({
    source      = ["aws.health"]
    detail-type = ["AWS Health Event"]
  })
  tags = merge(var.common_tags, { Name = "karpenter-health-${var.eks_cluster_name}" })
}

resource "aws_cloudwatch_event_target" "karpenter_health_event" {
  count = var.enable_karpenter ? 1 : 0
  rule  = aws_cloudwatch_event_rule.karpenter_health_event[0].name
  arn   = aws_sqs_queue.karpenter_interruption[0].arn
}

# IAM role for nodes provisioned by Karpenter (separate from managed node group role)
resource "aws_iam_role" "karpenter_node" {
  count = var.enable_karpenter ? 1 : 0
  name  = "karpenter-node-${var.eks_cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.common_tags, { Name = "karpenter-node-${var.eks_cluster_name}" })
}

resource "aws_iam_role_policy_attachment" "karpenter_node_eks_worker" {
  count      = var.enable_karpenter ? 1 : 0
  role       = aws_iam_role.karpenter_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni" {
  count      = var.enable_karpenter ? 1 : 0
  role       = aws_iam_role.karpenter_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ecr" {
  count      = var.enable_karpenter ? 1 : 0
  role       = aws_iam_role.karpenter_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ssm" {
  count      = var.enable_karpenter ? 1 : 0
  role       = aws_iam_role.karpenter_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach the Comet S3 access policy so Karpenter-provisioned nodes can access
# the Comet S3 bucket via the EC2 instance profile (keyID/secretKey = "IAM-ROLE").
resource "aws_iam_role_policy_attachment" "karpenter_node_s3" {
  count      = var.enable_karpenter && var.s3_enabled ? 1 : 0
  role       = aws_iam_role.karpenter_node[0].name
  policy_arn = var.comet_ec2_s3_iam_policy
}

resource "aws_iam_instance_profile" "karpenter_node" {
  count = var.enable_karpenter ? 1 : 0
  name  = "karpenter-node-${var.eks_cluster_name}"
  role  = aws_iam_role.karpenter_node[0].name

  tags = merge(var.common_tags, { Name = "karpenter-node-${var.eks_cluster_name}" })
}

# EKS access entry — lets Karpenter-provisioned nodes join the cluster
resource "aws_eks_access_entry" "karpenter_node" {
  count         = var.enable_karpenter ? 1 : 0
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.karpenter_node[0].arn
  type          = "EC2_LINUX"

  tags       = merge(var.common_tags, { Name = "karpenter-node-${var.eks_cluster_name}" })
  depends_on = [module.eks]
}

# IAM policy for the Karpenter controller
data "aws_iam_policy_document" "karpenter_controller" {
  count = var.enable_karpenter ? 1 : 0

  statement {
    sid    = "AllowScopedEC2InstanceAccessActions"
    effect = "Allow"
    resources = [
      "arn:aws:ec2:${var.region}::image/*",
      "arn:aws:ec2:${var.region}::snapshot/*",
      "arn:aws:ec2:${var.region}:*:security-group/*",
      "arn:aws:ec2:${var.region}:*:subnet/*",
    ]
    actions = ["ec2:RunInstances", "ec2:CreateFleet"]
  }

  statement {
    sid       = "AllowScopedEC2LaunchTemplateAccessActions"
    effect    = "Allow"
    resources = ["arn:aws:ec2:${var.region}:*:launch-template/*"]
    actions   = ["ec2:RunInstances", "ec2:CreateFleet"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.eks_cluster_name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid    = "AllowScopedEC2InstanceActionsWithTags"
    effect = "Allow"
    resources = [
      "arn:aws:ec2:${var.region}:*:fleet/*",
      "arn:aws:ec2:${var.region}:*:instance/*",
      "arn:aws:ec2:${var.region}:*:volume/*",
      "arn:aws:ec2:${var.region}:*:network-interface/*",
      "arn:aws:ec2:${var.region}:*:launch-template/*",
      "arn:aws:ec2:${var.region}:*:spot-instances-request/*",
    ]
    actions = ["ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${var.eks_cluster_name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid    = "AllowScopedResourceCreationTagging"
    effect = "Allow"
    resources = [
      "arn:aws:ec2:${var.region}:*:fleet/*",
      "arn:aws:ec2:${var.region}:*:instance/*",
      "arn:aws:ec2:${var.region}:*:volume/*",
      "arn:aws:ec2:${var.region}:*:network-interface/*",
      "arn:aws:ec2:${var.region}:*:launch-template/*",
      "arn:aws:ec2:${var.region}:*:spot-instances-request/*",
    ]
    actions = ["ec2:CreateTags"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${var.eks_cluster_name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid    = "AllowScopedDeletion"
    effect = "Allow"
    resources = [
      "arn:aws:ec2:${var.region}:*:instance/*",
      "arn:aws:ec2:${var.region}:*:launch-template/*",
    ]
    actions = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${var.eks_cluster_name}"
      values   = ["owned"]
    }
    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowRegionalReadActions"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid       = "AllowGlobalReadActions"
    effect    = "Allow"
    resources = ["*"]
    actions = [
      "iam:GetInstanceProfile",
      "pricing:GetProducts",
      "ssm:GetParameter",
      "eks:DescribeCluster",
    ]
  }

  statement {
    sid       = "AllowInterruptionQueueActions"
    effect    = "Allow"
    resources = [aws_sqs_queue.karpenter_interruption[0].arn]
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
    ]
  }

  statement {
    sid       = "AllowPassingInstanceRole"
    effect    = "Allow"
    resources = [aws_iam_role.karpenter_node[0].arn]
    actions   = ["iam:PassRole"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "karpenter_controller" {
  count = var.enable_karpenter ? 1 : 0

  name        = "karpenter-controller-${var.eks_cluster_name}"
  description = "Karpenter controller permissions for cluster ${var.eks_cluster_name}"
  policy      = data.aws_iam_policy_document.karpenter_controller[0].json

  tags = merge(var.common_tags, { Name = "karpenter-controller-${var.eks_cluster_name}" })
}

# IRSA role for the Karpenter controller pod
module "karpenter_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  count = var.enable_karpenter ? 1 : 0

  role_name = "${var.environment}-karpenter"

  role_policy_arns = {
    karpenter = aws_iam_policy.karpenter_controller[0].arn
  }

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:karpenter"]
    }
  }

  tags = merge(
    var.common_tags,
    {
      Name        = "${var.environment}-karpenter"
      Description = "IRSA role for Karpenter controller"
    }
  )
}

#########################################
#### Karpenter Helm Chart ####
#########################################
resource "helm_release" "karpenter_stsaas" {
  count = local.install_karpenter_via_helm ? 1 : 0

  name             = "karpenter"
  repository       = "https://helm.comet.com/"
  chart            = "comet-stsaas-karpenter"
  version          = var.karpenter_chart_version
  namespace        = "kube-system"
  create_namespace = false

  repository_username = var.karpenter_helm_username
  repository_password = var.karpenter_helm_password

  # Cluster identity — also forwarded to the Karpenter subchart
  set = [
    {
      name  = "clusterName"
      value = var.eks_cluster_name
    },
    # EC2 instance profile for all Karpenter-provisioned nodes
    {
      name  = "nodeInstanceProfile"
      value = aws_iam_instance_profile.karpenter_node[0].name
    },
    # Karpenter controller IRSA
    {
      name  = "karpenter.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = module.karpenter_irsa[0].iam_role_arn
    },
    # Karpenter controller settings (passed through to subchart)
    {
      name  = "karpenter.settings.clusterName"
      value = var.eks_cluster_name
    },
    {
      name  = "karpenter.settings.interruptionQueue"
      value = aws_sqs_queue.karpenter_interruption[0].name
    },
  ]

  # EC2 instance tags — merge common_tags (Terraform=true, Environment, etc.) with any
  # extra tags so Karpenter-provisioned nodes are tagged consistently with all other resources
  values = [
    yamlencode({
      tags = merge(var.common_tags, var.karpenter_extra_tags)
    })
  ]

  wait    = true
  timeout = 600

  depends_on = [
    module.eks,
    module.eks_blueprints_addons,
    module.karpenter_irsa,
    aws_iam_instance_profile.karpenter_node,
    aws_eks_access_entry.karpenter_node,
    aws_sqs_queue.karpenter_interruption,
    aws_ec2_tag.karpenter_subnet,
    aws_ec2_tag.karpenter_sg,
  ]
}

#########################################
#### EKS API ingress — fleet-wide CIDRs ####
#########################################
# These open the EKS cluster_security_group_id (the cluster's primary SG) on
# port 443 to fleet-wide management surfaces. Each ingress source is gated by
# its own toggle; the local map merges all enabled rules into a single
# for_each so the common attributes live in one place.

locals {
  eks_api_ingress_rules = merge(
    var.enable_argocd_management_eks_access ? {
      for cidr in distinct(var.argocd_management_cidrs) :
      "argocd-management-${replace(cidr, "/", "_")}" => {
        cidr        = cidr
        description = "Allow ArgoCD management to reach EKS API from ${cidr}"
        name        = "argocd-management-access-${replace(cidr, "/", "_")}"
      }
    } : {},
    var.enable_vpn_eks_api_access ? {
      "vpn" = {
        cidr        = var.vpn_client_cidr
        description = "Allow VPN clients to reach EKS API"
        name        = "vpn-eks-api-access"
      }
    } : {},
    var.enable_ci_runners_eks_api_access ? {
      "ci-runners" = {
        cidr        = var.ci_runners_cidr
        description = "Allow CI cluster runners to reach EKS API"
        name        = "ci-runners-eks-api-access"
      }
    } : {},
  )
}

resource "aws_vpc_security_group_ingress_rule" "eks_api" {
  for_each = local.eks_api_ingress_rules

  security_group_id = module.eks.cluster_primary_security_group_id
  description       = each.value.description
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value.cidr

  tags = merge(var.common_tags, { Name = each.value.name })
}

#########################################
#### Agentro EKS access + RBAC (DND-809) ####
#########################################
# EKS access entry maps the agentro IAM role to the k8s 'agentro' group, which
# is then bound to the built-in 'view' ClusterRole (excludes Secrets) plus the
# agentro-extras ClusterRole granting reads on cluster-scoped resources and
# operator CRDs the support agent needs to debug.

resource "aws_eks_access_entry" "agentro" {
  count = var.enable_agentro_access ? 1 : 0

  cluster_name      = module.eks.cluster_name
  principal_arn     = var.agentro_role_arn
  kubernetes_groups = ["agentro"]
}

resource "kubernetes_cluster_role_binding" "agentro_view" {
  count = var.enable_agentro_access ? 1 : 0

  metadata {
    name = "agentro-view"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "view"
  }

  subject {
    kind      = "Group"
    name      = "agentro"
    api_group = "rbac.authorization.k8s.io"
  }

  depends_on = [aws_eks_access_entry.agentro, time_sleep.wait_for_cluster_access]
}

resource "kubernetes_cluster_role" "agentro_extras" {
  count = var.enable_agentro_access ? 1 : 0

  depends_on = [time_sleep.wait_for_cluster_access]

  metadata {
    name = "agentro-extras"
  }

  rule {
    api_groups = [""]
    resources  = ["nodes", "nodes/metrics", "nodes/stats", "persistentvolumes"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses", "csinodes", "volumeattachments"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["apiextensions.k8s.io"]
    resources  = ["customresourcedefinitions"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/portforward", "services/portforward"]
    verbs      = ["get", "create"]
  }

  rule {
    api_groups = ["clickhouse.altinity.com"]
    resources  = ["clickhouseinstallations", "clickhouseinstallationtemplates", "clickhouseoperatorconfigurations"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["karpenter.sh"]
    resources  = ["nodepools", "nodeclaims"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = ["karpenter.k8s.aws"]
    resources  = ["ec2nodeclasses"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "agentro_extras" {
  count = var.enable_agentro_access ? 1 : 0

  metadata {
    name = "agentro-extras"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.agentro_extras[0].metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = "agentro"
    api_group = "rbac.authorization.k8s.io"
  }

  depends_on = [aws_eks_access_entry.agentro]
}

#########################################
#### Namespace nodegroup pinning ####
#########################################
# Annotates namespaces with scheduler.alpha.kubernetes.io/node-selector to route
# every Pod admitted into the namespace onto a specific node group. Skips
# kube-system + monitoring (they host DaemonSets and must schedule everywhere).
# Patches in place — does NOT create the namespace; create via Helm first.

resource "kubernetes_annotations" "app_ns_node_selector" {
  count = var.enable_namespace_nodegroup_pinning ? 1 : 0

  depends_on = [time_sleep.wait_for_cluster_access]

  api_version = "v1"
  kind        = "Namespace"
  metadata {
    name = coalesce(var.app_namespace, var.environment)
  }
  annotations = {
    "scheduler.alpha.kubernetes.io/node-selector" = "nodegroup_name=comet"
  }
  force = true
}

resource "kubernetes_annotations" "admin_ns_node_selector" {
  for_each = var.enable_namespace_nodegroup_pinning ? toset(var.admin_pinned_namespaces) : []

  depends_on = [time_sleep.wait_for_cluster_access]

  api_version = "v1"
  kind        = "Namespace"
  metadata {
    name = each.value
  }
  annotations = {
    "scheduler.alpha.kubernetes.io/node-selector" = "nodegroup_name=admin"
  }
  force = true
}

#########################################
#### Redis Insights namespace + agentro port-forward RBAC ####
#########################################
# Operational debug surface — provides a namespace for the redis-insights helm
# chart (installed by FRED-helm-apply) pinned to the admin NG. When combined
# with enable_agentro_access, also grants the agentro group port-forward in
# this namespace so the support agent can reach Redis via kubectl port-forward.

resource "kubernetes_namespace" "redis_insights" {
  count = var.enable_redis_insights_ns ? 1 : 0

  depends_on = [time_sleep.wait_for_cluster_access]

  metadata {
    name = "redis-insights"
    annotations = {
      "scheduler.alpha.kubernetes.io/node-selector" = "nodegroup_name=admin"
    }
  }
}

resource "kubernetes_role" "agentro_portforward" {
  count = var.enable_agentro_access && var.enable_redis_insights_ns ? 1 : 0

  metadata {
    name      = "agentro-portforward"
    namespace = kubernetes_namespace.redis_insights[0].metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/portforward"]
    verbs      = ["create"]
  }
}

resource "kubernetes_role_binding" "agentro_portforward" {
  count = var.enable_agentro_access && var.enable_redis_insights_ns ? 1 : 0

  metadata {
    name      = "agentro-portforward"
    namespace = kubernetes_namespace.redis_insights[0].metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.agentro_portforward[0].metadata[0].name
  }

  subject {
    kind      = "Group"
    name      = "agentro"
    api_group = "rbac.authorization.k8s.io"
  }
}
