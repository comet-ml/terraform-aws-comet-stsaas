output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "nodegroup_sg_id" {
  description = "ID of the node shared security group"
  value       = module.eks.node_security_group_id
}

output "external_secrets_irsa_role_arn" {
  description = "ARN of the External Secrets IRSA role"
  value       = var.enable_external_secrets ? module.external_secrets_irsa_role[0].iam_role_arn : null
}

output "external_secrets_irsa_role_name" {
  description = "Name of the External Secrets IRSA role"
  value       = var.enable_external_secrets ? module.external_secrets_irsa_role[0].iam_role_name : null
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for the EKS cluster"
  value       = module.eks.oidc_provider_arn
}