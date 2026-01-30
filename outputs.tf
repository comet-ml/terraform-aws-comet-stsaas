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
  description = "MySQL cluster (writer) endpoint for the RDS instance"
  value       = var.enable_rds ? module.comet_rds[0].mysql_host : null
}

output "mysql_reader_host" {
  description = "MySQL cluster reader endpoint for the RDS instance"
  value       = var.enable_rds ? module.comet_rds[0].mysql_reader_host : null
}

output "mysql_port" {
  description = "MySQL port"
  value       = var.enable_rds ? module.comet_rds[0].mysql_port : null
}

output "mysql_database_name" {
  description = "MySQL database name"
  value       = var.enable_rds ? module.comet_rds[0].mysql_database_name : null
}

output "rds_password_auto_generated" {
  description = "Whether the RDS master password was auto-generated (true) or provided explicitly (false)"
  value       = var.enable_rds ? var.rds_master_password == null : null
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