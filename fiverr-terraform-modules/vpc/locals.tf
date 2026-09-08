locals {
  config = yamldecode(file("${path.module}/vars.yaml"))

  project     = local.config.project
  environment = local.config.environment
  region      = local.config.region

  name_prefix = "${local.project}-${local.environment}"

  # AZ selection is data-driven so the same config is portable across regions
  # with different AZ names.
  az_count = local.config.vpc.availability_zone_count
  azs      = slice(data.aws_availability_zones.available.names, 0, local.az_count)

  # Subnet maps are keyed by AZ name (e.g. "us-east-1a") rather than a numeric
  # index, so removing or reordering an AZ does not shift every other subnet's
  # resource address in state.
  public_subnets = {
    for idx, cidr in local.config.subnets.public :
    local.azs[idx] => { cidr = cidr, az = local.azs[idx] }
  }
  private_subnets = {
    for idx, cidr in local.config.subnets.private :
    local.azs[idx] => { cidr = cidr, az = local.azs[idx] }
  }
  isolated_subnets = {
    for idx, cidr in local.config.subnets.isolated :
    local.azs[idx] => { cidr = cidr, az = local.azs[idx] }
  }

  # NAT placement. "single" pins one gateway to the first AZ; "per_az" places
  # one per AZ; "none" disables egress entirely.
  nat_mode = try(local.config.nat.mode, "single")
  nat_azs = local.nat_mode == "per_az" ? local.azs : (
    local.nat_mode == "single" ? slice(local.azs, 0, 1) : []
  )

  flow_logs_enabled     = try(local.config.flow_logs.enabled, true)
  flow_logs_destination = try(local.config.flow_logs.destination, "cloud-watch-logs")
  flow_logs_to_cw       = local.flow_logs_enabled && local.flow_logs_destination == "cloud-watch-logs"
  flow_logs_to_s3       = local.flow_logs_enabled && local.flow_logs_destination == "s3"
  flow_logs_kms_key_arn = try(local.config.flow_logs.kms_key_arn, "")

  gateway_s3          = try(local.config.endpoints.gateway.s3, false)
  gateway_dynamodb    = try(local.config.endpoints.gateway.dynamodb, false)
  interface_endpoints = try(local.config.endpoints.interface, [])

  tags = merge(
    {
      Project     = local.project
      Environment = local.environment
      ManagedBy   = "Terraform"
    },
    try(local.config.tags, {})
  )
}
