variable "environment" {
  description = "Deployment environment, i.e. dev/stage/prod, etc"
  type        = string
}

variable "common_tags" {
  type        = map(string)
  description = "Tags applied to all resources"
  default     = {}
}

variable "vpc_id" {
  description = "ID of the VPC the proxy ENIs live in"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs the proxy ENIs are placed in (private subnets of the VPC, matching the RDS cluster)"
  type        = list(string)
}

variable "allowed_sg_ids" {
  description = "Security group IDs allowed to connect to the proxy on the MySQL port (typically the EKS nodegroup SG)"
  type        = list(string)
  default     = []
}

variable "mysql_cluster_id" {
  description = "Aurora MySQL cluster identifier the proxy targets"
  type        = string
}

variable "mysql_sg_id" {
  description = "Security group ID of the MySQL cluster — the module adds an ingress rule to allow the proxy SG to reach it"
  type        = string
}

variable "mysql_master_username" {
  description = "MySQL master username (written to the proxy auth secret)"
  type        = string
}

variable "mysql_master_password" {
  description = "MySQL master password (written to the proxy auth secret)"
  type        = string
  sensitive   = true
}

variable "require_tls" {
  description = "Require TLS for client connections to the proxy. Recommended ON when rds_require_secure_transport is true at the cluster."
  type        = bool
  default     = true
}

variable "idle_client_timeout" {
  description = "Seconds a client connection can be idle before the proxy closes it"
  type        = number
  default     = 1800
}

variable "debug_logging" {
  description = "Enable proxy debug logging (verbose; useful when troubleshooting connection issues, otherwise off)"
  type        = bool
  default     = false
}

variable "max_connections_percent" {
  description = "Maximum percentage of the cluster's max_connections the proxy will open. Defaults match AWS guidance for Aurora MySQL."
  type        = number
  default     = 100
}

variable "max_idle_connections_percent" {
  description = "Maximum percentage of idle connections the proxy will keep warm"
  type        = number
  default     = 50
}

variable "connection_borrow_timeout" {
  description = "Seconds a client request waits for an available connection from the pool before failing"
  type        = number
  default     = 120
}
