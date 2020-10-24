# https://github.com/hashicorp/terraform/issues/4390#issuecomment-234963443
data "aws_caller_identity" "current" {} # used for accesing Account ID and ARN

# https://github.com/jetstack/cert-manager/issues/2147#issuecomment-537950172
data "aws_availability_zones" "available" {}

data "aws_ec2_instance_type_offering" "with_instance_types" {
  for_each = toset(data.aws_availability_zones.available.names)

  filter {
    name   = "instance-type"
    values = var.instance_types
  }

  filter {
    name   = "location"
    values = [each.value]
  }

  location_type = "availability-zone"

  preferred_instance_types = var.instance_types
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

locals {
  oidc_url = replace(module.eks.cluster_oidc_issuer_url, "https://", "")

  env_domain = replace("${var.cluster_env}-${var.domain}", ".", "-")

  cluster_name = "eks-${local.env_domain}"

  availability_zones_with_selected_instances = keys({
    for az, details in data.aws_ec2_instance_type_offering.with_instance_types :
    az => details.instance_type
  })
}
