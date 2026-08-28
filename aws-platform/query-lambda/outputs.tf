output "ecr_repository_url" {
  description = "URL do repositório ECR — use no build_and_push.sh"
  value       = aws_ecr_repository.duckdb.repository_url
}

output "function_name" {
  description = "Nome da função Lambda (vazio enquanto image_tag não for definido)"
  value       = local.create_function ? module.lambda_function_duckdb[0].function_name : ""
}

output "function_url" {
  description = "URL da função, quando habilitada"
  value       = local.create_function ? module.lambda_function_duckdb[0].function_url : ""
}
