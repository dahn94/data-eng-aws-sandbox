variable "environment" {
  description = "Ambiente de implantação (dev, prod)"
  type        = string
  default     = "dev"
}

variable "rds_password" {
  description = "Password for the RDS PostgreSQL instance. No default on purpose — pass via -var, TF_VAR_rds_password, or an untracked *.auto.tfvars."
  type        = string
  sensitive   = true
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach Postgres on 5432 (e.g. your IP as x.x.x.x/32). Empty = no inbound access from outside the VPC."
  type        = list(string)
  default     = []
}

variable "network_state_bucket" {
  description = "S3 bucket holding platform/network's state. No default on purpose — it is your own bucket, set in envs/*.tfvars."
  type        = string
}

variable "network_state_key" {
  description = "S3 key of platform/network's state for this environment"
  type        = string
}

variable "region" {
  description = "Região AWS onde os recursos serão criados"
  type        = string
  default     = "us-east-2"
}

variable "instance_class" {
  description = "Classe da instância RDS. db.t4g.micro é elegível ao free tier nos primeiros 12 meses; db.t4g.small custa ~US$25/mês rodando 24/7."
  type        = string
  default     = "db.t4g.micro"
}

variable "aws_endpoint_url" {
  description = <<-EOT
    URL única para onde mandar todas as chamadas da AWS. Vazio (o default) =
    AWS de verdade. Preencha com http://localhost:4566 para usar o LocalStack
    (veja local-services/localstack).
  EOT
  type        = string
  default     = ""
}
