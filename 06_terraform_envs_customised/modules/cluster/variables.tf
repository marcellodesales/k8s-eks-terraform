variable "aws_region" {
  default = "sa-east-1"
}

variable "cluster_env" {
  default = "my-env"
}

variable "domain" {
  default = "my-product"
}

variable "instance_types" {
  default = ["m5.large"]
}

variable "k8s_manage_aws_auth" {
  default = true
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

variable "namespaces_app" {
  default = ["dev", "qal"]
}

variable "namespaces_system" {
  default = []
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
