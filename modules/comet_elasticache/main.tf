locals {
  redis_port = 6379
}

resource "aws_elasticache_replication_group" "comet-ml-ec-redis" {
  engine                     = var.elasticache_engine
  engine_version             = var.elasticache_engine_version
  transit_encryption_enabled = var.elasticache_transit_encryption
  auth_token                 = var.elasticache_auth_token
  # AWS provider v6 errors when auth_token_update_strategy is set on a replication
  # group that has no auth_token, with one exception: the explicit removal path
  # auth_token=null + auth_token_update_strategy="DELETE" must reach AWS.
  auth_token_update_strategy  = (var.elasticache_auth_token != null || var.elasticache_auth_token_update_strategy == "DELETE") ? var.elasticache_auth_token_update_strategy : null
  automatic_failover_enabled  = var.elasticache_automatic_failover_enabled
  multi_az_enabled            = var.elasticache_multi_az_enabled
  preferred_cache_cluster_azs = var.elasticache_preferred_cache_cluster_azs
  replication_group_id        = "cometml-ec-redis-${var.environment}"
  node_type                   = var.elasticache_instance_type
  num_cache_clusters          = var.elasticache_num_cache_nodes
  parameter_group_name        = var.elasticache_param_group_name
  port                        = local.redis_port
  subnet_group_name           = aws_elasticache_subnet_group.comet-ml-ec-subnet-group.name
  security_group_ids          = [aws_security_group.redis_inbound_sg.id]
  description                 = "Redis for CometML"
  apply_immediately           = true

  tags = merge(
    var.common_tags,
    {
      Name = "cometml-ec-redis-${var.environment}"
    }
  )
}

resource "aws_elasticache_subnet_group" "comet-ml-ec-subnet-group" {
  name       = "cometml-ec-sng-${var.environment}"
  subnet_ids = var.elasticache_private_subnets

  tags = merge(
    var.common_tags,
    {
      Name = "cometml-ec-sng-${var.environment}"
    }
  )
}

resource "aws_security_group" "redis_inbound_sg" {
  name        = "cometml_redis_in_sg_${var.environment}"
  description = "Redis Security Group"
  vpc_id      = var.vpc_id

  tags = merge(
    var.common_tags,
    {
      Name = "cometml_redis_in_sg_${var.environment}"
    }
  )
}

resource "aws_vpc_security_group_ingress_rule" "redis_port_inbound_rule" {
  security_group_id = aws_security_group.redis_inbound_sg.id

  from_port                    = local.redis_port
  to_port                      = local.redis_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.elasticache_allow_from_sg
}
# VPN ingress to Redis (DND-752) — gated by enable_vpn_redis_access. Allows
# operators on the VPN to connect to Redis via kubectl port-forward through
# the cluster's Redis SG.
resource "aws_vpc_security_group_ingress_rule" "redis_vpn" {
  count = var.enable_vpn_redis_access ? 1 : 0

  security_group_id = aws_security_group.redis_inbound_sg.id
  description       = "VPN client access (DND-752)"
  from_port         = local.redis_port
  to_port           = local.redis_port
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpn_client_cidr

  tags = merge(var.common_tags, { Name = "redis-vpn-access" })
}
