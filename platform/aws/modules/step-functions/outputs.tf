output "state_machine_arns" {
  description = "ARNs das máquinas de estado criadas"
  value       = { for name, machine in aws_sfn_state_machine.state_machine : name => machine.arn }
}

output "state_machine_names" {
  description = "Nomes reais das máquinas de estado na AWS"
  value       = { for name, machine in aws_sfn_state_machine.state_machine : name => machine.name }
}

output "step_functions_role_arn" {
  description = "ARN do IAM role usado pelas máquinas de estado"
  value       = aws_iam_role.step_functions_role.arn
}

output "log_group_arns" {
  description = "ARNs dos log groups criados"
  value       = { for name, lg in aws_cloudwatch_log_group.step_functions_log_group : name => lg.arn }
}
