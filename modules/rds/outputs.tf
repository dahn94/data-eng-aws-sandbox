output "db_instance_endpoint" {
  description = "RDS endpoint in host:port form"
  value       = aws_db_instance.postgres.endpoint
}

output "db_instance_address" {
  description = "RDS hostname only (no port) — this is what DMS endpoints and JDBC hosts expect"
  value       = aws_db_instance.postgres.address
}

output "db_instance_port" {
  description = "RDS instance port"
  value       = aws_db_instance.postgres.port
}

output "db_instance_id" {
  description = "RDS instance ID"
  value       = aws_db_instance.postgres.id
}

output "db_name" {
  description = "Database name"
  value       = aws_db_instance.postgres.db_name
}

output "db_username" {
  description = "Master username"
  value       = aws_db_instance.postgres.username
}

output "security_group_id" {
  description = "Security group ID"
  value       = aws_security_group.postgres.id
}

output "db_instance_arn" {
  description = "ARN da instância. Origem de uma integração zero-ETL, que identifica o banco por ARN e não por endpoint."
  value       = aws_db_instance.postgres.arn
}
