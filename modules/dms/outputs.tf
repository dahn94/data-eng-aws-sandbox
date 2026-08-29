output "source_endpoint_arn" {
  description = "ARN of the source endpoint"
  value       = aws_dms_endpoint.source.endpoint_arn
}

output "target_endpoint_arn" {
  description = "ARN of the target endpoint"
  value       = aws_dms_endpoint.target.endpoint_arn
}

output "replication_task_arn" {
  description = "ARN of the replication task"
  value       = aws_dms_replication_task.main.replication_task_arn
}

output "replication_instance_arn" {
  description = "ARN of the replication instance"
  value       = aws_dms_replication_instance.main.replication_instance_arn
}

output "s3_output_prefix" {
  description = "Prefixo no S3 onde o DMS grava — é o caminho que os workloads devem ler"
  value       = "s3://${var.target_s3_config.bucket_name}/${var.target_s3_config.bucket_folder}"
}
