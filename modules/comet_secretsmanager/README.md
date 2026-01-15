# comet_secretsmanager

This module provisions AWS Secrets Manager secrets for storing Comet configuration.

## Resources Created (Toggleable)

| Secret | Path | Toggle Variable | Default |
|--------|------|-----------------|---------|
| Config | `cometml/{environment}/config` | `enable_config_secret` | `true` |
| Monitoring | `cometml/{environment}/monitoring-secrets` | `enable_monitoring_secret` | `false` |
| ClickHouse | `cometml/{environment}/clickhouse` | `enable_clickhouse_secret` | `false` |

## Config Secret Structure

The config secret contains the following keys:

| Key | Description |
|-----|-------------|
| MYSQL_PASSWORD | MySQL password |
| mysql-root-password | MySQL root password (same as MYSQL_PASSWORD) |
| mysql-replication-password | MySQL replication password (same as MYSQL_PASSWORD) |
| mysql-password | MySQL password (same as MYSQL_PASSWORD) |
| STATE_DB_PASS | State database password (same as MYSQL_PASSWORD) |
| MYSQL_ADMIN_PASSWORD | MySQL admin password (same as MYSQL_PASSWORD) |
| REDIS_TOKEN | Redis auth token |
| REDIS_URL | Redis URL (redis:// or rediss:// based on TLS setting) |
| SECRET_SEED | Secret seed (auto-generated if not provided) |
| SENDGRID_API_KEY | Base64 encoded SendGrid API key |
| S3_KEY | S3 key configuration |
| S3_SECRET | S3 secret configuration |
| S3_PRIVATE_KEY | S3 private key configuration |
| S3_PRIVATE_SECRET | S3 private secret configuration |
| S3_PUBLIC_KEY | S3 public key configuration |
| S3_PUBLIC_SECRET | S3 public secret configuration |
| access_key_id | AWS access key ID (empty) |
| access_key_secret | AWS access key secret (empty) |
| AWS_ACCESS_KEY_ID | AWS access key ID (empty) |
| AWS_SECRET_ACCESS_KEY | AWS secret access key (empty) |

## Monitoring Secret Structure

The monitoring secret contains the following keys:

| Key | Description |
|-----|-------------|
| grafana-admin-password | Grafana admin password |
| grafana-admin-user | Grafana admin username (defaults to "admin") |

## ClickHouse Secret Structure

The clickhouse secret contains the following keys:

| Key | Description |
|-----|-------------|
| monitoring_pass | ClickHouse monitoring password |

## Usage

```hcl
module "comet_secretsmanager" {
  source = "./modules/comet_secretsmanager"

  environment = var.environment
  common_tags = local.all_tags

  # Secret toggles
  enable_config_secret     = true   # Default
  enable_monitoring_secret = false  # Default
  enable_clickhouse_secret = false  # Default

  # Required (when enable_config_secret = true)
  mysql_password           = var.rds_master_password
  redis_endpoint           = module.comet_elasticache[0].redis_endpoint
  redis_port               = module.comet_elasticache[0].redis_port
  redis_transit_encryption = module.comet_elasticache[0].transit_encryption_enabled
  sendgrid_api_key         = var.sendgrid_api_key

  # Optional (config secret)
  secret_seed       = var.secret_seed  # Auto-generated if null
  redis_token       = "NA"
  s3_key            = "IAM-ROLE"
  s3_secret         = "IAM-ROLE"
  s3_private_key    = "IAM-ROLE"
  s3_private_secret = "IAM-ROLE"
  s3_public_key     = "IAM-ROLE"
  s3_public_secret  = "IAM-ROLE"

  # Required (when enable_monitoring_secret = true)
  grafana_admin_password = var.grafana_admin_password

  # Optional (monitoring secret)
  grafana_admin_user = "admin"  # Default

  # Required (when enable_clickhouse_secret = true)
  clickhouse_monitoring_password = var.clickhouse_monitoring_password
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| environment | Deployment environment, i.e. dev/stage/prod, etc | `string` | n/a | yes |
| enable_config_secret | Enable creation of the config secret | `bool` | `true` | no |
| enable_monitoring_secret | Enable creation of the monitoring-secrets secret | `bool` | `false` | no |
| enable_clickhouse_secret | Enable creation of the clickhouse secret | `bool` | `false` | no |
| mysql_password | MySQL password | `string` | n/a | yes |
| redis_endpoint | Redis/ElastiCache endpoint | `string` | n/a | yes |
| redis_port | Redis/ElastiCache port | `number` | `6379` | no |
| redis_transit_encryption | Whether Redis transit encryption is enabled | `bool` | n/a | yes |
| sendgrid_api_key | Base64 encoded SendGrid API key | `string` | n/a | yes |
| common_tags | A map of common tags | `map(string)` | `{}` | no |
| secret_seed | Secret seed value (auto-generated if null) | `string` | `null` | no |
| redis_token | Redis auth token | `string` | `"NA"` | no |
| s3_key | S3 key configuration | `string` | `"IAM-ROLE"` | no |
| s3_secret | S3 secret configuration | `string` | `"IAM-ROLE"` | no |
| s3_private_key | S3 private key configuration | `string` | `"IAM-ROLE"` | no |
| s3_private_secret | S3 private secret configuration | `string` | `"IAM-ROLE"` | no |
| s3_public_key | S3 public key configuration | `string` | `"IAM-ROLE"` | no |
| s3_public_secret | S3 public secret configuration | `string` | `"IAM-ROLE"` | no |
| grafana_admin_user | Grafana admin username | `string` | `"admin"` | no |
| grafana_admin_password | Grafana admin password | `string` | `null` | yes (if monitoring enabled) |
| clickhouse_monitoring_password | ClickHouse monitoring password | `string` | `null` | yes (if clickhouse enabled) |

## Outputs

| Name | Description |
|------|-------------|
| config_secret_arn | ARN of the config Secrets Manager secret |
| config_secret_name | Name of the config Secrets Manager secret |
| monitoring_secret_arn | ARN of the monitoring Secrets Manager secret |
| monitoring_secret_name | Name of the monitoring Secrets Manager secret |
| clickhouse_secret_arn | ARN of the ClickHouse Secrets Manager secret |
| clickhouse_secret_name | Name of the ClickHouse Secrets Manager secret |