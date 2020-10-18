variable "region" {
  default = "us-east-1"
}

variable "domain" {
  default = "example.com"
}

variable "subdomain" {
  default = "prod"
}

provider "aws" {
  region = var.region
}

module "zone" {
  source  = "terraform-aws-modules/route53/aws//modules/zones"
  version = "~> 1.0"

  zones = {
    "${var.subdomain}.${var.domain}" = {
      comment = "Domain ${var.subdomain}.${var.domain}"
      tags = {
        env = "${var.subdomain}.${var.domain}"
      }
    }
  }
}

# output "this_route53_zone_zone_id" {
#   description = "The name of the record"
#   value       = "${module.zone.aws_route53_zone.this["${var.subdomain}.${var.domain}]"}
# }
#
# output "this_route53_zone_name_servers" {
#   description = "The Zone Id"
#   value       = { for k, v in aws_route53_zone.this : k => v.name_servers }
# }
