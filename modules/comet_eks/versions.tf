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
    # kubernetes + helm are declared ONLY so brownfield clusters (upgrading from a
    # v1/v2 module version) can associate their leftover in-cluster / helm_release
    # resources with a provider long enough for the `removed` blocks in removed.tf to
    # drop them from state (destroy = false). v6 no longer CREATES any kubernetes/helm
    # resource — greenfield clusters never instantiate these providers. Removed again
    # in the permanent v6.0.0 tag (DND-1573 / DND-1257 brownfield migration).
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
