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