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

variable "rds_engine" {
  description = "Engine type for RDS database. Only aurora-mysql is supported: it supplies the parameter group family prefix, and the family derivation takes the version's first two components, which is the aurora-mysql convention. aurora-postgresql families are major-only (aurora-postgresql15, not aurora-postgresql15.2), so the derivation would produce a nonexistent family."
  type        = string

  # Also validated at the root, but repeated here because this module is usable
  # directly: without it a direct caller passing aurora-postgresql gets a malformed
  # family and a raw AWS error at apply instead of a message at plan.
  validation {
    condition     = var.rds_engine == "aurora-mysql"
    error_message = "rds_engine must be aurora-mysql — it is the only supported engine. The parameter group family is derived as <engine><major>.<minor>, which is the aurora-mysql convention; aurora-postgresql uses major-only families."
  }
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
  # The major/minor pair is canonical-only — no leading zeros ("08.0", "8.00") — and
  # every suffix component must be non-empty, so "8.0.", "8.0..1" and a trailing
  # "…3.11.1." are all rejected. Those are typos of a real version rather than a
  # version this module should grow into: "08.0" derives aurora-mysql08.0, which does
  # not exist, and unlike an unrecognized-but-plausible 8.5 no Aurora release is ever
  # spelled that way. A wrong-but-existing major.minor (say 9.9) is still accepted here
  # and left to AWS, which rejects the engine_version itself.
  validation {
    condition     = can(regex("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(\\.[^.]+)*$", var.rds_engine_version))
    error_message = "rds_engine_version must be a canonical major.minor pair, optionally followed by dot-separated point-release components (e.g. \"8.0\" or \"8.0.mysql_aurora.3.11.1\") — no leading zeros, and no empty component or trailing dot, because the parameter group family is derived from it."
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
  description = "Let AWS apply Aurora minor version upgrades during the maintenance window. Null leaves the current AWS-side setting untouched (v2.1.x never managed this attribute, so existing clusters are at AWS's default of true). Set false alongside a pinned rds_engine_version: otherwise an AWS-initiated upgrade makes the next plan attempt a downgrade back to the pin, which Aurora rejects, failing every apply until someone re-pins by hand."
  type        = bool
  default     = null

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
