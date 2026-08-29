output "namespace_name" {
  description = "Nome do namespace — é o identificador usado em GRANT USAGE de datashare"
  value       = aws_redshiftserverless_namespace.this.namespace_name
}

output "namespace_arn" {
  description = "ARN do namespace — alvo de integração zero-ETL e de resource policy"
  value       = aws_redshiftserverless_namespace.this.arn
}

output "namespace_id" {
  description = "ID do namespace, que é o valor devolvido por SELECT current_namespace no Redshift"
  value       = aws_redshiftserverless_namespace.this.namespace_id
}

output "workgroup_name" {
  description = "Nome do workgroup"
  value       = aws_redshiftserverless_workgroup.this.workgroup_name
}

output "workgroup_arn" {
  description = "ARN do workgroup"
  value       = aws_redshiftserverless_workgroup.this.arn
}

output "endpoint_address" {
  description = "Host de conexão do workgroup"
  value       = try(aws_redshiftserverless_workgroup.this.endpoint[0].address, null)
}

output "endpoint_port" {
  description = "Porta de conexão do workgroup"
  value       = try(aws_redshiftserverless_workgroup.this.endpoint[0].port, null)
}

output "database_name" {
  description = "Banco criado no namespace"
  value       = aws_redshiftserverless_namespace.this.db_name
}

output "admin_username" {
  description = "Usuário administrador do namespace"
  value       = aws_redshiftserverless_namespace.this.admin_username
}
