variable "environment" {
  description = "Ambiente de implantação (dev, prod)"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "Região AWS onde os recursos serão criados"
  type        = string
  default     = "us-east-2"
}

variable "network_state_bucket" {
  description = "S3 bucket com o state de platform/network. Sem default de propósito — é o seu bucket, definido em envs/*.tfvars."
  type        = string
}

variable "network_state_key" {
  description = "S3 key do state de platform/network para este ambiente"
  type        = string
}

variable "rds_state_bucket" {
  description = "S3 bucket com o state de platform/rds. Sem default de propósito — é o seu bucket, definido em envs/*.tfvars."
  type        = string
}

variable "rds_state_key" {
  description = "S3 key do state de platform/rds para este ambiente"
  type        = string
}

variable "redshift_admin_password" {
  description = <<-EOT
    Senha do administrador do Redshift deste workload. Sem default de propósito:
    passe por -var, TF_VAR_redshift_admin_password ou um *.auto.tfvars fora do
    Git. Precisa de 8-64 caracteres, com maiúscula, minúscula e número.
  EOT
  type        = string
  sensitive   = true
}

variable "base_capacity_rpu" {
  description = <<-EOT
    Capacidade base do workgroup, em RPU. 8 é o mínimo do serviço. Diferente de
    Glue e Lambda, o Redshift Serverless cobra por RPU enquanto processa
    consulta — este é o workload mais caro do repositório e o teardown importa.
  EOT
  type        = number
  default     = 8
}

variable "source_tables" {
  description = <<-EOT
    Tabelas da origem a replicar, no formato `banco.schema.tabela` (curinga `*`
    aceito). Vazio = replica tudo. Filtrar é o que mantém a integração
    proporcional: replicar o banco inteiro para usar duas tabelas é desperdício
    que não aparece até a fatura.
  EOT
  type        = list(string)
  default     = ["dataengsandbox.public.*"]
}
