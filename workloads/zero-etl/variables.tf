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
  description = "S3 bucket com o state de um Postgres externo. Só é lido quando create_source_db = false."
  type        = string
  default     = ""
}

variable "rds_state_key" {
  description = "S3 key do state do Postgres externo. Só é lido quando create_source_db = false."
  type        = string
  default     = ""
}

variable "rds_password" {
  description = <<-EOT
    Senha do Postgres de origem, quando este workload o cria
    (`create_source_db = true`). Sem default de propósito: passe por
    `TF_VAR_rds_password`. Ignorada quando você aponta para um banco externo.
  EOT
  type        = string
  sensitive   = true
  default     = ""
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
    Capacidade base do workgroup, em RPU. 4 é o mínimo do serviço em us-east-2;
    regiões sem a opção de 4 exigem 8. Diferente de Glue e Lambda, o Redshift
    Serverless cobra por RPU enquanto processa consulta — este é o workload mais
    caro do repositório e o teardown importa.
  EOT
  type        = number
  default     = 4
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
