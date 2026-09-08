# AWS VPC Foundation (Terraform)

A reusable, multi-AZ VPC foundation module intended to sit underneath application
modules (ECS, RDS, ALB, and similar). It provisions a three-tier network with
controlled egress, DNS, VPC flow logging, and hardened defaults, and exposes the
IDs and ARNs those downstream modules need.

## Overview

The module builds one VPC spanning a configurable number of Availability Zones,
with three subnet tiers per AZ:

- **public** — internet-facing resources (load balancers, NAT gateways)
- **private** — application workloads with outbound-only internet access via NAT
- **isolated** — data stores (RDS, ElastiCache) with no route off the VPC

Configuration is supplied through `vars.yaml`; there are no Terraform input
variables. The module manages networking only — it deliberately does not create
workloads, databases, or an S3 bucket for flow logs.

## Architecture

```
                         Internet
                            |
                    Internet Gateway
                            |
        +-------------------+-------------------+
        |  public subnets (one per AZ)          |   ALB, NAT GW
        |     - map_public_ip_on_launch = true  |
        +-------------------+-------------------+
                            |  (NAT egress)
        +-------------------+-------------------+
        |  private subnets (one per AZ)         |   app / ECS / EC2
        |     - default route -> NAT gateway    |
        +-------------------+-------------------+
        +---------------------------------------+
        |  isolated subnets (one per AZ)        |   RDS / ElastiCache
        |     - no route off the VPC            |
        +---------------------------------------+

S3 / DynamoDB gateway endpoints attach to the private and isolated route tables.
VPC flow logs -> CloudWatch Logs (default) or S3.
```

NAT placement is controlled by `nat.mode`:

- `single` — one NAT gateway in the first AZ, shared by all private subnets
  (lowest cost; egress depends on a single AZ).
- `per_az` — one NAT gateway per AZ (no cross-AZ egress dependency; higher cost).
- `none` — no NAT; private subnets have no outbound internet route.

## Features

- Multi-AZ, three-tier subnet layout driven entirely by `vars.yaml`
- Selectable NAT strategy (`single` / `per_az` / `none`) with an explicit
  cost/availability trade-off
- S3 and DynamoDB gateway endpoints (free) enabled by default to keep that
  traffic off the NAT data path
- Optional, opt-in interface endpoints with a dedicated, VPC-scoped security group
- VPC flow logs to CloudWatch Logs or S3, with configurable retention and
  optional customer-managed KMS encryption
- Default security group locked to deny-all
- Least-privilege IAM role for flow log delivery, scoped to its log group
- Input validation via preconditions to fail fast on common misconfigurations
- Subnets and route tables keyed by AZ name for stable state addresses

## AWS Resources Created

- `aws_vpc`
- `aws_internet_gateway`
- `aws_subnet` (public, private, isolated — one per AZ per tier)
- `aws_eip`, `aws_nat_gateway` (depending on `nat.mode`)
- `aws_route_table`, `aws_route`, `aws_route_table_association`
- `aws_vpc_endpoint` (S3/DynamoDB gateway; optional interface endpoints)
- `aws_security_group` (only when interface endpoints are enabled)
- `aws_flow_log` and, for CloudWatch delivery, `aws_cloudwatch_log_group`,
  `aws_iam_role`, and `aws_iam_role_policy`
- `aws_default_security_group` (locked to deny-all)

## Prerequisites

- Terraform >= 1.6
- AWS provider ~> 6.0 (see note under *Deployment*)
- AWS credentials supplied through a standard mechanism (CLI profile,
  environment variables, or an assumed IAM role). The module does not configure
  static credentials.
- For `flow_logs.destination: s3`, an existing S3 bucket ARN.
- For customer-managed flow-log encryption, an existing KMS key ARN.

## Repository Structure

```
modules/vpc/
├── locals.tf       # loads vars.yaml, derives AZs/subnets/NAT/tags
├── providers.tf    # Terraform + AWS provider version constraints
├── backend.tf      # state backend (local now; S3 template for later)
├── main.tf         # all AWS resources
├── variables.tf    # intentionally empty
├── vars.yaml       # configuration (sanitized example values)
└── outputs.tf      # exported IDs, ARNs, and maps
```

## Configuration

All configuration lives in `vars.yaml`. Each subnet list must contain exactly
`vpc.availability_zone_count` CIDRs, one per AZ.

| Key | Description |
| --- | --- |
| `project`, `environment`, `region` | Naming and provider region |
| `vpc.cidr` | VPC primary CIDR |
| `vpc.availability_zone_count` | Number of AZs to span |
| `subnets.public/private/isolated` | One CIDR per AZ, per tier |
| `nat.mode` | `single`, `per_az`, or `none` |
| `flow_logs.enabled` | Toggle VPC flow logs |
| `flow_logs.destination` | `cloud-watch-logs` or `s3` |
| `flow_logs.retention_in_days` | CloudWatch retention |
| `flow_logs.kms_key_arn` | Optional CMK for the log group |
| `flow_logs.s3_bucket_arn` | Required when destination is `s3` |
| `endpoints.gateway.s3/dynamodb` | Toggle free gateway endpoints |
| `endpoints.interface` | List of interface endpoint short-names |
| `tags` | Additional tags merged into every resource |

## Usage

Locally, within this repository:

```hcl
module "network" {
  source = "./modules/vpc"
}
```

From another repository, pinned to a release tag:

```hcl
module "network" {
  source = "git::https://github.com/usman-aws/fiverr-terraform-modules.git//modules/vpc?ref=v1.0.0"
}
```

Downstream modules consume the outputs, for example:

```hcl
subnets = module.network.private_subnet_ids
vpc_id  = module.network.vpc_id
```

See [`examples/vpc-basic`](../../examples/vpc-basic) for a runnable, standalone
invocation of this module as a caller would use it.

## Outputs

| Output | Description |
| --- | --- |
| `vpc_id`, `vpc_arn`, `vpc_cidr_block` | Core VPC identifiers |
| `availability_zones` | AZs spanned |
| `public/private/isolated_subnet_ids` | Subnet ID lists per tier |
| `public/private/isolated_subnets_by_az` | AZ → subnet ID maps |
| `public_route_table_id`, `private_route_table_ids`, `isolated_route_table_id` | Route table IDs |
| `internet_gateway_id` | IGW ID |
| `nat_gateway_ids`, `nat_public_ips` | NAT identifiers (empty when `nat.mode: none`) |
| `default_security_group_id` | Locked default SG ID |
| `flow_log_group_name` | CloudWatch log group name, if enabled |

No secrets are exported.

## Security Considerations

- The VPC default security group is locked to deny-all so nothing inherits an
  open default.
- Isolated subnets have no route to the internet; data stores placed there are
  unreachable from outside the VPC by routing, independent of security groups.
- The flow-log IAM role is scoped to its specific log group with stream-level
  permissions only (no wildcards).
- Interface endpoints, when enabled, use a dedicated security group that only
  permits HTTPS from the VPC CIDR.
- Network ACLs are left at the permissive AWS default; security groups are the
  stateful control plane for this module. The default NACL is intentionally not
  narrowed to deny-all, which would silently break traffic on subnets that use it.
- Public subnets set `map_public_ip_on_launch = true` by design. Application
  workloads should be launched in the private tier, not the public tier.

## High Availability / Reliability

Subnets and route tables are spread across every configured AZ. The honest
availability caveat is NAT: with `nat.mode: single`, all outbound traffic from
private subnets depends on one AZ, so an AZ failure removes egress for the whole
private tier. Use `nat.mode: per_az` for an egress path that tolerates the loss
of an AZ, at roughly N times the NAT cost. The module is not described as
"highly available" without per-AZ NAT.

## Monitoring / Observability

VPC flow logs are enabled by default (`ALL` traffic) and delivered to CloudWatch
Logs with 30-day retention, or to an existing S3 bucket. This module does not
create alarms or dashboards; those belong to the workloads that run on top of it.

## Cost Considerations

The dominant cost driver is NAT. Each NAT gateway carries an hourly charge plus
per-GB data processing, so `single` is the default and `per_az` multiplies that
cost by the AZ count. Gateway endpoints for S3 and DynamoDB are free and reduce
NAT data-processing charges, so they are on by default. Interface endpoints are
billed per-AZ per-hour plus data and are therefore off by default. Flow log
volume is bounded by the configured retention.

## Limitations

- Each subnet list must contain exactly one CIDR per AZ; the module does not
  auto-calculate subnet CIDRs (this keeps `terraform plan` explicit and
  reviewable).
- Preconditions validate list lengths, NAT mode, and the S3 flow-log
  requirement, but do not check that subnet CIDRs fall within the VPC CIDR or
  are non-overlapping; AWS rejects those at apply time.
- IPv6 is not configured.
- Flow-log delivery to S3 requires a pre-existing bucket; the module does not
  create it.
- Transit Gateway, VPC peering, VPN, and bastion/Client VPN access are out of
  scope by design and belong in separate connectivity modules.

## Deployment

Run directly as a standalone root module (from `modules/vpc/`):

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

State is stored locally by default. See `backend.tf` for a commented S3 backend
template and migration steps when you are ready to move to remote state.

The AWS provider constraint targets the current v6 major line. Confirm it
against the release you intend to use; to run on the v5 line instead, change the
constraint in `providers.tf` to `">= 5.40, < 7.0"`.

## Cleanup

```bash
terraform destroy
```

NAT gateways and their Elastic IPs are billed until destroyed, so tear down
non-permanent environments when they are not in use.

## Disclaimer

This module is provided as a portfolio reference implementation using sanitized
example values. Review and adapt the CIDR plan, region, tagging, and NAT and
logging choices to your own requirements before deploying to any account.