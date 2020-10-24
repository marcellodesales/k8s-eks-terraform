# create all Namespaces into EKS
resource "kubernetes_namespace" "k8s_namespaces" {
  for_each = toset(concat(var.namespaces_app, var.namespaces_system))

  metadata {
    annotations = {
      name = each.key
    }
    name = each.key
  }
}
