output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_arn" {
  description = "ARN of the VPC."
  value       = aws_vpc.this.arn
}

output "vpc_cidr_block" {
  description = "Primary CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "availability_zones" {
  description = "Availability Zones the VPC spans."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "IDs of the private (application) subnets."
  value       = [for s in aws_subnet.private : s.id]
}

output "isolated_subnet_ids" {
  description = "IDs of the isolated (data) subnets."
  value       = [for s in aws_subnet.isolated : s.id]
}

output "public_subnets_by_az" {
  description = "Map of AZ to public subnet ID."
  value       = { for az, s in aws_subnet.public : az => s.id }
}

output "private_subnets_by_az" {
  description = "Map of AZ to private subnet ID."
  value       = { for az, s in aws_subnet.private : az => s.id }
}

output "isolated_subnets_by_az" {
  description = "Map of AZ to isolated subnet ID."
  value       = { for az, s in aws_subnet.isolated : az => s.id }
}

output "public_route_table_id" {
  description = "ID of the shared public route table."
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "Map of AZ to private route table ID."
  value       = { for az, rt in aws_route_table.private : az => rt.id }
}

output "isolated_route_table_id" {
  description = "ID of the shared isolated route table."
  value       = aws_route_table.isolated.id
}

output "internet_gateway_id" {
  description = "ID of the internet gateway."
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_ids" {
  description = "Map of AZ to NAT gateway ID (empty when nat.mode is none)."
  value       = { for az, n in aws_nat_gateway.this : az => n.id }
}

output "nat_public_ips" {
  description = "Elastic IPs assigned to the NAT gateways."
  value       = [for e in aws_eip.nat : e.public_ip]
}

output "default_security_group_id" {
  description = "ID of the VPC default security group (locked to deny-all)."
  value       = aws_default_security_group.this.id
}

output "flow_log_group_name" {
  description = "CloudWatch Logs group receiving VPC flow logs, if enabled."
  value       = local.flow_logs_to_cw ? aws_cloudwatch_log_group.flow_logs[0].name : null
}
