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

output "security_group_id" {
  description = <<-EOT
    Security group do Postgres. Exposto para que um workload consiga abrir a
    própria regra de entrada em vez de o RDS ter que conhecer seus consumidores
    — quem chega depois é que declara o acesso (ex.: workloads/federated-query).
  EOT
  value       = module.rds_postgres.security_group_id
}

output "db_instance_arn" {
  description = <<-EOT
    ARN da instância Postgres. Exposto para o workloads/zero-etl, que declara a
    integração gerenciada apontando para a origem por ARN.
  EOT
  value       = module.rds_postgres.db_instance_arn
}
