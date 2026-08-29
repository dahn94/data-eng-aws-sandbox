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
    Capacidade base do workgroup, em RPU. 8 é o mínimo do serviço. O auto
    refresh da materialized view consome RPU sem ninguém pedir — é o preço de
    não ser mais dono do "quando", e aparece na fatura mesmo com o dashboard
    fechado.
  EOT
  type        = number
  default     = 8
}

variable "seed_bucket" {
  description = <<-EOT
    Bucket com os parquet que semeiam a tabela base. Vazio = o workload sobe com
    a tabela vazia e você insere linhas à mão (o README mostra como). Preencher
    é o que torna os números comparáveis com os dos outros workloads — ver
    ../DATASET.md.
  EOT
  type        = string
  default     = ""
}

variable "seed_prefix" {
  description = "Prefixo dentro de seed_bucket de onde o COPY lê. Precisa terminar em /."
  type        = string
  default     = "datasets/vendas/"
}

variable "mv_auto_refresh" {
  description = <<-EOT
    Liga o AUTO REFRESH da materialized view. É a variável que este workload
    existe para estudar: com `true`, o motor decide quando recomputar; com
    `false`, você volta a ser dono do agendamento — que é o mundo do pipeline.
  EOT
  type        = bool
  default     = true
}
