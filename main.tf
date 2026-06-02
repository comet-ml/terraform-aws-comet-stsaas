locals {
  resource_name = "comet-${var.environment}"
  all_tags = merge(
    {
      Terraform = "true"
    },
    var.environment_tag != "" ? { Environment = var.environment_tag } : {},
    var.common_tags
  )

  # Hostname for the Comet deployment (region-agnostic)
  comet_hostname = coalesce(var.comet_hostname, var.environment)

  # ACM certificate domain configuration
  # Uses comet_hostname (not environment) to ensure region-agnostic domain names
  acm_domain_name = var.enable_acm_certificate ? coalesce(var.acm_domain_name, "${local.comet_hostname}.comet-hosted.com") : null

  # RDS master password - use provided value or generated one
  # This ensures both RDS and Secrets Manager modules use the same password
  rds_master_password = var.rds_master_password != null ? var.rds_master_password : (
    var.enable_rds ? random_password.rds_master[0].result : null
  )
}

#############################
#### RDS Password Generation ####
#############################
# Generate random password for RDS if not provided
# Only created when enable_rds is true AND no password is provided
resource "random_password" "rds_master" {
  count = var.enable_rds && var.rds_master_password == null ? 1 : 0

  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"

  lifecycle {
    ignore_changes = [length, special, override_special, min_special, min_upper, min_lower, min_numeric, numeric, lower, upper]
  }
}

#######################
#### ACM Certificate ####
#######################
# Creates an ACM certificate for {environment}.comet-hosted.com with wildcard SAN
resource "aws_acm_certificate" "main" {
  count = var.enable_acm_certificate ? 1 : 0

  domain_name               = local.acm_domain_name
  subject_alternative_names = ["*.${local.acm_domain_name}"]
  validation_method         = "DNS"

  tags = merge(
    local.all_tags,
    {
      Name = local.acm_domain_name
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# DNS validation records in Route 53
resource "aws_route53_record" "acm_validation" {
  for_each = var.enable_acm_certificate ? {
    for dvo in aws_acm_certificate.main[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.acm_route53_zone_id
}

# Wait for certificate validation to complete
resource "aws_acm_certificate_validation" "main" {
  count = var.enable_acm_certificate && var.acm_wait_for_validation ? 1 : 0

  certificate_arn         = aws_acm_certificate.main[0].arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}

# Validation: acm_route53_zone_id is required when enable_acm_certificate is true
resource "terraform_data" "acm_validation" {
  count = var.enable_acm_certificate ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.acm_route53_zone_id != null
      error_message = "acm_route53_zone_id is required when enable_acm_certificate is true."
    }
  }
}
resource "terraform_data" "secretsmanager_validation" {
  count = var.enable_secretsmanager ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.enable_rds && var.enable_elasticache
      error_message = "enable_secretsmanager requires both enable_rds and enable_elasticache to be true."
    }
  }
}

resource "terraform_data" "rds_proxy_validation" {
  count = var.enable_rds_proxy ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.enable_rds
      error_message = "enable_rds_proxy requires enable_rds to be true."
    }
    precondition {
      condition     = var.enable_eks || length(var.rds_proxy_allowed_sg_ids) > 0 || length(var.rds_proxy_allowed_cidrs) > 0
      error_message = "enable_rds_proxy requires at least one ingress source: enable_eks=true (auto-wires the nodegroup SG), or non-empty rds_proxy_allowed_sg_ids, or non-empty rds_proxy_allowed_cidrs. Otherwise the proxy has no ingress rules and is unreachable."
    }
    precondition {
      condition     = var.rds_snapshot_identifier == null
      error_message = "enable_rds_proxy is not currently supported with rds_snapshot_identifier — the proxy auth secret would be written with vars that don't match the snapshot's embedded credentials. Disable enable_rds_proxy or open a follow-up to add an explicit rds_proxy_username/password override."
    }
  }
}

module "comet_vpc" {
  source      = "./modules/comet_vpc"
  count       = var.enable_vpc ? 1 : 0
  environment = var.environment
  common_tags = local.all_tags
  region      = var.region
  vpc_cidr    = var.vpc_cidr

  vpc_name            = var.vpc_name
  public_subnets      = var.public_subnets
  private_subnets     = var.private_subnets
  public_subnet_tags  = var.public_subnet_tags
  private_subnet_tags = var.private_subnet_tags

  eks_enabled        = var.enable_eks
  single_nat_gateway = var.single_nat_gateway

  enable_tgw_prep      = var.enable_tgw_prep
  enable_vpc_flow_logs = var.enable_vpc_flow_logs
  enable_s3_endpoint   = var.enable_s3_endpoint

  enable_vpc_interface_endpoints        = var.enable_vpc_interface_endpoints
  vpc_interface_endpoints_services      = var.vpc_interface_endpoints_services
  vpc_interface_endpoints_allowed_cidrs = var.vpc_interface_endpoints_allowed_cidrs

  enable_tgw_attachment                          = var.enable_tgw_attachment
  tgw_id                                         = var.tgw_id
  tgw_propagated_cidrs                           = var.tgw_propagated_cidrs
  tgw_attachment_dns_support                     = var.tgw_attachment_dns_support
  tgw_attachment_appliance_mode_support          = var.tgw_attachment_appliance_mode_support
  tgw_attachment_default_route_table_association = var.tgw_attachment_default_route_table_association
  tgw_attachment_default_route_table_propagation = var.tgw_attachment_default_route_table_propagation
}

module "comet_ec2" {
  source      = "./modules/comet_ec2"
  count       = var.enable_ec2 ? 1 : 0
  environment = var.environment
  common_tags = local.all_tags

  vpc_id                   = var.enable_vpc ? module.comet_vpc[0].vpc_id : var.comet_vpc_id
  comet_ec2_subnet         = var.enable_vpc ? module.comet_vpc[0].public_subnets[0] : var.comet_public_subnets[0]
  comet_ec2_ami_type       = var.comet_ec2_ami_type
  comet_ec2_ami_id         = var.comet_ec2_ami_id
  comet_ec2_instance_type  = var.comet_ec2_instance_type
  comet_ec2_instance_count = var.comet_ec2_instance_count
  comet_ec2_volume_type    = var.comet_ec2_volume_type
  comet_ec2_volume_size    = var.comet_ec2_volume_size
  comet_ec2_key            = var.comet_ec2_key

  alb_enabled      = var.enable_ec2_alb
  comet_ec2_alb_sg = var.enable_ec2_alb ? module.comet_ec2_alb[0].comet_alb_sg : null

  s3_enabled              = var.enable_s3
  comet_ec2_s3_iam_policy = var.enable_s3 ? module.comet_s3[0].comet_s3_iam_policy_arn : null
}

module "comet_ec2_alb" {
  source      = "./modules/comet_ec2_alb"
  count       = var.enable_ec2_alb ? 1 : 0
  environment = var.environment
  common_tags = local.all_tags

  vpc_id         = var.enable_vpc ? module.comet_vpc[0].vpc_id : var.comet_vpc_id
  public_subnets = var.enable_vpc ? module.comet_vpc[0].public_subnets : var.comet_public_subnets
  # Use provided certificate ARN, or the created ACM certificate if enabled
  ssl_certificate_arn = coalesce(
    var.ssl_certificate_arn,
    var.enable_acm_certificate ? aws_acm_certificate.main[0].arn : null
  )
}

module "comet_eks" {
  source      = "./modules/comet_eks"
  count       = var.enable_eks ? 1 : 0
  environment = var.environment
  region      = var.region
  common_tags = local.all_tags

  vpc_id                                       = var.enable_vpc ? module.comet_vpc[0].vpc_id : var.comet_vpc_id
  eks_private_subnets                          = var.enable_vpc ? module.comet_vpc[0].private_subnets : var.comet_private_subnets
  eks_cluster_name                             = var.eks_cluster_name
  eks_cluster_version                          = var.eks_cluster_version
  eks_cluster_endpoint_public_access           = var.eks_cluster_endpoint_public_access
  eks_cluster_endpoint_private_access          = var.eks_cluster_endpoint_private_access
  eks_cluster_security_group_additional_rules  = var.eks_cluster_security_group_additional_rules
  eks_private_access_cidrs                     = var.eks_private_access_cidrs
  eks_authentication_mode                      = var.eks_authentication_mode
  eks_enable_cluster_creator_admin_permissions = var.eks_enable_cluster_creator_admin_permissions
  eks_admin_role_arns                          = var.eks_admin_role_arns
  kms_key_administrators                       = var.eks_kms_key_administrators
  kms_key_users                                = var.eks_kms_key_users
  eks_mng_ami_type                             = var.eks_mng_ami_type
  eks_admin_ami_type                           = var.eks_admin_ami_type
  eks_comet_ami_type                           = var.eks_comet_ami_type
  eks_clickhouse_ami_type                      = var.eks_clickhouse_ami_type
  eks_mng_ami_id                               = var.eks_mng_ami_id
  eks_mng_disk_size                            = var.eks_mng_disk_size
  eks_aws_load_balancer_controller             = var.eks_aws_load_balancer_controller
  eks_cert_manager                             = var.eks_cert_manager
  eks_aws_cloudwatch_metrics                   = var.eks_aws_cloudwatch_metrics
  eks_external_dns                             = var.eks_external_dns
  eks_external_dns_r53_zones                   = var.eks_external_dns_r53_zones
  eks_enable_metrics_server                    = var.eks_enable_metrics_server
  eks_metrics_server_addon_version             = var.eks_metrics_server_addon_version
  eks_enable_cluster_autoscaler                = var.eks_enable_cluster_autoscaler

  s3_enabled              = var.enable_s3
  comet_ec2_s3_iam_policy = var.enable_s3 ? module.comet_s3[0].comet_s3_iam_policy_arn : null

  # MPM Infrastructure toggle
  enable_mpm_infra = var.enable_mpm_infra

  # Node Group Toggles
  enable_admin_node_group      = var.eks_enable_admin_node_group
  enable_comet_node_group      = var.eks_enable_comet_node_group
  enable_druid_node_group      = var.eks_enable_druid_node_group
  enable_airflow_node_group    = var.eks_enable_airflow_node_group
  enable_clickhouse_node_group = var.eks_enable_clickhouse_node_group

  # Admin Node Group
  eks_admin_name           = var.eks_admin_name
  eks_admin_instance_types = var.eks_admin_instance_types
  eks_admin_capacity_type  = var.eks_admin_capacity_type
  eks_admin_min_size       = var.eks_admin_min_size
  eks_admin_max_size       = var.eks_admin_max_size
  eks_admin_desired_size   = var.eks_admin_desired_size
  eks_admin_subnet_ids     = var.eks_admin_subnet_ids

  # Comet Node Group
  eks_comet_name           = var.eks_comet_name
  eks_comet_instance_types = var.eks_comet_instance_types
  eks_comet_capacity_type  = var.eks_comet_capacity_type
  eks_comet_min_size       = var.eks_comet_min_size
  eks_comet_max_size       = var.eks_comet_max_size
  eks_comet_desired_size   = var.eks_comet_desired_size
  eks_comet_subnet_ids     = var.eks_comet_subnet_ids

  # Druid Node Group
  eks_druid_name           = var.eks_druid_name
  eks_druid_instance_types = var.eks_druid_instance_types
  eks_druid_min_size       = var.eks_druid_min_size
  eks_druid_max_size       = var.eks_druid_max_size
  eks_druid_desired_size   = var.eks_druid_desired_size
  eks_druid_subnet_ids     = var.eks_druid_subnet_ids

  # Airflow Node Group
  eks_airflow_name           = var.eks_airflow_name
  eks_airflow_instance_types = var.eks_airflow_instance_types
  eks_airflow_min_size       = var.eks_airflow_min_size
  eks_airflow_max_size       = var.eks_airflow_max_size
  eks_airflow_desired_size   = var.eks_airflow_desired_size
  eks_airflow_subnet_ids     = var.eks_airflow_subnet_ids

  # ClickHouse Node Group
  eks_clickhouse_name                  = var.eks_clickhouse_name
  eks_clickhouse_instance_types        = var.eks_clickhouse_instance_types
  eks_clickhouse_capacity_type         = var.eks_clickhouse_capacity_type
  eks_clickhouse_min_size              = var.eks_clickhouse_min_size
  eks_clickhouse_max_size              = var.eks_clickhouse_max_size
  eks_clickhouse_desired_size          = var.eks_clickhouse_desired_size
  eks_clickhouse_volume_size           = var.eks_clickhouse_volume_size
  eks_clickhouse_volume_type           = var.eks_clickhouse_volume_type
  eks_clickhouse_volume_encrypted      = var.eks_clickhouse_volume_encrypted
  eks_clickhouse_delete_on_termination = var.eks_clickhouse_delete_on_termination
  eks_clickhouse_taints                = var.eks_clickhouse_taints
  eks_clickhouse_subnet_ids            = var.eks_clickhouse_subnet_ids

  # Additional custom node groups
  additional_node_groups = var.eks_additional_node_groups

  # Additional S3 bucket access
  additional_s3_bucket_arns = var.eks_additional_s3_bucket_arns

  # External Secrets IRSA role and Helm chart
  enable_external_secrets           = var.eks_enable_external_secrets
  external_secrets_chart_version    = var.eks_external_secrets_chart_version
  external_secrets_via_helm_release = var.eks_external_secrets_via_helm_release
  secretsmanager_environment        = var.secretsmanager_environment

  # Storage class configuration
  storage_class_reclaim_policy = var.eks_storage_class_reclaim_policy

  # Loki IRSA for S3 access
  enable_loki        = var.enable_loki_bucket
  loki_s3_bucket_arn = var.enable_s3 && var.enable_loki_bucket ? module.comet_s3[0].comet_loki_bucket_arn : null

  # CloudWatch Exporter IRSA for scraping AWS managed service metrics
  enable_cloudwatch_exporter = var.enable_cloudwatch_exporter

  # Monitoring namespace and Grafana credentials
  enable_monitoring_setup = var.enable_monitoring_setup
  monitoring_namespace    = var.monitoring_namespace
  grafana_admin_user      = var.grafana_admin_user
  grafana_admin_password  = var.grafana_admin_password

  # Karpenter prerequisites
  enable_karpenter           = var.eks_enable_karpenter
  karpenter_via_helm_release = var.eks_karpenter_via_helm_release

  # Karpenter Node Group (dedicated controller node group, created when enable_karpenter = true)
  eks_karpenter_node_instance_types  = var.eks_karpenter_node_instance_types
  eks_karpenter_node_min_size        = var.eks_karpenter_node_min_size
  eks_karpenter_node_max_size        = var.eks_karpenter_node_max_size
  eks_karpenter_node_desired_size    = var.eks_karpenter_node_desired_size
  eks_karpenter_node_disk_size       = var.eks_karpenter_node_disk_size
  eks_admin_karpenter_instance_types = var.eks_admin_karpenter_instance_types

  # Karpenter Helm chart
  karpenter_chart_version = var.eks_karpenter_chart_version
  karpenter_helm_username = var.eks_karpenter_helm_username
  karpenter_helm_password = var.eks_karpenter_helm_password
  karpenter_extra_tags    = var.eks_karpenter_extra_tags
}

module "comet_elasticache" {
  source      = "./modules/comet_elasticache"
  count       = var.enable_elasticache ? 1 : 0
  environment = var.environment
  common_tags = local.all_tags

  vpc_id                      = var.enable_vpc ? module.comet_vpc[0].vpc_id : var.comet_vpc_id
  elasticache_private_subnets = var.enable_vpc ? module.comet_vpc[0].private_subnets : var.comet_private_subnets
  elasticache_allow_from_sg = var.enable_ec2 ? module.comet_ec2[0].comet_ec2_sg_id : (
    var.enable_eks ? module.comet_eks[0].nodegroup_sg_id : (
  var.elasticache_allow_from_sg))
  elasticache_engine                      = var.elasticache_engine
  elasticache_engine_version              = var.elasticache_engine_version
  elasticache_instance_type               = var.elasticache_instance_type
  elasticache_param_group_name            = var.elasticache_param_group_name
  elasticache_num_cache_nodes             = var.elasticache_num_cache_nodes
  elasticache_transit_encryption          = var.elasticache_transit_encryption
  elasticache_auth_token                  = var.elasticache_auth_token
  elasticache_automatic_failover_enabled  = var.elasticache_automatic_failover_enabled
  elasticache_multi_az_enabled            = var.elasticache_multi_az_enabled
  elasticache_preferred_cache_cluster_azs = var.elasticache_preferred_cache_cluster_azs
}

module "comet_rds" {
  source                         = "./modules/comet_rds"
  count                          = var.enable_rds ? 1 : 0
  environment                    = coalesce(var.rds_environment, var.environment)
  rds_cluster_identifier         = var.rds_cluster_identifier
  rds_instance_identifier_prefix = var.rds_instance_identifier_prefix
  common_tags                    = local.all_tags

  availability_zones  = var.enable_vpc ? module.comet_vpc[0].azs : var.availability_zones
  vpc_id              = var.enable_vpc ? module.comet_vpc[0].vpc_id : var.comet_vpc_id
  rds_private_subnets = var.enable_vpc ? module.comet_vpc[0].private_subnets : var.comet_private_subnets
  rds_allow_from_sg = var.enable_ec2 ? module.comet_ec2[0].comet_ec2_sg_id : (
    var.enable_eks ? module.comet_eks[0].nodegroup_sg_id : (
  var.rds_allow_from_sg))
  rds_engine            = var.rds_engine
  rds_engine_version    = var.rds_engine_version
  rds_instance_type     = var.rds_instance_type
  rds_instance_count    = var.rds_instance_count
  rds_storage_encrypted = var.rds_storage_encrypted

  # Aurora Serverless v2 (optional)
  rds_serverless_v2_enabled                  = var.rds_serverless_v2_enabled
  rds_serverless_v2_min_capacity             = var.rds_serverless_v2_min_capacity
  rds_serverless_v2_max_capacity             = var.rds_serverless_v2_max_capacity
  rds_serverless_v2_seconds_until_auto_pause = var.rds_serverless_v2_seconds_until_auto_pause
  rds_iam_db_auth                            = var.rds_iam_db_auth
  rds_backup_retention_period                = var.rds_backup_retention_period
  rds_preferred_backup_window                = var.rds_preferred_backup_window
  rds_database_name                          = var.rds_database_name
  rds_master_username                        = var.rds_master_username
  rds_master_password                        = local.rds_master_password
  rds_snapshot_identifier                    = var.rds_snapshot_identifier
  rds_kms_key_id                             = var.rds_kms_key_id

  # Performance Insights and Enhanced Monitoring
  rds_performance_insights_enabled          = var.rds_performance_insights_enabled
  rds_performance_insights_retention_period = var.rds_performance_insights_retention_period
  rds_performance_insights_kms_key_id       = var.rds_performance_insights_kms_key_id
  rds_enhanced_monitoring_interval          = var.rds_enhanced_monitoring_interval

  # Deletion protection
  rds_deletion_protection = var.rds_deletion_protection

  # Storage type (aurora-iopt1 for I/O-Optimized)
  rds_storage_type = var.rds_storage_type

  # Additional MySQL cluster parameters (defaults include operational tunings)
  rds_cluster_parameters = var.rds_cluster_parameters

  # MySQL TLS enforcement (pending-reboot when flipped)
  rds_require_secure_transport = var.rds_require_secure_transport

  # Per-instance MySQL parameters (DB-instance parameter group)
  rds_db_parameters = var.rds_db_parameters
}

module "comet_rds_proxy" {
  source = "./modules/comet_rds_proxy"
  count  = var.enable_rds_proxy ? 1 : 0

  environment = var.environment
  common_tags = local.all_tags

  vpc_id     = var.enable_vpc ? module.comet_vpc[0].vpc_id : var.comet_vpc_id
  subnet_ids = var.enable_vpc ? module.comet_vpc[0].private_subnets : var.comet_private_subnets

  allowed_sg_ids = var.enable_eks ? [module.comet_eks[0].nodegroup_sg_id] : var.rds_proxy_allowed_sg_ids
  allowed_cidrs  = var.rds_proxy_allowed_cidrs

  mysql_cluster_id      = module.comet_rds[0].mysql_cluster_id
  mysql_sg_id           = module.comet_rds[0].mysql_sg_id
  mysql_master_username = var.rds_master_username
  mysql_master_password = local.rds_master_password

  require_tls                  = var.rds_proxy_require_tls
  idle_client_timeout          = var.rds_proxy_idle_client_timeout
  debug_logging                = var.rds_proxy_debug_logging
  max_connections_percent      = var.rds_proxy_max_connections_percent
  max_idle_connections_percent = var.rds_proxy_max_idle_connections_percent
  connection_borrow_timeout    = var.rds_proxy_connection_borrow_timeout

  depends_on = [module.comet_rds]
}

module "comet_s3" {
  source      = "./modules/comet_s3"
  count       = var.enable_s3 ? 1 : 0
  environment = var.environment
  common_tags = local.all_tags

  comet_s3_bucket  = var.s3_bucket_name
  s3_force_destroy = var.s3_force_destroy

  enable_mpm_infra   = var.enable_mpm_infra
  enable_loki_bucket = var.enable_loki_bucket
}

module "comet_secretsmanager" {
  source = "./modules/comet_secretsmanager"
  count  = var.enable_secretsmanager ? 1 : 0

  environment = coalesce(var.secretsmanager_environment, var.environment)
  common_tags = local.all_tags

  # Secret toggles
  enable_config_secret     = var.enable_config_secret
  enable_monitoring_secret = var.enable_monitoring_secret
  enable_clickhouse_secret = var.enable_clickhouse_secret

  # Database password (from RDS - uses provided or auto-generated password)
  mysql_password = local.rds_master_password

  # Redis configuration (from ElastiCache)
  redis_endpoint           = module.comet_elasticache[0].redis_endpoint
  redis_port               = module.comet_elasticache[0].redis_port
  redis_transit_encryption = module.comet_elasticache[0].transit_encryption_enabled
  redis_token              = var.redis_token

  # Secret seed (optional - will be auto-generated if not provided)
  secret_seed = var.secret_seed

  # SendGrid
  sendgrid_api_key = var.sendgrid_api_key

  # S3 configuration (defaults to IAM-ROLE)
  s3_key            = var.s3_key
  s3_secret         = var.s3_secret
  s3_private_key    = var.s3_private_key
  s3_private_secret = var.s3_private_secret
  s3_public_key     = var.s3_public_key
  s3_public_secret  = var.s3_public_secret

  # Monitoring secret configuration
  grafana_admin_user     = var.grafana_admin_user
  grafana_admin_password = var.grafana_admin_password

  # ClickHouse secret configuration
  clickhouse_monitoring_password = var.clickhouse_monitoring_password
  clickhouse_agentro_password    = var.clickhouse_agentro_password
  clickhouse_admin_password      = var.clickhouse_admin_password
  clickhouse_host                = var.clickhouse_host
  clickhouse_port                = var.clickhouse_port
  clickhouse_monitoring_username = var.clickhouse_monitoring_username

  depends_on = [
    module.comet_elasticache,
    module.comet_rds
  ]
}
