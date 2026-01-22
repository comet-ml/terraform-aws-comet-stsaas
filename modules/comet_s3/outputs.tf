output "comet_s3_iam_policy_arn" {
  description = "ARN of the IAM policy granting access to the provisioned bucket(s)"
  value       = aws_iam_policy.comet_s3_iam_policy.arn
}

output "comet_loki_bucket_name" {
  description = "Name of the Loki S3 bucket"
  value       = var.enable_loki_bucket ? aws_s3_bucket.comet_loki_bucket[0].id : null
}

output "comet_loki_bucket_arn" {
  description = "ARN of the Loki S3 bucket"
  value       = var.enable_loki_bucket ? aws_s3_bucket.comet_loki_bucket[0].arn : null
}