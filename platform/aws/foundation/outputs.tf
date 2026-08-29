output "configs_bucket" {
  description = "Bucket de configuração (tfstate, scripts Glue, jars)"
  value       = aws_s3_bucket.configs.id
}

output "raw_bucket" {
  description = "Bucket de dados brutos (destino do DMS, entrada dos workloads)"
  value       = aws_s3_bucket.data["raw"].id
}

output "curated_bucket" {
  description = "Bucket de dados curados (resultados de Data Quality)"
  value       = aws_s3_bucket.data["curated"].id
}

output "logs_bucket" {
  description = "Bucket de logs (checkpoints do Spark Streaming)"
  value       = aws_s3_bucket.data["logs"].id
}

output "lakehouse_table_bucket_arn" {
  description = "ARN do bucket S3 Tables usado pelos workloads Iceberg"
  value       = aws_s3tables_table_bucket.lakehouse.arn
}
