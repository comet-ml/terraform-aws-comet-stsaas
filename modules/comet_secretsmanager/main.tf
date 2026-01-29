resource "random_id" "secret_seed" {
  count       = var.enable_config_secret && var.secret_seed == null ? 1 : 0
  byte_length = 32
}

locals {
  secret_seed  = var.enable_config_secret ? (var.secret_seed != null ? var.secret_seed : random_id.secret_seed[0].hex) : null
  redis_scheme = var.redis_transit_encryption ? "rediss" : "redis"
  redis_url    = "${local.redis_scheme}://${var.redis_endpoint}:${var.redis_port}/"

  config_secret_value = var.enable_config_secret ? jsonencode({
    MYSQL_PASSWORD             = var.mysql_password
    MYSQL_PASSWORD_RO          = var.mysql_password
    MYSQL_PASSWORD_RW          = var.mysql_password
    REDIS_TOKEN                = var.redis_token
    S3_KEY                     = var.s3_key
    S3_PRIVATE_KEY             = var.s3_private_key
    S3_PRIVATE_SECRET          = var.s3_private_secret
    S3_PUBLIC_KEY              = var.s3_public_key
    S3_PUBLIC_SECRET           = var.s3_public_secret
    S3_SECRET                  = var.s3_secret
    SECRET_SEED                = local.secret_seed
    mysql-root-password        = var.mysql_password
    mysql-replication-password = var.mysql_password
    mysql-password             = var.mysql_password
    access_key_id              = ""
    access_key_secret          = ""
    STATE_DB_PASS              = var.mysql_password
    REDIS_URL                  = local.redis_url
    SENDGRID_API_KEY           = var.sendgrid_api_key
    MYSQL_ADMIN_PASSWORD       = var.mysql_password
    AWS_ACCESS_KEY_ID          = ""
    AWS_SECRET_ACCESS_KEY      = ""
  }) : null
}

#######################
#### Config Secret ####
#######################
resource "aws_secretsmanager_secret" "config" {
  count = var.enable_config_secret ? 1 : 0

  name        = "cometml/${var.environment}/config"
  description = "${var.environment} Config Secrets Manager"

  tags = var.common_tags
}

resource "aws_secretsmanager_secret_version" "config" {
  count = var.enable_config_secret ? 1 : 0

  secret_id     = aws_secretsmanager_secret.config[0].id
  secret_string = local.config_secret_value
}

############################
#### Monitoring Secret ####
############################
resource "aws_secretsmanager_secret" "monitoring" {
  count = var.enable_monitoring_secret ? 1 : 0

  name        = "cometml/${var.environment}/monitoring-secrets"
  description = "${var.environment} Monitoring Secrets Manager"

  tags = var.common_tags
}

resource "aws_secretsmanager_secret_version" "monitoring" {
  count = var.enable_monitoring_secret ? 1 : 0

  secret_id = aws_secretsmanager_secret.monitoring[0].id
  secret_string = jsonencode({
    grafana-admin-password = var.grafana_admin_password
    grafana-admin-user     = var.grafana_admin_user
  })
}

############################
#### ClickHouse Secret ####
############################
resource "aws_secretsmanager_secret" "clickhouse" {
  count = var.enable_clickhouse_secret ? 1 : 0

  name        = "cometml/${var.environment}/clickhouse"
  description = "${var.environment} ClickHouse Secrets Manager"

  tags = var.common_tags
}

resource "aws_secretsmanager_secret_version" "clickhouse" {
  count = var.enable_clickhouse_secret ? 1 : 0

  secret_id = aws_secretsmanager_secret.clickhouse[0].id
  secret_string = jsonencode({
    monitoring_pass = var.clickhouse_monitoring_password
  })
}
