output "glue_job_names" {
  description = "Nomes reais dos jobs Glue desta pipeline na AWS"
  value       = module.glue_jobs_s3tables.glue_job_names
}

output "state_machine_arns" {
  description = "ARNs das máquinas de estado desta pipeline"
  value       = module.step_functions.state_machine_arns
}

output "lakehouse_arn" {
  description = "ARN do bucket S3 Tables usado pela pipeline"
  value       = local.lakehouse_arn
}

output "raw_input_path" {
  description = "Caminho S3 de onde a pipeline lê. Precisa casar com a saída do DMS."
  value       = local.raw_input
}
