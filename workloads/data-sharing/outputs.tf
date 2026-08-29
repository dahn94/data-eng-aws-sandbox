output "producer_workgroup" {
  description = "Workgroup do produtor — quem é dono do dado"
  value       = module.producer.workgroup_name
}

output "consumer_workgroup" {
  description = "Workgroup do consumidor — quem lê sem copiar"
  value       = module.consumer.workgroup_name
}

output "producer_namespace_id" {
  description = "GUID do namespace produtor — é o endereço citado no CREATE DATABASE do consumidor"
  value       = module.producer.namespace_id
}

output "consumer_namespace_id" {
  description = "GUID do namespace consumidor — é o endereço citado no GRANT USAGE do produtor"
  value       = module.consumer.namespace_id
}

output "share_name" {
  description = "Nome do datashare criado no produtor"
  value       = var.share_name
}

output "consumer_database" {
  description = "Banco montado no consumidor a partir do share. Não ocupa armazenamento."
  value       = var.consumer_database_name
}

output "proof_query" {
  description = "A consulta que prova o ponto: o consumidor lê o dado do produtor sem ter cópia"
  value       = <<-EOT
    No Query Editor v2, escolha o workgroup ${module.consumer.workgroup_name} e rode:

      SELECT COUNT(*), MAX(pedido_em)
        FROM ${var.consumer_database_name}.public.vendas;

    Agora insira uma linha do lado do produtor (${module.producer.workgroup_name}):

      INSERT INTO vendas VALUES (1, 1, GETDATE(), 10.00, 'novo');

    Repita a consulta no consumidor. O MAX mudou, e nenhum job rodou entre as
    duas execuções — não há defasagem porque não há transporte.
  EOT
}
