terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Floor = the tightest real dependency: terraform-aws-modules/eks ~> 21.24
      # requires aws >= 6.52. No upper bound / bad-build exclusion here — that is
      # deployment policy (the wrapper pins e.g. "~> 6.50, != 6.57.0").
      version = ">= 6.52"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
    # kubernetes + helm: see modules/comet_eks/versions.tf — declared only so brownfield
    # clusters can drop leftover in-cluster/helm resources from state via removed.tf.
    # v5 creates no kubernetes/helm resources; the wrapper still passes these providers.
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0"
    }
  }
}
