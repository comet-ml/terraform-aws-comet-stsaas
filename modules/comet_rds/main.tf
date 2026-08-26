locals {
  mysql_port                  = 3306
  enhanced_monitoring_enabled = var.rds_enhanced_monitoring_interval > 0

  # Named once so the CloudWatch log groups can be built from the same identifier the
  # cluster uses — the group names RDS writes to are /aws/rds/cluster/<id>/<type>, so a
  # drift between the two would silently leave the real groups unmanaged (DND-1537).
  rds_cluster_identifier = coalesce(var.rds_cluster_identifier, "cometml-rds-cluster-${var.environment}")

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

  # Off by default: an AWS-initiated minor upgrade makes the next plan try to set
  # engine_version back down to the pinned value, which Aurora rejects — the apply
  # then fails until someone re-pins by hand.
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

# DND-1537: create the log groups ourselves, with retention, so they exist BEFORE the
# export is switched on below. If RDS gets there first it creates them with no retention
# ("never expire") and terraform then collides with an unmanaged resource — which is both
# how the orphaned zoox slowquery group came to bill 3.65 GB indefinitely, and an import
# nobody wants to do 16 times.
resource "aws_cloudwatch_log_group" "rds_exported_logs" {
  # Driven by rds_managed_log_group_types, NOT by the export list — see that variable for
  # why. Toggling an export off leaves the group in state, so re-enabling it later is a
  # no-op rather than a ResourceAlreadyExistsException.
  for_each = toset(var.rds_managed_log_group_types)

  name              = "/aws/rds/cluster/${local.rds_cluster_identifier}/${each.value}"
  retention_in_days = var.rds_log_retention_days
  kms_key_id        = var.rds_log_kms_key_id

  # Turning an export off must not delete the evidence already collected — that is the whole
  # point of exporting. Belt-and-braces now that the two lifecycles are decoupled: it only
  # bites when a type is removed from rds_managed_log_group_types, which is an explicit
  # "stop managing this group" rather than a side effect of changing the export list.
  # The cost is that a real teardown leaves the groups behind, but they carry finite
  # retention and expire on their own, unlike the never-expire orphan DND-1537 cleaned up.
  skip_destroy = true

  tags = merge(
    var.common_tags,
    {
      Name = "/aws/rds/cluster/${local.rds_cluster_identifier}/${each.value}"
    }
  )
}

resource "aws_rds_cluster" "cometml-db-cluster" {
  cluster_identifier                  = local.rds_cluster_identifier
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
  enabled_cloudwatch_logs_exports     = var.rds_enabled_cloudwatch_logs_exports

  # The log groups must exist with their retention already set before RDS starts
  # exporting, otherwise RDS creates them itself at "never expire" (DND-1537).
  depends_on = [aws_cloudwatch_log_group.rds_exported_logs]

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

  lifecycle {
    # final_snapshot_identifier is built from timestamp(), which re-evaluates on
    # every plan and would otherwise show a spurious perpetual diff (and drag
    # dependents to "known after apply"). It only matters at destroy time as the
    # snapshot name, so ignore in-place changes and keep the value first stored.
    ignore_changes = [final_snapshot_identifier]

    # Exporting a type that has no managed log group hands group creation back to
    # RDS, which makes it at never-expire — this module's own failure mode, through
    # a new door. Both variables default to the same list so this holds out of the
    # box; the precondition stops someone adding e.g. "general" to the export list
    # alone. A cross-variable `validation` block would be the natural home, but that
    # needs Terraform 1.9 and this repo's floor is >= 1.5.7.
    precondition {
      condition = alltrue([
        for t in var.rds_enabled_cloudwatch_logs_exports :
        contains(var.rds_managed_log_group_types, t)
      ])
      error_message = "Every exported log type must also be in rds_managed_log_group_types, or RDS creates its log group at never-expire."
    }
  }
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

# EKS Auto Mode nodes attach the cluster primary SG (not the managed node SG that
# rds_allow_from_sg references), so they need their own ingress rule to reach MySQL.
# Only created when the Auto Mode SG is passed in.
resource "aws_vpc_security_group_ingress_rule" "mysql_port_inbound_auto_mode" {
  count = var.rds_auto_mode_allow_from_sg != null ? 1 : 0

  security_group_id            = aws_security_group.mysql_sg.id
  from_port                    = local.mysql_port
  to_port                      = local.mysql_port
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.rds_auto_mode_allow_from_sg
  description                  = "MySQL from EKS Auto Mode nodes (cluster primary SG)"
}
