locals {
  external_dns_name      = "external-dns"
  external_dns_namespace = "kube-system"
}

# https://www.padok.fr/en/blog/external-dns-route53-eks
# https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md#amazon-eks
# https://medium.com/@peiruwang/eks-exposing-service-with-external-dns-3be8facc73b9
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
          "${local.oidc_url}:sub": "system:serviceaccount:${local.external_dns_namespace}:${local.external_dns_name}"
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
  policy      = file("${path.module}/k8s_system_external_dns-iam-policy.json")
}

resource "kubernetes_service_account" "external_dns" {
  metadata {
    name      = local.external_dns_name
    namespace = local.external_dns_namespace
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

  # https://github.com/kubernetes-sigs/external-dns/issues/961#issuecomment-708430115
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
  name       = kubernetes_service_account.external_dns.metadata.0.name
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
    value = var.aws_region
    type  = "string"
  }
}
