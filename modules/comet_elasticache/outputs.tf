output "redis_endpoint" {
  description = "Primary endpoint for the Redis replication group"
  value       = aws_elasticache_replication_group.comet-ml-ec-redis.primary_endpoint_address
}

output "redis_port" {
  description = "Port for the Redis replication group"
  value       = local.redis_port
}

output "redis_sg_id" {
  description = "Security group ID of the Redis replication group"
  value       = aws_security_group.redis_inbound_sg.id
}

output "transit_encryption_enabled" {
  description = "Whether transit encryption is enabled"
  value       = aws_elasticache_replication_group.comet-ml-ec-redis.transit_encryption_enabled
}
