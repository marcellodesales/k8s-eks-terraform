terraform {
  required_version = ">= 0.12"

  required_providers {
    aws    = ">= 3.0, < 4.0"
    random = "~> 3.0.0"
  }
}

provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  version = ">= 1.13.2"

  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
}

provider "helm" {
  version = "1.3.2"

  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    token                  = data.aws_eks_cluster_auth.cluster.token
    load_config_file       = false
  }
}
