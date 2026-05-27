output "proxy_endpoint" {
  description = "Writer endpoint of the RDS Proxy — clients connect here instead of the cluster endpoint"
  value       = aws_db_proxy.this.endpoint
}

output "proxy_arn" {
  description = "ARN of the RDS Proxy"
  value       = aws_db_proxy.this.arn
}

output "proxy_sg_id" {
  description = "Security group ID of the proxy ENIs"
  value       = aws_security_group.proxy.id
}

output "proxy_auth_secret_arn" {
  description = "ARN of the Secrets Manager secret holding proxy auth credentials"
  value       = aws_secretsmanager_secret.proxy_auth.arn
}
