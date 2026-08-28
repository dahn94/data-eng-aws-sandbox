output "function_name" {
  description = "Nome da função Lambda"
  value       = aws_lambda_function.python_lambda.function_name
}

output "function_arn" {
  description = "ARN da função Lambda"
  value       = aws_lambda_function.python_lambda.arn
}

output "function_url" {
  description = "URL da função, quando criada"
  value       = var.create_function_url ? aws_lambda_function_url.lambda_url[0].function_url : ""
}

output "role_arn" {
  description = "ARN do IAM role da função"
  value       = aws_iam_role.lambda_role.arn
}
