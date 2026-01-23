locals {
  volume_type                  = "gp3"
  volume_encrypted             = false
  volume_delete_on_termination = true

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

data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
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
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31.6"

  cluster_name                    = var.eks_cluster_name
  cluster_version                 = var.eks_cluster_version
  cluster_endpoint_public_access  = var.eks_cluster_endpoint_public_access
  cluster_endpoint_private_access = var.eks_cluster_endpoint_private_access

  cluster_security_group_additional_rules = local.cluster_security_group_rules

  authentication_mode                      = var.eks_authentication_mode
  enable_cluster_creator_admin_permissions = var.eks_enable_cluster_creator_admin_permissions

  access_entries = local.admin_access_entries

  vpc_id     = var.vpc_id
  subnet_ids = var.eks_private_subnets

  eks_managed_node_group_defaults = merge(
    {
      ami_type                   = var.eks_mng_ami_type
      enable_bootstrap_user_data = true
      # Set platform based on AMI type - AL2023 uses nodeadm, AL2 uses bootstrap.sh
      platform = startswith(var.eks_mng_ami_type, "AL2023") ? "al2023" : "linux"
      tags     = var.common_tags
    },
    var.eks_mng_ami_id != null ? {
      ami_id = var.eks_mng_ami_id
    } : {}
  )

  eks_managed_node_groups = merge(
    # Admin Node Group
    var.enable_admin_node_group ? {
      admin = {
        name           = var.eks_admin_name
        instance_types = var.eks_admin_instance_types
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
          nodegroup_name                  = "admin"
          "node-role.kubernetes.io/admin" = "true"
        }
        tags                         = var.common_tags
        tags_propagate_at_launch     = true
        launch_template_version      = "$Latest"
        iam_role_additional_policies = local.node_group_iam_policies
      }
    } : {},
    # Comet Node Group
    var.enable_comet_node_group ? {
      comet = {
        name           = var.eks_comet_name
        instance_types = var.eks_comet_instance_types
        min_size       = var.eks_comet_min_size
        max_size       = var.eks_comet_max_size
        desired_size   = var.eks_comet_desired_size
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
          nodegroup_name                  = "comet"
          "node-role.kubernetes.io/comet" = "true"
        }
        tags                         = var.common_tags
        tags_propagate_at_launch     = true
        launch_template_version      = "$Latest"
        iam_role_additional_policies = local.node_group_iam_policies
      }
    } : {},
    # Druid Node Group
    (var.enable_druid_node_group && var.enable_mpm_infra) ? {
      druid = {
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
          nodegroup_name                  = "druid"
          "node-role.kubernetes.io/druid" = "true"
        }
        tags                         = var.common_tags
        tags_propagate_at_launch     = true
        launch_template_version      = "$Latest"
        iam_role_additional_policies = local.node_group_iam_policies
      }
    } : {},
    # Airflow Node Group
    (var.enable_airflow_node_group && var.enable_mpm_infra) ? {
      airflow = {
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
          nodegroup_name                    = "airflow"
          "node-role.kubernetes.io/airflow" = "true"
        }
        tags                         = var.common_tags
        tags_propagate_at_launch     = true
        launch_template_version      = "$Latest"
        iam_role_additional_policies = local.node_group_iam_policies
      }
    } : {},
    # ClickHouse Node Group
    var.enable_clickhouse_node_group ? {
      clickhouse = {
        name           = var.eks_clickhouse_name
        instance_types = var.eks_clickhouse_instance_types
        min_size       = var.eks_clickhouse_min_size
        max_size       = var.eks_clickhouse_max_size
        desired_size   = var.eks_clickhouse_desired_size
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
          nodegroup_name                       = "clickhouse"
          "node-role.kubernetes.io/clickhouse" = "true"
        }
        taints                       = var.eks_clickhouse_taints
        tags                         = var.common_tags
        tags_propagate_at_launch     = true
        launch_template_version      = "$Latest"
        iam_role_additional_policies = local.node_group_iam_policies
      }
    } : {},
    # Additional custom node groups
    var.additional_node_groups
  )
}


module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "4.7.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "1.9.1"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  oidc_provider_arn = module.eks.oidc_provider_arn
  cluster_version   = module.eks.cluster_version

  eks_addons = {
    coredns            = {}
    vpc-cni            = {}
    kube-proxy         = {}
    aws-ebs-csi-driver = { service_account_role_arn = module.irsa-ebs-csi.iam_role_arn }
  }

  enable_aws_load_balancer_controller = var.eks_aws_load_balancer_controller
  enable_cert_manager                 = var.eks_cert_manager
  enable_aws_cloudwatch_metrics       = var.eks_aws_cloudwatch_metrics
  enable_external_dns                 = var.eks_external_dns
  external_dns_route53_zone_arns      = var.eks_external_dns_r53_zones
}

locals {
  # Build tag specifications for EBS CSI driver
  # Each tag needs to be a separate tagSpecification_N parameter with format "key=value"
  common_tags_list = [for k, v in var.common_tags : "${k}=${v}"]

  # Base tags for gp3 storage class
  gp3_base_tags  = ["Terraform=true", "StorageClass=gp3"]
  gp3_all_tags   = concat(local.gp3_base_tags, local.common_tags_list)
  gp3_tag_params = { for idx, tag in local.gp3_all_tags : "tagSpecification_${idx + 1}" => tag }

  # Base tags for comet-generic storage class
  comet_generic_base_tags  = ["Terraform=true", "StorageClass=comet-generic"]
  comet_generic_all_tags   = concat(local.comet_generic_base_tags, local.common_tags_list)
  comet_generic_tag_params = { for idx, tag in local.comet_generic_all_tags : "tagSpecification_${idx + 1}" => tag }
}

resource "kubernetes_storage_class" "gp3" {
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

  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
}

resource "kubernetes_storage_class" "comet_generic" {
  metadata {
    name   = "comet-generic"
    labels = var.common_tags
  }

  storage_provisioner = "ebs.csi.aws.com"

  parameters = merge(
    { type = "gp3" },
    local.comet_generic_tag_params
  )

  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true
}

#########################################
#### External Secrets IRSA Role ####
#########################################
# This role allows the external-secrets service account to access AWS Secrets Manager
module "external_secrets_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  count = var.enable_external_secrets ? 1 : 0

  # Role name matches the expected format: {environment}-external-secrets
  role_name = "${var.environment}-external-secrets"

  # Attach the external secrets policy that allows Secrets Manager access
  attach_external_secrets_policy = true

  # Limit access to secrets matching the environment's path pattern
  external_secrets_secrets_manager_arns = [
    "arn:aws:secretsmanager:*:*:secret:cometml/${var.environment}/*"
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

  role_name = "${var.environment}-loki"

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
    module.eks_blueprints_addons
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