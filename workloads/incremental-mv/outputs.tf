output "redshift_workgroup" {
  description = "Workgroup a escolher no Query Editor v2"
  value       = module.warehouse.workgroup_name
}

output "redshift_namespace" {
  description = "Namespace que guarda a tabela base e a materialized view"
  value       = module.warehouse.namespace_name
}

output "redshift_endpoint" {
  description = "Host de conexão do workgroup"
  value       = module.warehouse.endpoint_address
}

output "database_name" {
  description = "Banco onde a tabela base e a view vivem"
  value       = module.warehouse.database_name
}

output "materialized_view" {
  description = "Nome da view — é o que o dashboard consulta no lugar do agregado cru"
  value       = local.mv_name
}

output "auto_refresh_enabled" {
  description = "Se o motor é dono do 'quando'. Falso devolve o agendamento para você."
  value       = var.mv_auto_refresh
}

output "check_refresh_query" {
  description = "Como verificar que a view se atualizou sozinha, sem você ter pedido"
  value       = <<-EOT
    O Redshift registra cada refresh, inclusive os automáticos:

      SELECT mv_name, status, refresh_type, starttime, endtime
        FROM SVL_MV_REFRESH_STATUS
       WHERE mv_name = '${local.mv_name}'
       ORDER BY starttime DESC
       LIMIT 20;

    refresh_type = 'Auto' é a linha que prova o ponto deste workload: ninguém
    agendou, ninguém chamou, e o agregado está fresco.
  EOT
}
