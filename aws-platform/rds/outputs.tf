output "db_instance_endpoint" {
  description = "RDS endpoint in host:port form"
  value       = module.rds_postgres.db_instance_endpoint
}

output "db_instance_address" {
  description = "RDS hostname only — what DMS and psql expect"
  value       = module.rds_postgres.db_instance_address
}

output "db_instance_port" {
  description = "RDS instance port"
  value       = module.rds_postgres.db_instance_port
}

output "db_name" {
  description = "Database name"
  value       = module.rds_postgres.db_name
}

output "db_username" {
  description = "Master username"
  value       = module.rds_postgres.db_username
}
