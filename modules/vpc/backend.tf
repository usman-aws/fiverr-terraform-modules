# Terraform state backend.
#
# State is intentionally kept local for now (Terraform's default backend), so
# this module is not wired to any AWS account. There is no active remote backend
# block below.
#
# Note: `-backend=false` (used by CI as `terraform init -backend=false`) is a
# CLI flag that skips backend initialisation. It is not a value that can be set
# in this file. The file-level equivalent of "not connected yet" is simply to
# leave the S3 block below commented out, as it is here.
#
# To adopt remote state later: create the S3 bucket (versioned + encrypted) and
# a DynamoDB lock table out-of-band, uncomment the block, then run:
#
#   terraform init -migrate-state \
#     -backend-config="bucket=example-app-tfstate" \
#     -backend-config="key=vpc/terraform.tfstate" \
#     -backend-config="region=us-east-1" \
#     -backend-config="dynamodb_table=example-app-tf-locks"
#
# Prefer passing these via -backend-config over hard-coding them, so the same
# module can back multiple environments.

# terraform {
#   backend "s3" {
#     bucket         = "example-app-tfstate"
#     key            = "vpc/terraform.tfstate"
#     region         = "us-east-1"
#     encrypt        = true
#     dynamodb_table = "example-app-tf-locks" # Terraform < 1.10
#     # use_lockfile = true                   # Terraform >= 1.10 (S3-native locking)
#   }
# }
