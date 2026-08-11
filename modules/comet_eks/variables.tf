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

variable "eks_comet_use_name_prefix" {
  description = "Whether to treat eks_comet_name as a prefix (true, AWS appends a unique suffix) or as the exact node group name (false). Set false to adopt an existing comet node group whose name is fixed (e.g. a single-AZ 'comet-az2b' created out-of-band)."
  type        = bool
  default     = true
}

variable "eks_comet_iam_role_name" {
  description = "Base name for the comet node group IAM role (the module appends a unique suffix via name_prefix). Defaults to '<node-group-name>-eks-node-group'. Set explicitly to decouple the role name from the node group name — e.g. when adopting a node group whose name was changed out-of-band ('comet-az2b') but whose IAM role kept the original base ('comet-eks-node-group'), so the role is not replaced."
  type        = string
  default     = null
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

variable "eks_mng_force_update_version" {
  description = "Force EKS managed node group version updates to bypass the eviction API's PDB check. Default false (PDB-respecting) — appropriate for HA STSaaS deployments where customer PDBs accurately represent disruption budgets. Set to true on right-sized non-HA envs (e.g. UAT canaries with single-replica deployments) where PDBs structurally block any voluntary eviction. terminationGracePeriodSeconds is still honored either way."
  type        = bool
  default     = false
}

variable "eks_mng_use_latest_ami_release_version" {
  description = "When true (default), EKS managed node groups track the latest AMI release for their ami_type, so terraform bumps release_version on every apply (rolling the nodes). Set false to leave release_version AWS-managed (no AMI bump on apply), so AMI rolls can be scheduled separately from other terraform changes."
  type        = bool
  default     = true
}

variable "eks_mng_pin_launch_template_version" {
  description = "When false (default), the launch-template default_version auto-advances to the newest version, so any LT change rolls the nodes. Set true to stop auto-promoting new LT versions to default, so benign LT changes (e.g. tag-only version bumps) do NOT roll the nodes. Trade-off: deliberate LT changes (AMI/instance type) then require a separate default-version bump to take effect. Either way node groups reference the numeric default_version (not the \"$Latest\"/\"$Default\" aliases) so plans stay clean."
  type        = bool
  default     = false
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
  description = "Enables cert-manager in the EKS cluster (as a native EKS managed add-on)"
  type        = bool
}

variable "eks_cert_manager_addon_version" {
  description = "cert-manager EKS add-on version (e.g. v1.21.0-eksbuild.2). Null lets EKS pick the default for the cluster version."
  type        = string
  default     = null
}

variable "eks_external_dns" {
  description = "Enables ExternalDNS in the EKS cluster (as a native EKS managed add-on, using EKS Pod Identity for Route53 access)"
  type        = bool
}

variable "eks_external_dns_addon_version" {
  description = "external-dns EKS add-on version (e.g. v0.21.0-eksbuild.6). Null lets EKS pick the default for the cluster version."
  type        = string
  default     = null
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

variable "eks_enable_network_policy" {
  description = "Enables Kubernetes NetworkPolicy enforcement in the VPC CNI managed addon (sets enableNetworkPolicy=true, which runs the aws-eks-nodeagent). Without it, NetworkPolicy objects are created but silently not enforced. Required for the opik-python-backend / PP-engine / Ollie-engine egress policies. Defaults to true — enforcement is a safe superset (policies only restrict pods they explicitly select; unselected pods stay fully open)."
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

variable "secretsmanager_environment" {
  description = "Environment name used for Secrets Manager secret paths (e.g., cometml/{secretsmanager_environment}/config). If different from 'environment', both patterns will be allowed in the IAM policy."
  type        = string
  default     = null
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

# IRSA role-name overrides. Default null keeps the computed "${environment}-<role>"
# name. Set to adopt an existing differently-named role (e.g. a legacy hand-rolled
# "zoox-loki") by import/state-mv instead of recreating it — recreation would change
# the role ARN and break the K8s service account's IRSA annotation.
variable "loki_iam_role_name_override" {
  description = "Override the Loki IRSA role name. Null keeps the computed <environment>-loki name."
  type        = string
  default     = null
}

variable "external_secrets_iam_role_name_override" {
  description = "Override the External Secrets IRSA role name. Null keeps the computed <environment>-external-secrets name."
  type        = string
  default     = null
}

variable "external_secrets_namespace_service_accounts" {
  description = "OIDC-trusted <namespace>:<serviceaccount> subjects for the External Secrets IRSA role. Default trusts the standalone app's SA. During a migration to a different namespace (e.g. folding ESO into the comet-infra umbrella in comet-system), list BOTH the old and new subjects so tokens from either authenticate with no auth gap, then trim to just the new one."
  type        = list(string)
  default     = ["external-secrets:external-secrets"]
}

variable "aws_load_balancer_controller_namespace_service_accounts" {
  description = "OIDC-trusted <namespace>:<serviceaccount> subjects for the AWS Load Balancer Controller IRSA role. Default trusts the standalone app's SA (kube-system). When folding the controller into the comet-infra umbrella (comet-system ns), list BOTH old and new subjects for a zero-gap cutover, then trim to just the new one."
  type        = list(string)
  default     = ["kube-system:aws-load-balancer-controller"]
}

variable "cloudwatch_exporter_iam_role_name_override" {
  description = "Override the CloudWatch Exporter IRSA role name. Null keeps the computed <environment>-cloudwatch-exporter name."
  type        = string
  default     = null
}

variable "loki_s3_bucket_arn" {
  description = "ARN of the S3 bucket for Loki log storage"
  type        = string
  default     = null
}

# DND-1423: Bring-your-own-S3 IRSA roles. When a customer supplies their own S3
# bucket (e.g. ClickHouse remote backups), the pods that touch it need an IAM
# role assumable via IRSA and a policy scoped to that bucket. Each map entry
# provisions one such role + customer-managed policy + attachment. This
# generalizes roles previously created out-of-band during BYO-S3 onboarding
# (e.g. Zoox's ZooxS3Access) so the trusted ServiceAccounts are codified and
# reviewable. The map key is a short logical name used in resource naming.
variable "byo_s3_irsa_roles" {
  description = "Map of bring-your-own-S3 IRSA roles. Each entry grants the listed Kubernetes ServiceAccounts (via IRSA web-identity) scoped access to a customer-supplied S3 bucket. Empty by default (feature off)."
  type = map(object({
    # ARNs of the customer-supplied bucket(s). Permissions are scoped to these
    # (bucket + bucket/*) - do NOT pass arn:aws:s3:::* here.
    bucket_arns = list(string)
    # ServiceAccounts allowed to assume the role, as "<namespace>:<sa-name>".
    namespace_service_accounts = list(string)
    # Optional S3 action set. Null => the ClickHouse-backup default action set.
    actions = optional(list(string))
    # Optional overrides to adopt an existing out-of-band role/policy in place
    # (e.g. role_name_override="ZooxS3Access") via terraform import without
    # recreating it (recreation would change the ARN and break IRSA annotations).
    role_name_override   = optional(string)
    policy_name_override = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.byo_s3_irsa_roles :
      length(v.bucket_arns) > 0 && length(v.namespace_service_accounts) > 0
    ])
    error_message = "Each byo_s3_irsa_roles entry must set at least one bucket_arn and one namespace_service_account."
  }
  # Each bucket_arn must be an exact bucket ARN: arn:aws:s3:::<bucket>. No globs
  # (arn:aws:s3:::* would reintroduce the over-broad grant this feature removes)
  # and no trailing /* (main.tf appends /* itself -> would yield <bucket>/*/*).
  validation {
    condition = alltrue(flatten([
      for k, v in var.byo_s3_irsa_roles : [
        for arn in v.bucket_arns : can(regex("^arn:aws:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", arn))
      ]
    ]))
    error_message = "byo_s3_irsa_roles[*].bucket_arns entries must be an exact bucket ARN 'arn:aws:s3:::<bucket>' (no wildcards, no trailing /*, no object key)."
  }
  # Each entry must be "<namespace>:<sa-name>" (the format the upstream IRSA
  # module expands into system:serviceaccount:<ns>:<sa>). A malformed subject
  # silently produces a trust condition no pod can satisfy.
  validation {
    condition = alltrue(flatten([
      for k, v in var.byo_s3_irsa_roles : [
        for s in v.namespace_service_accounts : can(regex("^[a-z0-9][a-z0-9.-]*:[a-z0-9][a-z0-9.-]*$", s))
      ]
    ]))
    error_message = "byo_s3_irsa_roles[*].namespace_service_accounts entries must be '<namespace>:<sa-name>' (both non-empty, lowercase DNS-safe, exactly one colon)."
  }
  validation {
    condition = alltrue([
      for k, v in var.byo_s3_irsa_roles :
      v.role_name_override == null ? true : can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", v.role_name_override))
    ])
    error_message = "byo_s3_irsa_roles[*].role_name_override must match ^[a-zA-Z0-9+=,.@_-]{1,64}$."
  }
  # IAM customer-managed policy name: 1-128 chars from [a-zA-Z0-9+=,.@_-].
  validation {
    condition = alltrue([
      for k, v in var.byo_s3_irsa_roles :
      v.policy_name_override == null ? true : can(regex("^[a-zA-Z0-9+=,.@_-]{1,128}$", v.policy_name_override))
    ])
    error_message = "byo_s3_irsa_roles[*].policy_name_override must match ^[a-zA-Z0-9+=,.@_-]{1,128}$."
  }
}

# Monitoring bootstrap (namespace + Grafana Secret) moved out of this module:
# namespace -> comet-infra umbrella (ArgoCD); Secret -> External Secrets Operator.
# Vars enable_monitoring_setup / manage_monitoring_secret / monitoring_namespace /
# grafana_admin_user / grafana_admin_password removed in v5.0.0.

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

variable "eks_clickhouse_use_name_prefix" {
  description = "Whether to treat eks_clickhouse_name as a prefix (true, AWS appends a unique suffix) or as the exact node group name (false). Set false to adopt an existing ClickHouse node group whose name is fixed (e.g. a single-AZ 'clickhouse-az2b' created out-of-band)."
  type        = bool
  default     = true
}

variable "eks_clickhouse_iam_role_name" {
  description = "Base name for the ClickHouse node group IAM role (the module appends a unique suffix via name_prefix). Defaults to '<node-group-name>-eks-node-group'. Set explicitly to decouple the role name from the node group name — e.g. when adopting a node group renamed out-of-band ('clickhouse-az2b') whose IAM role kept the original base ('clickhouse-eks-node-group'), so the role is not replaced."
  type        = string
  default     = null
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

  validation {
    condition     = !(var.enable_karpenter && var.enable_auto_mode)
    error_message = "enable_karpenter and enable_auto_mode are mutually exclusive: EKS Auto Mode provisions nodes natively, so Karpenter must be disabled when Auto Mode is on."
  }
}

variable "enable_auto_mode" {
  description = <<-EOT
    Enable EKS Auto Mode. When true, the EKS control plane can provision nodes
    natively via the built-in node pools in `auto_mode_node_pools`. Auto Mode is
    designed to COEXIST with managed node groups: the enabled MNGs (admin, comet,
    etc.) continue to run, and Auto Mode node pools provision additional capacity
    alongside them. Use MNGs for pinned/system workloads and Auto Mode for
    elastic capacity. The upstream module auto-creates and wires the Auto Mode
    node IAM role. Auto Mode also provides block storage, load balancing, and
    networking natively (the EBS CSI IRSA/addon, ALB controller, and gp3
    StorageClass can be migrated away separately). Mutually exclusive with
    enable_karpenter.
  EOT
  type        = bool
  default     = false
}

variable "auto_mode_node_pools" {
  description = <<-EOT
    Built-in EKS Auto Mode node pools to enable (control-plane managed, no
    manifests required). Common values: "system", "general-purpose". Only used
    when enable_auto_mode = true. Custom NodePool/NodeClass CRDs (taints, limits,
    instance shaping) are NOT created here — they are cluster-side objects and
    should be managed via GitOps (e.g. ArgoCD), especially for private-endpoint
    clusters the Terraform runner cannot reach.
  EOT
  type        = list(string)
  default     = ["system", "general-purpose"]
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

variable "karpenter_extra_tags" {
  description = "Extra EC2 instance tags applied to all Karpenter-provisioned nodes (e.g. Environment)"
  type        = map(string)
  default     = {}
}

# StorageClasses (gp3 + comet-generic) moved to the comet-infra umbrella chart
# (ArgoCD). Vars storage_class_reclaim_policy / create_comet_generic_storage_class
# removed in v5.0.0 — reclaim policy and comet-generic creation are chart values now.

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

#####################
#### EKS API ingress — standardized fleet-wide access patterns
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
#### Namespace nodegroup pinning + Redis Insights — REMOVED in v5.0.0
#####################
# The scheduler.alpha node-selector annotations (enable_namespace_nodegroup_pinning,
# app_namespace, admin_pinned_namespaces) targeted legacy managed node groups and are
# obsolete under EKS Auto Mode (NodePools/NodeClasses handle scheduling). The
# redis-insights namespace (enable_redis_insights_ns) moved to the agentro-role/rbac
# local module. All four variables were removed with the resources they fed.
