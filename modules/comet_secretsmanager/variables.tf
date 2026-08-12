variable "environment" {
  description = "Deployment environment, i.e. dev/stage/prod, etc"
  type        = string
}

variable "common_tags" {
  type        = map(string)
  description = "A map of common tags"
  default     = {}
}

########################
#### Secret Toggles ####
########################
variable "enable_config_secret" {
  description = "Enable creation of the config secret"
  type        = bool
  default     = true
}

variable "enable_monitoring_secret" {
  description = "Enable creation of the monitoring-secrets secret"
  type        = bool
  default     = true
}

variable "enable_clickhouse_secret" {
  description = "Enable creation of the clickhouse secret"
  type        = bool
  default     = true
}

variable "enable_registry_secret" {
  description = "Enable creation of the per-cluster docker.comet.com image-pull secret (cometml/<environment>/registry), consumed by ESO. Requires registry_dockerconfigjson. Default false to preserve existing behavior; set true (with the value wired from the canonical cometml/shared/registry) for clusters that source the pull secret from Secrets Manager instead of the comet-ml chart's Git-values hook."
  type        = bool
  default     = false
}

variable "registry_dockerconfigjson" {
  description = "Secret payload for cometml/<environment>/registry — a JSON object with a \".dockerconfigjson\" property holding the docker.comet.com config (ESO extracts that property). Read at the root from the canonical prod-account cometml/shared/registry secret. Null unless enable_registry_secret is true."
  type        = string
  default     = null
  sensitive   = true
}

# Database passwords
variable "mysql_password" {
  description = "MySQL password (used for MYSQL_PASSWORD, MYSQL_PASSWORD_RO, MYSQL_PASSWORD_RW, mysql-root-password, mysql-replication-password, mysql-password, STATE_DB_PASS, MYSQL_ADMIN_PASSWORD)"
  type        = string
  sensitive   = true
}

# Redis configuration
variable "redis_endpoint" {
  description = "Redis/ElastiCache endpoint"
  type        = string
}

variable "redis_port" {
  description = "Redis/ElastiCache port"
  type        = number
  default     = 6379
}

variable "redis_transit_encryption" {
  description = "Whether Redis transit encryption is enabled (determines redis:// vs rediss:// URL scheme)"
  type        = bool
}

variable "redis_token" {
  description = "Redis auth token"
  type        = string
  default     = "NA"
  sensitive   = true
}

# Secret seed
variable "secret_seed" {
  description = "Secret seed value. If not provided, a random value will be generated."
  type        = string
  default     = null
  sensitive   = true
}

# SendGrid
variable "sendgrid_api_key" {
  description = "Base64 encoded SendGrid API key"
  type        = string
  sensitive   = true
}

# S3 configuration (defaults to IAM-ROLE)
variable "s3_key" {
  description = "S3 key configuration"
  type        = string
  default     = "IAM-ROLE"
}

variable "s3_secret" {
  description = "S3 secret configuration"
  type        = string
  default     = "IAM-ROLE"
  sensitive   = true
}

variable "s3_private_key" {
  description = "S3 private key configuration"
  type        = string
  default     = "IAM-ROLE"
}

variable "s3_private_secret" {
  description = "S3 private secret configuration"
  type        = string
  default     = "IAM-ROLE"
  sensitive   = true
}

variable "s3_public_key" {
  description = "S3 public key configuration"
  type        = string
  default     = "IAM-ROLE"
}

variable "s3_public_secret" {
  description = "S3 public secret configuration"
  type        = string
  default     = "IAM-ROLE"
  sensitive   = true
}

###############################
#### Monitoring Secret Vars ####
###############################
variable "grafana_admin_user" {
  description = "Grafana admin username"
  type        = string
  default     = "admin"
}

variable "grafana_admin_password" {
  description = "Grafana admin password. Required when enable_monitoring_secret is true."
  type        = string
  default     = null
  sensitive   = true
}

###############################
#### ClickHouse Secret Vars ####
###############################
variable "clickhouse_monitoring_password" {
  description = "ClickHouse monitoring password. Required when enable_clickhouse_secret is true."
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
  description = "In-cluster DNS name of the ClickHouse HTTP service. The comet-monitoring chart's clickhouse-exporter pulls this from the clickhouse secret to populate its k8s Secret. If null, defaults to `clickhouse-opik-clickhouse.{environment}.svc.cluster.local` (the standard STSaaS pattern)."
  type        = string
  default     = null
}

variable "clickhouse_port" {
  description = "ClickHouse HTTP port (used by clickhouse-exporter via the clickhouse secret)."
  type        = string
  default     = "8123"
}

variable "clickhouse_monitoring_username" {
  description = "ClickHouse user the monitoring exporter authenticates as. Default `opikmonitoring` matches the user the comet-ml chart provisions in the cluster (see opik.clickhouse.monitoring.username)."
  type        = string
  default     = "opikmonitoring"
}
