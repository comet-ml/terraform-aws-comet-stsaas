data "aws_availability_zones" "available" {}

locals {
  resource_name = "comet-${var.environment}"
  vpc_cidr      = var.vpc_cidr
  azs           = slice(data.aws_availability_zones.available.names, 0, 3)

  # When EKS is enabled, set subnet tags for AWS Load Balancer Controller auto-discovery.
  eks_public_subnet_tags  = var.eks_enabled ? { "kubernetes.io/role/elb" = "1" } : {}
  eks_private_subnet_tags = var.eks_enabled ? { "kubernetes.io/role/internal-elb" = "1" } : {}

  # TGW Connect-attachment targeting tag — set on private subnets when TGW prep is enabled.
  # The attachment resource is created in a follow-on change.
  tgw_private_subnet_tags = var.enable_tgw_prep ? { tgw_connect = "true" } : {}

  default_interface_endpoint_services = [
    "ecr.api",
    "ecr.dkr",
    "sts",
    "ec2",
    "ec2messages",
    "ssm",
    "ssmmessages",
    "secretsmanager",
    "logs",
    "monitoring",
    "eks",
  ]
  interface_endpoint_services = (
    length(var.vpc_interface_endpoints_services) > 0
    ? var.vpc_interface_endpoints_services
    : local.default_interface_endpoint_services
  )
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0.0"

  name = "${local.resource_name}-vpc"
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 5, 3 * k + 1)]

  enable_nat_gateway   = true
  enable_dns_hostnames = true
  single_nat_gateway   = var.single_nat_gateway

  enable_flow_log                      = var.enable_vpc_flow_logs
  create_flow_log_cloudwatch_iam_role  = var.enable_vpc_flow_logs
  create_flow_log_cloudwatch_log_group = var.enable_vpc_flow_logs

  # Manage so we can name
  manage_default_network_acl    = true
  default_network_acl_tags      = merge(var.common_tags, { Name = "${local.resource_name}-default" })
  manage_default_route_table    = true
  default_route_table_tags      = merge(var.common_tags, { Name = "${local.resource_name}-default" })
  manage_default_security_group = true
  default_security_group_tags   = merge(var.common_tags, { Name = "${local.resource_name}-default" })

  public_subnet_tags = merge(
    local.eks_public_subnet_tags,
    var.public_subnet_tags,
  )
  private_subnet_tags = merge(
    local.eks_private_subnet_tags,
    local.tgw_private_subnet_tags,
    var.private_subnet_tags,
  )
}

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_endpoint ? 1 : 0

  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(module.vpc.private_route_table_ids, module.vpc.public_route_table_ids)
  tags = merge(
    var.common_tags,
    { Name = "${local.resource_name}-s3-endpoint" }
  )
}

# Shared SG for interface VPC endpoints — allows HTTPS from the VPC plus the agentro
# management surface (ArgoCD mgmt VPC + VPN client pool by default) so internal AWS API
# calls work after we flip EKS API / RDS / ElastiCache endpoints private-only.
resource "aws_security_group" "vpc_interface_endpoints" {
  count = var.enable_vpc_interface_endpoints ? 1 : 0

  name        = "${local.resource_name}-vpc-endpoints"
  description = "Allow HTTPS to interface VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  tags = merge(
    var.common_tags,
    { Name = "${local.resource_name}-vpc-endpoints" }
  )
}

resource "aws_vpc_security_group_ingress_rule" "vpc_interface_endpoints_https" {
  for_each = var.enable_vpc_interface_endpoints ? toset(concat(
    [module.vpc.vpc_cidr_block],
    var.vpc_interface_endpoints_allowed_cidrs,
  )) : []

  security_group_id = aws_security_group.vpc_interface_endpoints[0].id
  description       = "HTTPS to interface VPC endpoints from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

resource "aws_vpc_endpoint" "interface" {
  for_each = var.enable_vpc_interface_endpoints ? toset(local.interface_endpoint_services) : []

  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_interface_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(
    var.common_tags,
    { Name = "${local.resource_name}-${each.key}-endpoint" }
  )
}
