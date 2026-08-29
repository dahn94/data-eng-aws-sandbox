output "integration_arn" {
  description = "ARN da integração zero-ETL — é aqui que se olha o status quando o dado não aparece"
  value       = aws_rds_integration.postgres_to_redshift.arn
}

output "redshift_workgroup" {
  description = "Workgroup a escolher no Query Editor v2"
  value       = module.warehouse.workgroup_name
}

output "redshift_namespace" {
  description = "Namespace que recebe a replicação"
  value       = module.warehouse.namespace_name
}

output "redshift_endpoint" {
  description = "Host de conexão do workgroup"
  value       = module.warehouse.endpoint_address
}

output "next_step" {
  description = "O passo manual que falta: a integração cria o banco de destino, mas quem o declara é você"
  value       = <<-EOT
    A integração replica para um banco que precisa ser criado uma vez, no
    Redshift, a partir do ID dela:

      CREATE DATABASE zeroetl_origem FROM INTEGRATION '<integration_id>'
        DATABASE dataengsandbox;

    O <integration_id> é o sufixo do integration_arn deste output. Depois disso
    as tabelas da origem aparecem sozinhas, e continuam aparecendo.
  EOT
}
