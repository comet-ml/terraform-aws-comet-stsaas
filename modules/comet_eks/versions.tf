terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Floor = terraform-aws-modules/eks ~> 21.24 requires aws >= 6.52. Keep in
      # sync with the root module versions.tf. Ceiling/bad-build pins live in the
      # wrapper, not here.
      version = ">= 6.52"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}
