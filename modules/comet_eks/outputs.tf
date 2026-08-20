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
  description = "ID of the node shared security group (managed node groups attach this)"
  value       = module.eks.node_security_group_id
}

output "cluster_primary_security_group_id" {
  description = "EKS-managed cluster primary security group. EKS Auto Mode nodes attach this SG (managed node groups use nodegroup_sg_id instead) — reference it where Auto Mode nodes need network access (e.g. data-layer SG ingress)."
  value       = module.eks.cluster_primary_security_group_id
}

output "cluster_autoscaler_irsa_role_arn" {
  description = "ARN of the Cluster Autoscaler IRSA role (serviceAccountName=kube-system/cluster-autoscaler). Wire this into the cluster-autoscaler Helm values as the service account annotation."
  value       = var.eks_enable_cluster_autoscaler ? module.cluster_autoscaler_irsa_role[0].iam_role_arn : null
}

# AWS Load Balancer Controller — installed per customer via ArgoCD (comet-gitops).
# Consume these in the ArgoCD Application / Helm values: annotate the controller
# ServiceAccount with the role ARN, and set clusterName / region / vpcId from the
# cluster facts below. The SA's <namespace>:<name> must be trusted by the role —
# see var.aws_load_balancer_controller_namespace_service_accounts (default
# kube-system:aws-load-balancer-controller; comet-system:<release>-aws-load-balancer-controller
# when folded into the comet-infra umbrella).
output "aws_load_balancer_controller_irsa_role_arn" {
  description = "ARN of the AWS Load Balancer Controller IRSA role. Annotate the controller ServiceAccount with this (serviceAccount.annotations.\"eks.amazonaws.com/role-arn\") in the ArgoCD-managed Helm values. The SA's <namespace>:<name> must be listed in aws_load_balancer_controller_namespace_service_accounts (the role's OIDC trust)."
  value       = var.eks_aws_load_balancer_controller ? module.aws_load_balancer_controller_irsa_role[0].iam_role_arn : null
}

output "aws_load_balancer_controller_irsa_role_name" {
  description = "Name of the AWS Load Balancer Controller IRSA role."
  value       = var.eks_aws_load_balancer_controller ? module.aws_load_balancer_controller_irsa_role[0].iam_role_name : null
}

# Cluster facts for the ArgoCD-managed controllers (ALB controller Helm values need
# clusterName + region + vpcId).
output "cluster_region" {
  description = "AWS region of the EKS cluster (for controller Helm values, e.g. aws-load-balancer-controller region)."
  value       = var.region
}

output "cluster_vpc_id" {
  description = "VPC ID of the EKS cluster (for controller Helm values, e.g. aws-load-balancer-controller vpcId)."
  value       = var.vpc_id
}

output "cluster_autoscaler_irsa_role_name" {
  description = "Name of the Cluster Autoscaler IRSA role"
  value       = var.eks_enable_cluster_autoscaler ? module.cluster_autoscaler_irsa_role[0].iam_role_name : null
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

output "loki_irsa_role_arn" {
  description = "ARN of the Loki IRSA role for S3 access"
  value       = var.enable_loki ? module.loki_irsa_role[0].iam_role_arn : null
}

output "loki_irsa_role_name" {
  description = "Name of the Loki IRSA role"
  value       = var.enable_loki ? module.loki_irsa_role[0].iam_role_name : null
}

output "cloudwatch_exporter_irsa_role_arn" {
  description = "ARN of the CloudWatch Exporter IRSA role"
  value       = var.enable_cloudwatch_exporter ? module.cloudwatch_exporter_irsa_role[0].iam_role_arn : null
}

output "cloudwatch_exporter_irsa_role_name" {
  description = "Name of the CloudWatch Exporter IRSA role"
  value       = var.enable_cloudwatch_exporter ? module.cloudwatch_exporter_irsa_role[0].iam_role_name : null
}

output "karpenter_irsa_role_arn" {
  description = "ARN of the Karpenter controller IRSA role"
  value       = var.enable_karpenter ? module.karpenter_irsa[0].iam_role_arn : null
}

output "karpenter_node_role_arn" {
  description = "ARN of the IAM role for Karpenter-provisioned nodes"
  value       = var.enable_karpenter ? aws_iam_role.karpenter_node[0].arn : null
}

output "karpenter_node_instance_profile_name" {
  description = "Name of the EC2 instance profile for Karpenter-provisioned nodes (used in EC2NodeClass)"
  value       = var.enable_karpenter ? aws_iam_instance_profile.karpenter_node[0].name : null
}

output "karpenter_interruption_queue_name" {
  description = "Name of the SQS queue for Karpenter spot interruption handling (used in Karpenter Helm values)"
  value       = var.enable_karpenter ? aws_sqs_queue.karpenter_interruption[0].name : null
}

output "karpenter_interruption_queue_url" {
  description = "URL of the SQS queue for Karpenter spot interruption handling"
  value       = var.enable_karpenter ? aws_sqs_queue.karpenter_interruption[0].url : null
}
