output "glue_job_names" {
  description = "Nomes reais dos jobs Glue desta pipeline na AWS"
  value       = module.glue_jobs_streaming.glue_job_names
}

output "opensearch_secret_arn" {
  description = "ARN do secret com as credenciais do OpenSearch"
  value       = aws_secretsmanager_secret.opensearch.arn
}

output "checkpoint_path" {
  description = "Caminho do checkpoint do Structured Streaming. Apague-o se quiser reprocessar do início."
  value       = local.checkpoint_path
}

output "streaming_host_instance_id" {
  description = "ID da instância do host, quando este workload a cria"
  value       = local.host_enabled ? module.streaming_host[0].instance_id : null
}

output "streaming_host_public_ip" {
  description = "IP público do host — use para alcançar as UIs da sua máquina"
  value       = local.host_enabled ? module.streaming_host[0].public_ip : null
}

output "streaming_host_private_ip" {
  description = "IP privado do host — é por aqui que o job Glue chega quando roda dentro da VPC"
  value       = local.host_enabled ? module.streaming_host[0].private_ip : null
}

output "streaming_host_resolvido" {
  description = "O endereço que o job efetivamente recebe em --STREAMING_HOST"
  value       = local.resolved_streaming_host
}

output "streaming_host_ssm_command" {
  description = "Como abrir um shell no host sem SSH nem porta aberta"
  value       = local.host_enabled ? module.streaming_host[0].ssm_connect_command : null
}
