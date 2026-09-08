# Version constraints only. Reusable modules should not configure a
# `provider "aws"` block of their own — that is the caller's responsibility,
# and hardcoding one here would prevent this module from being used with a
# caller-supplied provider (e.g. aliased for a specific region or account).
terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
