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

# Kubernetes provider using exec-based auth to avoid chicken-and-egg problem
# The exec block only runs during apply, not during plan
provider "kubernetes" {
  host                   = var.enable_eks ? module.comet_eks[0].cluster_endpoint : null
  cluster_ca_certificate = var.enable_eks ? base64decode(module.comet_eks[0].cluster_certificate_authority_data) : null

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.enable_eks ? module.comet_eks[0].cluster_name : "", "--region", var.region]
  }
}

# Helm provider using exec-based auth to avoid chicken-and-egg problem
provider "helm" {
  kubernetes {
    host                   = var.enable_eks ? module.comet_eks[0].cluster_endpoint : null
    cluster_ca_certificate = var.enable_eks ? base64decode(module.comet_eks[0].cluster_certificate_authority_data) : null

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.enable_eks ? module.comet_eks[0].cluster_name : "", "--region", var.region]
    }
  }
}

# Kubectl provider using exec-based auth to avoid chicken-and-egg problem
provider "kubectl" {
  host                   = var.enable_eks ? module.comet_eks[0].cluster_endpoint : null
  cluster_ca_certificate = var.enable_eks ? base64decode(module.comet_eks[0].cluster_certificate_authority_data) : null
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.enable_eks ? module.comet_eks[0].cluster_name : "", "--region", var.region]
  }
}