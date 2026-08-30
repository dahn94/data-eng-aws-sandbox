output "athena_catalog_name" {
  description = "Nome do catálogo federado a usar no FROM da query"
  value       = aws_athena_data_catalog.postgres.name
}

output "athena_workgroup" {
  description = "Workgroup que isola o custo deste caminho"
  value       = aws_athena_workgroup.federated.name
}

output "connector_function_name" {
  description = "Lambda do conector — é aqui que se olha o log quando a query federada falha"
  value       = "dataeng-sandbox-federated-${var.environment}-connector"
}

output "example_query" {
  description = "Query que prova o ponto: junta o estado de agora no Postgres com o histórico já no lake"
  value       = <<-EOT
    SELECT o.order_id, o.status, o.updated_at
    FROM "${aws_athena_data_catalog.postgres.name}"."public"."orders" AS o
    WHERE o.updated_at > current_timestamp - interval '15' minute;
  EOT
}
