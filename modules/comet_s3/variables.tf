variable "environment" {
  description = "Deployment environment, i.e. dev/stage/prod, etc"
  type        = string
}

variable "comet_s3_bucket" {
  description = "Name of S3 bucket"
  type        = string
}

variable "s3_force_destroy" {
  description = "Option to enable force delete of S3 bucket"
  type        = bool
}

variable "enable_mpm_infra" {
  description = "Sets buckets to be created for MPM Druid/Airflow"
  type        = bool
}

variable "enable_loki_bucket" {
  description = "Enable creation of S3 bucket for Loki logs"
  type        = bool
  default     = false
}

# Default null keeps the computed "comet-loki-${environment}-${suffix}" name. Set to
# adopt an existing differently-named bucket (e.g. legacy "zoox-loki") by import/state-mv
# instead of recreating it (which would destroy the live loki log data).
variable "loki_bucket_name_override" {
  description = "Override the Loki S3 bucket name. Null keeps the module-computed comet-loki-<environment>-<suffix> name."
  type        = string
  default     = null
}

variable "common_tags" {
  type        = map(string)
  description = "A map of common tags"
  default     = {}
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
  description = "Lifecycle rules applied to the comet S3 bucket when enable_s3_lifecycle = true. Each rule is `{id, status?, filter_prefix?, abort_incomplete_multipart_upload_days?, expiration_days?, noncurrent_version_expiration_days?, transitions: [{days, storage_class}]}`. Defaults match DND-1261 (delete-old-versions + FilesOlderThan12Months tier-down). Override to change retention/tiering per customer."
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
  description = "Lifecycle rules applied to the loki S3 bucket when enable_s3_lifecycle = true and enable_loki_bucket = true. Defaults match DND-1261 (delete-old-versions noncurrent-30d + transition-to-IA at 30d). Same schema as comet_bucket_lifecycle_rules."
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
