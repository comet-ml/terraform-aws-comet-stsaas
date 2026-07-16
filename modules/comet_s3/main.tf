locals {
  suffix = substr(sha1("${var.environment}"), 0, 8)

  # Buckets that get a lifecycle configuration. Each key produces one
  # aws_s3_bucket_lifecycle_configuration resource. Empty rule lists are
  # filtered out so we never call AWS PutBucketLifecycleConfiguration with
  # an empty rule set (the API rejects that).
  s3_lifecycle_targets = var.enable_s3_lifecycle ? merge(
    length(var.comet_bucket_lifecycle_rules) > 0 ? {
      comet = {
        bucket_id = aws_s3_bucket.comet_s3_bucket.id
        rules     = var.comet_bucket_lifecycle_rules
      }
    } : {},
    var.enable_loki_bucket && length(var.loki_bucket_lifecycle_rules) > 0 ? {
      loki = {
        bucket_id = aws_s3_bucket.comet_loki_bucket[0].id
        rules     = var.loki_bucket_lifecycle_rules
      }
    } : {},
  ) : {}
}

resource "aws_s3_bucket" "comet_s3_bucket" {
  bucket = var.comet_s3_bucket

  force_destroy = var.s3_force_destroy

  tags = merge(
    var.common_tags,
    {
      Name = var.comet_s3_bucket
    }
  )
}

resource "aws_s3_bucket" "comet_druid_bucket" {
  count = var.enable_mpm_infra ? 1 : 0

  bucket = "comet-druid-${var.environment}-${local.suffix}"

  force_destroy = var.s3_force_destroy

  tags = merge(
    var.common_tags,
    {
      Name = "comet-druid-${var.environment}-${local.suffix}"
    }
  )
}

resource "aws_s3_bucket" "comet_airflow_bucket" {
  count = var.enable_mpm_infra ? 1 : 0

  bucket = "comet-airflow-${var.environment}-${local.suffix}"

  force_destroy = var.s3_force_destroy

  tags = merge(
    var.common_tags,
    {
      Name = "comet-airflow-${var.environment}-${local.suffix}"
    }
  )
}

resource "aws_s3_bucket" "comet_loki_bucket" {
  count = var.enable_loki_bucket ? 1 : 0

  bucket = coalesce(var.loki_bucket_name_override, "comet-loki-${var.environment}-${local.suffix}")

  force_destroy = var.s3_force_destroy

  tags = merge(
    var.common_tags,
    {
      Name = "comet-loki-${var.environment}-${local.suffix}"
    }
  )
}

resource "aws_s3_bucket_versioning" "comet" {
  count = var.enable_s3_versioning ? 1 : 0

  bucket = aws_s3_bucket.comet_s3_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "loki" {
  count = var.enable_s3_versioning && var.enable_loki_bucket ? 1 : 0

  bucket = aws_s3_bucket.comet_loki_bucket[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "buckets" {
  for_each = local.s3_lifecycle_targets

  bucket = each.value.bucket_id

  dynamic "rule" {
    for_each = each.value.rules
    content {
      id     = rule.value.id
      status = rule.value.status

      filter {
        prefix = rule.value.filter_prefix
      }

      dynamic "abort_incomplete_multipart_upload" {
        for_each = rule.value.abort_incomplete_multipart_upload_days != null ? [1] : []
        content {
          days_after_initiation = rule.value.abort_incomplete_multipart_upload_days
        }
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days != null ? [1] : []
        content {
          days = rule.value.expiration_days
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_version_expiration_days != null ? [1] : []
        content {
          noncurrent_days = rule.value.noncurrent_version_expiration_days
        }
      }

      dynamic "transition" {
        for_each = rule.value.transitions
        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }
    }
  }
}

resource "aws_iam_policy" "comet_s3_iam_policy" {
  name        = "comet-s3-access-policy-${local.suffix}"
  description = "Policy for access to comet S3 buckets"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = "s3:*",
        Resource = concat(
          [
            aws_s3_bucket.comet_s3_bucket.arn,
            "${aws_s3_bucket.comet_s3_bucket.arn}/*"
          ],
          var.enable_mpm_infra ? [
            aws_s3_bucket.comet_druid_bucket[0].arn,
            "${aws_s3_bucket.comet_druid_bucket[0].arn}/*",
            aws_s3_bucket.comet_airflow_bucket[0].arn,
            "${aws_s3_bucket.comet_airflow_bucket[0].arn}/*"
          ] : [],
          var.enable_loki_bucket ? [
            aws_s3_bucket.comet_loki_bucket[0].arn,
            "${aws_s3_bucket.comet_loki_bucket[0].arn}/*"
          ] : []
        )
      }
    ]
  })

  tags = merge(
    var.common_tags,
    {
      Name = "comet-s3-access-policy-${local.suffix}"
    }
  )
}
