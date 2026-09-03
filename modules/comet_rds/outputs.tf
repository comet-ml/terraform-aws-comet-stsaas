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
# rather than hand-assembled up to fifteen times.
#
# These are the MANAGED groups (rds_managed_log_group_types), deliberately not the exported
# ones — import needs every group under management, including a `slowquery` group that is
# still empty because slow_query_log=0. Consumers wiring alarms or metric filters want
# mysql_exported_log_types below to filter by, or they will alarm on a group nothing writes to.
output "mysql_log_group_names" {
  description = "CloudWatch log group names for the RDS log groups this module MANAGES, keyed by log type. Superset of what is actively exported — cross-reference mysql_exported_log_types. Use when adopting a cluster whose export was enabled out-of-band: comet_rds is counted, so the index is required, and the address is relative to the caller: terraform import 'module.comet.module.comet_rds[0].aws_cloudwatch_log_group.rds_exported_logs[\"error\"]' <name>"
  value       = { for t, lg in aws_cloudwatch_log_group.rds_exported_logs : t => lg.name }
}

output "mysql_log_group_arns" {
  description = "CloudWatch log group ARNs for the RDS log groups this module MANAGES, keyed by log type. Superset of what is actively exported — filter by mysql_exported_log_types before attaching metric filters, subscription filters or alarms, or you will target a group nothing writes to."
  value       = { for t, lg in aws_cloudwatch_log_group.rds_exported_logs : t => lg.arn }
}

output "mysql_exported_log_types" {
  description = "MySQL log types the cluster is actively exporting. Subset of the keys in mysql_log_group_names / mysql_log_group_arns. Note a type can be exported and still produce nothing — 'slowquery' stays empty until slow_query_log=1 is set via rds_cluster_parameters."
  value       = aws_rds_cluster.cometml-db-cluster.enabled_cloudwatch_logs_exports
}
