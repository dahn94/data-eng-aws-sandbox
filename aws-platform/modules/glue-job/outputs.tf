output "glue_job_names" {
  description = "Nomes reais dos jobs na AWS, por chave lógica"
  value       = { for k, v in aws_glue_job.glue_job : k => v.name }
}

output "glue_job_arns" {
  description = "ARNs dos jobs criados"
  value       = { for k, v in aws_glue_job.glue_job : k => v.arn }
}

output "glue_job_role_arn" {
  description = "ARN do IAM role usado pelos jobs"
  value       = aws_iam_role.glue_job_role.arn
}

output "glue_job_role_name" {
  description = "Nome do IAM role usado pelos jobs"
  value       = aws_iam_role.glue_job_role.name
}

output "jar_uris" {
  description = "URIs S3 dos jars enviados por este módulo"
  value       = [for o in aws_s3_object.jar : "s3://${o.bucket}/${o.key}"]
}
