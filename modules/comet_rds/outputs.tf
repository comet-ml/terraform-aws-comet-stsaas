output "mysql_host" {
  description = "MySQL cluster (writer) endpoint"
  value       = aws_rds_cluster.cometml-db-cluster.endpoint
}

output "mysql_reader_host" {
  description = "MySQL cluster reader endpoint"
  value       = aws_rds_cluster.cometml-db-cluster.reader_endpoint
}

output "mysql_port" {
  description = "MySQL port"
  value       = aws_rds_cluster.cometml-db-cluster.port
}

output "mysql_database_name" {
  description = "MySQL database name"
  value       = aws_rds_cluster.cometml-db-cluster.database_name
}

output "mysql_cluster_id" {
  description = "Aurora MySQL cluster identifier"
  value       = aws_rds_cluster.cometml-db-cluster.id
}

output "mysql_sg_id" {
  description = "Security group ID of the MySQL cluster"
  value       = aws_security_group.mysql_sg.id
}

# DND-1537: every cluster whose export was enabled out-of-band needs its existing group
# imported before it can adopt this module, so the import address has to be derivable
# rather than hand-assembled up to fifteen times. ARNs are what alarms and metric filters
# will want.
output "mysql_log_group_names" {
  description = "CloudWatch log group names for the exported RDS logs, keyed by log type. Use when adopting a cluster whose export was enabled out-of-band: terraform import 'module.<path>.aws_cloudwatch_log_group.rds_exported_logs[\"error\"]' <name>"
  value       = { for t, lg in aws_cloudwatch_log_group.rds_exported_logs : t => lg.name }
}

output "mysql_log_group_arns" {
  description = "CloudWatch log group ARNs for the exported RDS logs, keyed by log type. For metric filters, subscription filters and alarm targets."
  value       = { for t, lg in aws_cloudwatch_log_group.rds_exported_logs : t => lg.arn }
}
