variable "environment" {
  description = "Ambiente de implantação (dev, prod)"
  type        = string
  default     = "dev"
}

variable "rds_password" {
  description = "Password for the RDS PostgreSQL instance (same value used in aws-platform/rds). No default on purpose."
  type        = string
  sensitive   = true
}

variable "s3_bucket_raw" {
  description = "Nome do bucket S3 para armazenar dados brutos (criado por aws-platform/foundation)"
  type        = string
}

variable "network_state_bucket" {
  description = "S3 bucket holding aws-platform/network's state. No default on purpose — it is your own bucket, set in envs/*.tfvars."
  type        = string
}

variable "network_state_key" {
  description = "S3 key of aws-platform/network's state for this environment"
  type        = string
}

variable "rds_state_bucket" {
  description = "S3 bucket holding aws-platform/rds's state. No default on purpose — it is your own bucket, set in envs/*.tfvars."
  type        = string
}

variable "rds_state_key" {
  description = "S3 key of aws-platform/rds's state for this environment"
  type        = string
}

variable "region" {
  description = "Região AWS onde os recursos serão criados"
  type        = string
  default     = "us-east-2"
}

variable "raw_output_prefix" {
  description = "Pasta dentro de s3_bucket_raw onde o DMS grava. Precisa casar com raw_input_prefix da pipeline amazonsales."
  type        = string
  default     = "raw/postgres"
}

variable "replication_instance_class" {
  description = "Classe da instância de replicação do DMS"
  type        = string
  default     = "dms.t3.micro"
}

variable "create_vpc_role" {
  description = "Cria a role dms-vpc-role (única por conta AWS). false se ela já existir."
  type        = bool
  default     = true
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
