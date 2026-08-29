output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the created VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = aws_subnet.private[*].id
}

output "s3_gateway_endpoint_id" {
  description = "ID of S3 Gateway VPC endpoint"
  value       = aws_vpc_endpoint.s3_gateway.id
}

output "dms_subnet_group_id" {
  description = "ID of DMS replication subnet group"
  value       = aws_dms_replication_subnet_group.this.replication_subnet_group_id
}
