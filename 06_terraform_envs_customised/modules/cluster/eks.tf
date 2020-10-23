resource "aws_iam_policy" "eks_worker_policy" {
  name        = "worker-policy-${local.env_domain}"
  description = "Worker policy for the ALB Ingress"

  policy = file("${path.module}/eks-worker-iam-policy.json")
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "13.0.0"

  cluster_name    = local.cluster_name
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

      instance_type = var.instance_types[0]
    }
  }

  write_kubeconfig   = true
  config_output_path = "./"

  workers_additional_policies = [aws_iam_policy.eks_worker_policy.arn]
}
