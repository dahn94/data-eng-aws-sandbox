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
