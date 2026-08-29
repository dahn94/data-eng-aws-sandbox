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

variable "rds_password" {
  description = <<-EOT
    Senha do Postgres. Sem default de propósito: passe por -var,
    TF_VAR_rds_password ou um *.auto.tfvars fora do Git. Vai para o Secrets
    Manager, que é de onde o conector lê — a senha não fica no state do
    Terraform em texto claro nem é argumento da Lambda.
  EOT
  type        = string
  sensitive   = true
}

variable "spill_bucket_name" {
  description = <<-EOT
    Bucket onde o conector despeja resultado que não cabe na resposta da Lambda
    ("spill"). Este workload cria o bucket — ele é dele, não da foundation:
    o ciclo de vida do spill é o do conector, e some junto no destroy.
  EOT
  type        = string
}

variable "athena_results_bucket_name" {
  description = "Bucket onde o Athena grava o resultado das queries deste workload"
  type        = string
}

variable "connector_lambda_memory_mb" {
  description = <<-EOT
    Memória da Lambda do conector. 3008 é o default da AWS; aqui fica menor
    porque as queries de estudo são pequenas. Suba se ver spill frequente.
  EOT
  type        = number
  default     = 1024
}

variable "connector_lambda_timeout_s" {
  description = "Timeout da Lambda do conector, em segundos. O teto do Athena por chamada é 900."
  type        = number
  default     = 300
}

variable "spill_retention_days" {
  description = "Dias até o spill ser expirado. É dado intermediário e descartável — reter custa sem servir a nada."
  type        = number
  default     = 3
}
