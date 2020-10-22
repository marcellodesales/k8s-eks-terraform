terraform {
  required_version = ">= 0.12"

  required_providers {
    aws    = ">= 3.0, < 4.0"
    random = "~> 3.0.0"
  }
}

# https://github.com/hashicorp/terraform/issues/4390#issuecomment-234963443
data "aws_caller_identity" "current" {} # used for accesing Account ID and ARN
