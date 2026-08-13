variable "environment" {
  description = "Deployment environment, i.e. dev/stage/prod, etc"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC that will contain the provisioned resources"
  type        = string
}

variable "elasticache_private_subnets" {
  description = "IDs of private subnets within the VPC"
  type        = list(string)
}

variable "elasticache_allow_from_sg" {
  description = "Security group from which connections to ElastiCache will be allowed"
  type        = string
}

variable "elasticache_engine" {
  description = "Engine type for Elasticache cluster"
  type        = string
}

variable "elasticache_engine_version" {
  description = "Version number for Elasticache engine"
  type        = string
}

variable "elasticache_instance_type" {
  description = "Elasticache instance type"
  type        = string
}

variable "elasticache_param_group_name" {
  description = "Name for the Elasticache cluster parameter group"
  type        = string
}

variable "elasticache_num_cache_nodes" {
  description = "Number of nodes in the Elasticache cluster"
  type        = number
}

variable "elasticache_transit_encryption" {
  description = "Enable transit encryption for ElastiCache"
  type        = bool
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
  description = "Ordered list of preferred AZs for cache cluster nodes. Length must equal elasticache_num_cache_nodes. Use to pin all nodes to a single AZ (e.g., [\"us-east-1b\"] with num_cache_nodes=1) to eliminate cross-AZ traffic. Null leaves AZ placement to AWS."
  type        = list(string)
  default     = null
}

variable "elasticache_auth_token" {
  description = "Auth token for ElastiCache"
  type        = string
  default     = null
}

variable "elasticache_auth_token_update_strategy" {
  description = "Strategy applied when elasticache_auth_token changes. Valid values: SET (replace immediately), ROTATE (add new token, keep old valid for transition), DELETE (remove auth)."
  type        = string
  default     = "ROTATE"

  validation {
    condition     = contains(["SET", "ROTATE", "DELETE"], var.elasticache_auth_token_update_strategy)
    error_message = "elasticache_auth_token_update_strategy must be one of SET, ROTATE, DELETE."
  }
}

variable "common_tags" {
  type        = map(string)
  description = "A map of common tags"
  default     = {}
}

variable "vpn_client_cidr" {
  description = "CIDR of the VPN client pool. Opened unconditionally on the Redis SG (port 6379) for operator port-forward access via the VPN (DND-752, DND-1522). Required — the root module always supplies it; the default lives only there so the value can't drift between submodules."
  type        = string
}
