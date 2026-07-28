########################
#### Module toggles ####
########################
variable "enable_vpc" {
  description = "Toggles the comet_vpc module, to provision a new VPC for hosting the Comet resources"
  type        = bool
}

variable "enable_ec2" {
  description = "Toggles the comet_ec2 module, to provision EC2 resources for running Comet"
  type        = bool
  default     = false
}

variable "enable_ec2_alb" {
  description = "Toggles the comet_ec2_alb module, to provision an ALB in front of the EC2 instance"
  type        = bool
}

variable "enable_eks" {
  description = "Toggles the comet_eks module, to provision EKS resources for running Comet"
  type        = bool
}

variable "enable_elasticache" {
  description = "Toggles the comet_elasticache module for provisioning Comet Redis on elasticache"
  type        = bool
}

variable "enable_rds" {
  description = "Toggles the comet_rds module for provisioning Comet RDS database"
  type        = bool
}

variable "enable_s3" {
  description = "Toggles the comet_s3 module for provisioning Comet S3 bucket"
  type        = bool
}

variable "enable_mpm_infra" {
  description = "Creates S3 buckets for MPM Druid/Airflow workloads (used by comet_s3 module)"
  type        = bool
  default     = false
}

variable "enable_loki_bucket" {
  description = "Enable creation of S3 bucket for Loki logs (used by comet_s3 module)"
  type        = bool
  default     = true
}

# Name overrides for resources whose identity downstream consumers depend on.
# Default null keeps the computed name; set to adopt an existing differently-named
# resource (e.g. a legacy hand-rolled "zoox-loki") by import/state-mv rather than
# recreating it (bucket recreation = log loss; IRSA role recreation = broken SA
# annotation). Backward-compatible: existing envs leave these null.
variable "loki_bucket_name_override" {
  description = "Override the Loki S3 bucket name. Null keeps the module-computed comet-loki-<environment>-<suffix> name."
  type        = string
  default     = null
  validation {
    # Null = unset. Otherwise enforce S3 bucket naming (3-63 chars, lowercase
    # alphanumerics/'.'/'-', start+end alphanumeric) so a malformed override fails
    # at plan time, not mid-apply in aws_s3_bucket.
    condition     = var.loki_bucket_name_override == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.loki_bucket_name_override))
    error_message = "loki_bucket_name_override must be a valid S3 bucket name: 3-63 chars, lowercase letters/digits/'.'/'-', starting and ending alphanumeric."
  }
}

variable "loki_iam_role_name_override" {
  description = "Override the Loki IRSA role name. Null keeps the computed <environment>-loki name."
  type        = string
  default     = null
  validation {
    condition     = var.loki_iam_role_name_override == null || can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.loki_iam_role_name_override))
    error_message = "loki_iam_role_name_override must be a valid IAM role name: 1-64 chars from [a-zA-Z0-9+=,.@_-]."
  }
}

# DND-1423: Bring-your-own-S3 IRSA roles (see modules/comet_eks/variables.tf for
# the full schema). Empty by default => feature off. Set an entry per customer
# BYO bucket that pods must reach via IRSA (e.g. ClickHouse remote backups).
variable "byo_s3_irsa_roles" {
  description = "Map of bring-your-own-S3 IRSA roles. Each entry grants listed Kubernetes ServiceAccounts (via IRSA) scoped access to a customer-supplied S3 bucket. Empty by default."
  type = map(object({
    bucket_arns                = list(string)
    namespace_service_accounts = list(string)
    actions                    = optional(list(string))
    role_name_override         = optional(string)
    policy_name_override       = optional(string)
  }))
  default = {}
}

variable "external_secrets_iam_role_name_override" {
  description = "Override the External Secrets IRSA role name. Null keeps the computed <environment>-external-secrets name."
  type        = string
  default     = null
  validation {
    condition     = var.external_secrets_iam_role_name_override == null || can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.external_secrets_iam_role_name_override))
    error_message = "external_secrets_iam_role_name_override must be a valid IAM role name: 1-64 chars from [a-zA-Z0-9+=,.@_-]."
  }
}

variable "cloudwatch_exporter_iam_role_name_override" {
  description = "Override the CloudWatch Exporter IRSA role name. Null keeps the computed <environment>-cloudwatch-exporter name."
  type        = string
  default     = null
  validation {
    condition     = var.cloudwatch_exporter_iam_role_name_override == null || can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.cloudwatch_exporter_iam_role_name_override))
    error_message = "cloudwatch_exporter_iam_role_name_override must be a valid IAM role name: 1-64 chars from [a-zA-Z0-9+=,.@_-]."
  }
}

variable "eks_enable_karpenter" {
  description = "Enable Karpenter prerequisites in the EKS module: discovery tags, SQS interruption queue, EventBridge rules, node IAM role/instance profile, and controller IRSA role"
  type        = bool
  default     = false
}

variable "eks_enable_auto_mode" {
  description = "Enable EKS Auto Mode: the control plane provisions nodes natively via the built-in node pools (see eks_auto_mode_node_pools). Coexists with managed node groups — enabled MNGs keep running and Auto Mode adds elastic capacity alongside them. Mutually exclusive with eks_enable_karpenter. Auto Mode also provides block storage / load balancing / networking natively — see docs/auto-mode-migration-plan.md before removing the EBS CSI role, ALB controller, or gp3 StorageClass."
  type        = bool
  default     = false
}

variable "eks_auto_mode_node_pools" {
  description = "Built-in EKS Auto Mode node pools to enable when eks_enable_auto_mode = true. Common values: \"system\", \"general-purpose\". Custom NodePool/NodeClass CRDs are managed via GitOps (ArgoCD), not this module."
  type        = list(string)
  default     = ["system", "general-purpose"]
}

variable "eks_karpenter_via_helm_release" {
  description = <<-EOT
    When true, install the Karpenter Helm chart via an in-module helm_release.
    When false (default), skip the helm_release and assume Karpenter is deployed
    externally (e.g., ArgoCD). AWS-side prerequisites (IRSA, SQS, instance
    profile, discovery tags) are created either way.

    MIGRATION SAFETY: flipping true to false on a customer where the in-module
    helm_release is currently in TF state will run `helm uninstall` on the next
    apply, DELETING the Karpenter controller — autoscaling stops. Before
    flipping, either adopt via ArgoCD or `terraform state rm` the helm_release.
    See the comet_eks sub-module variable docs for the full migration sequence.
  EOT
  type        = bool
  default     = false
}

variable "enable_cloudwatch_exporter" {
  description = "Enable CloudWatch Exporter IRSA role for scraping ElastiCache, RDS, and other AWS managed service metrics (used by comet_eks module)"
  type        = bool
  default     = false
}

variable "enable_monitoring_setup" {
  description = "Enable monitoring namespace and Grafana credentials secret in EKS (used by comet_eks module)"
  type        = bool
  default     = true
}

variable "manage_monitoring_secret" {
  description = "When true (default), Terraform manages the monitoring Grafana credentials Secret. Set false when External Secrets Operator owns it (ExternalSecret with creationPolicy: Owner). Only applies when enable_monitoring_setup = true."
  type        = bool
  default     = true
}

variable "monitoring_namespace" {
  description = "Kubernetes namespace for monitoring resources"
  type        = string
  default     = "monitoring"
}

variable "enable_secretsmanager" {
  description = "Toggles the comet_secretsmanager module for provisioning Comet Secrets Manager secrets. Requires enable_rds and enable_elasticache to be true."
  type        = bool
  default     = true
}

variable "enable_config_secret" {
  description = "Enable creation of the config secret (cometml/{environment}/config)"
  type        = bool
  default     = true
}

variable "enable_monitoring_secret" {
  description = "Enable creation of the monitoring-secrets secret (cometml/{environment}/monitoring-secrets)"
  type        = bool
  default     = true
}

variable "enable_clickhouse_secret" {
  description = "Enable creation of the clickhouse secret (cometml/{environment}/clickhouse)"
  type        = bool
  default     = true
}

################
#### Global ####
################
variable "environment" {
  description = "Deployment environment, i.e. dev/stage/prod, etc"
  type        = string
  default     = "dev"
}

variable "secretsmanager_environment" {
  description = "Environment name used for Secrets Manager secret paths (e.g., cometml/{secretsmanager_environment}/config). Defaults to 'environment' if not set. Useful for multi-region deployments where infrastructure names include region but secrets should be region-agnostic."
  type        = string
  default     = null
}

variable "comet_hostname" {
  description = "Hostname prefix for the Comet deployment (e.g., 'mercedesamgf1' results in 'mercedesamgf1.comet-hosted.com'). Defaults to 'environment' if not set. Useful for multi-region deployments where infrastructure names include region but hostnames should be region-agnostic."
  type        = string
  default     = null
}

variable "rds_environment" {
  description = "Override environment name for RDS resource naming. When null, falls back to var.environment. Use this when the environment was shortened but RDS resources were originally created with a longer name."
  type        = string
  default     = null
}

variable "rds_cluster_identifier" {
  description = "Override for the RDS cluster identifier. When null, uses the default pattern. Use this when the cluster was created with a different naming convention than the current module version."
  type        = string
  default     = null
}

variable "rds_instance_identifier_prefix" {
  description = "Override prefix for RDS instance identifiers. When null, uses the default pattern. Instance index is appended automatically."
  type        = string
  default     = null
}

variable "region" {
  description = "AWS region to provision resources in"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones from region"
  type        = list(string)
  default     = null
}

variable "comet_vpc_id" {
  description = "ID of an existing VPC to provision resources in"
  type        = string
  default     = null
}

variable "comet_private_subnets" {
  description = "List of private subnets IDs from existing VPC to provision resources in"
  type        = list(string)
  default     = null
}

variable "comet_public_subnets" {
  description = "List of public subnets IDs from existing VPC to provision resources in"
  type        = list(string)
  default     = null
}

#######################
#### Module inputs ####
#######################

#### comet_vpc ####
variable "vpc_cidr" {
  description = "CIDR block for the VPC to provision"
  type        = string
  default     = "10.0.0.0/16"
}

#### comet_ec2 ####
variable "comet_ec2_ami_type" {
  type        = string
  description = "Operating system type for the EC2 instance AMI"
  default     = "ubuntu22"
  validation {
    condition     = can(regex("^al2$|^al2023$|^rhel(7|8|9)$|^ubuntu(18|20|22)$", var.comet_ec2_ami_type))
    error_message = "Invalid OS type. Allowed values are 'al2', 'al2023', 'rhel7', 'rhel8', 'rhel9', 'ubuntu20', 'ubuntu22'."
  }
}

variable "comet_ec2_ami_id" {
  description = "AMI ID for the EC2 instance"
  type        = string
  default     = ""
}

variable "comet_ec2_instance_type" {
  description = "Instance type for the EC2 instance"
  type        = string
  default     = "m7i.4xlarge"
}

variable "comet_ec2_instance_count" {
  description = "Number of EC2 instances to provision"
  type        = number
  default     = 1
}

variable "comet_ec2_volume_type" {
  description = "EBS volume type for the EC2 instance root volume"
  type        = string
  default     = "gp3"
}

variable "comet_ec2_volume_size" {
  description = "Size, in gibibytes (GiB), for the EC2 instance root volume"
  type        = number
  default     = 1024
}

variable "comet_ec2_key" {
  description = "Name of the SSH key to configure on the EC2 instance"
  type        = string
  default     = null
}

#### ACM Certificate ####
variable "enable_acm_certificate" {
  description = "Enable creation of an ACM certificate for {environment}.comet-hosted.com and *.{environment}.comet-hosted.com"
  type        = bool
  default     = false
}

variable "acm_domain_name" {
  description = "Base domain name for the ACM certificate. Defaults to '{comet_hostname}.comet-hosted.com'"
  type        = string
  default     = null
}

variable "acm_route53_zone_id" {
  description = "Route 53 hosted zone ID for DNS validation. Required when enable_acm_certificate is true."
  type        = string
  default     = null
}

variable "acm_wait_for_validation" {
  description = "Whether to wait for the certificate to be validated before completing"
  type        = bool
  default     = true
}

#### comet_ec2_alb ####
variable "ssl_certificate_arn" {
  description = "ARN of the ACM certificate to use for the ALB. If enable_acm_certificate is true and this is not set, the created certificate will be used."
  type        = string
  default     = null
}

#### comet_eks ####
variable "eks_cluster_name" {
  description = "Name for EKS cluster"
  type        = string
  default     = "comet-eks"
}

variable "eks_cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  type        = string
  default     = "1.34"
}

variable "eks_cluster_endpoint_public_access" {
  description = "Enable public access to the EKS cluster API endpoint"
  type        = bool
  default     = true
}

variable "eks_cluster_deletion_protection" {
  description = "Enable EKS cluster deletion protection. When true, the cluster cannot be deleted via the AWS API until protection is disabled. Requires upstream eks/aws module v21.1.0+."
  type        = bool
  default     = true
}

variable "eks_cluster_endpoint_private_access" {
  description = "Enable private access to the EKS cluster API endpoint"
  type        = bool
  default     = false
}

variable "eks_cluster_security_group_additional_rules" {
  description = "Additional security group rules for the EKS cluster security group (e.g., for VPN access)"
  type        = any
  default     = {}
}

variable "eks_private_access_cidrs" {
  description = "List of CIDR blocks that can access the EKS API via private endpoint (e.g., VPN subnets). Only applied when private endpoint access is enabled."
  type        = list(string)
  default     = []
}

variable "eks_authentication_mode" {
  description = "Authentication mode for the EKS cluster. Valid values: CONFIG_MAP, API, API_AND_CONFIG_MAP"
  type        = string
  default     = "API_AND_CONFIG_MAP"

  validation {
    condition     = contains(["CONFIG_MAP", "API", "API_AND_CONFIG_MAP"], var.eks_authentication_mode)
    error_message = "Authentication mode must be CONFIG_MAP, API, API_AND_CONFIG_MAP."
  }
}

variable "eks_enable_cluster_creator_admin_permissions" {
  description = "Grant the cluster creator admin permissions via EKS access entry"
  type        = bool
  default     = true
}

variable "eks_admin_role_arns" {
  description = "List of IAM role ARNs to grant AmazonEKSClusterAdminPolicy via EKS Access Entries"
  type        = list(string)
  default     = []
}

variable "eks_kms_key_administrators" {
  description = "List of IAM ARNs (users/roles) that should have administrator access to the EKS KMS key. These principals can manage the key (update, delete, etc.)."
  type        = list(string)
  default     = []
}

variable "eks_kms_key_users" {
  description = "List of IAM ARNs (users/roles) that should have usage access to the EKS KMS key. These principals can use the key for encryption/decryption operations."
  type        = list(string)
  default     = []
}

variable "eks_mng_ami_type" {
  description = "AMI family to use for the EKS nodes (default for all nodegroups). Ignored if eks_mng_ami_id is set."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "eks_admin_ami_type" {
  description = "AMI type override for admin nodegroup. Null uses the default (eks_mng_ami_type)."
  type        = string
  default     = null
}

variable "eks_comet_ami_type" {
  description = "AMI type override for comet nodegroup. Set to AL2023_ARM_64_STANDARD for Graviton."
  type        = string
  default     = null
}

variable "eks_clickhouse_ami_type" {
  description = "AMI type override for ClickHouse nodegroup. Null uses the default (eks_mng_ami_type)."
  type        = string
  default     = null
}

variable "eks_mng_ami_id" {
  description = "Specific AMI ID to use for all EKS node groups (e.g., ami-0123456789abcdef0). If set, overrides eks_mng_ami_type."
  type        = string
  default     = null
}

variable "eks_mng_force_update_version" {
  description = "Force EKS managed node group version updates to bypass the eviction API's PDB check. Default false (PDB-respecting) — appropriate for HA STSaaS deployments. Set to true on right-sized non-HA envs (e.g. UAT canaries with single-replica deployments) where PDBs structurally block any voluntary eviction. terminationGracePeriodSeconds is still honored either way."
  type        = bool
  default     = false
}

variable "eks_mng_use_latest_ami_release_version" {
  description = "When true (default), EKS managed node groups track the latest AMI release for their ami_type, so terraform bumps release_version on every apply (rolling the nodes). Set false to leave release_version AWS-managed (no AMI bump on apply), so AMI rolls can be scheduled separately from other terraform changes (e.g. during a state consolidation that must not touch workloads)."
  type        = bool
  default     = true
}

variable "eks_mng_pin_launch_template_version" {
  description = "When false (default), node groups track the latest launch-template version, so any LT change rolls the nodes. Set true to track \"$Default\" and stop auto-promoting new LT versions to default, so benign LT changes (e.g. tag-only version bumps) do NOT roll the nodes. Trade-off: deliberate LT changes (AMI/instance type) then require a separate default-version bump to take effect. Useful for workload-neutral applies (e.g. a state consolidation)."
  type        = bool
  default     = false
}

# Node Group Toggles
variable "eks_enable_admin_node_group" {
  description = "Enable admin node group for EKS cluster management tasks"
  type        = bool
  default     = true
}

variable "eks_enable_comet_node_group" {
  description = "Enable comet node group for main Comet application workloads"
  type        = bool
  default     = true
}

variable "eks_enable_druid_node_group" {
  description = "Enable druid node group for Apache Druid workloads (requires enable_mpm_infra to be true)"
  type        = bool
  default     = true
}

variable "eks_enable_airflow_node_group" {
  description = "Enable airflow node group for Apache Airflow workloads (requires enable_mpm_infra to be true)"
  type        = bool
  default     = true
}

variable "eks_enable_clickhouse_node_group" {
  description = "Enable dedicated ClickHouse node group"
  type        = bool
  default     = true
}

# Admin Node Group Variables
variable "eks_admin_name" {
  description = "Name for the admin node group"
  type        = string
  default     = "admin"
}

variable "eks_admin_instance_types" {
  description = "Instance types for admin node group"
  type        = list(string)
  default     = ["t3.large"]
}

variable "eks_admin_min_size" {
  description = "Minimum number of nodes in admin node group"
  type        = number
  default     = 1
}

variable "eks_admin_max_size" {
  description = "Maximum number of nodes in admin node group"
  type        = number
  default     = 3
}

variable "eks_admin_desired_size" {
  description = "Desired number of nodes in admin node group"
  type        = number
  default     = 2
}

# Comet Node Group Variables
variable "eks_comet_name" {
  description = "Name for the comet node group"
  type        = string
  default     = "comet"
}

variable "eks_comet_use_name_prefix" {
  description = "Whether to treat eks_comet_name as a prefix (true, AWS appends a unique suffix) or as the exact node group name (false). Set false to adopt an existing comet node group whose name is fixed (e.g. a single-AZ 'comet-az2b' created out-of-band)."
  type        = bool
  default     = true
}

variable "eks_comet_iam_role_name" {
  description = "Base name for the comet node group IAM role (module appends a unique suffix). Defaults to '<node-group-name>-eks-node-group'. Set to decouple the role name from the node group name when adopting a node group renamed out-of-band whose IAM role kept the original base (avoids role + node-group replacement)."
  type        = string
  default     = null
}

variable "eks_comet_capacity_type" {
  description = "Capacity type for comet node group: ON_DEMAND or SPOT. SPOT is ~70% cheaper but interruptible — only safe for non-prod (dev/UAT) clusters."
  type        = string
  default     = "ON_DEMAND"
  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.eks_comet_capacity_type)
    error_message = "eks_comet_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "eks_admin_capacity_type" {
  description = "Capacity type for admin node group: ON_DEMAND or SPOT. SPOT is ~70% cheaper but interruptible — only safe for non-prod (dev/UAT) clusters."
  type        = string
  default     = "ON_DEMAND"
  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.eks_admin_capacity_type)
    error_message = "eks_admin_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "eks_clickhouse_capacity_type" {
  description = "Capacity type for ClickHouse node group: ON_DEMAND or SPOT. SPOT is ~70% cheaper but interruptible — only safe for non-prod (dev/UAT) clusters. ClickHouse is stateful; only set SPOT when data loss on eviction is acceptable."
  type        = string
  default     = "ON_DEMAND"
  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.eks_clickhouse_capacity_type)
    error_message = "eks_clickhouse_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "eks_comet_instance_types" {
  description = "Instance types for comet node group"
  type        = list(string)
  default     = ["m7i.4xlarge"]
}

variable "eks_comet_min_size" {
  description = "Minimum number of nodes in comet node group"
  type        = number
  default     = 2
}

variable "eks_comet_max_size" {
  description = "Maximum number of nodes in comet node group"
  type        = number
  default     = 10
}

variable "eks_comet_desired_size" {
  description = "Desired number of nodes in comet node group"
  type        = number
  default     = 3
}

variable "eks_mng_disk_size" {
  description = "Size of the storage disks for nodes in EKS cluster"
  type        = number
  default     = 500
}

variable "eks_aws_load_balancer_controller" {
  description = "Enables the AWS Load Balancer Controller in the EKS cluster"
  type        = bool
  default     = true
}

variable "eks_cert_manager" {
  description = "Enables cert-manager in the EKS cluster (native EKS managed add-on, no IAM required)"
  type        = bool
  default     = false
}

variable "eks_cert_manager_addon_version" {
  description = "cert-manager EKS add-on version (e.g. v1.21.0-eksbuild.2). Null lets EKS pick the default for the cluster version."
  type        = string
  default     = null
}

variable "eks_aws_cloudwatch_metrics" {
  description = "Enables AWS Cloudwatch Metrics in the EKS cluster"
  type        = bool
  default     = false
}

variable "eks_external_dns" {
  description = "Enables ExternalDNS in the EKS cluster (native EKS managed add-on, using EKS Pod Identity for Route53 access)"
  type        = bool
  default     = false
}

variable "eks_external_dns_addon_version" {
  description = "external-dns EKS add-on version (e.g. v0.21.0-eksbuild.6). Null lets EKS pick the default for the cluster version."
  type        = string
  default     = null
}

variable "eks_external_dns_r53_zones" {
  description = "Route 53 zones for external-dns to have access to"
  type        = list(string)
  default = [
    "arn:aws:route53:::hostedzone/XYZ"
  ]
}

variable "eks_enable_metrics_server" {
  description = "Enables the metrics-server EKS managed addon (required for HPA and `kubectl top`). Also opens node SG port 10251 so the kube-apiserver can reach the metrics-server pod."
  type        = bool
  default     = true
}

variable "eks_metrics_server_addon_version" {
  description = "Pinned version of the metrics-server EKS managed addon. Set to null to use the AWS default for the cluster's Kubernetes version."
  type        = string
  default     = null
}

# Observability add-ons (native EKS managed add-ons, no IAM required).
variable "eks_enable_kube_state_metrics" {
  description = "Enable the kube-state-metrics EKS managed add-on (cluster object state metrics for Prometheus)."
  type        = bool
  default     = false
}

variable "eks_kube_state_metrics_addon_version" {
  description = "Pinned kube-state-metrics add-on version. Null uses the AWS default for the cluster version."
  type        = string
  default     = null
}

variable "eks_enable_prometheus_node_exporter" {
  description = "Enable the prometheus-node-exporter EKS managed add-on (per-node hardware/OS metrics for Prometheus)."
  type        = bool
  default     = false
}

variable "eks_prometheus_node_exporter_addon_version" {
  description = "Pinned prometheus-node-exporter add-on version. Null uses the AWS default for the cluster version."
  type        = string
  default     = null
}

variable "eks_enable_node_monitoring_agent" {
  description = "Enable the eks-node-monitoring-agent EKS managed add-on (node health monitoring / auto-repair signals)."
  type        = bool
  default     = false
}

variable "eks_node_monitoring_agent_addon_version" {
  description = "Pinned eks-node-monitoring-agent add-on version. Null uses the AWS default for the cluster version."
  type        = string
  default     = null
}

variable "eks_enable_cluster_autoscaler" {
  description = "Enables the Cluster Autoscaler IRSA role and ASG auto-discovery tags. The cluster-autoscaler Helm release itself is deployed out-of-band (ArgoCD AppSet). Toggling this creates the IAM role and tags the EKS-managed ASGs so the autoscaler can discover and scale them."
  type        = bool
  default     = false
}

# Druid Node Group Variables
variable "eks_druid_name" {
  description = "Name for the druid node group"
  type        = string
  default     = "druid"
}

variable "eks_druid_instance_types" {
  description = "Instance types for druid node group"
  type        = list(string)
  default     = ["m7i.2xlarge"]
}

variable "eks_druid_min_size" {
  description = "Minimum number of nodes in druid node group"
  type        = number
  default     = 2
}

variable "eks_druid_max_size" {
  description = "Maximum number of nodes in druid node group"
  type        = number
  default     = 8
}

variable "eks_druid_desired_size" {
  description = "Desired number of nodes in druid node group"
  type        = number
  default     = 4
}

# Airflow Node Group Variables
variable "eks_airflow_name" {
  description = "Name for the airflow node group"
  type        = string
  default     = "airflow"
}

variable "eks_airflow_instance_types" {
  description = "Instance types for airflow node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "eks_airflow_min_size" {
  description = "Minimum number of nodes in airflow node group"
  type        = number
  default     = 1
}

variable "eks_airflow_max_size" {
  description = "Maximum number of nodes in airflow node group"
  type        = number
  default     = 4
}

variable "eks_airflow_desired_size" {
  description = "Desired number of nodes in airflow node group"
  type        = number
  default     = 2
}

# ClickHouse Node Group Variables
variable "eks_clickhouse_name" {
  description = "Name for the ClickHouse node group"
  type        = string
  default     = "clickhouse"
}

variable "eks_clickhouse_use_name_prefix" {
  description = "Whether to treat eks_clickhouse_name as a prefix (true, AWS appends a unique suffix) or as the exact node group name (false). Set false to adopt an existing ClickHouse node group whose name is fixed (e.g. a single-AZ 'clickhouse-az2b' created out-of-band)."
  type        = bool
  default     = true
}

variable "eks_clickhouse_iam_role_name" {
  description = "Base name for the ClickHouse node group IAM role (module appends a unique suffix). Defaults to '<node-group-name>-eks-node-group'. Set to decouple the role name from the node group name when adopting a node group renamed out-of-band whose IAM role kept the original base (avoids role + node-group replacement)."
  type        = string
  default     = null
}

variable "eks_clickhouse_instance_types" {
  description = "Instance types for the ClickHouse node group"
  type        = list(string)
  default     = ["m7i.2xlarge"]
}

variable "eks_clickhouse_min_size" {
  description = "Minimum number of ClickHouse nodes"
  type        = number
  default     = 2
}

variable "eks_clickhouse_max_size" {
  description = "Maximum number of ClickHouse nodes"
  type        = number
  default     = 3
}

variable "eks_clickhouse_desired_size" {
  description = "Desired number of ClickHouse nodes"
  type        = number
  default     = 2
}

variable "eks_clickhouse_volume_size" {
  description = "EBS volume size in GB for ClickHouse nodes"
  type        = number
  default     = 500
}

variable "eks_clickhouse_volume_type" {
  description = "EBS volume type for ClickHouse nodes"
  type        = string
  default     = "gp3"
}

variable "eks_clickhouse_volume_encrypted" {
  description = "Enable EBS encryption for ClickHouse volumes"
  type        = bool
  default     = true
}

variable "eks_clickhouse_delete_on_termination" {
  description = "Delete EBS volumes on instance termination"
  type        = bool
  default     = true
}

variable "eks_clickhouse_taints" {
  description = "Taints to apply to ClickHouse node group. Map keyed by taint name (v21 of upstream eks/aws expects map, not list)."
  type = map(object({
    key    = string
    value  = string
    effect = string
  }))
  default = {
    clickhouse = {
      key    = "clickhouse"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  }
}

# Karpenter Node Group Variables
# Used only when eks_enable_karpenter = true. See modules/comet_eks/variables.tf for details.

variable "eks_karpenter_node_instance_types" {
  description = "Instance types for the Karpenter controller node group"
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]
}

variable "eks_karpenter_node_min_size" {
  description = "Minimum number of nodes in the Karpenter controller node group"
  type        = number
  default     = 1
}

variable "eks_karpenter_node_max_size" {
  description = "Maximum number of nodes in the Karpenter controller node group"
  type        = number
  default     = 2
}

variable "eks_karpenter_node_desired_size" {
  description = "Desired number of nodes in the Karpenter controller node group"
  type        = number
  default     = 1
}

variable "eks_karpenter_node_disk_size" {
  description = "EBS root volume size in GB for Karpenter controller nodes"
  type        = number
  default     = 50
}

variable "eks_admin_karpenter_instance_types" {
  description = "Instance types for the admin node group when Karpenter is enabled. These nodes run system workloads only (cert-manager, LBC, etc.) so smaller instances are appropriate."
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]
}

variable "eks_karpenter_chart_version" {
  description = "Version of the comet-stsaas-karpenter Helm chart to install from helm.comet.com"
  type        = string
  default     = "0.1.0"
}

variable "eks_karpenter_helm_username" {
  description = "Username for the helm.comet.com Helm repository"
  type        = string
  sensitive   = true
  default     = ""
}

variable "eks_karpenter_helm_password" {
  description = "Password for the helm.comet.com Helm repository"
  type        = string
  sensitive   = true
  default     = ""
}

variable "eks_karpenter_extra_tags" {
  description = "Extra EC2 instance tags applied to all Karpenter-provisioned nodes (e.g. Environment)"
  type        = map(string)
  default     = {}
}

variable "eks_additional_node_groups" {
  description = "Additional EKS managed node groups to create beyond the predefined ones (admin, comet, druid, airflow, clickhouse)"
  type        = any
  default     = {}
}

variable "eks_additional_s3_bucket_arns" {
  description = "Additional S3 bucket ARNs to grant access to from EKS node groups (for buckets created outside this module)"
  type        = list(string)
  default     = []
}

variable "eks_enable_external_secrets" {
  description = "Enable External Secrets IRSA role and Helm chart for accessing AWS Secrets Manager from EKS"
  type        = bool
  default     = true
}

variable "eks_external_secrets_chart_version" {
  description = "Helm chart version for external-secrets"
  type        = string
  default     = "2.2.0"
}

variable "eks_external_secrets_via_helm_release" {
  description = <<-EOT
    When true, install external-secrets (CRDs + operator + ClusterSecretStore) via
    in-module helm_release resources. When false (default), skip the K8s-side
    resources and assume external-secrets is deployed externally (e.g., ArgoCD).
    The IRSA role is created either way.

    MIGRATION SAFETY: flipping true to false on a customer where the in-module
    helm_release is currently in TF state will run `helm uninstall` on the next
    apply, DELETING the K8s resources. Before flipping, either adopt the
    resources via ArgoCD (annotate them so the helm uninstall is a no-op) or
    `terraform state rm` the helm_release. See the comet_eks sub-module variable
    docs for the full migration sequence.
  EOT
  type        = bool
  default     = false
}

variable "eks_storage_class_reclaim_policy" {
  description = "Reclaim policy for the gp3 and comet-generic StorageClasses. Use 'Retain' to preserve volumes after PVC deletion (recommended for production), or 'Delete' to automatically delete volumes. Note: StorageClass reclaimPolicy is immutable; existing deployments require StorageClass deletion and recreation."
  type        = string
  default     = "Retain"

  validation {
    condition     = contains(["Retain", "Delete"], var.eks_storage_class_reclaim_policy)
    error_message = "Must be 'Retain' or 'Delete'."
  }
}

variable "eks_create_comet_generic_storage_class" {
  description = "Create the comet-generic StorageClass via this module. Set false when comet-generic is owned by the comet-ml Helm chart (Helm/ArgoCD) to avoid dual ownership. The gp3 StorageClass is always created by this module."
  type        = bool
  default     = true
}

#### comet_elasticache ####
variable "elasticache_allow_from_sg" {
  description = "Security group from which to allow connections to ElastiCache, to use when provisioning with existing compute"
  type        = string
  default     = null
}

variable "elasticache_engine" {
  description = "Engine type for ElastiCache cluster"
  type        = string
  default     = "redis"
}

variable "elasticache_engine_version" {
  description = "Version number for ElastiCache engine"
  type        = string
  default     = "7.1"
}

variable "elasticache_instance_type" {
  description = "ElastiCache instance type"
  type        = string
  default     = "cache.r4.xlarge"
}

variable "elasticache_param_group_name" {
  description = "Name for the ElastiCache cluster parameter group"
  type        = string
  default     = "default.redis7"
}

variable "elasticache_num_cache_nodes" {
  description = "Number of nodes in the ElastiCache cluster"
  type        = number
  default     = 1
}

variable "elasticache_transit_encryption" {
  description = "Enable transit encryption for ElastiCache"
  type        = bool
  default     = true
}

variable "elasticache_auth_token" {
  description = "Auth token for ElastiCache"
  type        = string
  default     = null
}

variable "elasticache_auth_token_update_strategy" {
  description = "Strategy applied when elasticache_auth_token changes. Required by AWS provider v6 when auth_token is set. Valid values: SET (replace immediately), ROTATE (add new token, keep old valid for transition), DELETE."
  type        = string
  default     = "ROTATE"
}

variable "elasticache_automatic_failover_enabled" {
  description = "Enable automatic failover for the ElastiCache replication group. Requires at least one replica (elasticache_num_cache_nodes >= 2)."
  type        = bool
  default     = false
}

variable "elasticache_multi_az_enabled" {
  description = "Enable Multi-AZ for the ElastiCache replication group. Requires automatic_failover to also be enabled and at least one replica in a different AZ."
  type        = bool
  default     = false
}

variable "elasticache_preferred_cache_cluster_azs" {
  description = "Ordered list of preferred AZs for cache cluster nodes. Length must equal elasticache_num_cache_nodes. Use to pin all nodes to a single AZ (e.g., [\"us-east-1b\"] with num_cache_nodes=1) to eliminate cross-AZ traffic between the workload and Redis. Null leaves AZ placement to AWS."
  type        = list(string)
  default     = null
}

#### comet_rds ####
variable "rds_allow_from_sg" {
  description = "Security group from which to allow connections to RDS, to use when provisioning with existing compute"
  type        = string
  default     = null
}

variable "rds_engine" {
  description = "Engine type for RDS database"
  type        = string
  default     = "aurora-mysql"
}

variable "rds_engine_version" {
  description = "Engine version number for RDS database"
  type        = string
  default     = "8.0"
}

variable "rds_instance_type" {
  description = "Instance type for RDS database"
  type        = string
  default     = "db.r5.xlarge"
}

variable "rds_instance_count" {
  description = "Number of RDS instances in the database cluster"
  type        = number
  default     = 2
}

variable "rds_serverless_v2_enabled" {
  description = "Enable Aurora Serverless v2. When true, instances use db.serverless and the cluster gets a serverless_v2_scaling_configuration block. rds_instance_type is ignored."
  type        = bool
  default     = false
}

variable "rds_serverless_v2_min_capacity" {
  description = "Minimum ACU for Aurora Serverless v2. Set to 0 to enable auto-pause (Aurora MySQL 3.08+, PostgreSQL 16.3+). Otherwise minimum is 0.5."
  type        = number
  default     = 0.5
}

variable "rds_serverless_v2_max_capacity" {
  description = "Maximum ACU for Aurora Serverless v2."
  type        = number
  default     = 1.0
}

variable "rds_serverless_v2_seconds_until_auto_pause" {
  description = "Seconds of idle before auto-pause kicks in. Only effective when rds_serverless_v2_min_capacity = 0. Min 300 (5 min), max 86400 (24 h)."
  type        = number
  default     = 300
}

variable "rds_storage_encrypted" {
  description = "Enables encryption for RDS storage"
  type        = bool
  default     = true
}

variable "rds_iam_db_auth" {
  description = "Enables IAM auth for the database in RDS"
  type        = bool
  default     = true
}

variable "rds_backup_retention_period" {
  description = "Days specified for RDS snapshot retention period"
  type        = number
  # DND-1485: STSaaS standard is a 7-day recovery window. The previous default (14)
  # silently doubled Aurora continuous-backup storage/cost for every customer that
  # migrated onto this module without an override (DND-1323). Default to 7 to match
  # the fleet norm; customers wanting more set it explicitly.
  default = 7
}

variable "rds_preferred_backup_window" {
  description = "Backup window for RDS (UTC)"
  type        = string
  default     = "02:00-04:00"
}

variable "rds_deletion_protection" {
  description = "Enable deletion protection for RDS cluster"
  type        = bool
  default     = true
}

variable "rds_storage_type" {
  description = "Aurora storage type. Use 'aurora-iopt1' for I/O-Optimized (eliminates I/O charges, 30% instance surcharge). Default null uses Aurora Standard."
  type        = string
  default     = null
}

variable "rds_database_name" {
  description = "Name for the application database in RDS"
  type        = string
  default     = "logger"
}

variable "rds_master_username" {
  description = "Master username for RDS database"
  type        = string
  default     = "admin"
}

variable "rds_master_password" {
  description = "Master password for RDS database. If not provided, a random password will be generated and stored in Secrets Manager."
  type        = string
  default     = null
  sensitive   = true
}

variable "rds_snapshot_identifier" {
  description = "Snapshot identifier to restore the RDS cluster from. If provided, the cluster will be restored from this snapshot instead of being created fresh."
  type        = string
  default     = null
}

variable "rds_kms_key_id" {
  description = "ARN of the KMS key to use for encryption. Required when restoring from a KMS-encrypted shared snapshot. If not specified, the default RDS KMS key will be used."
  type        = string
  default     = null
}

variable "rds_performance_insights_enabled" {
  description = "Enable Performance Insights for RDS instances"
  type        = bool
  default     = true
}

variable "rds_performance_insights_retention_period" {
  description = "Retention period for Performance Insights data in days. Valid values are 7, 31, 62, 93, 124, 155, 186, 217, 248, 279, 310, 341, 372, 403, 434, 465, 496, 527, 558, 589, 620, 651, 682, 713, or 731."
  type        = number
  default     = 7
}

variable "rds_performance_insights_kms_key_id" {
  description = "ARN of KMS key to encrypt Performance Insights data. If not specified, the default RDS KMS key will be used."
  type        = string
  default     = null
}

variable "rds_enhanced_monitoring_interval" {
  description = "Interval in seconds for Enhanced Monitoring metrics collection. Valid values are 0, 1, 5, 10, 15, 30, 60. Set to 0 to disable Enhanced Monitoring."
  type        = number
  default     = 60
}

#### comet_s3 ####
variable "s3_bucket_name" {
  description = "Name for S3 bucket"
  type        = string
}

variable "s3_force_destroy" {
  description = "Option to enable force delete of S3 bucket"
  type        = bool
  default     = false
}

variable "enable_s3_versioning" {
  description = "Enable S3 bucket versioning on the comet bucket and (when enable_loki_bucket=true) the loki bucket. Existing objects are unaffected; only writes after enabling get version IDs."
  type        = bool
  default     = false
}

variable "enable_s3_lifecycle" {
  description = "Enable AWS-managed lifecycle rules on the comet bucket and (when enable_loki_bucket=true) the loki bucket. Rules come from comet_bucket_lifecycle_rules / loki_bucket_lifecycle_rules (defaults match DND-1261). noncurrent_version_expiration clauses are no-op on unversioned buckets."
  type        = bool
  default     = false
}

variable "comet_bucket_lifecycle_rules" {
  description = "Lifecycle rules applied to the comet S3 bucket when enable_s3_lifecycle = true. Defaults match DND-1261. Override to change retention/tiering per customer."
  type = list(object({
    id                                     = string
    status                                 = optional(string, "Enabled")
    filter_prefix                          = optional(string, "")
    abort_incomplete_multipart_upload_days = optional(number)
    expiration_days                        = optional(number)
    noncurrent_version_expiration_days     = optional(number)
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
  }))
  default = [
    {
      id                                     = "delete-old-versions"
      abort_incomplete_multipart_upload_days = 1
      noncurrent_version_expiration_days     = 10
    },
    {
      id = "FilesOlderThan12Months"
      transitions = [
        { days = 365, storage_class = "STANDARD_IA" },
        { days = 730, storage_class = "GLACIER_IR" },
      ]
    },
  ]
}

variable "loki_bucket_lifecycle_rules" {
  description = "Lifecycle rules applied to the loki S3 bucket when enable_s3_lifecycle = true and enable_loki_bucket = true. Defaults match DND-1261. Same schema as comet_bucket_lifecycle_rules."
  type = list(object({
    id                                     = string
    status                                 = optional(string, "Enabled")
    filter_prefix                          = optional(string, "")
    abort_incomplete_multipart_upload_days = optional(number)
    expiration_days                        = optional(number)
    noncurrent_version_expiration_days     = optional(number)
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
  }))
  default = [
    {
      id                                     = "delete-old-versions"
      abort_incomplete_multipart_upload_days = 1
      noncurrent_version_expiration_days     = 30
    },
    {
      id = "transition-to-ia"
      transitions = [
        { days = 30, storage_class = "STANDARD_IA" },
      ]
    },
  ]
}

#### comet_vpc ####
variable "single_nat_gateway" {
  description = "Controls whether single NAT gateway used for all public subnets"
  type        = bool
  default     = true
}

variable "enable_tgw_prep" {
  description = "Tag private subnets with tgw_connect=true so a future TGW attachment can target them. The attachment itself is created separately."
  type        = bool
  default     = false
}

variable "vpc_name" {
  description = "Override the VPC name. Defaults to comet-$${environment}-vpc. Set this when adopting an existing brownfield VPC whose name differs."
  type        = string
  default     = null
}

variable "public_subnets" {
  description = "Override the public subnet CIDR list. Defaults to cidrsubnet(vpc_cidr, 8, k) for k in 0..2. Set this when adopting an existing brownfield VPC whose subnet layout differs from the formula."
  type        = list(string)
  default     = null

  validation {
    condition     = var.public_subnets == null || length(coalesce(var.public_subnets, [])) > 0
    error_message = "public_subnets override must contain at least one CIDR; pass null to use the default formula."
  }
}

variable "private_subnets" {
  description = "Override the private subnet CIDR list. Defaults to cidrsubnet(vpc_cidr, 5, 3*k+1) for k in 0..2. Set this when adopting an existing brownfield VPC whose subnet layout differs from the formula."
  type        = list(string)
  default     = null

  validation {
    condition     = var.private_subnets == null || length(coalesce(var.private_subnets, [])) > 0
    error_message = "private_subnets override must contain at least one CIDR; pass null to use the default formula."
  }
}

variable "public_subnet_tags" {
  description = "Additional tags applied to public subnets (merged with EKS auto-discovery tags)."
  type        = map(string)
  default     = {}
}

variable "private_subnet_tags" {
  description = "Additional tags applied to private subnets (merged with EKS auto-discovery and TGW tags)."
  type        = map(string)
  default     = {}
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC Flow Logs to CloudWatch (creates the IAM role and log group when true)"
  type        = bool
  default     = false
}

variable "enable_s3_endpoint" {
  description = "Provision the S3 gateway VPC endpoint attached to all route tables"
  type        = bool
  default     = true
}

variable "enable_vpc_interface_endpoints" {
  description = "Provision interface VPC endpoints for AWS-managed services so workloads can reach them without NAT/Internet egress. Required when flipping EKS API / RDS / ElastiCache endpoints private-only."
  type        = bool
  default     = false
}

variable "vpc_interface_endpoints_services" {
  description = "Override list of interface endpoint service short-names (without the com.amazonaws.<region>. prefix). When empty, defaults to: ecr.api, ecr.dkr, sts, ec2, ec2messages, ssm, ssmmessages, sqs, secretsmanager, logs, monitoring, eks. sqs covers Karpenter spot-interruption queues."
  type        = list(string)
  default     = []
}

variable "vpc_interface_endpoints_allowed_cidrs" {
  description = "Additional CIDR blocks allowed to reach interface VPC endpoints on 443 (in addition to the VPC's own CIDR). Defaults to the agentro management surface: 10.162.0.0/16 (ArgoCD mgmt VPC) + 10.126.0.0/15 (VPN client pool). Set to [] to allow only in-VPC traffic."
  type        = list(string)
  default     = ["10.162.0.0/16", "10.126.0.0/15"]
}

variable "enable_tgw_attachment" {
  description = "Attach this VPC to a pre-existing Transit Gateway (whose ID must be passed via tgw_id). Adds routes on every private route table for the destinations in tgw_propagated_cidrs."
  type        = bool
  default     = false
}

variable "tgw_id" {
  description = "ID of the pre-existing (and, if cross-account, RAM-shared) Transit Gateway to attach the VPC to. Required when enable_tgw_attachment is true."
  type        = string
  default     = null
}

variable "tgw_propagated_cidrs" {
  description = "Destination CIDRs to route via the TGW attachment from every private route table. Defaults to the agentro management surface (VPN client pool + ArgoCD mgmt VPC)."
  type        = list(string)
  default     = ["10.126.0.0/15", "10.162.0.0/16"]
}

variable "tgw_attachment_dns_support" {
  description = "Whether the TGW attachment resolves DNS hostnames to private addresses across attachments. Accepts 'enable' or 'disable'."
  type        = string
  default     = "enable"
}

variable "tgw_attachment_appliance_mode_support" {
  description = "Whether the TGW attachment maintains traffic-flow affinity through stateful appliances. Accepts 'enable' or 'disable'."
  type        = string
  default     = "disable"
}

variable "tgw_attachment_default_route_table_association" {
  description = "Associate the attachment with the TGW's default route table. Set false when the TGW uses custom route tables and another account manages the association."
  type        = bool
  default     = true
}

variable "tgw_attachment_default_route_table_propagation" {
  description = "Propagate this VPC's CIDR to the TGW's default route table. Set false when propagation is managed by the TGW owner account."
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "A map of tags to apply to resources"
  type        = map(string)
}

variable "environment_tag" {
  description = "Deployment identifier"
  type        = string
  default     = ""
}

#### comet_secretsmanager ####
variable "sendgrid_api_key" {
  description = "Base64 encoded SendGrid API key (required when enable_secretsmanager is true)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "secret_seed" {
  description = "Secret seed value for Comet. If not provided, a random value will be generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "s3_key" {
  description = "S3 key configuration for Secrets Manager"
  type        = string
  default     = "IAM-ROLE"
}

variable "s3_secret" {
  description = "S3 secret configuration for Secrets Manager"
  type        = string
  default     = "IAM-ROLE"
  sensitive   = true
}

variable "s3_private_key" {
  description = "S3 private key configuration for Secrets Manager"
  type        = string
  default     = "IAM-ROLE"
}

variable "s3_private_secret" {
  description = "S3 private secret configuration for Secrets Manager"
  type        = string
  default     = "IAM-ROLE"
  sensitive   = true
}

variable "s3_public_key" {
  description = "S3 public key configuration for Secrets Manager"
  type        = string
  default     = "IAM-ROLE"
}

variable "s3_public_secret" {
  description = "S3 public secret configuration for Secrets Manager"
  type        = string
  default     = "IAM-ROLE"
  sensitive   = true
}

variable "redis_token" {
  description = "Redis auth token for Secrets Manager"
  type        = string
  default     = "NA"
  sensitive   = true
}

#### comet_secretsmanager - monitoring secret ####
variable "grafana_admin_user" {
  description = "Grafana admin username for monitoring secret"
  type        = string
  default     = "admin"
}

variable "grafana_admin_password" {
  description = "Grafana admin password for monitoring secret. Required when enable_monitoring_secret is true."
  type        = string
  default     = null
  sensitive   = true
}

#### comet_secretsmanager - clickhouse secret ####
variable "clickhouse_monitoring_password" {
  description = "ClickHouse monitoring password for clickhouse secret. Required when enable_clickhouse_secret is true."
  type        = string
  default     = null
  sensitive   = true
}

variable "clickhouse_agentro_password" {
  description = "ClickHouse password for the read-only agentro user. If null and enable_clickhouse_secret is true, a random 32-char password is generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "clickhouse_admin_password" {
  description = "ClickHouse password for the opik admin user. If null and enable_clickhouse_secret is true, a random 32-char password is generated."
  type        = string
  default     = null
  sensitive   = true
}

variable "clickhouse_host" {
  description = "In-cluster DNS name of the ClickHouse HTTP service (used by the comet-monitoring clickhouse-exporter). If null, defaults to `clickhouse-opik-clickhouse.{environment}.svc.cluster.local`."
  type        = string
  default     = null
}

variable "clickhouse_port" {
  description = "ClickHouse HTTP port (used by clickhouse-exporter)."
  type        = string
  default     = "8123"
}

variable "clickhouse_monitoring_username" {
  description = "ClickHouse user the monitoring exporter authenticates as. Default matches the user the comet-ml chart provisions."
  type        = string
  default     = "opikmonitoring"
}

variable "rds_cluster_parameters" {
  description = "Additional MySQL parameters applied to the cluster parameter group on top of the module's baseline character-set/collation/innodb defaults. Defaults include operational tunings (wait_timeout, max_execution_time, innodb purge settings, aurora_read_replica_read_committed) used across Comet STSAAS deployments. Pass [] to disable, or override with a custom list."
  type = list(object({
    name         = string
    value        = string
    apply_method = string
  }))
  default = [
    { name = "aurora_read_replica_read_committed", value = "ON", apply_method = "immediate" },
    { name = "innodb_max_purge_lag", value = "1000000", apply_method = "immediate" },
    { name = "innodb_max_purge_lag_delay", value = "300000", apply_method = "immediate" },
    { name = "innodb_purge_batch_size", value = "5000", apply_method = "immediate" },
    { name = "innodb_purge_threads", value = "16", apply_method = "pending-reboot" },
    { name = "max_execution_time", value = "60000", apply_method = "immediate" },
    { name = "wait_timeout", value = "1800", apply_method = "immediate" },
  ]
}

variable "rds_require_secure_transport" {
  description = "Reject MySQL connections that don't use TLS. Sets require_secure_transport=ON on the cluster parameter group (Aurora MySQL value format; vanilla MySQL uses 1/0). Applies pending-reboot. Default false to preserve existing behavior; new STSAAS customers should onboard with this true."
  type        = bool
  default     = false
}

variable "rds_db_parameters" {
  description = "Per-instance MySQL parameters applied to the DB-instance parameter group. For instance-specific overrides of cluster-level settings (rarely needed; use rds_cluster_parameters for fleet-wide tunings). Empty by default."
  type = list(object({
    name         = string
    value        = string
    apply_method = string
  }))
  default = []
}

#### comet_rds_proxy ####
variable "enable_rds_proxy" {
  description = "Provision an RDS Proxy in front of the Aurora MySQL cluster (connection pooling, faster failover). Requires enable_rds. Auth via a dedicated Secrets Manager secret created by the sub-module."
  type        = bool
  default     = false
}

variable "rds_proxy_allowed_sg_ids" {
  description = "When enable_eks=false, the list of security group IDs allowed to connect to the proxy on 3306. When enable_eks=true the EKS nodegroup SG is wired in automatically and this is ignored."
  type        = list(string)
  default     = []
}

variable "rds_proxy_allowed_cidrs" {
  description = "CIDR blocks allowed to connect to the proxy on 3306 (in addition to allowed SGs). Defaults to the agentro VPN client pool (10.126.0.0/15)."
  type        = list(string)
  default     = ["10.126.0.0/15"]
}

variable "rds_proxy_require_tls" {
  description = "Require TLS for client connections to the proxy. Should be true whenever rds_require_secure_transport is true."
  type        = bool
  default     = true
}

variable "rds_proxy_idle_client_timeout" {
  description = "Seconds a client connection can be idle before the proxy closes it"
  type        = number
  default     = 1800
}

variable "rds_proxy_debug_logging" {
  description = "Enable proxy debug logging (verbose)"
  type        = bool
  default     = false
}

variable "rds_proxy_max_connections_percent" {
  description = "Maximum percentage of the cluster's max_connections the proxy will open"
  type        = number
  default     = 100
}

variable "rds_proxy_max_idle_connections_percent" {
  description = "Maximum percentage of idle connections the proxy will keep warm"
  type        = number
  default     = 50
}

variable "rds_proxy_connection_borrow_timeout" {
  description = "Seconds a client request waits for an available connection from the pool before failing"
  type        = number
  default     = 120
}

# Per-Node-Group Subnet Pinning
# When set, restricts a specific node group to a subset of subnets (typically a
# single AZ). Use to align node placement with stateful workload PVs that are
# AZ-bound (e.g. ClickHouse EBS volumes), or to reduce cross-AZ data transfer.
# When null (the default), the node group inherits the cluster-wide subnets and
# spans all AZs. The subnets must be a subset of the EKS cluster's subnets.
variable "eks_admin_subnet_ids" {
  description = "Subnet IDs for the admin node group. When set, overrides cluster-wide subnets for this NG only (typically single-AZ pinning). Must be a subset of the EKS cluster subnets."
  type        = list(string)
  default     = null
}

variable "eks_comet_subnet_ids" {
  description = "Subnet IDs for the comet node group. When set, overrides cluster-wide subnets for this NG only (typically single-AZ pinning). Must be a subset of the EKS cluster subnets."
  type        = list(string)
  default     = null
}

variable "eks_druid_subnet_ids" {
  description = "Subnet IDs for the druid node group. When set, overrides cluster-wide subnets for this NG only (typically single-AZ pinning). Must be a subset of the EKS cluster subnets."
  type        = list(string)
  default     = null
}

variable "eks_airflow_subnet_ids" {
  description = "Subnet IDs for the airflow node group. When set, overrides cluster-wide subnets for this NG only (typically single-AZ pinning). Must be a subset of the EKS cluster subnets."
  type        = list(string)
  default     = null
}

variable "eks_clickhouse_subnet_ids" {
  description = "Subnet IDs for the ClickHouse node group. When set, overrides cluster-wide subnets for this NG only. CRITICAL: must match the AZ of any existing ClickHouse EBS volumes — otherwise the CH pod cannot reschedule onto the new NG. Verify with: kubectl get pv <PV_NAME> -o jsonpath='{.spec.nodeAffinity...zone...}'."
  type        = list(string)
  default     = null
}

#####################
#### EKS API ingress — standardized fleet-wide access (v1.19.0)
#####################

variable "enable_argocd_management_eks_access" {
  description = "Open EKS API (port 443) to the ArgoCD management cluster CIDRs in argocd_management_cidrs. Required for ArgoCD to deploy into this cluster from the central mgmt cluster."
  type        = bool
  default     = false
}

variable "argocd_management_cidrs" {
  description = "CIDRs allowed to reach the EKS API for ArgoCD management. Defaults cover the ArgoCD mgmt VPC + cluster CIDRs."
  type        = list(string)
  default     = ["10.162.0.0/16", "10.100.0.0/16"]
}

variable "enable_vpn_eks_api_access" {
  description = "Open EKS API (port 443) to the VPN client pool CIDR. Required after flipping endpoint_public_access=false (DND-915)."
  type        = bool
  default     = false
}

variable "vpn_client_cidr" {
  description = "CIDR of the VPN client pool. Used by enable_vpn_eks_api_access and enable_vpn_redis_access."
  type        = string
  default     = "10.126.0.0/15"
}

variable "enable_ci_runners_eks_api_access" {
  description = "Open EKS API (port 443) to the CI runners cluster CIDR. Required for CI workflows that exec against the cluster (DND-1153)."
  type        = bool
  default     = false
}

variable "ci_runners_cidr" {
  description = "CIDR of the CI runners cluster."
  type        = string
  default     = "10.4.0.0/16"
}

#####################
#### Namespace nodegroup pinning
#####################

variable "enable_namespace_nodegroup_pinning" {
  description = "Annotate the application namespace with nodegroup_name=comet and admin_pinned_namespaces with nodegroup_name=admin via scheduler.alpha. Skips kube-system + monitoring."
  type        = bool
  default     = false
}

variable "app_namespace" {
  description = "Application namespace to pin to the comet node group. Defaults to the module environment (which matches the Helm chart's default namespace)."
  type        = string
  default     = null
}

variable "admin_pinned_namespaces" {
  description = "Namespaces to pin to the admin node group. Defaults cover the cluster's add-on namespaces."
  type        = list(string)
  default     = ["cert-manager", "external-dns", "external-secrets"]
}

#####################
#### Redis Insights namespace + agentro port-forward RBAC
#####################

variable "enable_redis_insights_ns" {
  description = "Create the redis-insights Kubernetes namespace with scheduler.alpha annotation pinning to admin NG."
  type        = bool
  default     = false
}

#####################
#### Redis VPN ingress (comet_elasticache passthrough)
#####################

variable "enable_vpn_redis_access" {
  description = "Add a VPN client CIDR ingress rule on the Redis SG (port 6379) so operators on the VPN can connect via kubectl port-forward (DND-752)."
  type        = bool
  default     = false
}
