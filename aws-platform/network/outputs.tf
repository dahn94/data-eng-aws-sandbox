output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc_public.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC — used by other modules to allow in-VPC traffic"
  value       = module.vpc_public.vpc_cidr
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc_public.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc_public.private_subnet_ids
}

output "dms_subnet_group_id" {
  description = "ID of the DMS replication subnet group"
  value       = module.vpc_public.dms_subnet_group_id
}
