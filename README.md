# fiverr-terraform-modules

[![Terraform CI](https://github.com/usman-aws/fiverr-terraform-modules/actions/workflows/terraform.yml/badge.svg)](https://github.com/usman-aws/fiverr-terraform-modules/actions/workflows/terraform.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A collection of reusable, production-minded Terraform modules for AWS,
built as sanitized portfolio reference implementations — each one documents
its architecture, security posture, cost drivers, and limitations rather than
just its inputs and outputs.

## Modules

| Module | Description |
| --- | --- |
| [`modules/vpc`](modules/vpc) | Multi-AZ, three-tier VPC foundation (public / private / isolated subnets, selectable NAT strategy, flow logs, gateway + optional interface endpoints). |

Each module's README covers its own Overview, Architecture, Features, AWS
Resources Created, Configuration, Usage, Outputs, Security Considerations,
High Availability, Cost Considerations, Limitations, and Deployment steps.

## Usage

Consume a module directly from GitHub, pinned to a release tag:

```hcl
module "network" {
  source = "git::https://github.com/usman-aws/fiverr-terraform-modules.git//modules/vpc?ref=v1.0.0"
}
```

Pin `?ref=` to a tag rather than a branch — `main` can change under you.
See each module's own README for its specific inputs and outputs.

## Repository Structure

```
.
├── modules/            # one directory per module, e.g. modules/vpc
├── examples/           # runnable examples that call a module, one per module
├── .github/workflows/  # CI (and a disabled apply-pipeline template)
├── .tflint.hcl          # shared tflint rules, applied recursively
└── LICENSE
```

## Requirements

- Terraform >= 1.6
- AWS provider ~> 6.0 (see each module's README for the v5-line alternative)
- AWS credentials via a standard mechanism (CLI profile, environment
  variables, or an assumed IAM role) — no module configures static
  credentials or its own provider block.

## CI

[`.github/workflows/terraform.yml`](.github/workflows/terraform.yml) runs on
every push and pull request:

- `terraform fmt -check -recursive`
- auto-discovery of every root configuration (each `modules/*` and
  `examples/*`) followed by `terraform init -backend=false` + `terraform
  validate` for each, via a matrix — so a new module needs no workflow changes
- `tflint --recursive`
- `checkov` static security analysis

[`terraform-apply.yml.example`](.github/workflows/terraform-apply.yml.example)
is a disabled template for a plan-on-PR / approval-gated apply-on-merge
pipeline via GitHub OIDC; see the comments at the top of that file to enable
it for a given module.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add a module, the
conventions modules in this repo follow, and the release process.

## License

[MIT](LICENSE) — see the license file. These modules are sanitized reference
implementations; review and adapt configuration, tagging, and security
choices to your own requirements before deploying to any AWS account.
