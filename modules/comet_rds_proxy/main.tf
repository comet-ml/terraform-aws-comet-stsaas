locals {
  resource_name = "cometml-rds-proxy-${var.environment}"
  secret_name   = "cometml/${var.environment}/rds-proxy-auth"
}

# Dedicated Secrets Manager secret in the format RDS Proxy requires:
# {"username": "...", "password": "..."}. The existing comet_secretsmanager
# config secret has the password split across many app-specific keys and isn't
# usable directly by RDS Proxy.
resource "aws_secretsmanager_secret" "proxy_auth" {
  name = local.secret_name

  tags = merge(
    var.common_tags,
    { Name = local.secret_name }
  )
}

resource "aws_secretsmanager_secret_version" "proxy_auth" {
  secret_id = aws_secretsmanager_secret.proxy_auth.id
  secret_string = jsonencode({
    username = var.mysql_master_username
    password = var.mysql_master_password
  })
}

# Proxy IAM role: trusts the RDS service, reads the auth secret.
resource "aws_iam_role" "proxy" {
  name = "${local.resource_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "rds.amazonaws.com" }
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "proxy_read_secret" {
  name = "${local.resource_name}-read-secret"
  role = aws_iam_role.proxy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = aws_secretsmanager_secret.proxy_auth.arn
    }]
  })
}

# Dedicated SG for proxy ENIs. Ingress allowed from caller-provided SGs
# (typically the EKS nodegroup SG) on the MySQL port.
resource "aws_security_group" "proxy" {
  name        = "${local.resource_name}-sg"
  description = "RDS Proxy ENIs"
  vpc_id      = var.vpc_id

  tags = merge(
    var.common_tags,
    { Name = "${local.resource_name}-sg" }
  )
}

resource "aws_vpc_security_group_ingress_rule" "proxy_from_caller" {
  for_each = toset(var.allowed_sg_ids)

  security_group_id            = aws_security_group.proxy.id
  description                  = "MySQL from ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = each.value
}

resource "aws_vpc_security_group_ingress_rule" "proxy_from_cidr" {
  for_each = toset(var.allowed_cidrs)

  security_group_id = aws_security_group.proxy.id
  description       = "MySQL from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 3306
  to_port           = 3306
  cidr_ipv4         = each.value
}

# Allow the proxy SG to reach the MySQL cluster SG.
resource "aws_vpc_security_group_ingress_rule" "mysql_from_proxy" {
  security_group_id            = var.mysql_sg_id
  description                  = "RDS Proxy to MySQL cluster"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.proxy.id
}

# Proxy egress — when an SG is created via terraform, AWS does NOT add the
# default allow-all egress rule (only the console does). Without these rules
# the proxy capacity stays in PENDING_PROXY_CAPACITY forever because it
# cannot reach the cluster on 3306 or Secrets Manager on 443.
resource "aws_vpc_security_group_egress_rule" "proxy_to_mysql" {
  security_group_id            = aws_security_group.proxy.id
  description                  = "RDS Proxy egress to MySQL cluster"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = var.mysql_sg_id
}

resource "aws_vpc_security_group_egress_rule" "proxy_aws_api" {
  security_group_id = aws_security_group.proxy.id
  description       = "RDS Proxy egress to AWS APIs (Secrets Manager, KMS)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_db_proxy" "this" {
  name                   = local.resource_name
  engine_family          = "MYSQL"
  role_arn               = aws_iam_role.proxy.arn
  vpc_subnet_ids         = var.subnet_ids
  vpc_security_group_ids = [aws_security_group.proxy.id]
  require_tls            = var.require_tls
  idle_client_timeout    = var.idle_client_timeout
  debug_logging          = var.debug_logging

  auth {
    auth_scheme = "SECRETS"
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.proxy_auth.arn
  }

  tags = merge(
    var.common_tags,
    { Name = local.resource_name }
  )

  depends_on = [aws_secretsmanager_secret_version.proxy_auth]
}

resource "aws_db_proxy_default_target_group" "this" {
  db_proxy_name = aws_db_proxy.this.name

  connection_pool_config {
    max_connections_percent      = var.max_connections_percent
    max_idle_connections_percent = var.max_idle_connections_percent
    connection_borrow_timeout    = var.connection_borrow_timeout
  }
}

resource "aws_db_proxy_target" "this" {
  db_proxy_name         = aws_db_proxy.this.name
  target_group_name     = aws_db_proxy_default_target_group.this.name
  db_cluster_identifier = var.mysql_cluster_id
}
