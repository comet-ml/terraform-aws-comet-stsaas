variable "environment" {
  description = "Deployment environment, i.e. dev/stage/prod, etc"
  type        = string
}

variable "rds_cluster_identifier" {
  description = "Override for RDS cluster identifier. When null, uses default pattern 'cometml-rds-cluster-{environment}'."
  type        = string
  default     = null
}

variable "rds_instance_identifier_prefix" {
  description = "Override prefix for RDS instance identifiers. When null, uses default pattern 'cometml-rds-{environment}'. Instance index is appended."
  type        = string
  default     = null
}

variable "availability_zones" {
  description = "List of availability zones from VPC"
  type        = list(string)
}

variable "vpc_id" {
  description = "ID of the VPC that will contain the provisioned resources"
  type        = string
}

variable "rds_private_subnets" {
  description = "IDs of private subnets within the VPC"
  type        = list(string)
}

variable "rds_allow_from_sg" {
  description = "Security group from which to allow connections to RDS"
  type        = string
}

variable "rds_auto_mode_allow_from_sg" {
  description = "Additional security group allowed to reach RDS — the EKS Auto Mode cluster primary SG. Auto Mode nodes attach a different SG than managed node groups, so without this a pod on an Auto Mode node cannot reach MySQL. Null (default) creates no extra rule."
  type        = string
  default     = null
}

variable "rds_engine" {
  description = "Engine type for RDS database"
  type        = string
}

variable "rds_engine_version" {
  description = "Engine version number for RDS database"
  type        = string

  # Shape only, not an allowlist of 5.7|8.0|8.4: the parameter group family is derived
  # from the first two components, so a value like "8" or "" derives a nonexistent
  # family that passes plan (the precondition compares the derived value to itself) and
  # fails at apply with a raw AWS error. Pinning known families here would reject a
  # future 8.5 and recreate the trap the hardcoded family default already caused.
  #
  # The major/minor pair is canonical-only — no leading zeros ("08.0", "8.00") and no
  # empty suffix component ("8.0."). Those are typos of a real version rather than a
  # version this module should grow into: "08.0" derives aurora-mysql08.0, which does
  # not exist, and unlike an unrecognized-but-plausible 8.5 no Aurora release is ever
  # spelled that way. A wrong-but-existing major.minor (say 9.9) is still accepted here
  # and left to AWS, which rejects the engine_version itself.
  validation {
    condition     = can(regex("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(\\.[^.].*)?$", var.rds_engine_version))
    error_message = "rds_engine_version must be a canonical major.minor pair, optionally followed by a point-release suffix (e.g. \"8.0\" or \"8.0.mysql_aurora.3.11.1\") — no leading zeros and no trailing dot, because the parameter group family is derived from it."
  }
}

# Decoupled from rds_engine_version (DND-875): the family is coarse
# ("aurora-mysql8.0") while engine_version may be a pinned point release
# ("8.0.mysql_aurora.3.11.1"). Interpolating the version into the family yields
# a nonexistent family and forces parameter-group replacement.
#
# CHANGING THE FAMILY ON A LIVE CLUSTER NEEDS AN OUT-OF-BAND SEQUENCE. family is
# ForceNew on both parameter-group resources and their names are static, so a family
# change (e.g. an 8.0 -> 8.4 upgrade) plans a replacement terraform cannot execute:
# it destroys first, and AWS refuses to delete a parameter group still associated
# with a live cluster.
#
# Use a TEMPORARY group to detach terraform's own, rather than importing a renamed
# one — adopting a differently-named group leaves terraform wanting to rename it back
# (name is ForceNew too), so the next plan is another replacement and the destroy
# fails for the same reason. That does not terminate; this does:
#
#   1. Create a temporary parameter group out of band at the new family.
#   2. Modify the cluster to use it. Terraform's own group is now unattached.
#   3. Apply normally. Terraform destroys its group (the delete now succeeds),
#      recreates it at the new family under the same static name, and re-attaches
#      the cluster via db_cluster_parameter_group_name.
#   4. Delete the temporary group.
#
# Same shape for aws_db_parameter_group via db_instance_parameter_group_name.
variable "rds_parameter_group_family" {
  description = "Parameter group family for the cluster and DB parameter groups. Leave null to derive it from rds_engine + rds_engine_version, which is almost always what you want. This is NOT the engine version — only aurora-mysql5.7, aurora-mysql8.0 and aurora-mysql8.4 exist, and every Aurora MySQL 3.x point release uses aurora-mysql8.0. Changing it on a live cluster requires an out-of-band sequence; see the comment above this variable."
  type        = string
  default     = null

  validation {
    condition     = var.rds_parameter_group_family == null || can(regex("^aurora-mysql(5\\.7|8\\.0|8\\.4)$", var.rds_parameter_group_family))
    error_message = "rds_parameter_group_family must be null (derived from the engine version) or one of: aurora-mysql5.7, aurora-mysql8.0, aurora-mysql8.4."
  }
}

variable "rds_auto_minor_version_upgrade" {
  description = "Let AWS apply Aurora minor version upgrades during the maintenance window. Defaults to false: with a pinned rds_engine_version, an AWS-initiated upgrade makes the next plan attempt a downgrade back to the pin, which Aurora rejects and which fails every apply until someone re-pins by hand."
  type        = bool
  default     = false
}

variable "rds_instance_type" {
  description = "Instance type for RDS database. Ignored when rds_serverless_v2_enabled = true (db.serverless is used)."
  type        = string
}

variable "rds_instance_count" {
  description = "Number of RDS instances in the database cluster"
  type        = number
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
}

variable "rds_iam_db_auth" {
  description = "Enables IAM auth for the database in RDS"
  type        = bool
}

variable "rds_backup_retention_period" {
  description = "Days specified for RDS snapshotretention period"
  type        = number
}

variable "rds_preferred_backup_window" {
  description = "Backup window for RDS"
  type        = string
}

variable "rds_database_name" {
  description = "Name for the application database in RDS"
  type        = string
}

variable "rds_master_username" {
  description = "Master username for RDS database"
  type        = string
  default     = "admin"
}

variable "rds_master_password" {
  description = "Master password for RDS database"
  type        = string
}

variable "common_tags" {
  type        = map(string)
  description = "A map of common tags"
  default     = {}
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

# DND-1537: without these, no STSaaS cluster exported anything and the MySQL error log
# was unreadable — agentro is granted rds:DescribeDBLogFiles but not
# rds:DownloadDBLogFilePortion, so an investigation could see that a log file existed
# and how large it was, but not a byte of its contents. Exporting to CloudWatch Logs
# closes that without widening the IAM role.
variable "rds_enabled_cloudwatch_logs_exports" {
  description = "MySQL log types the CLUSTER exports to CloudWatch Logs. 'error' carries the entries that matter for post-mortems (CUST-6816). 'slowquery' produces nothing unless slow_query_log=1 is also set via rds_cluster_parameters — it is enabled here so the log group exists and is retention-managed from the moment that parameter is turned on. Pass [] to stop exporting; the log groups themselves are governed separately by rds_managed_log_group_types, so disabling an export never removes a group from state."
  type        = list(string)
  default     = ["error", "slowquery"]

  validation {
    condition     = alltrue([for t in var.rds_enabled_cloudwatch_logs_exports : contains(["audit", "error", "general", "slowquery"], t)])
    error_message = "Valid Aurora MySQL log types are: audit, error, general, slowquery."
  }
}

# Deliberately separate from rds_enabled_cloudwatch_logs_exports: one variable driving both
# the cluster attribute and the log-group for_each would make disabling an export a one-way
# door. The group would leave state while surviving in AWS (skip_destroy), and re-enabling
# the export later would fail on ResourceAlreadyExistsException — the same collision this
# whole change exists to prevent, just deferred and self-inflicted.
#
# Keeping them apart means toggling an export is purely a cluster-attribute change. A type
# listed here but not exported yields an empty log group with retention already set, which
# is the desired state for slowquery on the 15 clusters where slow_query_log=0.
variable "rds_managed_log_group_types" {
  description = "MySQL log types whose CloudWatch log groups this module creates and manages retention for. Should be a superset of rds_enabled_cloudwatch_logs_exports — a type listed here but not exported simply yields an empty group with retention already applied, ready for when the export (or slow_query_log) is switched on. Removing a type here stops managing its group; it is NOT deleted, because of skip_destroy."
  type        = list(string)
  default     = ["error", "slowquery"]

  validation {
    condition     = alltrue([for t in var.rds_managed_log_group_types : contains(["audit", "error", "general", "slowquery"], t)])
    error_message = "Valid Aurora MySQL log types are: audit, error, general, slowquery."
  }
}

# The cluster and Performance Insights both take a KMS key; the log groups should too.
# Left at the service-managed key by default (no behaviour change), but exposed now rather
# than after this reaches 16 clusters — retrofitting it later means touching every env a
# second time, at exactly the moment DND-1537 flips slow_query_log=1 and the groups start
# carrying customer SQL text. Also what trivy AVD-AWS-0017 asks for.
variable "rds_log_kms_key_id" {
  description = "ARN of a KMS key to encrypt the RDS CloudWatch log groups. Default null uses the CloudWatch service-managed key. Worth setting for environments whose slow query log will carry customer SQL text. When first setting this, the KMS key policy must grant logs.<region>.amazonaws.com permission to use the key, or CreateLogGroup fails with InvalidParameterException — which reads like a terraform problem and is not."
  type        = string
  default     = null
}

# RDS auto-creates /aws/rds/cluster/<id>/<type> with NO retention ("never expire") the
# instant an export is enabled. That is how the pre-rebuild zoox slowquery group came to
# hold 3.65 GB of dead data indefinitely (DND-1537). The groups are therefore created
# explicitly, with retention, and the cluster depends on them so they exist first.
# 0 ("never expire") is deliberately NOT accepted. It is what RDS applies when it creates
# these groups itself, and the reason DND-1537 found an orphan holding 3.65 GB of dead data
# indefinitely — a module whose purpose is to prevent that should not offer it as an option.
# These groups carry error and slow-query logs, i.e. customer SQL text once slow_query_log
# is on, so unbounded retention is the wrong default to make reachable. 3653 (10 years) is
# available if something genuinely needs to keep them a long time.
variable "rds_log_retention_days" {
  description = "Retention for the RDS CloudWatch log groups, in days. Must be finite — 'never expire' is not offered, see DND-1537."
  type        = number
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.rds_log_retention_days)
    error_message = "Must be a finite retention period CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653). 0 / never-expire is intentionally not permitted."
  }
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

variable "rds_cluster_parameters" {
  description = "Additional MySQL parameters applied to the cluster parameter group on top of the module's baseline character-set/collation/innodb defaults. Defaults include operational tunings (wait_timeout, max_execution_time, innodb purge settings, aurora_read_replica_read_committed) used across Comet STSAAS deployments, plus innodb_monitor_enable=module_trx so information_schema.INNODB_METRICS exposes transaction-subsystem counters (powers the 'Active Transactions' panel on the comet-rds-overview Grafana dashboard — DND-1307 / DND-1263). Pass [] to disable, or override with a custom list."
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
    { name = "innodb_monitor_enable", value = "module_trx", apply_method = "immediate" },
  ]
}

variable "rds_require_secure_transport" {
  description = "Reject MySQL connections that don't use TLS. Sets require_secure_transport=ON on the cluster parameter group (Aurora MySQL value format; vanilla MySQL uses 1/0). Applies pending-reboot. Default false to preserve existing behavior; new STSAAS customers should onboard with this true."
  type        = bool
  default     = false
}

variable "rds_db_parameters" {
  description = "Per-instance MySQL parameters applied to the DB-instance parameter group. Use this for parameters that should override the cluster-level pg on individual instances (e.g. operational tunings, instance-specific monitoring). Empty by default to preserve current behavior — every customer historically inherited only the cluster pg."
  type = list(object({
    name         = string
    value        = string
    apply_method = string
  }))
  default = []
}
