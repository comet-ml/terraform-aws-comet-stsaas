output "config_secret_arn" {
  description = "ARN of the config Secrets Manager secret"
  value       = var.enable_config_secret ? aws_secretsmanager_secret.config[0].arn : null
}

output "config_secret_name" {
  description = "Name of the config Secrets Manager secret"
  value       = var.enable_config_secret ? aws_secretsmanager_secret.config[0].name : null
}

output "monitoring_secret_arn" {
  description = "ARN of the monitoring Secrets Manager secret"
  value       = var.enable_monitoring_secret ? aws_secretsmanager_secret.monitoring[0].arn : null
}

output "monitoring_secret_name" {
  description = "Name of the monitoring Secrets Manager secret"
  value       = var.enable_monitoring_secret ? aws_secretsmanager_secret.monitoring[0].name : null
}

output "clickhouse_secret_arn" {
  description = "ARN of the ClickHouse Secrets Manager secret"
  value       = var.enable_clickhouse_secret ? aws_secretsmanager_secret.clickhouse[0].arn : null
}

output "clickhouse_secret_name" {
  description = "Name of the ClickHouse Secrets Manager secret"
  value       = var.enable_clickhouse_secret ? aws_secretsmanager_secret.clickhouse[0].name : null
}
