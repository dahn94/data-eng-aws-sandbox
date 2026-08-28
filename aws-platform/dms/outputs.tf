output "s3_output_prefix" {
  description = "Caminho S3 onde o DMS grava. As pipelines leem daqui."
  value       = module.dms.s3_output_prefix
}

output "replication_task_arn" {
  description = "ARN da task de replicação — use para iniciá-la pelo console ou pela CLI"
  value       = module.dms.replication_task_arn
}
