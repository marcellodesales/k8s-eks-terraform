locals {
  autoscaler_name      = "cluster-autoscaler"
  autoscaler_namespace = "kube-system"
}

#https://github.com/kubernetes/autoscaler/tree/master/charts/cluster-autoscaler-chart#aws---using-auto-discovery-of-tagged-instance-groups
# https://docs.aws.amazon.com/eks/latest/userguide/cluster-autoscaler.html#ca-deploy
# https://gitlab.lukapo.com/terraform/aws/eks/module.eks-iam-cluster-autoscaler
# If this does nt work https://github.com/lablabs/terraform-aws-eks-cluster-autoscaler/blob/master/examples/basic/main.tf#L43-L48
resource "aws_iam_role" "cluster_autoscaler" {
  name               = "${module.eks.cluster_id}-cluster-autoscaler"
  assume_role_policy = data.aws_iam_policy_document.cluster_autoscaler_oidc_assume.json
}

data "aws_iam_policy_document" "cluster_autoscaler_oidc_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.oidc_url}"]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url}:sub"
      values   = ["system:serviceaccount:${local.autoscaler_namespace}:${local.autoscaler_name}"]
    }
  }
}

# https://docs.aws.amazon.com/eks/latest/userguide/cluster-autoscaler.html#ca-ng-considerations
data "aws_iam_policy_document" "cluster_autoscaler" {
  statement {
    sid    = "clusterAutoscalerAll"
    effect = "Allow"

    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "ec2:DescribeLaunchTemplateVersions",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "clusterAutoscalerOwn"
    effect = "Allow"

    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "autoscaling:UpdateAutoScalingGroup",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/kubernetes.io/cluster/${local.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/enabled"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  name_prefix = "${module.eks.cluster_id}-cluster-autoscaler"
  role        = aws_iam_role.cluster_autoscaler.name
  policy      = data.aws_iam_policy_document.cluster_autoscaler.json
}

resource "kubernetes_service_account" "cluster_autoscaler" {
  metadata {
    name      = local.autoscaler_name
    namespace = local.autoscaler_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.cluster_autoscaler.arn
    }
  }
  automount_service_account_token = true
}

resource "kubernetes_cluster_role" "cluster_autoscaler" {
  metadata {
    name = local.autoscaler_name
  }

  # https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml#L11-L64
  rule {
    api_groups = [""]
    resources  = ["services", "pods", "endpoints"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["events", "endpoints"]
    verbs      = ["create", "patch"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods/eviction"]
    verbs      = ["create"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods/status"]
    verbs      = ["update"]
  }
  rule {
    api_groups     = [""]
    resources      = ["endpoints"]
    resource_names = ["cluster-autoscaler"]
    verbs          = ["get", "update"]
  }
  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["watch", "list", "get", "update"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods", "services", "replicationcontrollers", "persistentvolumeclaims", "persistentvolumes"]
    verbs      = ["watch", "list", "get"]
  }
  rule {
    api_groups = ["extensions"]
    resources  = ["replicasets", "daemonsets"]
    verbs      = ["watch", "list", "get"]
  }
  rule {
    api_groups = ["policy"]
    resources  = ["poddisruptionbudgets"]
    verbs      = ["watch", "list"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["statefulsets", "replicasets", "daemonsets"]
    verbs      = ["watch", "list", "get"]
  }
  rule {
    api_groups = ["storage.k8s.io"]
    resources  = ["storageclasses", "csinodes"]
    verbs      = ["watch", "list", "get"]
  }
  rule {
    api_groups = ["batch", "extensions"]
    resources  = ["jobs"]
    verbs      = ["get", "list", "watch", "patch"]
  }
  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    verbs      = ["create"]
  }
  rule {
    api_groups     = ["coordination.k8s.io"]
    resource_names = ["cluster-autoscaler"]
    resources      = ["leases"]
    verbs          = ["get", "update"]
  }
  # https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml#L66-L81
  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["create", "list", "watch"]
  }
  rule {
    api_groups     = [""]
    resources      = ["configmaps"]
    resource_names = ["cluster-autoscaler-status", "cluster-autoscaler-priority-expander"]
    verbs          = ["delete", "get", "update", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "cluster_autoscaler" {
  metadata {
    name = local.autoscaler_name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.cluster_autoscaler.metadata.0.name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.cluster_autoscaler.metadata.0.name
    namespace = kubernetes_service_account.cluster_autoscaler.metadata.0.namespace
  }
}

# Nodes are already tagged with the needed tags by eks
# k8s.io/cluster-autoscaler/eks-ppd-d1matrix-com	owned
# k8s.io/cluster-autoscaler/enabled	true
# https://docs.aws.amazon.com/eks/latest/userguide/cluster-autoscaler.html#ca-ng-asg-tags
# https://docs.aws.amazon.com/eks/latest/userguide/cluster-autoscaler.html#ca-deploy
resource "helm_release" "cluster_autoscaler" {
  # Upgrade to https://github.com/kubernetes/autoscaler/tree/master/charts/cluster-autoscaler-chart
  name       = kubernetes_service_account.cluster_autoscaler.metadata.0.name
  namespace  = kubernetes_service_account.cluster_autoscaler.metadata.0.namespace
  wait       = true
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler-chart"
  version    = "1.1.0"

  # set {
  #   name  = "sslCertPath"
  #   value = "/etc/ssl/certs/ca-bundle.crt"
  # }

  set {
    name  = "provider"
    value = "aws"
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  set {
    name  = "name"
    value = "eks-${local.env_domain}-cluster-autoscaler"
  }

  set {
    name  = "rbac.create"
    value = false
  }

  set {
    name  = "rbac.serviceAccount.create"
    value = false
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = kubernetes_service_account.cluster_autoscaler.metadata.0.name
  }

  set {
    name  = "rbac.serviceAccount.annotations.\"eks.amazonaws.com/role-arn\""
    value = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${aws_iam_role.cluster_autoscaler.name}"
  }

  set {
    name  = "autoDiscovery.enabled"
    value = true
  }

  set {
    name  = "autoDiscovery.clusterName"
    value = local.cluster_name
  }

  set {
    name  = "cluster-autoscaler.kubernetes.io/safe-to-evict"
    value = false
  }
}
