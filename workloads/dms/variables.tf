variable "environment" {
  description = "Ambiente de implantação (dev, prod)"
  type        = string
  default     = "dev"
}

variable "rds_password" {
  description = "Senha do Postgres de origem deste workload. Sem default de propósito: passe por TF_VAR_rds_password."
  type        = string
  sensitive   = true
}

variable "s3_bucket_raw" {
  description = "Nome do bucket S3 para armazenar dados brutos (criado por platform/aws/foundation)"
  type        = string
}

variable "network_state_bucket" {
  description = "S3 bucket holding platform/aws/network's state. No default on purpose — it is your own bucket, set in envs/*.tfvars."
  type        = string
}

variable "network_state_key" {
  description = "S3 key of platform/aws/network's state for this environment"
  type        = string
}

variable "rds_state_bucket" {
  description = "S3 bucket com o state de um Postgres externo. Só é lido quando create_source_db = false."
  type        = string
  default     = ""
}

variable "rds_state_key" {
  description = "S3 key do state do Postgres externo. Só é lido quando create_source_db = false."
  type        = string
  default     = ""
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
# ---------------------------------------------------------------------------
# A fonte deste workload
# ---------------------------------------------------------------------------
#
# Cada workload cria o próprio Postgres de origem. A alternativa — um banco
# compartilhado — obrigava a aplicar outra pasta antes desta e fazia um único
# parameter group carregar a união das exigências de todos, escondendo quem
# precisava do quê.
#
# Não há custo extra em ter três definições: só um experimento roda por vez, e
# o banco sobe e é destruído junto com o workload.

variable "create_source_db" {
  description = <<-EOT
    Cria o Postgres de origem deste workload, a partir de `../../modules/rds`.

    Desligue para apontar para um Postgres que já existe — o seu, ou o de outro
    time — preenchendo `rds_state_bucket` e `rds_state_key`. É o cenário
    realista: na vida real o banco transacional pertence a quem escreve nele, e
    o time de dados só lê.
  EOT
  type        = bool
  default     = true
}

variable "source_db_instance_class" {
  description = "Classe da instância da fonte. `db.t4g.micro` está no free tier nos 12 primeiros meses."
  type        = string
  default     = "db.t4g.micro"
}

variable "source_db_allocated_storage" {
  description = "Disco da fonte em GB"
  type        = number
  default     = 20
}

variable "source_db_allowed_cidr_blocks" {
  description = "CIDRs que alcançam o Postgres além da própria VPC. Vazio = só de dentro da VPC."
  type        = list(string)
  default     = []
}
