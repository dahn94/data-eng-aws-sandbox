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
  description = "S3 bucket com o state de platform/aws/network. Sem default de propósito — é o seu bucket, definido em envs/*.tfvars."
  type        = string
}

variable "network_state_key" {
  description = "S3 key do state de platform/aws/network para este ambiente"
  type        = string
}

variable "redshift_admin_password" {
  description = <<-EOT
    Senha do administrador dos dois namespaces (produtor e consumidor). Sem
    default de propósito: passe por -var ou TF_VAR_redshift_admin_password.
    Precisa de 8-64 caracteres, com maiúscula, minúscula e número.
  EOT
  type        = string
  sensitive   = true
}

variable "base_capacity_rpu" {
  description = <<-EOT
    Capacidade base de CADA workgroup, em RPU. 4 é o mínimo do serviço em
    us-east-2; regiões sem a opção de 4 exigem 8. Este é o único workload do
    repositório que cria dois — a demonstração exige duas pontas. Leia a seção
    de custo do README antes de aplicar.
  EOT
  type        = number
  default     = 4
}

variable "seed_bucket" {
  description = <<-EOT
    Bucket com os parquet que semeiam a tabela do produtor. Vazio = o produtor
    sobe com a tabela vazia; o compartilhamento continua demonstrável, só não
    tem volume para medir. Ver ../DATASET.md.
  EOT
  type        = string
  default     = ""
}

variable "seed_prefix" {
  description = "Prefixo dentro de seed_bucket de onde o COPY lê. Precisa terminar em /."
  type        = string
  default     = "datasets/vendas/"
}

variable "share_name" {
  description = "Nome do datashare no produtor. Minúsculas e underscore — é um identificador SQL."
  type        = string
  default     = "vendas_share"
}

variable "consumer_database_name" {
  description = <<-EOT
    Nome do banco que o consumidor monta a partir do datashare. É um banco sem
    armazenamento próprio: ele aponta para os dados do produtor.
  EOT
  type        = string
  default     = "vendas_do_time_de_dados"
}
