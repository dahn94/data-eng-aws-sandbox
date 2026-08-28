variable "project_name" {
  description = "Nome do projeto, usado como prefixo dos recursos IAM"
  type        = string
}

variable "environment" {
  description = "Ambiente (dev, prod). Entra no nome de todos os recursos."
  type        = string
}

variable "region" {
  description = "Região AWS onde os recursos serão criados"
  type        = string
  default     = "us-east-2"
}

variable "definitions_path" {
  description = "Diretório com as definições JSON das máquinas de estado"
  type        = string
  default     = "scripts/step-functions-definitions"
}

variable "state_machines" {
  description = "Mapa {nome_lógico = {definition_file, type}}. O nome real na AWS ganha o sufixo do ambiente."
  type = map(object({
    definition_file = string
    type            = string
  }))
}

variable "template_variables" {
  description = <<-EOT
    Valores extras disponíveis para a definição JSON, além de account_id,
    region, project_name e environment. Use $${nome} dentro do JSON.
  EOT
  type        = map(string)
  default     = {}
}

variable "glue_job_arns" {
  description = "ARNs dos jobs Glue que a máquina de estado pode disparar. A policy é limitada a eles."
  type        = list(string)
  default     = []
}

variable "additional_iam_statements" {
  description = "Declarações IAM adicionais para a política da máquina de estado"
  type        = list(any)
  default     = []
}

variable "log_retention_days" {
  description = "Dias de retenção dos logs no CloudWatch"
  type        = number
  default     = 14
}

variable "include_execution_data" {
  description = "Se deve incluir dados de execução nos logs"
  type        = bool
  default     = true
}

variable "logging_level" {
  description = "Nível de logging (ALL, ERROR, FATAL, OFF)"
  type        = string
  default     = "ALL"
}
