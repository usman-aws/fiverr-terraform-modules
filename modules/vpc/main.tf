data "aws_availability_zones" "available" {
  state = "available"
}

# Fail fast on the most common misconfigurations rather than surfacing them as
# opaque index or apply-time errors.
resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = length(local.config.subnets.public) == local.az_count
      error_message = "subnets.public must contain one CIDR per AZ (length must equal vpc.availability_zone_count)."
    }
    precondition {
      condition     = length(local.config.subnets.private) == local.az_count
      error_message = "subnets.private must contain one CIDR per AZ (length must equal vpc.availability_zone_count)."
    }
    precondition {
      condition     = length(local.config.subnets.isolated) == local.az_count
      error_message = "subnets.isolated must contain one CIDR per AZ (length must equal vpc.availability_zone_count)."
    }
    precondition {
      condition     = contains(["single", "per_az", "none"], local.nat_mode)
      error_message = "nat.mode must be one of: single, per_az, none."
    }
    precondition {
      condition     = !local.flow_logs_to_s3 || try(local.config.flow_logs.s3_bucket_arn, "") != ""
      error_message = "flow_logs.s3_bucket_arn is required when flow_logs.destination is s3."
    }
  }
}

resource "aws_vpc" "this" {
  cidr_block           = local.config.vpc.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, { Name = local.name_prefix })
}

# Lock the VPC's default security group to deny-all. Nothing should attach to
# it; this prevents a resource that omits an explicit SG from inheriting an
# open default.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-default-locked" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = local.name_prefix })
}

#checkov:skip=CKV_AWS_130:Public tier is for ALBs/NAT gateways by design; application workloads belong in the private tier (see README Security Considerations).
resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-public-${each.value.az}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-private-${each.value.az}"
    Tier = "private"
  })
}

resource "aws_subnet" "isolated" {
  for_each = local.isolated_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-isolated-${each.value.az}"
    Tier = "isolated"
  })
}

resource "aws_eip" "nat" {
  for_each = toset(local.nat_azs)

  domain = "vpc"

  tags = merge(local.tags, { Name = "${local.name_prefix}-nat-${each.key}" })
}

resource "aws_nat_gateway" "this" {
  for_each = toset(local.nat_azs)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = merge(local.tags, { Name = "${local.name_prefix}-nat-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

# One private route table per AZ so per-AZ NAT works without restructuring when
# switching nat.mode. In "single" mode every table points at the same gateway.
resource "aws_route_table" "private" {
  for_each = toset(local.azs)

  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-private-${each.key}" })
}

resource "aws_route" "private_nat" {
  for_each = local.nat_mode == "none" ? toset([]) : toset(local.azs)

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[local.nat_mode == "per_az" ? each.key : local.nat_azs[0]].id
}

# Isolated subnets share a single route table with no route off the VPC. Only
# gateway endpoint routes (if enabled) are added to it.
resource "aws_route_table" "isolated" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, { Name = "${local.name_prefix}-isolated" })
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_route_table_association" "isolated" {
  for_each = aws_subnet.isolated

  subnet_id      = each.value.id
  route_table_id = aws_route_table.isolated.id
}

resource "aws_vpc_endpoint" "s3" {
  count = local.gateway_s3 ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [for rt in aws_route_table.private : rt.id],
    [aws_route_table.isolated.id],
  )

  tags = merge(local.tags, { Name = "${local.name_prefix}-s3" })
}

resource "aws_vpc_endpoint" "dynamodb" {
  count = local.gateway_dynamodb ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${local.region}.dynamodb"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [for rt in aws_route_table.private : rt.id],
    [aws_route_table.isolated.id],
  )

  tags = merge(local.tags, { Name = "${local.name_prefix}-dynamodb" })
}

#checkov:skip=CKV2_AWS_5:Attached to aws_vpc_endpoint.interface via security_group_ids below; checkov's attachment check does not recognize VPC interface endpoints as a consumer.
resource "aws_security_group" "vpc_endpoints" {
  count = length(local.interface_endpoints) > 0 ? 1 : 0

  name        = "${local.name_prefix}-vpce"
  description = "HTTPS from within the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  egress {
    description = "Responses to VPC CIDR"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-vpce" })
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoints)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${local.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for s in aws_subnet.private : s.id]
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-${replace(each.value, ".", "-")}" })
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = local.flow_logs_to_cw ? 1 : 0

  name              = "/aws/vpc/flow-logs/${local.name_prefix}"
  retention_in_days = try(local.config.flow_logs.retention_in_days, 30)
  kms_key_id        = local.flow_logs_kms_key_arn != "" ? local.flow_logs_kms_key_arn : null

  tags = merge(local.tags, { Name = "${local.name_prefix}-flow-logs" })
}

data "aws_iam_policy_document" "flow_logs_assume" {
  count = local.flow_logs_to_cw ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  count = local.flow_logs_to_cw ? 1 : 0

  name               = "${local.name_prefix}-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume[0].json
}

# Scoped to the delivery log group only; the group is pre-created by Terraform,
# so the role needs stream-level permissions but not CreateLogGroup.
data "aws_iam_policy_document" "flow_logs" {
  count = local.flow_logs_to_cw ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      aws_cloudwatch_log_group.flow_logs[0].arn,
      "${aws_cloudwatch_log_group.flow_logs[0].arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  count = local.flow_logs_to_cw ? 1 : 0

  name   = "${local.name_prefix}-vpc-flow-logs"
  role   = aws_iam_role.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_logs[0].json
}

resource "aws_flow_log" "this" {
  count = local.flow_logs_enabled ? 1 : 0

  vpc_id               = aws_vpc.this.id
  traffic_type         = "ALL"
  log_destination_type = local.flow_logs_to_s3 ? "s3" : "cloud-watch-logs"
  log_destination      = local.flow_logs_to_s3 ? try(local.config.flow_logs.s3_bucket_arn, null) : aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn         = local.flow_logs_to_cw ? aws_iam_role.flow_logs[0].arn : null

  tags = merge(local.tags, { Name = "${local.name_prefix}-flow-logs" })
}
