data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Como nos jobs Glue: o ambiente entra no nome, senão dev e prod colidem.
  machine_names = { for k, v in var.state_machines : k => "${k}-${var.environment}" }
}

resource "aws_iam_role" "step_functions_role" {
  name = "${local.name_prefix}-step-functions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "step_functions_policy" {
  name        = "${local.name_prefix}-step-functions-policy"
  description = "Policy for the ${local.name_prefix} state machines"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "Logging"
          Effect = "Allow"
          Action = [
            "logs:CreateLogDelivery",
            "logs:GetLogDelivery",
            "logs:UpdateLogDelivery",
            "logs:DeleteLogDelivery",
            "logs:ListLogDeliveries",
            "logs:PutResourcePolicy",
            "logs:DescribeResourcePolicies",
            "logs:DescribeLogGroups",
          ]
          # Estas ações do CloudWatch Logs não aceitam recurso específico.
          Resource = "*"
        }
      ],
      # Permissão de disparar Glue limitada aos jobs desta pipeline, em vez do
      # glue:StartJobRun em Resource = "*" que estava antes.
      length(var.glue_job_arns) > 0 ? [
        {
          Sid    = "RunPipelineGlueJobs"
          Effect = "Allow"
          Action = [
            "glue:StartJobRun",
            "glue:GetJobRun",
            "glue:GetJobRuns",
            "glue:BatchStopJobRun",
          ]
          Resource = var.glue_job_arns
        }
      ] : [],
      var.additional_iam_statements,
    )
  })
}

resource "aws_iam_role_policy_attachment" "step_functions_policy_attachment" {
  role       = aws_iam_role.step_functions_role.name
  policy_arn = aws_iam_policy.step_functions_policy.arn
}

data "local_file" "step_functions_definition" {
  for_each = var.state_machines
  filename = "${var.definitions_path}/${each.value.definition_file}"
}

# A definição JSON é um template: os placeholders ${...} são preenchidos aqui
# para que o mesmo arquivo sirva a qualquer conta, região e ambiente.
locals {
  substitutions = merge(
    {
      account_id   = data.aws_caller_identity.current.account_id
      region       = var.region
      project_name = var.project_name
      environment  = var.environment
    },
    var.template_variables,
  )

}

resource "aws_sfn_state_machine" "state_machine" {
  for_each = var.state_machines

  name     = local.machine_names[each.key]
  role_arn = aws_iam_role.step_functions_role.arn
  type     = each.value.type

  definition = templatestring(
    data.local_file.step_functions_definition[each.key].content,
    local.substitutions,
  )

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions_log_group[each.key].arn}:*"
    include_execution_data = var.include_execution_data
    level                  = var.logging_level
  }
}

resource "aws_cloudwatch_log_group" "step_functions_log_group" {
  for_each = var.state_machines

  name              = "/aws/states/${local.machine_names[each.key]}"
  retention_in_days = var.log_retention_days
}
