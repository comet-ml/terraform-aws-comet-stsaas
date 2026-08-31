output "region" {
  description = "Region resources are provisioned in"
  value       = var.region
}

output "comet_ec2_instance" {
  description = "ID of the Comet EC2 instance"
  value       = var.enable_ec2 ? module.comet_ec2[0].comet_ec2_instance_id : null
}

output "comet_ec2_public_ip" {
  description = "EIP associated with the Comet EC2 instance"
  value       = var.enable_ec2 ? module.comet_ec2[0].comet_ec2_public_ip : null
}

output "comet_alb_dns_name" {
  description = "DNS name of the ALB fronting the Comet EC2 instance"
  value       = var.enable_ec2_alb ? module.comet_ec2_alb[0].alb_dns_name : null
}

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate created for the environment"
  value       = var.enable_acm_certificate ? aws_acm_certificate.main[0].arn : null
}

output "acm_certificate_domain_name" {
  description = "Domain name of the ACM certificate"
  value       = var.enable_acm_certificate ? aws_acm_certificate.main[0].domain_name : null
}

output "acm_certificate_status" {
  description = "Status of the ACM certificate"
  value       = var.enable_acm_certificate ? aws_acm_certificate.main[0].status : null
}

output "mysql_host" {
  description = "MySQL writer endpoint clients should connect to. The RDS Proxy endpoint when rds_use_proxy_endpoint = true, otherwise the Aurora cluster writer endpoint. Feed this into the Helm mysql host value."
  value = var.enable_rds ? (
    local.rds_proxy_endpoint_in_use ? module.comet_rds_proxy[0].proxy_endpoint : module.comet_rds[0].mysql_host
  ) : null
}

# Deliberately NOT proxy-backed: the proxy created here is writer-only (no
# aws_db_proxy_endpoint with target_role = READ_ONLY), so pointing readers at it
# would silently send read traffic to the writer. Reads stay on the Aurora RO
# endpoint until a read-only proxy endpoint exists.
output "mysql_reader_host" {
  description = "MySQL cluster reader endpoint. Always the Aurora reader endpoint — the RDS Proxy is writer-only, so this is never swapped to the proxy."
  value       = var.enable_rds ? module.comet_rds[0].mysql_reader_host : null
}

output "mysql_proxy_endpoint" {
  description = "RDS Proxy endpoint, or null when the proxy is disabled. Exposed independently of rds_use_proxy_endpoint so the proxy can be provisioned and tested before cutting traffic over."
  value       = local.rds_proxy_provisioned ? module.comet_rds_proxy[0].proxy_endpoint : null
}

# null rather than false when there is no RDS at all, so it matches mysql_host and
# the other mysql_* outputs — false would claim "connect to the cluster writer"
# while mysql_host is null and there is no writer to connect to.
output "mysql_proxy_in_use" {
  description = "Whether mysql_host resolves to the RDS Proxy (true) or the Aurora cluster writer endpoint (false). Null when enable_rds is false, matching mysql_host."
  value       = var.enable_rds ? local.rds_proxy_endpoint_in_use : null
}

output "mysql_port" {
  description = "MySQL port"
  value       = var.enable_rds ? module.comet_rds[0].mysql_port : null
}

output "mysql_database_name" {
  description = "MySQL database name"
  value       = var.enable_rds ? module.comet_rds[0].mysql_database_name : null
}

output "mysql_sg_id" {
  description = "Security group ID of the MySQL (Aurora) cluster — wrappers add ingress rules to this instead of looking it up by name (DND-1522)"
  value       = var.enable_rds ? module.comet_rds[0].mysql_sg_id : null
}

output "mysql_log_group_names" {
  description = "CloudWatch log group names for the RDS log groups this module MANAGES, keyed by log type. Superset of what is actively exported — cross-reference mysql_exported_log_types. Needed to build the terraform import address when adopting a cluster whose export was enabled out-of-band (DND-1537)."
  value       = var.enable_rds ? module.comet_rds[0].mysql_log_group_names : null
}

output "mysql_log_group_arns" {
  description = "CloudWatch log group ARNs for the RDS log groups this module MANAGES, keyed by log type. Superset of what is actively exported — filter by mysql_exported_log_types before attaching metric filters, subscription filters or alarms, or you will target a group nothing writes to."
  value       = var.enable_rds ? module.comet_rds[0].mysql_log_group_arns : null
}

output "mysql_exported_log_types" {
  description = "MySQL log types the cluster is actively exporting. Subset of the keys in mysql_log_group_names / mysql_log_group_arns. A type can be exported and still produce nothing — 'slowquery' stays empty until slow_query_log=1 is set via rds_cluster_parameters."
  value       = var.enable_rds ? module.comet_rds[0].mysql_exported_log_types : null
}

output "rds_password_auto_generated" {
  description = "Whether the RDS master password was auto-generated (true) or provided explicitly (false)"
  value       = var.enable_rds ? nonsensitive(var.rds_master_password == null) : null
}

output "redis_sg_id" {
  description = "Security group ID of the Redis (ElastiCache) replication group — wrappers add ingress rules to this instead of looking it up by name (DND-1522)"
  value       = var.enable_elasticache ? module.comet_elasticache[0].redis_sg_id : null
}

output "configure_kubectl" {
  description = "Configure kubectl: run the following command to update your kubeconfig with the newly provisioned cluster."
  value       = var.enable_eks ? "aws eks update-kubeconfig --region ${var.region} --name ${module.comet_eks[0].cluster_name}" : null
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = try(module.comet_eks[0].cluster_name, null)
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = try(module.comet_eks[0].cluster_endpoint, null)
}

output "eks_cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for the EKS cluster"
  value       = try(module.comet_eks[0].cluster_certificate_authority_data, null)
  sensitive   = true
}

# Deprecated: Use eks_cluster_endpoint instead
output "comet_eks_endpoint" {
  description = "EKS cluster endpoint (deprecated: use eks_cluster_endpoint)"
  value       = var.enable_eks ? module.comet_eks[0].cluster_endpoint : null
  sensitive   = true
}

# Deprecated: Use eks_cluster_certificate_authority_data instead
output "comet_eks_cert" {
  description = "EKS cluster cert (deprecated: use eks_cluster_certificate_authority_data)"
  value       = var.enable_eks ? base64decode(module.comet_eks[0].cluster_certificate_authority_data) : null
  sensitive   = true
}

output "comet_config_secret_arn" {
  description = "ARN of the Comet config Secrets Manager secret"
  value       = var.enable_secretsmanager ? module.comet_secretsmanager[0].config_secret_arn : null
}

output "comet_config_secret_name" {
  description = "Name of the Comet config Secrets Manager secret"
  value       = var.enable_secretsmanager ? module.comet_secretsmanager[0].config_secret_name : null
}

output "comet_monitoring_secret_arn" {
  description = "ARN of the Comet monitoring Secrets Manager secret"
  value       = var.enable_secretsmanager ? module.comet_secretsmanager[0].monitoring_secret_arn : null
}

output "comet_monitoring_secret_name" {
  description = "Name of the Comet monitoring Secrets Manager secret"
  value       = var.enable_secretsmanager ? module.comet_secretsmanager[0].monitoring_secret_name : null
}

output "comet_clickhouse_secret_arn" {
  description = "ARN of the Comet ClickHouse Secrets Manager secret"
  value       = var.enable_secretsmanager ? module.comet_secretsmanager[0].clickhouse_secret_arn : null
}

output "comet_clickhouse_secret_name" {
  description = "Name of the Comet ClickHouse Secrets Manager secret"
  value       = var.enable_secretsmanager ? module.comet_secretsmanager[0].clickhouse_secret_name : null
}

output "cluster_autoscaler_irsa_role_arn" {
  description = "ARN of the Cluster Autoscaler IRSA role (bind to kube-system/cluster-autoscaler service account)"
  value       = var.enable_eks && var.eks_enable_cluster_autoscaler ? module.comet_eks[0].cluster_autoscaler_irsa_role_arn : null
}

output "cluster_autoscaler_irsa_role_name" {
  description = "Name of the Cluster Autoscaler IRSA role"
  value       = var.enable_eks && var.eks_enable_cluster_autoscaler ? module.comet_eks[0].cluster_autoscaler_irsa_role_name : null
}

# AWS Load Balancer Controller — deployed per stsaas customer via ArgoCD (comet-gitops).
# Feed these into the customer's ArgoCD Application / Helm values.
output "aws_load_balancer_controller_irsa_role_arn" {
  description = "ARN of the AWS Load Balancer Controller IRSA role. Annotate the controller ServiceAccount with this in the ArgoCD-managed Helm values. The SA's <namespace>:<name> must be listed in aws_load_balancer_controller_namespace_service_accounts (the role's OIDC trust) — default kube-system:aws-load-balancer-controller, or the comet-system umbrella subject when folded."
  value       = var.enable_eks && var.eks_aws_load_balancer_controller ? module.comet_eks[0].aws_load_balancer_controller_irsa_role_arn : null
}

output "aws_load_balancer_controller_irsa_role_name" {
  description = "Name of the AWS Load Balancer Controller IRSA role"
  value       = var.enable_eks && var.eks_aws_load_balancer_controller ? module.comet_eks[0].aws_load_balancer_controller_irsa_role_name : null
}

output "eks_cluster_region" {
  description = "AWS region of the EKS cluster (for ArgoCD-managed controller Helm values, e.g. aws-load-balancer-controller region)"
  value       = var.enable_eks ? module.comet_eks[0].cluster_region : null
}

output "eks_cluster_vpc_id" {
  description = "VPC ID of the EKS cluster (for ArgoCD-managed controller Helm values, e.g. aws-load-balancer-controller vpcId)"
  value       = var.enable_eks ? module.comet_eks[0].cluster_vpc_id : null
}

output "external_secrets_irsa_role_arn" {
  description = "ARN of the External Secrets IRSA role for accessing AWS Secrets Manager"
  value       = var.enable_eks && var.eks_enable_external_secrets ? module.comet_eks[0].external_secrets_irsa_role_arn : null
}

output "external_secrets_irsa_role_name" {
  description = "Name of the External Secrets IRSA role"
  value       = var.enable_eks && var.eks_enable_external_secrets ? module.comet_eks[0].external_secrets_irsa_role_name : null
}

output "comet_loki_bucket_name" {
  description = "Name of the Loki S3 bucket"
  value       = var.enable_s3 && var.enable_loki_bucket ? module.comet_s3[0].comet_loki_bucket_name : null
}

output "comet_loki_bucket_arn" {
  description = "ARN of the Loki S3 bucket"
  value       = var.enable_s3 && var.enable_loki_bucket ? module.comet_s3[0].comet_loki_bucket_arn : null
}

output "loki_irsa_role_arn" {
  description = "ARN of the Loki IRSA role for S3 access"
  value       = var.enable_eks && var.enable_loki_bucket ? module.comet_eks[0].loki_irsa_role_arn : null
}

output "loki_irsa_role_name" {
  description = "Name of the Loki IRSA role"
  value       = var.enable_eks && var.enable_loki_bucket ? module.comet_eks[0].loki_irsa_role_name : null
}

output "cloudwatch_exporter_irsa_role_arn" {
  description = "ARN of the CloudWatch Exporter IRSA role"
  value       = var.enable_eks && var.enable_cloudwatch_exporter ? module.comet_eks[0].cloudwatch_exporter_irsa_role_arn : null
}

output "cloudwatch_exporter_irsa_role_name" {
  description = "Name of the CloudWatch Exporter IRSA role"
  value       = var.enable_eks && var.enable_cloudwatch_exporter ? module.comet_eks[0].cloudwatch_exporter_irsa_role_name : null
}

output "karpenter_irsa_role_arn" {
  description = "ARN of the Karpenter controller IRSA role — annotate the karpenter ServiceAccount with this"
  value       = var.enable_eks && var.eks_enable_karpenter ? module.comet_eks[0].karpenter_irsa_role_arn : null
}

output "karpenter_node_role_arn" {
  description = "ARN of the IAM role for Karpenter-provisioned nodes"
  value       = var.enable_eks && var.eks_enable_karpenter ? module.comet_eks[0].karpenter_node_role_arn : null
}

output "karpenter_node_instance_profile_name" {
  description = "Name of the EC2 instance profile for Karpenter-provisioned nodes — set in EC2NodeClass .spec.instanceProfile"
  value       = var.enable_eks && var.eks_enable_karpenter ? module.comet_eks[0].karpenter_node_instance_profile_name : null
}

output "karpenter_interruption_queue_name" {
  description = "Name of the SQS queue for Karpenter interruption handling — set in Karpenter Helm values .settings.interruptionQueue"
  value       = var.enable_eks && var.eks_enable_karpenter ? module.comet_eks[0].karpenter_interruption_queue_name : null
}
