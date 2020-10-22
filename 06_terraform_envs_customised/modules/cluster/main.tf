
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
  version                = ">= 1.13.2"
}

data "aws_availability_zones" "available" {
}

module "vpc" {
  source               = "terraform-aws-modules/vpc/aws"
  version              = "2.60.0"
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

  #  https://github.com/terraform-aws-modules/terraform-aws-eks/issues/965#issuecomment-694807730
  #  https://eksctl.io/usage/iamserviceaccounts/#usage-without-config-files
  #  $ eksctl utils associate-iam-oidc-provider --cluster=eks-ppd-d1matrix-com --approve
  #  [ℹ]  eksctl version 0.30.0
  #  [ℹ]  using region sa-east-1
  #  [ℹ]  will create IAM Open ID Connect provider for cluster "eks-ppd-d1matrix-com" in "sa-east-1"
  #  [✔]  created IAM Open ID Connect provider for cluster "eks-ppd-d1matrix-com" in "sa-east-1"

  #  aws iam list-open-id-connect-providers
  #  aws iam delete-open-id-connect-provider --open-id-connect-provider-arn arn:aws:iam::761010771720:oidc-provider/oidc.eks.sa-east-1.amazonaws.com/id/E7673F2895FCDE4A30155E0774F8EDF8
  enable_irsa = true

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
  version = "1.3.2"
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
  namespace  = "kube-system"
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

# https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md#amazon-eks
# https://tech.polyconseil.fr/external-dns-helm-terraform.html
# https://www.padok.fr/en/blog/external-dns-route53-eks
variable "external_dns_chart_log_level" {
  description = "External-dns Helm chart log leve. Possible values are: panic, debug, info, warning, error, fatal"
  type        = string
  default     = "debug"
}

variable "external_dns_zoneType" {
  description = "External-dns Helm chart AWS DNS zone type (public, private or empty for both)"
  type        = string
  default     = ""
}

variable "external_dns_domain_filters" {
  description = "External-dns Domain filters."
  type        = list(string)
}

# https://github.com/jetstack/cert-manager/issues/2147#issuecomment-537950172
locals {
  oidc_url = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
}

resource "aws_iam_role" "external_dns" {
  name = "${module.eks.cluster_id}-external-dns"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_url}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${local.oidc_url}:sub": "system:serviceaccount:kube-system:external-dns"
        }
      }
    }
  ]
}
EOF

}

resource "aws_iam_role_policy" "external_dns" {
  name_prefix = "${module.eks.cluster_id}-external-dns"
  role        = aws_iam_role.external_dns.name
  policy      = file("${path.module}/external-dns-iam-policy.json")
}

resource "kubernetes_service_account" "external_dns" {
  metadata {
    name      = "external-dns"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.external_dns.arn
    }
  }
  automount_service_account_token = true
}

resource "kubernetes_cluster_role" "external_dns" {
  metadata {
    name = "external-dns"
  }

  rule {
    api_groups = [""]
    resources  = ["services", "pods", "endpoints"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["extensions", "networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["watch", "list"]
  }
}

resource "kubernetes_cluster_role_binding" "external_dns" {
  metadata {
    name = "external-dns"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.external_dns.metadata.0.name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.external_dns.metadata.0.name
    namespace = kubernetes_service_account.external_dns.metadata.0.namespace
  }
}

resource "helm_release" "external_dns" {
  name       = "external-dns"
  namespace  = kubernetes_service_account.external_dns.metadata.0.namespace
  wait       = true
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "external-dns"
  version    = "3.4.9"

  set {
    name  = "rbac.create"
    value = false
  }

  set {
    name  = "serviceAccount.create"
    value = false
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.external_dns.metadata.0.name
  }

  set {
    name  = "rbac.pspEnabled"
    value = false
  }

  set {
    name  = "name"
    value = "eks-${local.env_domain}-external-dns"
  }

  set {
    name  = "provider"
    value = "aws"
  }

  set {
    name  = "policy"
    value = "sync"
    type  = "string"
  }

  set {
    name  = "logLevel"
    value = var.external_dns_chart_log_level
    type  = "string"
  }

  set {
    name  = "sources"
    value = "{ingress,service}"
  }

  set {
    name  = "domainFilters"
    value = "{${join(",", var.external_dns_domain_filters)}}"
  }

  set {
    name  = "aws.zoneType"
    value = var.external_dns_zoneType
    type  = "string"
  }

  set {
    name  = "aws.region"
    value = var.region
    type  = "string"
  }
}
