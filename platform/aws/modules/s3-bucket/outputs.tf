output "id" {
  description = "Nome do bucket, que é o id na AWS"
  value       = aws_s3_bucket.this.id
}

output "arn" {
  description = "ARN do bucket"
  value       = aws_s3_bucket.this.arn
}
