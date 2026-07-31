provider "aws" {
  region = var.region

  default_tags {
    tags = merge(
      {
        Terraform = "true"
      },
      var.environment_tag != "" ? { Environment = var.environment_tag } : {},
      var.common_tags
    )
  }
}
