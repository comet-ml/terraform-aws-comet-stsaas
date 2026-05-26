variable "environment" {
  description = "Deployment environment, i.e. dev/stage/prod, etc"
  type        = string
}

variable "eks_enabled" {
  description = "Indicates if EKS module enabled"
  type        = bool
}

variable "single_nat_gateway" {
  description = "Controls whether single NAT gateway used for all public subnets"
  type        = bool
}

variable "common_tags" {
  type        = map(string)
  description = "A map of common tags"
  default     = {}
}

variable "region" {
  description = "AWS region to provision resources in"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (must be a valid RFC1918 private range)"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be valid CIDR notation."
  }

  validation {
    condition = anytrue([
      can(regex("^10\\.", var.vpc_cidr)),
      can(regex("^172\\.(1[6-9]|2[0-9]|3[01])\\.", var.vpc_cidr)),
      can(regex("^192\\.168\\.", var.vpc_cidr)),
    ])
    error_message = "vpc_cidr must be inside an RFC1918 private range (10/8, 172.16/12, or 192.168/16)."
  }
}

variable "private_subnet_tags" {
  type        = map(string)
  description = "A map of tags for private subnets"
  default     = {}
}

variable "public_subnet_tags" {
  type        = map(string)
  description = "A map of tags for public subnets"
  default     = {}
}

variable "enable_tgw_prep" {
  description = "Tag private subnets with tgw_connect=true so a future TGW attachment can target them. The attachment itself is created separately."
  type        = bool
  default     = false
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
