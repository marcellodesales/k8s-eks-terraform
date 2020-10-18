
variable "region" {
  default = "sa-east-1"
}

provider "aws" {
  region = var.region
}

variable "cluster_env" {
  default = "my-env"
}

variable "domain" {
  default = "my-product"
}

variable "instance_type" {
  default = "m5.large"
}

variable "k8s_manage_aws_auth" {
  default = true
}

locals {
  env_domain = "${replace(var.cluster_env, ".", "-")}-${replace(var.domain, ".", "-")}"
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
  version                = "~> 1.11"
}

data "aws_availability_zones" "available" {
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.47.0"

  name                 = "k8s-${local.env_domain}-vpc"
  cidr                 = "172.16.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["172.16.1.0/24", "172.16.2.0/24", "172.16.3.0/24"]
  public_subnets       = ["172.16.4.0/24", "172.16.5.0/24", "172.16.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/eks-${local.env_domain}" = "shared"
    "kubernetes.io/role/elb"                        = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/eks-${local.env_domain}" = "shared"
    "kubernetes.io/role/internal-elb"               = "1"
  }
}

variable "k8s_version" {
  default = 1.17
}

variable "k8s_max_capacity" {
  default = 5
}

variable "k8s_min_capacity" {
  default = 1
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "13.0.0"

  cluster_name    = "eks-${local.env_domain}"
  cluster_version = var.k8s_version
  manage_aws_auth = var.k8s_manage_aws_auth

  subnets = module.vpc.private_subnets

  vpc_id = module.vpc.vpc_id

  node_groups = {
    first = {
      desired_capacity = var.k8s_min_capacity
      max_capacity     = var.k8s_max_capacity
      min_capacity     = var.k8s_min_capacity

      instance_type = var.instance_type
    }
  }

  write_kubeconfig   = true
  config_output_path = "./"

  workers_additional_policies = [aws_iam_policy.worker_policy.arn]
}

resource "aws_iam_policy" "worker_policy" {
  name        = "worker-policy-${local.env_domain}"
  description = "Worker policy for the ALB Ingress"

  policy = file("${path.module}/iam-policy-eks-worker.json")
}

provider "helm" {
  version = "1.3.1"
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    token                  = data.aws_eks_cluster_auth.cluster.token
    load_config_file       = false
  }
}

resource "helm_release" "ingress" {
  name       = "ingress"
  chart      = "aws-alb-ingress-controller"
  repository = "http://storage.googleapis.com/kubernetes-charts-incubator"
  version    = "1.0.2"

  set {
    name  = "autoDiscoverAwsRegion"
    value = "true"
  }
  set {
    name  = "autoDiscoverAwsVpcID"
    value = "true"
  }
  set {
    name  = "clusterName"
    value = "eks-${local.env_domain}"
  }
}
