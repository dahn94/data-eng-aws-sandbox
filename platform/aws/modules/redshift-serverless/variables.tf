variable "name" {
  description = "Nome base do namespace e do workgroup. Deve ser único na conta/região."
  type        = string
}

variable "environment" {
  description = "Ambiente de implantação (dev, prod)"
  type        = string
}

variable "database_name" {
  description = "Banco criado dentro do namespace"
  type        = string
  default     = "dev"
}

variable "admin_username" {
  description = "Usuário administrador do namespace"
  type        = string
  default     = "admin"
}

variable "admin_password" {
  description = "Senha do administrador. Sem default de propósito — passe por TF_VAR ou Secrets Manager."
  type        = string
  sensitive   = true
}

variable "subnet_ids" {
  description = <<-EOT
    Subnets do workgroup. Sem Enhanced VPC Routing bastam 2 subnets em 2 AZs
    (suportado desde julho/2025); com EVR ligado passam a ser exigidas 3 em 3
    AZs. Cada subnet precisa de pelo menos 3 IPs livres para o workgroup mudar
    de capacidade.
  EOT
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups do workgroup. Quem instancia o módulo é dono deles."
  type        = list(string)
}

variable "base_capacity_rpu" {
  description = <<-EOT
    Capacidade base em RPU. 4 é o mínimo do serviço em us-east-2 (era 8 até
    2025); regiões que ainda não receberam a opção de 4 exigem 8, e o apply
    falha se você pedir menos do que a região aceita. O workgroup cobra por RPU
    enquanto processa consulta — é a diferença de modelo em relação a Glue e
    Lambda, que só cobram por execução.
  EOT
  type        = number
  default     = 4
}

variable "max_capacity_rpu" {
  description = "Teto de RPU por consulta. -1 = sem teto explícito."
  type        = number
  default     = -1
}

variable "publicly_accessible" {
  description = "Expor o workgroup na internet. Falso: ele vive na subnet privada, como o resto."
  type        = bool
  default     = false
}

variable "enhanced_vpc_routing" {
  description = <<-EOT
    Força todo o tráfego do Redshift pela VPC. Ligar isto exige 3 subnets em 3
    AZs — o platform/aws/network hoje cria 2. Ligar sem estender a rede quebra o
    apply.
  EOT
  type        = bool
  default     = false
}

variable "case_sensitive_identifier" {
  description = <<-EOT
    Torna identificadores sensíveis a maiúsculas. Requisito das integrações
    zero-ETL, que replicam nomes de objeto da origem como eles são.
  EOT
  type        = bool
  default     = false
}

variable "iam_role_arns" {
  description = "Roles que o namespace pode assumir (para ler S3, por exemplo)"
  type        = list(string)
  default     = []
}

variable "default_iam_role_arn" {
  description = "Role assumida por padrão. Precisa estar em iam_role_arns."
  type        = string
  default     = null
}

variable "log_exports" {
  description = "Logs enviados ao CloudWatch: userlog, connectionlog, useractivitylog"
  type        = list(string)
  default     = ["userlog", "connectionlog"]
}
