module "vpc" {
  source               = "terraform-aws-modules/vpc/aws"
  version              = "2.60.0"
  name                 = "k8s-${local.env_domain}-vpc"
  cidr                 = "172.16.0.0/16"
  azs                  = local.availability_zones_with_selected_instances
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
