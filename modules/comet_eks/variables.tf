variable "environment" {
  description = "Deployment environment, i.e. dev/stage/prod, etc"
  type        = string
}

variable "region" {
  description = "AWS region for resources"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC that the EKS cluster will be launched in"
  type        = string
}

variable "eks_private_subnets" {
  description = "IDs of private subnets within the VPC"
  type        = list(string)
}

variable "eks_cluster_name" {
  description = "Name for the EKS cluster"
  type        = string
}

variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
}

variable "eks_cluster_endpoint_public_access" {
  description = "Enable public access to the EKS cluster API endpoint"
  type        = bool
  default     = true
}

variable "eks_cluster_endpoint_private_access" {
  description = "Enable private access to the EKS cluster API endpoint"
  type        = bool
  default     = false
}

variable "eks_cluster_security_group_additional_rules" {
  description = "Additional security group rules for the EKS cluster security group"
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

variable "kms_key_administrators" {
  description = "List of IAM ARNs (users/roles) that should have administrator access to the EKS KMS key. These principals can manage the key."
  type        = list(string)
  default     = []
}

variable "kms_key_users" {
  description = "List of IAM ARNs (users/roles) that should have usage access to the EKS KMS key. These principals can use the key for encryption/decryption."
  type        = list(string)
  default     = []
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

variable "eks_admin_capacity_type" {
  description = "Capacity type for admin node group: ON_DEMAND or SPOT. SPOT is ~70% cheaper but interruptible — only safe for non-prod (dev/UAT) clusters."
  type        = string
  default     = "ON_DEMAND"
  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.eks_admin_capacity_type)
    error_message = "eks_admin_capacity_type must be ON_DEMAND or SPOT."
  }
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

variable "eks_mng_ami_type" {
  description = "AMI family to use for the EKS nodes (default for all nodegroups). Ignored if eks_mng_ami_id is set."
  type        = string
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

variable "eks_comet_instance_types" {
  description = "Instance types for comet node group"
  type        = list(string)
  default     = ["m7i.4xlarge"]
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
}

variable "eks_aws_load_balancer_controller" {
  description = "Enables the AWS Load Balancer Controller in the EKS cluster"
  type        = bool
}

variable "eks_cert_manager" {
  description = "Enables cert-manager in the EKS cluster"
  type        = bool
}

variable "eks_aws_cloudwatch_metrics" {
  description = "Enables AWS Cloudwatch Metrics in the EKS cluster"
  type        = bool
}

variable "eks_external_dns" {
  description = "Enables ExternalDNS in the EKS cluster"
  type        = bool
}

variable "eks_external_dns_r53_zones" {
  description = "Route 53 zones for external-dns to have access to"
  type        = list(string)
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

variable "eks_enable_cluster_autoscaler" {
  description = "Enables the Cluster Autoscaler IRSA role and ASG auto-discovery tags. The cluster-autoscaler Helm release itself is deployed out-of-band (ArgoCD AppSet). Toggling this creates the IAM role and tags the EKS-managed ASGs so the autoscaler can discover and scale them."
  type        = bool
  default     = false
}

variable "s3_enabled" {
  description = "Indicates if S3 bucket is being provisioned for Comet"
  type        = bool
  default     = null
}

variable "comet_ec2_s3_iam_policy" {
  description = "Policy with access to S3 to associate with EKS worker nodes"
  type        = string
  default     = null
}

# Node Group Toggles
variable "enable_admin_node_group" {
  description = "Enable admin node group for EKS cluster management tasks"
  type        = bool
  default     = true
}

variable "enable_comet_node_group" {
  description = "Enable comet node group for main Comet application workloads"
  type        = bool
  default     = true
}

variable "enable_druid_node_group" {
  description = "Enable druid node group for Apache Druid workloads (requires enable_mpm_infra to be true)"
  type        = bool
  default     = true
}

variable "enable_airflow_node_group" {
  description = "Enable airflow node group for Apache Airflow workloads (requires enable_mpm_infra to be true)"
  type        = bool
  default     = true
}

variable "enable_mpm_infra" {
  description = "Master toggle for MPM infrastructure (Druid/Airflow node groups will only be created if this is true)"
  type        = bool
  default     = false
}

variable "enable_external_secrets" {
  description = "Enable External Secrets IRSA role and Helm chart for accessing AWS Secrets Manager"
  type        = bool
  default     = true
}

variable "external_secrets_via_helm_release" {
  description = <<-EOT
    When true, the module installs external-secrets (CRDs, operator, webhook, and
    the ClusterSecretStore manifest) via in-module helm_release + kubectl_manifest
    resources. When false (default), the module skips those K8s-side resources and
    assumes external-secrets is deployed externally (e.g., via ArgoCD). The AWS-side
    IRSA role gets created either way so the external deployment can wire its
    ServiceAccount to it.

    MIGRATION SAFETY: If the in-module helm_release is currently in the customer's
    TF state, flipping this from true to false on the next apply will trigger
    `helm uninstall`, DELETING the K8s resources (Deployments, Services,
    ServiceAccounts, CRDs, etc.). Safe per-customer sequence:
      1. Stand up the ArgoCD app pointing at the same chart + values.
      2. Either annotate existing K8s resources with
         `app.kubernetes.io/managed-by: ArgoCD` and adjust the
         `meta.helm.sh/release-name` annotations so the next uninstall is a no-op,
         OR `terraform state rm` the helm_release before applying.
      3. Then flip this to false and apply. TF state will have nothing to destroy.

    On stsaasuat specifically: the in-module helm_release was left in a broken
    state by the DND-1214 apply (K8s resources orphaned, helm metadata gone).
    Flipping to false on stsaasuat is safe — TF just stops fighting a release
    that already doesn't own anything.
  EOT
  type        = bool
  default     = false
}

variable "secretsmanager_environment" {
  description = "Environment name used for Secrets Manager secret paths (e.g., cometml/{secretsmanager_environment}/config). If different from 'environment', both patterns will be allowed in the IAM policy."
  type        = string
  default     = null
}

variable "external_secrets_chart_version" {
  description = "Helm chart version for external-secrets. Must align with the comet-devops umbrella chart pinned in comet-gitops (currently 2.2.0); using an older version leaves stale CRDs whose conversion webhook references a service that gets removed when ArgoCD takes over the operator install, blocking ArgoCD sync until the CRDs are patched."
  type        = string
  default     = "2.2.0"
}

variable "enable_loki" {
  description = "Enable Loki IRSA role for accessing S3 bucket for log storage"
  type        = bool
  default     = false
}

variable "enable_cloudwatch_exporter" {
  description = "Enable CloudWatch Exporter IRSA role for scraping ElastiCache, RDS, and other AWS managed service metrics"
  type        = bool
  default     = false
}

variable "loki_s3_bucket_arn" {
  description = "ARN of the S3 bucket for Loki log storage"
  type        = string
  default     = null
}

variable "enable_monitoring_setup" {
  description = "Enable monitoring namespace and Grafana credentials secret"
  type        = bool
  default     = false
}

variable "monitoring_namespace" {
  description = "Kubernetes namespace for monitoring resources"
  type        = string
  default     = "monitoring"
}

variable "grafana_admin_user" {
  description = "Grafana admin username"
  type        = string
  default     = "admin"
}

variable "grafana_admin_password" {
  description = "Grafana admin password"
  type        = string
  sensitive   = true
  default     = null
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

variable "common_tags" {
  type        = map(string)
  description = "A map of common tags"
  default     = {}
}

# ClickHouse Node Group Toggle
variable "enable_clickhouse_node_group" {
  description = "Enable dedicated ClickHouse node group"
  type        = bool
  default     = false
}

# ClickHouse Node Group Variables
variable "eks_clickhouse_name" {
  description = "Name for the ClickHouse node group"
  type        = string
  default     = "clickhouse"
}

variable "eks_clickhouse_instance_types" {
  description = "Instance types for the ClickHouse node group"
  type        = list(string)
  default     = ["m7i.2xlarge"]
}

variable "eks_clickhouse_capacity_type" {
  description = "Capacity type for ClickHouse node group: ON_DEMAND or SPOT. SPOT is ~70% cheaper but interruptible — only safe for non-prod (dev/UAT) clusters. ClickHouse is a stateful workload; only set SPOT when data loss on eviction is acceptable."
  type        = string
  default     = "ON_DEMAND"
  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.eks_clickhouse_capacity_type)
    error_message = "eks_clickhouse_capacity_type must be ON_DEMAND or SPOT."
  }
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
  description = "Taints to apply to ClickHouse node group"
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = [
    {
      key    = "clickhouse"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  ]
}

variable "additional_node_groups" {
  description = "Additional EKS managed node groups to create beyond the predefined ones (admin, comet, druid, airflow, clickhouse)"
  type        = any
  default     = {}
}

variable "additional_s3_bucket_arns" {
  description = "Additional S3 bucket ARNs to grant access to (for buckets created outside this module)"
  type        = list(string)
  default     = []
}

variable "enable_karpenter" {
  description = "Enable Karpenter prerequisites: discovery tags on subnets and node security group, SQS interruption queue, EventBridge rules, node IAM role/instance profile, and controller IRSA role. Outputs can be consumed by a separate Karpenter Helm release."
  type        = bool
  default     = false
}

variable "karpenter_via_helm_release" {
  description = <<-EOT
    When true, the module installs the Karpenter Helm chart
    (comet-stsaas-karpenter) via an in-module helm_release. When false (default),
    the module skips the helm_release and assumes Karpenter is deployed externally
    (e.g., via ArgoCD). The AWS-side prerequisites (IRSA, SQS, instance profile,
    discovery tags) get created either way so the external deployment can wire
    them up.

    MIGRATION SAFETY: If the in-module helm_release is currently in the customer's
    TF state, flipping this from true to false on the next apply will trigger
    `helm uninstall`, DELETING the Karpenter controller + its K8s resources. Until
    something recreates them, the cluster has no autoscaler — running nodes stay
    but no new nodes spawn for pending pods. Safe per-customer sequence:
      1. Stand up the ArgoCD app for Karpenter pointing at the same chart + values.
      2. Either annotate existing Karpenter K8s resources with
         `app.kubernetes.io/managed-by: ArgoCD` and adjust
         `meta.helm.sh/release-name` so the next uninstall is a no-op,
         OR `terraform state rm` the helm_release before applying.
      3. Then flip this to false and apply.
  EOT
  type        = bool
  default     = false
}

# Karpenter Node Group Variables
# Used only when enable_karpenter = true. This dedicated node group hosts the Karpenter
# controller exclusively (taint: dedicated=karpenter:NoSchedule). All other node groups
# are disabled when Karpenter is enabled — Karpenter provisions them dynamically.

variable "eks_karpenter_node_instance_types" {
  description = "Instance types for the Karpenter controller node group. Only needs to fit the Karpenter controller (~1 CPU, 1Gi) plus kube-system daemonsets."
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]
}

variable "eks_karpenter_node_min_size" {
  description = "Minimum number of nodes in the Karpenter controller node group"
  type        = number
  default     = 1
}

variable "eks_karpenter_node_max_size" {
  description = "Maximum number of nodes in the Karpenter controller node group (2 allows rolling updates)"
  type        = number
  default     = 2
}

variable "eks_karpenter_node_desired_size" {
  description = "Desired number of nodes in the Karpenter controller node group"
  type        = number
  default     = 1
}

variable "eks_karpenter_node_disk_size" {
  description = "EBS root volume size in GB for Karpenter controller nodes. Smaller than workload nodes since only system pods run here."
  type        = number
  default     = 50
}

variable "eks_admin_karpenter_instance_types" {
  description = "Instance types for the admin node group when Karpenter is enabled. These nodes run system workloads only (cert-manager, LBC, etc.) so smaller instances are appropriate."
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]
}

variable "karpenter_chart_version" {
  description = "Version of the comet-stsaas-karpenter Helm chart to install from helm.comet.com"
  type        = string
  default     = "0.1.0"
}

variable "karpenter_helm_username" {
  description = "Username for the helm.comet.com Helm repository"
  type        = string
  sensitive   = true
  default     = ""
}

variable "karpenter_helm_password" {
  description = "Password for the helm.comet.com Helm repository"
  type        = string
  sensitive   = true
  default     = ""
}

variable "karpenter_extra_tags" {
  description = "Extra EC2 instance tags applied to all Karpenter-provisioned nodes (e.g. Environment)"
  type        = map(string)
  default     = {}
}

variable "storage_class_reclaim_policy" {
  description = "Reclaim policy for the gp3 and comet-generic StorageClasses. Use 'Retain' to preserve volumes after PVC deletion (recommended for production), or 'Delete' to automatically delete volumes."
  type        = string
  default     = "Retain"

  validation {
    condition     = contains(["Retain", "Delete"], var.storage_class_reclaim_policy)
    error_message = "Must be 'Retain' or 'Delete'."
  }
}

# Per-Node-Group Subnet Pinning
# When set, restricts a specific node group to a subset of subnets (typically a
# single AZ). Use to align node placement with stateful workload PVs that are
# AZ-bound (e.g. ClickHouse EBS volumes), or to reduce cross-AZ data transfer.
# When null (the default), the node group inherits eks_private_subnets and
# spans all AZs. The subnets must be a subset of eks_private_subnets.
variable "eks_admin_subnet_ids" {
  description = "Subnet IDs for the admin node group. When set, overrides eks_private_subnets for this NG only (typically used for single-AZ pinning). Must be a subset of eks_private_subnets."
  type        = list(string)
  default     = null
}

variable "eks_comet_subnet_ids" {
  description = "Subnet IDs for the comet node group. When set, overrides eks_private_subnets for this NG only (typically used for single-AZ pinning). Must be a subset of eks_private_subnets."
  type        = list(string)
  default     = null
}

variable "eks_druid_subnet_ids" {
  description = "Subnet IDs for the druid node group. When set, overrides eks_private_subnets for this NG only (typically used for single-AZ pinning). Must be a subset of eks_private_subnets."
  type        = list(string)
  default     = null
}

variable "eks_airflow_subnet_ids" {
  description = "Subnet IDs for the airflow node group. When set, overrides eks_private_subnets for this NG only (typically used for single-AZ pinning). Must be a subset of eks_private_subnets."
  type        = list(string)
  default     = null
}

variable "eks_clickhouse_subnet_ids" {
  description = "Subnet IDs for the ClickHouse node group. When set, overrides eks_private_subnets for this NG only. CRITICAL: must match the AZ of any existing ClickHouse EBS volumes — otherwise the CH pod cannot reschedule onto the new NG. Verify with: kubectl get pv <PV_NAME> -o jsonpath='{.spec.nodeAffinity...zone...}'."
  type        = list(string)
  default     = null
}

