variable "function_name" {
  description = "Nome da função Lambda, usado como prefixo dos recursos"
  type        = string
}

variable "description" {
  description = "Descrição da função"
  type        = string
  default     = ""
}

variable "image_uri" {
  description = "URI completa da imagem no ECR, com tag imutável ou digest"
  type        = string
}

variable "timeout" {
  description = "Timeout da função em segundos"
  type        = number
  default     = 60
}

variable "memory_size" {
  description = "Memória da função em MB"
  type        = number
  default     = 512
}

variable "ephemeral_storage_size" {
  description = "Tamanho de /tmp em MB"
  type        = number
  default     = 512
}

variable "environment_variables" {
  description = "Variáveis de ambiente da função. Não coloque segredos aqui — use o Secrets Manager."
  type        = map(string)
  default     = {}
}

variable "create_function_url" {
  description = "Cria uma Function URL para a função"
  type        = bool
  default     = false
}

variable "function_url_auth_type" {
  description = "Autenticação da Function URL. NONE deixa a função aberta na internet — use AWS_IAM."
  type        = string
  default     = "AWS_IAM"

  validation {
    condition     = contains(["AWS_IAM", "NONE"], var.function_url_auth_type)
    error_message = "function_url_auth_type deve ser AWS_IAM ou NONE."
  }
}

variable "allowed_origins" {
  description = "Origens permitidas no CORS. Vazio = sem bloco CORS."
  type        = list(string)
  default     = []
}

variable "readable_buckets" {
  description = "Buckets S3 que a função pode ler"
  type        = list(string)
  default     = []
}

variable "s3tables_bucket_arn" {
  description = "ARN do bucket S3 Tables que a função pode consultar. Vazio = sem permissão de s3tables."
  type        = string
  default     = ""
}

variable "additional_policy_arns" {
  description = "ARNs de políticas IAM adicionais para anexar ao role"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Dias de retenção dos logs no CloudWatch"
  type        = number
  default     = 14
}
