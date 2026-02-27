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

  tags = merge(
    var.common_tags,
    {
      Name = "additional-s3-access-policy-${var.eks_cluster_name}"
    }
  )
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

  # KMS key access control for cluster encryption
  kms_key_administrators = var.kms_key_administrators
  kms_key_users          = var.kms_key_users

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
    # Karpenter Node Group — created when Karpenter is enabled.
    # Dedicated to the Karpenter controller only; tainted so no other pods schedule here.
    # All other node groups are suppressed when Karpenter is enabled (Karpenter provisions them).
    var.enable_karpenter ? {
      karpenter = {
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
        taints = [
          {
            key    = "dedicated"
            value  = "karpenter"
            effect = "NO_SCHEDULE"
          }
        ]
        tags                         = var.common_tags
        tags_propagate_at_launch     = true
        launch_template_version      = "$Latest"
        iam_role_additional_policies = local.node_group_iam_policies
      }
    } : {},
    # Admin Node Group — disabled when Karpenter is enabled (Karpenter provisions admin nodes)
    (var.enable_admin_node_group && !var.enable_karpenter) ? {
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
    # Comet Node Group — disabled when Karpenter is enabled (Karpenter provisions comet nodes)
    (var.enable_comet_node_group && !var.enable_karpenter) ? {
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
    # Druid Node Group — disabled when Karpenter is enabled
    (var.enable_druid_node_group && var.enable_mpm_infra && !var.enable_karpenter) ? {
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
    # Airflow Node Group — disabled when Karpenter is enabled
    (var.enable_airflow_node_group && var.enable_mpm_infra && !var.enable_karpenter) ? {
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
    # ClickHouse Node Group — requires explicit opt-in AND Karpenter must be disabled
    (var.enable_clickhouse_node_group && !var.enable_karpenter) ? {
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
  count = var.enable_external_secrets ? 1 : 0

  name             = "external-secrets-crds"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version
  namespace        = "external-secrets"
  create_namespace = true

  # Only install CRDs, disable everything else
  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "webhook.create"
    value = "false"
  }

  set {
    name  = "certController.create"
    value = "false"
  }

  set {
    name  = "createOperator"
    value = "false"
  }

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
  count = var.enable_external_secrets ? 1 : 0

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
  set {
    name  = "installCRDs"
    value = "false"
  }

  # Match values from comet-devops values.yaml
  set {
    name  = "replicaCount"
    value = "1"
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.automount"
    value = "true"
  }

  # IRSA annotation from values-dply.yaml pattern
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.external_secrets_irsa_role[0].iam_role_arn
  }

  # Webhook configuration from values.yaml
  set {
    name  = "webhook.create"
    value = "true"
  }

  set {
    name  = "webhook.replicaCount"
    value = "1"
  }

  # CertController configuration from values.yaml
  set {
    name  = "certController.create"
    value = "true"
  }

  set {
    name  = "certController.replicaCount"
    value = "1"
  }

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
  count = var.enable_external_secrets ? 1 : 0

  depends_on = [helm_release.external_secrets]

  # Wait for webhook endpoints to be fully registered
  # The comet-devops README notes timing issues with the webhook on first install
  create_duration = "60s"
}

# Using kubectl_manifest instead of kubernetes_manifest to avoid the chicken-and-egg problem
# where kubernetes_manifest tries to connect to the cluster during plan before it exists
resource "kubectl_manifest" "cluster_secret_store" {
  count = var.enable_external_secrets ? 1 : 0

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