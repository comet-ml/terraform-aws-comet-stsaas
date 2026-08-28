locals {
  mysql_port                  = 3306
  enhanced_monitoring_enabled = var.rds_enhanced_monitoring_interval > 0

  # AWS derives the family from the engine plus the version's first two components:
  # "8.0.mysql_aurora.3.11.1" and the bare "8.0" both -> aurora-mysql8.0.
  # Built from var.rds_engine rather than a hardcoded prefix so a non-aurora-mysql
  # engine produces a family that names the engine it was given.
  rds_expected_parameter_group_family = "${var.rds_engine}${join(".", slice(split(".", var.rds_engine_version), 0, min(2, length(split(".", var.rds_engine_version)))))}"

  # Derived unless overridden, so pinning a point release never silently changes the
  # family, and the precondition below only fires on an explicit contradiction.
  rds_parameter_group_family = coalesce(var.rds_parameter_group_family, local.rds_expected_parameter_group_family)
}

# Cross-field check: each var is individually valid but the pair can still be
# incompatible (e.g. version 8.0.mysql_aurora.3.11.1 with family aurora-mysql5.7).
# AWS only rejects that when the cluster is associated, after the parameter groups
# already exist — fail at plan instead. Only reachable when the family is set
# explicitly; the derived value matches by construction.
resource "terraform_data" "parameter_group_family_matches_engine_version" {
  lifecycle {
    precondition {
      condition     = local.rds_parameter_group_family == local.rds_expected_parameter_group_family
      error_message = "rds_parameter_group_family (${local.rds_parameter_group_family}) does not match rds_engine/rds_engine_version (${var.rds_engine} ${var.rds_engine_version}), which requires ${local.rds_expected_parameter_group_family}. Leave rds_parameter_group_family unset to derive it."
    }
  }
}

# IAM role for Enhanced Monitoring
resource "aws_iam_role" "rds_enhanced_monitoring" {
  count = local.enhanced_monitoring_enabled ? 1 : 0
  name  = "cometml-rds-enhanced-monitoring-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  count      = local.enhanced_monitoring_enabled ? 1 : 0
  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_subnet_group" "comet-ml-rds-subnet" {
  name       = "cometml-rds-sgn-${var.environment}"
  subnet_ids = var.rds_private_subnets
  tags = merge(
    var.common_tags,
    {
      Name = "cometml-rds-sng-${var.environment}"
    }
  )
}

resource "aws_rds_cluster_instance" "comet-ml-rds-mysql" {
  count              = var.rds_instance_count
  identifier         = "${coalesce(var.rds_instance_identifier_prefix, "cometml-rds-${var.environment}")}-${count.index}"
  cluster_identifier = aws_rds_cluster.cometml-db-cluster.id
  instance_class     = var.rds_serverless_v2_enabled ? "db.serverless" : var.rds_instance_type
  engine             = var.rds_engine
  engine_version     = var.rds_engine_version
  apply_immediately  = true

  # Set false alongside a pinned engine_version: an AWS-initiated minor upgrade makes
  # the next plan try to set engine_version back down to the pin, which Aurora rejects
  # — the apply then fails until someone re-pins by hand.
  #
  # This covers ordinary maintenance-window upgrades only. AWS still force-upgrades for
  # critical security fixes and at end-of-support regardless of this setting, which
  # produces the same downgrade-loop symptom; the fix there is to move the pin forward
  # to the version AWS landed on, not to re-pin the old one.
  #
  # Null leaves the attribute unmanaged, which is the default on this line: v2.1.x
  # never set it, so existing clusters stay at AWS's default instead of being flipped
  # by an unrelated apply.
  auto_minor_version_upgrade = var.rds_auto_minor_version_upgrade

  # Performance Insights
  performance_insights_enabled          = var.rds_performance_insights_enabled
  performance_insights_retention_period = var.rds_performance_insights_enabled ? var.rds_performance_insights_retention_period : null
  performance_insights_kms_key_id       = var.rds_performance_insights_enabled ? var.rds_performance_insights_kms_key_id : null

  # Enhanced Monitoring
  monitoring_interval = var.rds_enhanced_monitoring_interval
  monitoring_role_arn = local.enhanced_monitoring_enabled ? aws_iam_role.rds_enhanced_monitoring[0].arn : null

  tags = merge(
    var.common_tags,
    {
      Name = "cometml-rds-${var.environment}-${count.index}"
    }
  )
}

resource "aws_rds_cluster" "cometml-db-cluster" {
  cluster_identifier                  = coalesce(var.rds_cluster_identifier, "cometml-rds-cluster-${var.environment}")
  db_subnet_group_name                = aws_db_subnet_group.comet-ml-rds-subnet.name
  availability_zones                  = var.availability_zones
  database_name                       = var.rds_snapshot_identifier == null ? var.rds_database_name : null
  storage_encrypted                   = var.rds_storage_encrypted
  kms_key_id                          = var.rds_kms_key_id
  iam_database_authentication_enabled = var.rds_iam_db_auth
  master_username                     = var.rds_snapshot_identifier == null ? var.rds_master_username : null
  master_password                     = var.rds_snapshot_identifier == null ? var.rds_master_password : null
  snapshot_identifier                 = var.rds_snapshot_identifier
  engine                              = var.rds_engine
  engine_version                      = var.rds_engine_version
  backup_retention_period             = var.rds_backup_retention_period
  final_snapshot_identifier           = "cometml-rds-backup-${var.environment}-${formatdate("DD-MMM-YYYY-hh-mm-ss", timestamp())}"
  preferred_backup_window             = var.rds_preferred_backup_window
  vpc_security_group_ids              = [aws_security_group.mysql_sg.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.cometml-cluster-pg.name
  db_instance_parameter_group_name    = aws_db_parameter_group.cometml-db-pg.name
  allow_major_version_upgrade         = true
  deletion_protection                 = var.rds_deletion_protection
  storage_type                        = var.rds_storage_type
  apply_immediately                   = true

  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.rds_serverless_v2_enabled ? [1] : []
    content {
      min_capacity             = var.rds_serverless_v2_min_capacity
      max_capacity             = var.rds_serverless_v2_max_capacity
      seconds_until_auto_pause = var.rds_serverless_v2_min_capacity == 0 ? var.rds_serverless_v2_seconds_until_auto_pause : null
    }
  }

  tags = merge(
    var.common_tags,
    {
      Name = "cometml-rds-cluster-${var.environment}"
    }
  )
}

resource "aws_rds_cluster_parameter_group" "cometml-cluster-pg" {
  name        = "cometml-rds-cluster-pg-${var.environment}"
  family      = local.rds_parameter_group_family
  description = "CometML RDS cluster parameter group"

  tags = merge(
    var.common_tags,
    {
      Name = "cometml-rds-cluster-pg-${var.environment}"
    }
  )

  parameter {
    apply_method = "pending-reboot"
    name         = "character_set_server"
    value        = "utf8mb4"
  }
  parameter {
    apply_method = "pending-reboot"
    name         = "character_set_connection"
    value        = "utf8mb4"
  }
  parameter {
    apply_method = "pending-reboot"
    name         = "character_set_database"
    value        = "utf8mb4"
  }
  parameter {
    apply_method = "pending-reboot"
    name         = "character_set_results"
    value        = "utf8mb4"
  }
  parameter {
    apply_method = "pending-reboot"
    name         = "collation_connection"
    value        = "utf8mb4_unicode_ci"
  }
  parameter {
    apply_method = "pending-reboot"
    name         = "collation_server"
    value        = "utf8mb4_unicode_ci"
  }
  parameter {
    apply_method = "pending-reboot"
    name         = "innodb_flush_log_at_trx_commit"
    value        = "1"
  }
  parameter {
    apply_method = "pending-reboot"
    name         = "innodb_lock_wait_timeout"
    value        = "120"
  }
  parameter {
    apply_method = "pending-reboot"
    name         = "max_allowed_packet"
    value        = "157286400"
  }
  parameter {
    apply_method = "pending-reboot"
    name         = "thread_stack"
    value        = "6291456"
  }
  parameter {
    apply_method = "pending-reboot"
    name         = "group_concat_max_len"
    value        = "1000000"
  }
  parameter {
    apply_method = "pending-reboot"
    name         = "log_bin_trust_function_creators"
    value        = "1"
  }

  dynamic "parameter" {
    for_each = var.rds_cluster_parameters
    content {
      apply_method = parameter.value.apply_method
      name         = parameter.value.name
      value        = parameter.value.value
    }
  }

  dynamic "parameter" {
    for_each = var.rds_require_secure_transport ? [1] : []
    content {
      apply_method = "pending-reboot"
      name         = "require_secure_transport"
      value        = "ON"
    }
  }
}

# Instance-level (DB) parameter group. Aurora cluster parameter groups apply
# fleet-wide; this DB pg lets operators set per-instance overrides without
# touching the cluster pg. Empty by default — caller-provided extras come
# through var.rds_db_parameters.
resource "aws_db_parameter_group" "cometml-db-pg" {
  name        = "cometml-rds-db-pg-${var.environment}"
  family      = local.rds_parameter_group_family
  description = "CometML RDS DB-instance parameter group"

  tags = merge(
    var.common_tags,
    {
      Name = "cometml-rds-db-pg-${var.environment}"
    }
  )

  dynamic "parameter" {
    for_each = var.rds_db_parameters
    content {
      apply_method = parameter.value.apply_method
      name         = parameter.value.name
      value        = parameter.value.value
    }
  }
}

resource "aws_security_group" "mysql_sg" {
  name        = "${var.environment}_mysql_sg"
  description = "CometML RDS cluster security group"
  vpc_id      = var.vpc_id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.environment}_mysql_sg"
    }
  )
}

resource "aws_vpc_security_group_ingress_rule" "mysql_port_inbound_ec2" {
  security_group_id            = aws_security_group.mysql_sg.id
  from_port                    = local.mysql_port
  to_port                      = local.mysql_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.rds_allow_from_sg
}
